<#
.SYNOPSIS
  Infrastructure DevLab QuickStart Deployment
.DESCRIPTION
  Set Environment Variables or pass parameters.
  $Env:AZURE_SUBSCRIPTION = "<your_sub_id>"
  $Env:AZURE_LOCATION = "southcentralus"

.EXAMPLE
  .\Make-Lab.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM'; ModuleVersion='6.7.0'}

Param(
  [string]$Subscription = $Env:AZURE_SUBSCRIPTION,
  [string]$Location = $Env:AZURE_LOCATION,
  [string]$ResourceGroupName = "ImageFactory"
)

if ( !$Subscription) { throw "Subscription Required" }
if ( !$ResourceGroupName) { throw "ResourceGroupName Required" }
if ( !$Location) { throw "Location Required" }


###############################
## Azure Intialize           ##
###############################
$functionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "scripts/functions.ps1"
if (Test-Path $functionPath) { . $functionPath }

$BASE_DIR = Split-Path ($Script:MyInvocation.MyCommand.Path)
$DEPLOYMENT = Split-Path $BASE_DIR -Leaf

LoginAzure $Subscription
CreateResourceGroup $ResourceGroupName $Location


##############################
## Deploy Template          ##
##############################
Write-Color -Text "`r`n---------------------------------------------------- "-Color Yellow
Write-Color -Text "Deploying ", "deployLab.json ", "template..." -Color Green, Red, Green
Write-Color -Text "---------------------------------------------------- "-Color Yellow
New-AzureRmResourceGroupDeployment -Name $DEPLOYMENT `
  -TemplateFile $BASE_DIR\Templates\deployLab.json `
  -LabName $ResourceGroupName `
  -ResourceGroupName $ResourceGroupName
