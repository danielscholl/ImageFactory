# Introduction
Infrastructure as Code - Dev Test Lab

## Scripted Deployment

1. __Deploy Template using PowerShell Scripts__

```powershell
./install.ps1
```

## Manual Deploment

1. __Modify Template Parameters as desired__

2. __Create Company Resource Goup__

```powershell
Login-AzureRMAccount

$ResourceGroupName = 'MyLab'
$Location = 'southcentralus'
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
```

3. __Deploy Template to Resource Group__

```powershell
New-AzureRmResourceGroupDeployment -Name iac-devtestLab `
  -TemplateFile azuredeploy.json `
  -TemplateParameterFile azuredeploy.parameters.json `
  -ResourceGroupName $ResourceGroupName 
```
