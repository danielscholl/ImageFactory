<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
  .\Retire-Images.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM'; ModuleVersion='6.7.0'}

Param
(
  [Parameter(Mandatory=$true, HelpMessage="The location of the factory configuration files")]
  [string] $ConfigurationLocation,

  [Parameter(Mandatory=$true, HelpMessage="The ID of the subscription containing the Image Factory")]
  [string] $SubscriptionId,

  [Parameter(Mandatory=$true, HelpMessage="The name of the Image Factory DevTest Lab")]
  [string] $DevTestLabName,

  [Parameter(Mandatory=$true, HelpMessage="The number of images to save")]
  [int] $ImagesToSave
)

$ConfigurationLocation = (Resolve-Path $ConfigurationLocation).Path

$functionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "functions.ps1"
if (Test-Path $functionPath) { . $functionPath }

# Get Image Information from Configuration
$imageList = GetImageInfosForLab $DevTestLabName
$goldenImagesFolder = Join-Path $ConfigurationLocation "GoldenImages"
$goldenImageFiles = Get-ChildItem $goldenImagesFolder -Recurse -Filter "*.json" | Select-Object FullName

# Get Lab Information from Configuration
$jsonLabList = Join-Path $ConfigurationLocation "Labs.json"
$labList = ConvertFrom-Json -InputObject (Get-Content $jsonLabList -Raw)
$labRG = (Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $DevTestLabName}).ResourceGroupName


# Compare the list to what is specified in configuration and get things that need to be deleted.
$thingsToDelete = $imageList |  Group-Object {$_.imagePath} |
                                ForEach-Object {$_.Group |
                                Sort-Object timestamp -Descending |
                                Select-Object -Skip $ImagesToSave}

foreach($imageInfo in $imageList) {
    $filePath = Join-Path $goldenImagesFolder $imageInfo.imagePath
    $configFile = $goldenImageFiles | Where-Object {$_.FullName -eq $filePath}
    if(!$configFile)
    {
        Write-Color -Text "Deleting image ", $imageInfo.imageName, " because the json file has been removed" -Color green, yellow, green
        $thingsToDelete = [Array](([Array]$thingsToDelete) + $imageInfo)
    }
}

if($thingsToDelete -and $thingsToDelete.Count -gt 0)
{
  Write-Color -Text "Found ", $thingsToDelete.Count, " JSON Info Objects to delete in the ", $storageAcctName, " storage account" -Color green, yellow, green, yellow, green

  $lab = Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $DevTestLabName}
  $labStorageInfo = GetStorageInfo $lab
  $storageAcctName = $labStorageInfo.storageAcctName
  $storageContext = New-AzureStorageContext -StorageAccountName $storageAcctName -StorageAccountKey $labStorageInfo.storageAcctKey
  $container = 'imagefactoryvhds'

  foreach($thingToDelete in $thingsToDelete) {
    Write-Color -Text "Deleting image ", $thingToDelete.imageName, " from ", $DevTestLabName, " in storage account ", $storageAcctName -Color green, yellow, green, yellow, green, yellow

    $vhdBlobName = $thingToDelete.vhdFileName
    Write-Color -Text "  Deleting ", $vhdBlobName -Color red, yellow
    Remove-AzureStorageBlob -Context $storageContext -Container $container -Blob $vhdBlobName -Force

    $jsonBlobName = $vhdBlobName.Replace('.vhd', '.json')
    Write-Color -Text "  Deleting ", $jsonBlobName -Color red, yellow
    Remove-AzureStorageBlob -Context $storageContext -Container $container -Blob $jsonBlobName -Force
  }
}
else
{
  Write-Color -Text "No files to delete from the ", $DevTestLabName -Color green, yellow
}

$jobs = @()

# Script block for deleting images
$deleteVM_ScriptBlock = {
    Param($imageToDelete)

    if((Get-AzureRmContext).Subscription.Id -ne $imageToDelete.SubscriptionId){
      Write-Output "Switching subscription $($imageToDelete.SubscriptionId)"
      Set-AzureRmContext -SubscriptionId $imageToDelete.SubscriptionId | Out-Null
    }

    Write-Output "Deleting Image: $($imageToDelete.ResourceName)"
    Remove-AzureRmResource -ResourceName $imageToDelete.ResourceName -ResourceGroupName $imageToDelete.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/customImages' -ApiVersion '2016-05-15' -Force
    Write-Output "Deleting Image: $($imageToDelete.ResourceName)"
}


# Add our 'current' lab (the factory lab) to the list of labs we're going to iterate through
$factorylabInfo = (New-Object PSObject |
   Add-Member -PassThru NoteProperty ResourceGroup $labRg |
   Add-Member -PassThru NoteProperty SubscriptionId $SubscriptionId |
   Add-Member -PassThru NoteProperty Labname $DevTestLabName
)

$labList.Labs = ($labList.Labs + $factorylabInfo)
$sortedLabList = $labList.Labs | Sort-Object {$_.SubscriptionId}

<# Sample Lab Object
{
  "SubscriptionId":  "587fe9d7-7309-4503-bc68-b35528a3217a",
  "LabName":  "DevLab",
  "ImagePaths":  "Win2016/SQLServer2017.json Win10/VS2017.json"
}
#>
foreach ($lab in $sortedLabList) {
  SelectSubscription $lab.SubscriptionId
  $labRG = (Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $lab.LabName}).ResourceGroupName
  $labImages = Get-AzureRmResource -ResourceName $lab.LabName -ResourceGroupName $labRG -ResourceType 'Microsoft.DevTestLab/labs/customImages' -ApiVersion '2016-05-15'

  $imagesToDelete = $labImages | Where-Object {$_.Tags } | ForEach-Object { New-Object -TypeName PSObject -Prop @{
    ResourceName=$_.ResourceName
    ResourceGroupName=$_.ResourceGroupName
    SubscriptionId=$_.SubscriptionId
    CreationDate=$_.Properties.CreationDate
    ImagePath=getTagValue $_ 'ImagePath'
  }} |
  Group-Object {$_.ImagePath} |
  ForEach-Object {$_.Group | Sort-Object CreationDate -Descending | Select-Object -Skip $ImagesToSave}

  # Delete the custom images we found in the search above
  foreach ($imageToDelete in $imagesToDelete) {
    $jobs += Start-Job -Name $imageToDelete.ResourceName -ScriptBlock $deleteVM_ScriptBlock -ArgumentList $imageToDelete
  }

  foreach($image in $labImages){
    # If this image is for an ImagePath that no longer exists then delete it. They must have removed this image from the factory
    $imagePath = getTagValue $image 'ImagePath'
    $resName = $image.ResourceName

    if($imagePath) {
      $filePath = Join-Path $goldenImagesFolder $imagePath
      $existingFile = $goldenImageFiles | Where-Object {$_.FullName -eq $filePath}

        if(!$existingFile) {
          # The GoldenImage template for this image has been deleted. We should delete this image (unless we are already deleting it from previous check)
          $alreadyDeletingImage = $imageObjectsToDelete | Where-Object {$_.ResourceName -eq $resName }

          if($alreadyDeletingImage) { Write-Color -Text "Image $resName is for a removed GoldenImage and has also been expired" -Color green }
          else {
            Write-Color "Image $resName is for a removed GoldenImage. Starting job to remove the image." -Color green
            $jobs += Start-Job -Name $image.ResourceName -ScriptBlock $deleteVM_ScriptBlock -ArgumentList $image
          }
        }
        else {
          # If this is an image from a target lab, make sure it has not been removed from the labs.json file
          $labName = $lab.LabName

          if($labName -ne $DevTestLabName) {
            $shouldCopyToLab = ShouldCopyImageToLab -lab $lab -image $imagePath

            if(!$shouldCopyToLab) {
              Write-Color -Text "Adding a job to remove the Image ", $resName, " due to it not being located in Labs.json for ", $labName -Color green, yellow, green, yellow
              $jobs += Start-Job -Name $image.ResourceName -ScriptBlock $deleteVM_ScriptBlock -ArgumentList $image
            }
          }
        }
    }
    else {
      Write-Color -Text "Image ", $resName, " is being ignored because it does not have the ImagePath tag" -color red, yellow, red
    }
  }
}

if($jobs.Count -ne 0)
{
    Write-Color -Text "Waiting for Image deletion jobs to complete" -Color green
    foreach ($job in $jobs) { Receive-Job $job -Wait | Write-Output }
    Remove-Job -Job $jobs
}
else { Write-Color -Text "No images to delete from the Labs!" -Color green }
