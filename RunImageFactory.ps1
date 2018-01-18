Param (
  [Parameter(HelpMessage="The Azure Subscription Id")]
  [string]$Subscription = $Env:AZURE_SUBSCRIPTION,

  [Parameter(HelpMessage="The Azure Region Location")]
  [string]$Location = $Env:AZURE_LOCATION,

  [Parameter(HelpMessage="The Local VM Administrator Name")]
  [string]$AdminUserName = $Env:AZURE_ADMINUSER,

  [Parameter(HelpMessage="The Local VM Administrator Password")]
  [string]$AdminPassword = $Env:AZURE_ADMINPASSWORD,

  [Parameter(Mandatory=$true, HelpMessage="DevTest Lab Name")]
  [string]$DevTestLabName
)

# Source In Environment Variables for Secret Settings
. ./QuickStarts/env.ps1
Get-ChildItem Env:AZURE*

if (!$Subscription) { 
  if (!$Env:AZURE_SUBSCRIPTION) {throw "SubscriptionId Required" }
  else {$Subscription = $Env:AZURE_SUBSCRIPTION}
}
if ( !$Location) {
  if (!$Env:AZURE_LOCATION) {throw "Location Required" }
  else {$Location = $Env:AZURE_LOCATION}
}
if ( !$AdminUserName) {
  if (!$Env:AZURE_ADMINUSER) {throw "AdminUserName Required" }
  else {$AdminUserName = $Env:AZURE_ADMINUSER}
}
if ( !$AdminPassword) {
  if (!$Env:AZURE_ADMINPASSWORD) {throw "AdminPassword Required" }
  else {$AdminPassword = $Env:AZURE_ADMINPASSWORD}
}

# Set Variables
$ConfigFiles = "./Configuration"

Add-AzureRmAccount
Select-AzureRmSubscription -SubscriptionId $Subscription


# Scrape source code control for json files + create all VMs discovered
.\MakeGoldenImageVMs.ps1 -ConfigurationLocation $ConfigFiles `
  -DevTestLabName $DevTestLabName `
  -machineUserName $AdminUserName `
  -machinePassword (ConvertTo-SecureString -String "$AdminPassword" -AsPlainText -Force) `
  -StandardTimeoutMinutes 60 `
  -vmSize "Standard_A3"

# For all running VMs, save as images
.\SnapImagesFromVMs.ps1 -DevTestLabName $DevTestLabName

# For all images, distribute to all labs who have 'signed up' for those images
.\DistributeImages.ps1 -ConfigurationLocation $ConfigFiles `
  -SubscriptionId $Subscription `
  -DevTestLabName $DevTestLabName `
  -maxConcurrentJobs 20

# Clean up any leftover stopped VMs in the factory
.\CleanUpFactory.ps1 -DevTestLabName $DevTestLabName

# Retire all 'old' images from the factory lab and all other connected labs (cascade deletes)
.\RetireImages.ps1  -ConfigurationLocation  $ConfigFiles `
  -SubscriptionId $Subscription `
  -DevTestLabName $DevTestLabName `
  -ImagesToSave 2
