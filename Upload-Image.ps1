<#
.Synopsis
   Creates a Virtual Image from an on-premesis vhd file
.DESCRIPTION
   This script will import a virtual machine from a VHD File

   *** ASSUMES THE IMAGE IS SYSPREPPED ****
.EXAMPLE
   ./Upload-Image.ps1
#>

Param(
  [Parameter(Mandatory=$true, HelpMessage="The name of the lab")]
  [string] $DevTestLabName,

  [Parameter(HelpMessage="The location for the Image Group")]
  [string]$Location = "eastus2",

  [Parameter(HelpMessage="The Local Machine Path for where VHD's are found")]
  [string]$LocalPath = "C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks\",

  [Parameter(HelpMessage="The VHD File Name to be uploaded")]
  [string]$vhd = "Win10_Base.vhd"
)

$BASE_DIR = Split-Path ($Script:MyInvocation.MyCommand.Path)
$ImageName = $Vhd.TrimEnd('.vhd')
$ImageDesc = "Uploaded Image"


# Get or Create a TestLab.
$Lab = Get-AzureRmResource -ResourceId ('/subscriptions/' + (Get-AzureRmContext).Subscription.Id + '/resourceGroups/' + $DevTestLabName + '/providers/Microsoft.DevTestLab/labs/' + $DevTestLabName)
if (!$Lab) {
  Write-Warning -Message "DevTest Lab $Lab not found. Creating the DevTest Lab $Lab"
  ./Make-Lab.ps1
}

# Get StorageAccount and Ensure Container Exists
$ContainerName = "uploads"
$Access = "Off"

$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $Lab.ResourceGroupName
$Keys = Get-AzureRmStorageAccountKey -Name $StorageAccount.StorageAccountName -ResourceGroupName $Lab.ResourceGroupName
$StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $Keys[0].Value
$Container = Get-AzureStorageContainer -Name $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue
if (!$Container) {
  Write-Warning -Message "Storage Container $ContainerName not found. Creating the Container $ContainerName"
  New-AzureStorageContainer -Name $ContainerName -Context $StorageContext -Permission $Access
}

# Get or Upload a VHD
$Destination = ('https://' + $StorageAccount.StorageAccountName + '.blob.core.windows.net/' + $ContainerName + '/' + $Vhd)
$Blob = Get-AzureStorageBlob -Container $ContainerName -Context $StorageContext  -Blob $Vhd -ErrorAction Ignore
if (!$Blob) {
  $VhdPath = $LocalPath + $Vhd
  Write-Warning -Message "Storage Blob $Vhd not found. Uploading the VHD $Vhd ...."
  Add-AzureRmVhd -ResourceGroupName $Lab.ResourceGroupName -Destination $Destination -LocalFilePath $VhdPath -NumberOfUploaderThreads 4  -Verbose
}

# Create an Image
New-AzureRmResourceGroupDeployment -Name $Vhd `
  -ResourceGroupName $lab.ResourceGroupName  `
  -TemplateFile $BASE_DIR\Templates\deployImageFromVhd.json `
  -existingLabName $DevTestLabName `
  -existingVhdUri $Destination `
  -imageName $ImageName `
  -imageDescription $ImageDesc `
  -imagePath $Vhd
