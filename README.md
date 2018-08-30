# Image Factory

This Repository is a reworked ImageFactory script base upgraded to PowerShell AzureRM version 6.7.

_Read the Fantastic Blog Series to see how you can integrate into VSTS for no touch automation builds._

- [Image Factory Blog Series](https://blogs.msdn.microsoft.com/devtestlab/tag/image-factory-series/)


__Requirements:__

1. [Windows Powershell](https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell?view=powershell-5.1)

```powershell
  $PSVersionTable.PSVersion

  # Result
  Major  Minor  Build  Revision
  -----  -----  -----  --------
  5      1      17134  248
```

2. [Azure PowerShell Modules](https://www.powershellgallery.com/packages/Azure/5.1.1)

```powershell
  Get-Module AzureRM -list | Select-Object Name,Version

  # Result
  Name  Version
  ----  -------
  Azure 6.7.0
```

3. [AzureRM Powershell Modules](https://www.powershellgallery.com/packages/AzureRM/5.1.1)

```powershell
  Get-Module AzureRM.* -list | Select-Object Name,Version

  # Filtered Results
  Name                                  Version
  ----                                  -------
  AzureRM.Compute                       5.5.0
  AzureRM.DevTestLabs                   4.0.7
  AzureRM.KeyVault                      5.1.1
  AzureRM.Network                       5.4.1
  AzureRM.Profile                       5.4.0
  AzureRM.Resources                     6.4.0
  AzureRM.Storage                       5.0.2
```

4. Install Required PowerShell Modules if needed

```powershell
Install-Module AzureRM -RequiredVersion 6.7.0
Import-Module AzureRM -RequiredVersion 6.7.0
```

1. Setup a Private env.ps1 file to source in private settings from environment variabls for use in the project.

Copy env_sample.ps1 to env.ps1 and modify it as appropriate

```powershell
###############################################################################################################
# Environment Settings ########################################################################################

$Env:AZURE_SUBSCRIPTION = "<your_subscription_id>"                          # Azure Desired Subscription Id
$Env:AZURE_LOCATION = "<your_region>"                                       # Azure Desired Region
$Env:AZURE_ADMINUSER = "<local_admin_user>"                                 # Virtual Machine Local Admin UserName
$Env:AZURE_ADMINPASSWORD = "<local_admin_password>"                         # Virtual Machine Local Admin Password

###############################################################################################################
```

2. Setup a DevTest Lab to use as an Imaging Factory.

```powershell
# Source into the shell your environment variables
. .\env.ps1 

# Build a DevTest Lab
./Make-Lab.ps1
```

3. Setup a DevTest Lab(s) to use as a Personal Lab

```powershell
# Source into the shell your environment variables
. .\env.ps1 

# Build a Development Lab
.\Make-Lab -ResourceGroupName DevLab

# Build a Test Lab
.\Make-Lab -ResourceGroupName TestLab
```

4. Subscribe your lab for deployment by defining your lab and desired images into the Labs.json file.

.\Configuration\Labs.json
```javascript
{
  "Labs": [{
    "SubscriptionId": "<your_subscription_id>",
    "LabName": "DevLab",
    "ImagePaths": [
      "Win10/VS2017.json",
      "Win2016/Datacenter.json"
    ]
  },
  {
    "SubscriptionId": "<your_subscription_id>",
    "LabName": "TestLab",
    "ImagePaths": [
      "Win10/VS2017.json"
    ]
  }]
}
```

5. Run the Image Factory

```powershell
./Run-Factory.ps1
```



