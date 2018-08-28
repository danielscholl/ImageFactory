<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
  .\Distribute-Image.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM'; ModuleVersion='6.7.0'}

param
(
    [Parameter(Mandatory=$true, HelpMessage="The location of the factory configuration files")]
    [string] $ConfigurationLocation,

    [Parameter(Mandatory=$true, HelpMessage="The ID of the subscription containing the images")]
    [string] $SubscriptionId,

    [Parameter(Mandatory=$true, HelpMessage="The name of the lab")]
    [string] $DevTestLabName,

    [Parameter(Mandatory=$true, HelpMessage="The number of script blocks we can run in parallel")]
    [int] $MaxJobs
)

<# Sample StorageInfo Object
  ----------------------
    storageAcctName: alab3637

    Name  : resourceGroupName
    Value : lab

    Name  : storageAcctKey
    Value : {a_storage_key}
#>

<# Sample LabInfo Object
  ----------------------
    SubscriptionId : 67e82f75-4ce1-49e1-943e-37d4491aa83c
    LabName        : Lab
    ImagePaths     : {Win10/custombox.json}
#>

<# Sample ImageInfo Object
  ----------------------
    timestamp   : 8/24/2018 1:14:33 PM
    description : Windows 10 with Visual Studio
    osType      : Windows
    imageName   : Win10_custombox-Aug-24-2018
    imagePath   : Win10\custombox.json
    vhdFileName : c3870516-4428-45e1-97a7-e44aaf43a0f9.vhd
#>

$ErrorActionPreference = 'Continue'
$ConfigurationLocation = (Resolve-Path $ConfigurationLocation).Path
$scriptFolder = Split-Path $Script:MyInvocation.MyCommand.Path

$functionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "functions.ps1"
if (Test-Path $functionPath) { . $functionPath }

# Get Factory Information
$factory = Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $DevTestLabName}
$factoryStorageInfo = GetStorageInfo $factory

# Get Image Information from Configuration
$imageList = GetImageInfosForLab $DevTestLabName
$goldenImagesFolder = Join-Path $ConfigurationLocation "GoldenImages"

# Get Lab Information from Configuration
$jsonLabList = Join-Path $ConfigurationLocation "Labs.json"
$labList = ConvertFrom-Json -InputObject (Get-Content $jsonLabList -Raw)
validateImages $labList.Labs
validateLabs $labList.Labs
Write-Color -Text "Found ", @($labList.Labs).Length, " target lab." -color green, yellow, green
$sortedLabList = $labList.Labs | Sort-Object {$_.SubscriptionId}

$copyList = New-Object System.Collections.ArrayList

foreach ($labInfo in $sortedLabList) {

  foreach ($imageInfo in $imageList) {

    $copyToLab = ShouldCopyImageToLab $labInfo $imageInfo.imagePath

    if($copyToLab -eq $true) {
      # Switch over to Specified Lab
      SelectSubscription $labInfo.SubscriptionId

      # Retrieve and test if exists the Target Lab Resource Group
      $labRG = (Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $labInfo.LabName}).ResourceGroupName
      if(!$labRG) { Write-Color -Text "Unable to find lab: ", $labInfo.LabName, " in subscription: ", $labInfo.SubscriptionId -Color red, yellow, red, yellow }

      # Retrieve the Target Lab and Get StorageInfo
      $lab = Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' -ResourceName $labInfo.LabName -ResourceGroupName $labRG
      $labStorageInfo = GetStorageInfo $lab


      # Retrieve and test if exists the Target Image
      $existingTargetImage = Get-AzureRmResource -ResourceName $labInfo.LabName -ResourceGroupName $labRG -ResourceType 'Microsoft.DevTestLab/labs/customImages' -ApiVersion '2016-05-15' | Where-Object {$_.Name -eq $imageInfo.imageName}
      if($existingTargetImage) {
        Write-Color -Text $imageInfo.imageName, " has been found in the ", $labinfo.LabName, " NO OVERWRITE!!" -Color yellow, green, yellow, red
        continue;
      }

      # Test to see that the Lab is the same location as the factory.
      if( $factory.Location -ne $lab.Location){
        Write-Color -Text "Location Mismatch. ", "$($factory.Name) is in $($factory.Location) but $($lab.Name) is in $($lab.Location)" -Color red, yellow
        continue;
      }

      # Setup the DTO and add it to our list
      $dto = @{
        imageName         = $imageInfo.imageName
        imageDescription  = $imageInfo.description
        imagePath         = $imageInfo.imagePath
        osType            = $imageInfo.osType
        vhdFileName       = $imageInfo.vhdFileName
        isVhdSysPrepped   = $true

        sourceSubscriptionId      = $SubscriptionId
        sourceLabName             = $factory.Name
        sourceResourceGroup       = $factory.ResourceGroupName
        sourceStorageAccountName  = $factoryStorageInfo.storageAcctName
        sourceStorageKey          = $factoryStorageInfo.storageAcctKey

        destSubscriptionId        = $labInfo.SubscriptionId
        destLabName               = $lab.Name
        destResourceGroup         = $lab.ResourceGroupName
        destStorageAccountName    = $labStorageInfo.storageAcctName
        destStorageKey            = $labStorageInfo.storageAcctKey
      }
      $copyList.Add($dto) | Out-Null
    }
  }
}

$jobs = @()

<#
  This is the script block that will run in a background job.  We can fire off the copy as a parallel background job.
#>
$copyVHD_ScriptBlock = {
  Param($dto, $scriptFolder)
  $container = "imagefactoryvhds"

  $srcContext = New-AzureStorageContext -StorageAccountName $dto.sourceStorageAccountName -StorageAccountKey $dto.sourceStorageKey
  $srcURI = $srcContext.BlobEndPoint + "$container/" + $dto.vhdFileName

  $destContext = New-AzureStorageContext -StorageAccountName $dto.destStorageAccountName -StorageAccountKey $dto.destStorageKey
  New-AzureStorageContainer -Context $destContext -Name $container -ErrorAction Ignore

  $job_handle = Start-AzureStorageBlobCopy -srcUri $srcURI -SrcContext $srcContext -DestContainer $container -DestBlob $dto.vhdFileName -DestContext $destContext -Force

  Write-Output ("Started copying " + $dto.vhdFileName + " to " + $dto.targetStorageAccountName + " at " + (Get-Date -format "h:mm:ss tt"))
  $job = $job_handle | Get-AzureStorageBlobCopyState
  $statusCount = 0

  while($job.Status -eq "Pending") {
    $job = $job_handle | Get-AzureStorageBlobCopyState
    [int]$perComplete = ($job.BytesCopied/$job.TotalBytes)*100

    Write-Progress -Activity "Copying blob..." -status "Percentage Complete" -percentComplete "$perComplete"

    if($perComplete -gt $statusCount) {
      $statusCount = [math]::Ceiling($perComplete) + 3
      Write-Output "%$perComplete percent complete"
    }

    Start-Sleep 30
  }

  if($job.Status -eq "Success") {
    Write-Output ($dto.vhdFileName + " successfully copied to Lab " + $dto.targetLabName + ". Deploying image " + $dto.imageName)

    # Now that we have a VHD in the right storage account we need to create the actual image by deploying an ARM template
    Write-Output "Switching subscription $($dto.destSubscriptionId)"
    Set-AzureRmContext -SubscriptionId $dto.destSubscriptionId | Out-Null

    $templatePath = Join-Path $scriptFolder "../Templates/deployImage.json"
    $vhdUri = $destContext.BlobEndPoint + "$container/" + $dto.vhdFileName

    $deployName = "Deploy-$($dto.imageName)"
    $deployResult = New-AzureRmResourceGroupDeployment -Name $deployName `
                      -ResourceGroupName $dto.destResourceGroup `
                      -TemplateFile $templatePath `
                      -existingLabName $dto.destLabName `
                      -existingVhdUri $vhdUri `
                      -imageOsType $dto.osType `
                      -isVhdSysPrepped $dto.isVhdSysPrepped `
                      -imageName $dto.imageName `
                      -imageDescription $dto.imageDescription `
                      -imagePath $dto.imagePath

    # Delete the deployment information so that we dont use up the total deployments for this resource group
    Remove-AzureRmResourceGroupDeployment -ResourceGroupName $dto.destResourceGroup -Name $deployName  -ErrorAction SilentlyContinue | Out-Null

    if($deployResult.ProvisioningState -eq "Succeeded"){
        Write-Output "Image successfully deployed. Deleting copied VHD"
        Remove-AzureStorageBlob -Context $destContext -Container $container -Blob $dto.vhdFileName
        Write-Output "VHD sucessfully deleted"
    }
    else { Write-Error "Image deploy failed. We should stop now" }
  }
}

$copyCount = $copyList.Count
$jobIndex = 0

foreach ($dto in $copyList) {

  # Do not start more than $MaxJobs at one time
  while ((Get-Job -State 'Running').Count -ge $MaxJobs){
    Write-Color -Text "Throttling background tasks after starting ", $jobIndex, " of ", $copyCount, " tasks" -Color green, yellow, green, yellow, green
    Start-Sleep -Seconds 30
  }

  $jobIndex++
  Write-Color -Text "Creating background task to distribute image ", $jobIndex, " of ", $copyCount -Color green, yello, green, yellow
  $jobs += Start-Job -ScriptBlock $copyVHD_ScriptBlock -ArgumentList $dto, $scriptFolder
}

if($jobs.Count -ne 0)
{
  Write-Color -Text "Waiting for ", $($jobs.Count), " Image replication jobs to complete" -Color green, yellow, green
  foreach ($job in $jobs){
    Receive-Job $job -Wait | Write-Output
  }
  Remove-Job -Job $jobs
}
else
{
  Write-Color -Text "No images to distribute" -Color Green
}


foreach ($dto in $copyList)
{
    SelectSubscription $dto.destSubscriptionId

    # Remove the root container from the target labs since we dont need it any more
    $storageContext = New-AzureStorageContext -StorageAccountName $dto.destStorageAccountName -StorageAccountKey $dto.destStorageKey
    $container = "imagefactoryvhds"

    $rootContainer = Get-AzureStorageContainer -Context $storageContext -Name $container -ErrorAction Ignore
    if($rootContainer -ne $null)
    {
        Write-Color -Text "Deleting the $container container in the lab storage account" -green
        Remove-AzureStorageContainer -Context $storageContext -Name $container -Force
    }

}

Write-Color -Text "Distribution of ", $jobs.Count, " images is complete" -Color green, yellow, green
