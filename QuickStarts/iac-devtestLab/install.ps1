<#
.SYNOPSIS
  Infrastructure QuickStart
.DESCRIPTION
  Set Environment Variables or pass parameters.
  $Env:AZURE_SUBSCRIPTION = "<your_sub_id>"
  $Env:AZURE_LOCATION = "southcentralus"

.EXAMPLE
  .\install.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM.Resources'; ModuleVersion='5.0'}

Param(
  [string]$Subscription = $Env:AZURE_SUBSCRIPTION,
  [string]$Location = $Env:AZURE_LOCATION,
  [Parameter(Mandatory=$true)]
  [string]$ResourceGroupName
)

if ( !$Subscription) { throw "Subscription Required" }
if ( !$ResourceGroupName) { throw "ResourceGroupName Required" }
if ( !$Location) { throw "Location Required" }


###############################
## Azure Intialize           ##
###############################
$FunctionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "../functions.psm1"
Import-Module $FunctionPath -Force

$BASE_DIR = Split-Path ($Script:MyInvocation.MyCommand.Path)
$DEPLOYMENT = Split-Path $BASE_DIR -Leaf

LoginAzure $Subscription
CreateResourceGroup $ResourceGroupName $Location


##############################
## Deploy Template          ##
##############################
Write-Color -Text "`r`n---------------------------------------------------- "-Color Yellow
Write-Color -Text "Deploying ", "$DEPLOYMENT ", "template..." -Color Green, Red, Green
Write-Color -Text "---------------------------------------------------- "-Color Yellow
New-AzureRmResourceGroupDeployment -Name $DEPLOYMENT `
  -TemplateFile $BASE_DIR\azuredeploy.json `
  -TemplateParameterFile $BASE_DIR\azuredeploy.parameters.json `
  -labName $ResourceGroupName `
  -ResourceGroupName $ResourceGroupName
