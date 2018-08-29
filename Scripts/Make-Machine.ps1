<#
.SYNOPSIS

.DESCRIPTION

.EXAMPLE
  .\Make-GoldImageVMs.ps1
  Version History
  v1.0   - Initial Release
#>
#Requires -Version 5.1
#Requires -Module @{ModuleName='AzureRM'; ModuleVersion='6.7.0'}

Param
(
  [Parameter(Mandatory=$true, HelpMessage="The full path to the module to import")]
  [string] $ModulePath,

  [Parameter(Mandatory=$true, HelpMessage="The full path of the template file")]
  [string] $TemplateFilePath,

  [Parameter(Mandatory=$true, HelpMessage="The name of the lab")]
  [string] $DevTestLabName,

  [Parameter(Mandatory=$true, HelpMessage="The name of the VM to create")]
  [string] $vmName,

  [Parameter(Mandatory=$true, HelpMessage="The path to the image file")]
  [string] $imagePath,

  [Parameter(Mandatory=$true, HelpMessage="The admin username for the VM")]
  [string] $machineUserName,

  [Parameter(Mandatory=$true, HelpMessage="The admin password for the VM")]
  [System.Security.SecureString] $machinePassword,

  [Parameter(Mandatory=$true, HelpMessage="The name of the lab")]
  [string] $vmSize,

  [boolean] $includeSysprep = $false
)

if (Test-Path $ModulePath) { . $ModulePath }

Write-Color -Text "`r`n---------------------------------------------------- "-Color Yellow
Write-Color -Text "         LabVm ARM Template Deployment Start         " -Color Green
Write-Color -Text "---------------------------------------------------- "-Color Yellow

$existingVms = Get-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceName $DevTestLabName | Where-Object { $_.Name -eq "$DevTestLabName/$vmName"}

# Fall out if the VM exists already
if($existingVms.Count -ne 0){
  Write-Color -Text "Factory VM creation failed because there is an existing VM named $vmName in Lab $DevTestLabName" -Color Red
  return ""
}
else {
  $deployName = "Deploy-$vmName"
  $ResourceGroupName = (Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $DevTestLabName}).ResourceGroupName
  $updatedTemplateFilePath = $TemplateFilePath

  if($includeSysprep) {
    Write-Color -Text "Adding sysprep step" -Color green
    $updatedTemplateFilePath = [System.IO.Path]::GetTempFileName()
    makeUpdatedTemplateFile $TemplateFilePath $updatedTemplateFilePath
  }


  Write-Color -Text "Sent Group Deployment: ", "$deployName" -Color green, yellow
  $vmDeployResult = New-AzureRmResourceGroupDeployment -Name $deployName -ResourceGroupName $ResourceGroupName -TemplateFile $updatedTemplateFilePath -labName $DevTestLabName -newVMName $vmName  -userName $machineUserName -password $machinePassword -size $vmSize


  # Clean up the deployment so we don't run out on the group.
  Write-Color -Text "Deployment Success! Starting Cleanup.... " -Color green
  Remove-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $deployName  -ErrorAction SilentlyContinue | Out-Null


  if($vmDeployResult.ProvisioningState -eq "Succeeded") {

    Write-Color -Text "Determining artifact status." -Color green
    $existingVm = Get-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs/virtualMachines" -ResourceName "$DevTestLabName/$vmName"


    # Determine Artifact Deployment Success
    $filter = '$expand=Properties($expand=ComputeVm,NetworkInterface,Artifacts)'
    $vmResource = Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs/virtualmachines' -Name $existingVm.Name -ResourceGroupName $existingVm.ResourceGroupName -ExpandProperties
    $existingVmArtStatus = $vmResource.Properties.ArtifactDeploymentStatus

    Write-Color -Text 'Artifact Deployment Status:' -color red
    Write-Color -Text "---------------------------------------------" -color blue
    Write-Output ('  ArtifactDeploymentStatus: ' + $existingVmArtStatus.deploymentStatus)


    foreach($artifact in $vmResource.Properties.artifacts)
    {
      $artifactShortId = $artifact.artifactId.Substring($artifact.artifactId.LastIndexOf('/', $artifact.artifactId.LastIndexOf('/', $artifact.artifactId.LastIndexOf('/')-1)-1))
      $artifactStatus = $artifact.status
      Write-Color -Text "    Artifact result: $artifactStatus  $artifactShortId " -Color yellow
    }


    if ($existingVmArtStatus.totalArtifacts -eq 0 -or $existingVmArtStatus.deploymentStatus -eq "Succeeded")
    {
      Write-Color -Text "Successfully deployed $vmName from $imagePath" -Color Green
      Write-Color -Text "Stamping the VM $vmName with originalImageFile $imagePath" -Color Green

      $tags = $existingVm.Tags
      if((get-command -Name 'New-AzureRmResourceGroup').Parameters["Tag"].ParameterType.FullName -eq 'System.Collections.Hashtable'){
        $tags += @{ImagePath=$imagePath}
      }
      else {
        # older versions of the cmdlets use a hashtable array to represent the Tags
        $tags += @{Name="ImagePath";Value="$imagePath"}
      }

      Write-Color -Text "Getting resource ID from Existing Vm" -Color Green
      $vmResourceId = $existingVm.ResourceId
      Write-Color -Text "Resource ID: ", "$vmResourceId" -Color Green, Cyan
      Set-AzureRmResource -ResourceId $vmResourceId -Tag $tags -Force | Out-Null
    }
    else {
      if ($existingVmArtStatus.deploymentStatus -ne "Succeeded") {
        Write-Color -Text ("Artifact deployment status is: " + $existingVmArtStatus.deploymentStatus) -Color red
      }

      Write-Color -Text "Deploying VM artifacts failed. $vmName from $TemplateFilePath. Failure details follow:" -Color red
      $failedArtifacts = ($vmResource.Properties.Artifacts | Where-Object {$_.status -ne "Succeeded"})

      if($failedArtifacts -ne $null) {
        foreach($failedArtifact in $failedArtifacts) {
          if($failedArtifact.status -eq 'Pending') {
            Write-Color -Text ('Pending Artifact ID: ' + $failedArtifact.artifactId) -color cyan
          }
          elseif($failedArtifact.status -eq 'Skipped') {
            Write-Color -Text ('Skipped Artifact ID: ' + $failedArtifact.artifactId) -color yellow
          }
          else {
            Write-Color -Text ('Failed Artifact ID: ' + $failedArtifact.artifactId) -color red
            Write-Color -Text ('   Artifact Status: ' + $failedArtifact.status) -color red
            Write-Color -Text ('   DeploymentStatusMessage:  ' + $failedArtifact.deploymentStatusMessage) -color red
            Write-Color -Text ('   VmExtensionStatusMessage: ' + $failedArtifact.vmExtensionStatusMessage) -color red
            Write-Color -Text '' -color red
          }
        }
      }

      Write-Color -Text "Deleting VM $vmName after failed artifact deployment" -Color Green
      Remove-AzureRmResource -ResourceId $existingVm.ResourceId -ApiVersion 2016-05-15 -Force
    }
  }
  else {
    Write-Color -Text "Deploying VM failed:  ", "$vmName", " $TemplateFilePath" -Color red, yellow, cyan
  }

  return $vmName
}
