###############################
## FUNCTIONS                 ##
###############################
function Write-Color([String[]]$Text, [ConsoleColor[]]$Color = "White", [int]$StartTab = 0, [int] $LinesBefore = 0, [int] $LinesAfter = 0, [string] $LogFile = "", $TimeFormat = "yyyy-MM-dd HH:mm:ss") {
  # version 0.2
  # - added logging to file
  # version 0.1
  # - first draft
  #
  # Notes:
  # - TimeFormat https://msdn.microsoft.com/en-us/library/8kb3ddd4.aspx

  $DefaultColor = $Color[0]
  if ($LinesBefore -ne 0) {  for ($i = 0; $i -lt $LinesBefore; $i++) { Write-Host "`n" -NoNewline } } # Add empty line before
  if ($StartTab -ne 0) {  for ($i = 0; $i -lt $StartTab; $i++) { Write-Host "`t" -NoNewLine } }  # Add TABS before text
  if ($Color.Count -ge $Text.Count) {
    for ($i = 0; $i -lt $Text.Length; $i++) { Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine }
  }
  else {
    for ($i = 0; $i -lt $Color.Length ; $i++) { Write-Host $Text[$i] -ForegroundColor $Color[$i] -NoNewLine }
    for ($i = $Color.Length; $i -lt $Text.Length; $i++) { Write-Host $Text[$i] -ForegroundColor $DefaultColor -NoNewLine }
  }
  Write-Host
  if ($LinesAfter -ne 0) {  for ($i = 0; $i -lt $LinesAfter; $i++) { Write-Host "`n" } }  # Add empty line after
  if ($LogFile -ne "") {
    $TextToFile = ""
    for ($i = 0; $i -lt $Text.Length; $i++) {
      $TextToFile += $Text[$i]
    }
    Write-Output "[$([datetime]::Now.ToString($TimeFormat))]$TextToFile" | Out-File $LogFile -Encoding unicode -Append
  }
}

function LoginAzure ([string] $Subscription) {
  # Required Argument $1 = Subscription

  if (!$Subscription) { throw "Subscription Required" }
  Write-Color -Text "Logging in and setting subscription..." -Color Green
  if ([string]::IsNullOrEmpty($(Get-AzureRmContext).Account)) {Login-AzureRmAccount}
  Set-AzureRmContext -SubscriptionId $Subscription | Out-null
}
function CreateResourceGroup([string]$ResourceGroupName, [string]$Location) {
  # Required Argument $1 = RESOURCE_GROUP
  # Required Argument $2 = LOCATION

  Get-AzureRmResourceGroup -Name $ResourceGroupName -ev notPresent -ea 0 | Out-null

  if ($notPresent) {
    Write-Host "Creating Resource Group $ResourceGroupName..." -ForegroundColor Yellow
    New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
  }
  else {
    Write-Color -Text "Resource Group ", "$ResourceGroupName ", "already exists." -Color Green, Red, Green
  }
}

function SelectSubscription($Subscription) {
  # Required Argument $1 = Subscription

  if((Get-AzureRmContext).Subscription.Id -ne $Subscription){
    Write-Color -Text "Switching subscription ", $Subscription -Color green, yellow
    Set-AzureRmContext -SubscriptionId $Subscription | Out-Null
  }
}

function makeUpdatedTemplateFile ($origTemplateFile, $outputFile)
{
  $armTemplate = Get-Content -Raw -Encoding Ascii $origTemplateFile | ConvertFrom-Json

  # Modify the template and add the Sysprep or deprovision artifact to the list of artifacts for the VM
  $newArtifact = @{}
  if ($armTemplate.resources[0].properties.galleryImageReference.osType -eq 'Windows')
  {
      $artifactName = 'windows-sysprep'
  }
  else
  {
      $artifactName = 'linux-deprovision'
  }

  $fullArtifactId = "[resourceId('Microsoft.DevTestLab/labs/artifactSources/artifacts', parameters('labName'), 'public repo', '$artifactName')]"
  $newArtifact.artifactId = $fullArtifactId
  $existingArtifacts = $armTemplate.resources[0].properties.artifacts

  if (!$existingArtifacts -or $existingArtifacts.Count -eq 0)
  {
    Write-Color -Text "Adding the artifact: ", "$artifactName ", "$origTemplateFile" -Color green, yellow, cyan
    $artifactCollection = New-Object System.Collections.ArrayList
    $artifactCollection.Add($newArtifact)
    $armTemplate.resources[0].properties | Add-Member -Type NoteProperty -name 'artifacts' -Value $artifactCollection -Force
  }
  elseif ($existingArtifacts[$existingArtifacts.count - 1].artifactId -eq $fullArtifactId)
  {
    Write-Color -Text "$origTemplateFile already has the Sysprep/Deprovision artifact. It will not be added again" -Color Green
  }
  else
  {
      # The ARM template does not end with the sysprep/deprovision artifact. We will add it
      # this is the common case
      Write-Color -Text "Adding $artifactName artifact to ",  "$origTemplateFile" -Color Green, Cyan
      $armTemplate.resources[0].properties.artifacts += $newArtifact
  }

  Write-Color -Text "Writing modified ARM template to ", "$outputFile" -Color Green, Cyan
  ($armTemplate | ConvertTo-Json -Depth 100 | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }).Replace('\', '\\') | Out-File $outputFile
}


function GetStorageInfo ($lab)
{
    $labRgName= $lab.ResourceGroupName
    $sourceLab = Get-AzureRmResource -ResourceName $lab.Name -ResourceGroupName $labRgName -ResourceType 'Microsoft.DevTestLab/labs'
    $storageAcctValue = $sourceLab.Properties.artifactsStorageAccount
    $storageAcctName = $storageAcctValue.Substring($storageAcctValue.LastIndexOf('/') + 1)

    $storageAcct = (Get-AzureRMStorageAccountKey  -StorageAccountName $storageAcctName -ResourceGroupName $labRgName)
    $storageAcctKey = $storageAcct.Value[0]

    $result = @{
        resourceGroupName = $labRgName
        storageAcctName = $storageAcctName
        storageAcctKey = $storageAcctKey
    }
    return $result
}

function EnsureRootContainerExists ($labStorageInfo)
{
    $storageContext = New-AzureStorageContext -StorageAccountName $labStorageInfo.storageAcctName -StorageAccountKey $labStorageInfo.storageAcctKey
    $rootContainerName = 'imagefactoryvhds'
    $rootContainer = Get-AzureStorageContainer -Context $storageContext -Name $rootContainerName -ErrorAction Ignore
    if($rootContainer -eq $null)
    {
        Write-Color -Text "Creating the ", "$rootContainerName", " container in the target storage account" -Color green, yellow, green
        $rootContainer = New-AzureStorageContainer -Context $storageContext -Name $rootContainerName
    }
}

function GetImageInfosForLab ($DevTestLabName)
{
    $lab = Get-AzureRmResource -ResourceType 'Microsoft.DevTestLab/labs' | Where-Object { $_.Name -eq $DevTestLabName}
    $labRgName= $lab.ResourceGroupName
    $sourceLab = Get-AzureRmResource -ResourceName $DevTestLabName -ResourceGroupName $labRgName -ResourceType 'Microsoft.DevTestLab/labs'
    $storageAcctValue = $sourceLab.Properties.artifactsStorageAccount
    $storageAcctName = $storageAcctValue.Substring($storageAcctValue.LastIndexOf('/') + 1)

    $storageAcct = (Get-AzureRMStorageAccountKey  -StorageAccountName $storageAcctName -ResourceGroupName $labRgName)
    $storageAcctKey = $storageAcct.Value[0]

    $storageContext = New-AzureStorageContext -StorageAccountName $storageAcctName -StorageAccountKey $storageAcctKey

    $rootContainerName = 'imagefactoryvhds'

    $jsonBlobs = Get-AzureStorageBlob -Context $storageContext -Container $rootContainerName -Blob '*json'

    Write-Color -Text "Downloading ", @($jsonBlobs).Length, " json files from factory storage." -Color green, yellow, green
    $downloadFolder = Join-Path $env:TEMP 'ImageFactoryDownloads'
    if(Test-Path -Path $downloadFolder)
    {
        Remove-Item $downloadFolder -Recurse | Out-Null
    }
    New-Item -Path $downloadFolder -ItemType Directory | Out-Null
    $jsonBlobs | Get-AzureStorageBlobContent -Destination $downloadFolder | Out-Null

    $sourceImageInfos = @()

    $downloadedFileNames = Get-ChildItem -Path $downloadFolder
    foreach($file in $downloadedFileNames)
    {
        $imageObj = (Get-Content $file.FullName -Raw) | ConvertFrom-Json
        $imageObj.timestamp = [DateTime]::Parse($imageObj.timestamp)
        $sourceImageInfos += $imageObj
    }

    return $sourceImageInfos
}

function getTagValue($resource, $tagName){
  $result = $null
  if ($resource.Tags){
      $result = $resource.Tags | Where-Object {$_.Name -eq $tagName}
      if($result){
          $result = $result.Value
      }
      else {
          $result = $resource.Tags[$tagName]
      }
  }
  $result
}

function GetImageName ($imagePathValue)
{
    $splitImagePath = $imagePathValue.Split('\')
    if($splitImagePath.Length -eq 1){
        #the image is directly in the GoldenImages folder. Just use the file name as the image name.
        $imagename = $splitImagePath[0]
    }
    else {
        #this image is in a folder within GoldenImages. Name the image <FolderName>  <fileName> with <FolderName> set to the name of the folder that contains the image
        $segmentCount = $splitImagePath.Length
        $imagename = $splitImagePath[$segmentCount - 2] + "_" + $splitImagePath[$segmentCount - 1]
    }

    #clean up some special characters in the image name and stamp it with todays date
    $imagename = $imagename.Replace(".json", "").Replace(".", "_").Replace(" ", "-")
    $imagename = $imagename +  "-" + (Get-Date -Format 'MMM-d-yyyy')
    return $imagename
}

function ShouldCopyImageToLab ($lab, $imagePathValue)
{
  $retval = $false
  foreach ($labImagePath in $lab.ImagePaths) {
    if ($imagePathValue.StartsWith($labImagePath.Replace("/", "\"))) {
      $retVal = $true;
      break;
    }
  }
  $retval
}

function validateImages($labs)
{
  # Iterate through each of the ImagePath entries in the lab and make sure that it points to at least one existing json file
  $goldenImageFiles = Get-ChildItem $goldenImagesFolder -Recurse -Filter "*.json" | Select-Object FullName

  foreach ($lab in $labs){
    foreach ($labImagePath in $lab.ImagePaths) {
      $filePath = Join-Path $goldenImagesFolder $labImagePath
      $matchingImages = $goldenImageFiles | Where-Object {$_.FullName.StartsWith($filePath,"CurrentCultureIgnoreCase")}

      if($matchingImages.Count -eq 0) {
        $labName = $lab.LabName
        Write-Color -Text "The Lab named ", $labName, " contains an ImagePath entry ", $labImagePath, " which does not point to any existing files in the GoldenImages folder." -Color red, yellow, red, yellow, red
      }
    }
  }
}
function validateLabs($labs)
{
  # Iterate through each of the ImagePath entries in the lab and make sure that it points to at least one existing json file
  $goldenImageFiles = Get-ChildItem $goldenImagesFolder -Recurse -Filter "*.json" | Select-Object FullName

  foreach($goldenImage in $goldenImageFiles)
  {
    # Find labs that references this image. If we dont find one, log an error.
    $foundLab = $false
    $imageRelativePath = $goldenImage.FullName.Substring($goldenImagesFolder.Length)
    if($imageRelativePath.StartsWith('\')) { $imageRelativePath = $imageRelativePath.Substring(1) }
    $imageRelativePath = $imageRelativePath.Replace('\', '/')

    foreach($lab in $labs) {
      if(!$foundLab) {
        foreach ($labImagePath in $lab.ImagePaths) {
          if($imageRelativePath.StartsWith($labImagePath)) {
            $foundLab = $true
            break
          }
        }
      }
    }

    if(!$foundLab) { Write-Color -Text "Labs.json does not include any labs that reference ", $($goldenImage.FullName) -Color red, yellow }
  }
}
