<#
.SYNOPSIS
  ImageFactory Control Script
.DESCRIPTION

.EXAMPLE
  .\Run-ImageFactory.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM'; ModuleVersion='6.7.0'}

Param (
  [Parameter(HelpMessage="The Azure Subscription Id")]
  [string]$Subscription = $Env:AZURE_SUBSCRIPTION,

  [Parameter(HelpMessage="The Azure Region Location")]
  [string]$Location = $Env:AZURE_LOCATION,

  [Parameter(HelpMessage="The Local VM Administrator Name")]
  [string]$AdminUserName = $Env:AZURE_ADMINUSER,

  [Parameter(HelpMessage="The Local VM Administrator Password")]
  [securestring]$AdminPassword = (ConvertTo-SecureString -String "$Env:AZURE_ADMINPASSWORD" -AsPlainText -Force),

  [Parameter(HelpMessage="DevTest Lab Name")]
  [string]$DevTestLabName = "ImageFactory",

  [Parameter(HelpMessage="Show Environment Variables")]
  [string]$ShowEnv = $false
)

if($ShowEnv -eq $true) {Get-ChildItem Env:AZURE*}

# Test for Required Environment Settings
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


###############################
## Azure Intialize           ##
###############################
$ConfigFiles = "./Configuration"
$functionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "Scripts/functions.ps1"
if (Test-Path $functionPath) { . $functionPath }
LoginAzure $Subscription


##############################
## Execute SubScripts       ##
##############################

# Scrape source code control for json files + create all VMs discovered
# .\Scripts\Make-GoldImageVMs.ps1 -ConfigurationLocation $ConfigFiles `
#   -DevTestLabName $DevTestLabName `
#   -AdminUserName $AdminUserName `
#   -AdminPassword $AdminPassword `
#   -StandardTimeoutMinutes 60

# For all created VMs, save as images
# .\Scripts\Snap-Image.ps1 -DevTestLabName $DevTestLabName

# For all images, distribute to all labs that have 'signed up' for the image
# .\Scripts\Distribute-Image.ps1 -ConfigurationLocation $ConfigFiles `
#   -SubscriptionId $Subscription `
#   -DevTestLabName $DevTestLabName `
#   -MaxJobs 20

# Clean up any leftover stopped VMs in the factory
#.\Scripts\CleanUp-Factory.ps1 -DevTestLabName $DevTestLabName

##  TODO STILL
# Retire all 'old' images from the factory lab and all other connected labs (cascade deletes)
.\Scripts\Retire-Images.ps1  -ConfigurationLocation  $ConfigFiles `
  -SubscriptionId $Subscription `
  -DevTestLabName $DevTestLabName `
  -ImagesToSave 2
