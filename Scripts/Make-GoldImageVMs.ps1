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
    [Parameter(Mandatory=$true, HelpMessage="The location of the factory configuration files")]
    [string] $ConfigurationLocation,

    [Parameter(Mandatory=$true, HelpMessage="The name of the lab")]
    [string] $DevTestLabName,

    [Parameter(Mandatory=$true, HelpMessage="The admin username for the VM")]
    [string] $AdminUserName,

    [Parameter(Mandatory=$true, HelpMessage="The admin password for the VM")]
    [System.Security.SecureString] $AdminPassword,

    [Parameter(Mandatory=$true, HelpMessage="The number of minutes to wait before timing out Azure operations")]
    [int] $StandardTimeoutMinutes,

    [Parameter(HelpMessage="The name of the lab")]
    [string] $Size = "Standard_A3",

    [Parameter(HelpMessage="Specifies whether or not to sysprep the created VMs")]
    [boolean] $includeSysprep = $true

)


$ConfigurationLocation = (Resolve-Path $ConfigurationLocation).Path
$scriptFolder = Split-Path $Script:MyInvocation.MyCommand.Path

$functionPath = Join-Path (Split-Path ($Script:MyInvocation.MyCommand.Path)) "functions.ps1"
if (Test-Path $functionPath) { . $functionPath }

$makeVM_script = Join-Path $scriptFolder "Make-Machine.ps1"
$imageListLocation = Join-Path $ConfigurationLocation "GoldenImages"
$files = Get-ChildItem $imageListLocation -Recurse -Filter "*.json"

$createdVms = New-Object System.Collections.ArrayList
$usedVmNames = @()
$jobList = @()
foreach ($file in $files)
{
  # Grab the image path relative to the GoldenImages folder
  $imagePath = $file.FullName.Substring($imageListLocation.Length + 1)

  # Extract the VM name for each file
  $vmName = $file.BaseName.Replace("_", "").Replace(" ", "").Replace(".", "")
  $intName = 0
  if ([System.Int32]::TryParse($vmName, [ref]$intName))
  {
    Write-Output "Adding prefix to vm named $vmName because it cannot be fully numeric"
    $vmName = ('vm' + $vmName)
  }

  if($vmName.Length -gt 15) {
    $shortenedName = $vmName.Substring(0, 13)
    Write-Output "VM name $vmName is too long. Shortening to $shortenedName"
    $vmName = $shortenedName
  }

  while ($usedVmNames.Contains($vmName)){
    $nameRoot = $vmName
    if($vmName.Length -gt 12) { $nameRoot = $vmName.Substring(0, 12) }

    $updatedName = $nameRoot + (Get-Random -Minimum 1 -Maximum 999).ToString("000")
    Write-Output "VM name $vmName has already been used. Reassigning to $updatedName"
    $vmName = $updatedName
  }
  $usedVmNames += $vmName

  Write-Output "Starting job to create a VM named $vmName for $imagePath"
  $jobList += Start-Job -Name $file.Name -FilePath $makeVM_script `
    -ArgumentList `
      $functionPath, `
      $file.FullName, `
      $DevTestLabName, `
      $vmName, `
      $imagePath, `
      $AdminUserName, `
      $AdminPassword, `
      $Size, `
      $includeSysprep
}

Write-Output "Waiting for $($jobList.Count) VM creation jobs to complete"

foreach ($job in $jobList) {
  $jobOutput = Receive-Job $job -Wait
  Write-Output $jobOutput

  $createdVMName = $jobOutput[$jobOutput.Length - 1]
  if($createdVMName) { $createdVms.Add($createdVMName) }
}

Remove-Job -Job $jobList
