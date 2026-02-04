param(
  [string]$InstallDir = "$env:USERPROFILE\\OrcaSlicerPortable",
  [string]$Repo = "MeharPro/orca-config",
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Get-GitHubJson([string]$Url) {
  $headers = @{
    "Accept" = "application/vnd.github+json"
    "User-Agent" = "orca-config-installer"
  }
  return Invoke-RestMethod -Uri $Url -Headers $headers
}

Write-Host "Fetching latest mirrored release from $Repo..."
$release = Get-GitHubJson "https://api.github.com/repos/$Repo/releases/latest"

$assetCandidates = $release.assets |
  Where-Object { $_.name -match "(?i)portable" -and $_.name -match "(?i)win" } |
  Sort-Object -Property @{ Expression = {
      if ($_.name -match "(?i)\\.zip$") { 2 }
      elseif ($_.name -match "(?i)\\.7z$") { 1 }
      else { 0 }
    }; Descending = $true
  }, @{ Expression = "size"; Descending = $true }

$asset = $assetCandidates | Select-Object -First 1

if (-not $asset) {
  throw "Could not find a Windows Portable asset on the latest release of $Repo."
}

if ((Test-Path $InstallDir) -and (-not $Force)) {
  $existing = Get-ChildItem -Path $InstallDir -Force -ErrorAction SilentlyContinue
  if ($existing -and $existing.Count -gt 0) {
    throw "InstallDir '$InstallDir' is not empty. Re-run with -Force to overwrite."
  }
}

$zipName = $asset.name
$zipUrl = $asset.browser_download_url

$tempDir = Join-Path $env:TEMP "orca-config"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$zipPath = Join-Path $tempDir $zipName

Write-Host "Downloading $zipName..."
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -Headers @{ "User-Agent" = "orca-config-installer" }

Write-Host "Extracting to $InstallDir..."
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if ($zipName -match "(?i)\\.zip$") {
  Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
} elseif ($zipName -match "(?i)\\.7z$") {
  $sevenZip = Get-Command "7z" -ErrorAction SilentlyContinue
  if (-not $sevenZip) {
    throw "Asset is a .7z archive, but '7z' is not in PATH. Install 7-Zip or download the .zip variant."
  }
  & $sevenZip.Source x $zipPath "-o$InstallDir" -y | Out-Null
} else {
  throw "Unknown archive type: $zipName"
}

# If the user cloned this repo and runs the script from it, copy their custom configs alongside the install.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$configSource = Join-Path $repoRoot "configs"

if (Test-Path $configSource) {
  $configTarget = Join-Path $InstallDir "user-configs"
  New-Item -ItemType Directory -Force -Path $configTarget | Out-Null
  Copy-Item -Recurse -Force (Join-Path $configSource "*") $configTarget
  Write-Host "Copied configs into: $configTarget"
}

Write-Host "Done."
