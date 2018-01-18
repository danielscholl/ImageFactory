# Image Factory

This Repository is to play with Image Factories provided by Azure DevTest Labs.


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
. .\QuickStarts\env.ps1 

# Build a DevTest Lab
.\QuickStarts\iac-devtestLab\install.ps1 -ResourceGroupName imageFactory
```

3. Setup a DevTest Lab to use as a Personal Lab

>Note: This can be in an alternate subscription as long as the tenant of the logged in user has access to the subscription.

```powershell
# Source into the shell your environment variables
. .\QuickStarts\env.ps1 

# Build a DevTest Lab
.\QuickStarts\iac-devtestLab\install.ps1 -ResourceGroupName myLab
```

4. Subscribe your lab for deployment by defining your lab and desired images into the Labs.json file.

.\Configuration\Labs.json
```javascript
{
  "Labs": [{
    "ResourceGroup": "<your_lab_group>",
    "SubscriptionId": "<your_subscription_id>",
    "LabName": "<your_lab_name>",
    "ImagePaths": [
      "Win10/VS2017.json",
      "Win2016/Datacenter.json"
    ]
  }]
}
```

5. Run the Image Factory

```powershell
./RunImageFactory.ps1
```

_Track the Blog Series to see how you can integrate into VSTS for no touch automation builds._

- [Image Factory Part 1](https://blogs.msdn.microsoft.com/devtestlab/2016/09/14/introduction-get-vms-ready-in-minutes-by-setting-up-image-factory-in-azure-devtest-labs/)

- [Image Factory Part 2](https://blogs.msdn.microsoft.com/devtestlab/2017/10/25/image-factory-part-2-setup-vsts-to-create-vms-based-on-devtest-labs/)