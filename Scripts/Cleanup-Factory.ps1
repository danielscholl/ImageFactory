<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
  .\Cleanup-Factory.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM'; ModuleVersion='6.7.0'}

Param
(
    [Parameter(Mandatory=$true, HelpMessage="The name of the DevTest Lab to clean up")]
    [string] $DevTestLabName
)

$functionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "functions.ps1"
if (Test-Path $functionPath) { . $functionPath }

$vmList = Get-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceGroupName $DevTestLabName
$jobs = @()

$deleteVM_ScriptBlock = {
  Param($machine)

  Write-Output "Start Delete: $($machine.ResourceName)"
  Remove-AzureRmResource -ResourceId $machine.ResourceId -ApiVersion 2016-05-15 -Force
  Write-Output "End Delete: $($machine.ResourceName)"
}

foreach ($machine in $vmList) {
    $ignoreTagName = 'FactoryIgnore'

    $factoryIgnoreTag = GetTagValue $machine $ignoreTagName
    $imagePathTag = GetTagValue $machine 'ImagePath'
    $provisionState = (Get-AzureRmResource -ResourceId $machine.ResourceId).Properties.ProvisioningState

    if(($provisionState -ne "Succeeded") -and ($provisionState -ne "Creating")) {
      # Provisioning Failures.
      Write-Color -Text "Failed to provision properly.  Performing Machine Delete", $machine -Color green, yellow

      $jobs += Start-Job -ScriptBlock $deleteVM_ScriptBlock -ArgumentList $machine
    }
    elseif(!$factoryIgnoreTag -and !$imagePathTag) {
      # Machine not tagged.
      Write-Color -Text $machine.ResourceName, " is not recognized in the lab.  You should tag it using $ignoreTagName" -Color yellow, red
    }
    elseif($factoryIgnoreTag) {
      # Machine tagged
      Write-Output "Ignoring VM $($machine.ResourceName) because it has the $ignoreTagName tag"
    }
    else {
      Write-Color -Text "Performing Machine Delete ", $machine.ResourceName -Color green, yellow
      $jobs += Start-Job -ScriptBlock $deleteVM_ScriptBlock -ArgumentList $machine
    }
}

if($jobs.Count -ne 0) {
  Write-Color -Text "Waiting for VM Delete jobs to complete" -Color green

  foreach ($job in $jobs) { Receive-Job $job -Wait | Write-Output }
  Remove-Job -Job $jobs
}
else { Write-Color -Text "No VMs to delete" -Color green }

Write-Color -Text "Cleanup complete" -Color green
