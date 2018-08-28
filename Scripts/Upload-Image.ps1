<#
.Synopsis
   Creates a Virtual Image from a on-prem vhd file
.DESCRIPTION
   This script will import a virtual machine
.EXAMPLE
   ./Upload-Image.ps1
#>

param([string]$Location = "eastus2",
  [string]$vhd = "Win10_Base.vhd",
  [string]$ResourceGroupName = "images",
  [string]$ContainerName = "vhds",
  [string]$StorageType = "Standard_LRS",
  [string]$VhdPath = "C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks\" + $vhd)

function Get-UniqueString ([string]$id, $length=13)
{
    $hashArray = (new-object System.Security.Cryptography.SHA512Managed).ComputeHash($id.ToCharArray())
    -join ($hashArray[1..$length] | ForEach-Object { [char]($_ % 26 + [byte][char]'a') })
}

# Create a Resource Group
Get-AzureRmResourceGroup -Name $ResourceGroupName -ev notPresent -ea 0 | Out-null
if ($notPresent) {
  Write-Warning -Message "Creating Resource Group $ResourceGroupName..."
  New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

$Unique=$(Get-UniqueString -id $(Get-AzureRmResourceGroup -Name $ResourceGroupName))
$StorageName = "$($unique.ToString().ToLower())storage"

# Creating a Storage Account
$StorageAccount = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName
if (!$StorageAccount) {
  Write-Warning -Message "Storage Container $ContainerName not found. Creating the Storage Account $StorageName"
  $StorageAccount = New-AzureRmStorageAccount -Name $StorageName -ResourceGroupName $ResourceGroupName -Location $location -SkuName $StorageType -Kind "Storage"
}


# Creating a Container
$Access = "Off"
$Keys = Get-AzureRmStorageAccountKey -Name $StorageAccount.StorageAccountName -ResourceGroupName $ResourceGroupName
$StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $Keys[0].Value
$Container = Get-AzureStorageContainer -Name $ContainerName -Context $StorageContext -ErrorAction SilentlyContinue
if (!$Container) {
  Write-Warning -Message "Storage Container $ContainerName not found. Creating the Container $ContainerName"
  New-AzureStorageContainer -Name $ContainerName -Context $StorageContext -Permission $Access
}


# Uploading a VHD
$Destination = ('https://' + $StorageAccount.StorageAccountName + '.blob.core.windows.net/' + $ContainerName + '/' + $Vhd)
$Blob = Get-AzureStorageBlob -Container $ContainerName -Context $StorageContext  -Blob $Vhd -ErrorAction Ignore

if (!$Blob) {
  Write-Warning -Message "Storage Blob $Vhd not found. Uploading the VHD $Vhd ...."
  Add-AzureRmVhd -ResourceGroupName $ResourceGroupName -Destination $Destination -LocalFilePath $VhdPath -NumberOfUploaderThreads 4  -Verbose
}


# Get the lab object.
$LabGroup = "ImageFactory"
$LabName = "ImageFactory"
$ImageName = $Vhd.TrimEnd('.vhd')
$ImageDesc = "Uploaded Image"
$lab = Get-AzureRmResource -ResourceId ('/subscriptions/' + (Get-AzureRmContext).Subscription.Id + '/resourceGroups/' + $LabGroup + '/providers/Microsoft.DevTestLab/labs/' + $LabName)

# Get the lab storage account and lab storage account key values.
$labStorageAccount = Get-AzureRmResource -ResourceId $lab.Properties.defaultStorageAccount
$labStorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $labStorageAccount.ResourceGroupName -Name $labStorageAccount.ResourceName)[0].Value

# Set up the parameters object.
$parameters = @{existingLabName="$($lab.Name)"; existingVhdUri=$Destination; imageOsType='windows'; isVhdSysPrepped=$false; imageName=$ImageName; imageDescription=$ImageDesc}
New-AzureRmResourceGroupDeployment -ResourceGroupName $lab.ResourceGroupName -Name CreateCustomImage -TemplateUri 'https://raw.githubusercontent.com/Azure/azure-devtestlab/master/Samples/201-dtl-create-customimage-from-vhd/azuredeploy.json' -TemplateParameterObject $parameters

exit

# Create a managed image from the uploaded VHD
$ImageName = $Vhd.TrimEnd('.vhd')
$Image = Get-AzureRmImage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -ErrorAction Ignore
if (!$Image) {
  Write-Warning -Message "Image $Image not found. Creating the Image $ImageName ...."
  $ImageConfig = New-AzureRmImageConfig -Location $Location
  $ImageConfig = Set-AzureRmImageOsDisk -Image $ImageConfig -OsType Windows -OsState Generalized -BlobUri $Destination
  New-AzureRmImage -ImageName $imageName -ResourceGroupName $ResourceGroupName -Image $imageConfig
}
