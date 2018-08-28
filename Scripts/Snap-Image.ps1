<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
  .\Make-GoldImageVMs.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM'; ModuleVersion='6.7.0'}

Param
(
  [Parameter(Mandatory=$true, HelpMessage="The name of the DevTest Lab")]
  [string] $DevTestLabName
)

$functionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "functions.ps1"
if (Test-Path $functionPath) { . $functionPath }

$lab = Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $DevTestLabName}
$labRgName= $lab.ResourceGroupName

# Get Storage Account information for the lab.
$labStorageInfo = GetStorageInfo $lab

# Create Storage Container
EnsureRootContainerExists $labStorageInfo

$existingImageInfos = GetImageInfosForLab $DevTestLabName

$labVMs = Get-AzureRmResource -ResourceName $DevTestLabName -ResourceGroupName $labRgName -ResourceType 'Microsoft.DevTestLab/labs/virtualMachines' -ApiVersion '2016-05-15' | Where-Object {$_.Properties.ProvisioningState -eq 'Succeeded'}
$jobs = @()
$copyObjects = New-Object System.Collections.ArrayList

foreach($labVm in $labVMs)
{
  # make sure we have a container in the storage account that matches the imagepath and date for this vhd

  # Get the Tag from the Machine that stored our Image Path
  $imagePath = getTagValue $labVm 'ImagePath'
  if(!$imagePath) {
      Write-Color -Text "Ignoring ", "$($labVm.Name)", " because it does not have the ImagePath tag" -Color green, yellow, green
      continue
  }


  # Craft a name that we can use for the Image
  $imageName = GetImageName $imagePath
  while ($existingImageInfos | Where-Object {$_.imageName -eq $imageName})
  {
      #There is an existing image with this name. We must be running the factory multiple times today.
      $lastChar = $imageName[$imageName.Length - 1]
      $intVal = 0
      if ([System.Int32]::TryParse($lastChar, [ref]$intVal)) {
        $imageName = $imageName + 'A' # last character is a number (probably part of the date). Append an A
      }
      else {
          #last character is a letter. Increment the letter
          $newLastChar = [char](([int]$lastChar) + 1)
          $imageName = $imageName.SubString(0, ($imageName.Length - 1)) + $newLastChar
      }
  }


  $computeVM = Get-AzureRmVM -Status | Where-Object -FilterScript {$_.Id -eq $labVM.Properties.computeId}
  if(!$computeVM) {  Write-Color -Text "No compute VM for ID $labVM.Properties.computeId"  -Color red }

  <#
    Determine the ready state of the machine.
    1. If the VM has a PowerState Property which is 'VM deallocated' then VM is ready. (Version 6 Powershell)
    2. If the VM has a Statuses Property which is 'PowerState/deallocated' then the VM is ready.  (Old Powershell)  ** REMOVE?
    3. All othercases something is up and don't copy as the VHD will be locked.
  #>
  if($computeVM.PowerState -and $computeVM.PowerState -eq 'VM deallocated') { $isReady = $true }
  else {
      $foundPowerState = $computeVM.Statuses | Where-Object {$_.Code -eq 'PowerState/deallocated'}

      if($foundPowerState) { $isReady = $true }
      else { $isReady = $false }
  }
  if($isReady -ne $true) {
      Write-Output ("$($labVM.Name) because it is not currently stopped/deallocated so it will not be copied")
      continue
  }

  # Craft an Info Object for use and add it to our list.
  $copyInfo = @{
      computeRGName = $computeVM.ResourceGroupName
      computeDiskname = $computeVM.StorageProfile.OsDisk.Name
      osType = $labVM.Properties.osType
      fileId = ([Guid]::NewGuid()).ToString()
      description = $labVM.Properties.notes.Replace("Golden Image: ", "")
      storageAcctName = $labStorageInfo.storageAcctName
      storageAcctKey = $labStorageInfo.storageAcctKey
      imagePath = $imagePath
      imageName = $imageName
  }
  $copyObjects.Add($copyInfo)
}

<#
  This is the script block that will run as a background job.  We can fire off the copies as background jobs as a
  parallel process.
#>
$storeVHD_ScriptBlock = {
  Param($modulePath, $copyObject)

  $vhdFileName = $copyObject.fileId + ".vhd"
  $jsonFileName = $copyObject.fileId + ".json"
  $jsonFilePath = Join-Path $Env:TEMP $jsonFileName
  $imageName = $copyObject.imageName
  Write-Output "Storing image: $imageName"

  $vhdInfo = @{
    imageName = $imageName
    imagePath = $copyObject.imagePath
    description = $copyObject.description
    osType = $copyObject.osType
    vhdFileName = $vhdFileName
    timestamp = (Get-Date).ToUniversalTime().ToString()
  }
  ConvertTo-Json -InputObject $vhdInfo | Out-File $jsonFilePath

  try {
    Write-Output "Getting SAS token for disk $($copyObject.computeDiskname) in resource group $($copyObject.computeRGName)"
    $url = (Grant-AzureRmDiskAccess -ResourceGroupName $copyObject.computeRGName -DiskName $copyObject.computeDiskname -Access Read -DurationInSecond 36000).AccessSAS
    $storageContext = New-AzureStorageContext -StorageAccountName $copyObject.storageAcctName -StorageAccountKey $copyObject.storageAcctKey

    Write-Output "Starting vhd copy..."
    $copyHandle = Start-AzureStorageBlobCopy -AbsoluteUri $url -DestContainer 'imagefactoryvhds' -DestBlob $vhdFileName -DestContext $storageContext -Force

    Write-Output ("Started copy of " + $copyObject.computeDiskname + " at " + (Get-Date -format "h:mm:ss tt"))
    $copyStatus = $copyHandle | Get-AzureStorageBlobCopyState
    $statusCount = 0

    while($copyStatus.Status -eq "Pending"){
      $copyStatus = $copyHandle | Get-AzureStorageBlobCopyState

      if($copyStatus.TotalBytes) {
          [int]$perComplete = ($copyStatus.BytesCopied/$copyStatus.TotalBytes)*100
          Write-Progress -Activity "Copying blob..." -status "Percentage Complete" -percentComplete "$perComplete"
      }
      else {
          Write-Output "copyStatus.TotalBytes is not specified."
          Write-Output $copyStatus
      }

      if($perComplete -gt $statusCount) {
          $statusCount = [math]::Ceiling($perComplete) + 3
          Write-Output "%$perComplete percent complete"
      }

      #add a message to help debug long-running copy operations that seem to hang
      Write-Output ("Copied a total of " + $copyStatus.BytesCopied + " of " + $copyStatus.TotalBytes + " bytes")

      Start-Sleep 60
    }

    if($copyStatus.Status -eq "Success") {
      Write-Output ("Successfully copied " + $copyObject.computeDiskname + " at " + (Get-Date -format "h:mm:ss tt"))

      # Copy the companion .json file into the storage account next to the vhd file
      Set-AzureStorageBlobContent -Context $storageContext -File $jsonFilePath -Container 'imagefactoryvhds'
    }
    else {
      if($copyStatus) {
        Write-Output $copyStatus
        Write-Error ("Copy Status for $imageName should be Success but is reported as " + $copyStatus.Status)
      }
      else {  Write-Error "There is no copy status" }
    }
  }
  finally {
    Write-Output "Removing vhd disk lock $($copyObject.computeDiskname) in resource group $($copyObject.computeRGName)"
    Revoke-AzureRmDiskAccess -ResourceGroupName $copyObject.computeRGName -DiskName $copyObject.computeDiskname
  }
}


foreach ($copyObject in $copyObjects) {
  $jobIndex++
  Write-Color -Text "Creating VHD replication job to store VHD $jobIndex of $($copyObjects.Count)" -Color green

  $jobs += Start-Job -ScriptBlock $storeVHD_ScriptBlock -ArgumentList $modulePath, $copyObject
  Start-Sleep -Seconds 3
}

if($jobs.Count -ne 0)
{
    Write-Color -Text "Waiting for VHD replication jobs to complete" -Color yellow
    foreach ($job in $jobs) { Receive-Job $job -Wait | Write-Output }
    Remove-Job -Job $jobs
}
else { Write-Color -Text "No VHDs to replicate" -Color yellow }

Write-Color -Text 'Finished storing sysprepped VHDs' -Color green
