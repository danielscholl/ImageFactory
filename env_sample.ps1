###############################################################################################################
# Environment Settings ########################################################################################

$Env:AZURE_SUBSCRIPTION = "<your_subscription_id>"                          # Azure Desired Subscription Id
$Env:AZURE_LOCATION = "<your_region>"                                       # Azure Desired Region
$Env:AZURE_ADMINUSER = "<local_admin_user>"                                 # Virtual Machine Local Admin UserName
$Env:AZURE_ADMINPASSWORD = "<local_admin_password>"                         # Virtual Machine Local Admin Password

###############################################################################################################
Get-ChildItem Env:AZURE*
