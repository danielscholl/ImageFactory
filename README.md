# Image Factory

This Repository is a reworked ImageFactory script base upgraded to PowerShell AzureRM version 6.7.


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

_Read the Blog Series to see how you can integrate into VSTS for no touch automation builds._

- [Image Factory Blog Series](https://blogs.msdn.microsoft.com/devtestlab/tag/image-factory-series/)

