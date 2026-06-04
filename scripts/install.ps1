param(
  [string]$Version = "latest",
  [string]$InstallDir = $env:CONTROLKEEL_INSTALL_DIR,
  [string]$Repository = $(if ($env:CONTROLKEEL_GITHUB_REPO) { $env:CONTROLKEEL_GITHUB_REPO } else { "aryaminus/controlkeel" })
)

$ErrorActionPreference = "Stop"

function Get-DefaultInstallDir {
  if ($InstallDir) {
    return $InstallDir
  }

  return (Join-Path $env:LOCALAPPDATA "Programs\ControlKeel")
}

function Get-ReleaseBaseUrl {
  if ($Version -eq "latest") {
    return "https://github.com/$Repository/releases/latest/download"
  }

  return "https://github.com/$Repository/releases/download/v$Version"
}

$AssetName = "controlkeel-windows-x86_64.exe"
$DestinationRoot = Get-DefaultInstallDir
$Destination = Join-Path $DestinationRoot "controlkeel.exe"
$BaseUrl = Get-ReleaseBaseUrl
$DownloadUrl = "$BaseUrl/$AssetName"

# Verify the download against the published controlkeel-checksums.txt before
# moving it into place. Fails closed: missing checksums, missing entry, or a
# mismatch all abort. Set $env:CONTROLKEEL_SKIP_CHECKSUM=1 to bypass.
function Confirm-Checksum {
  param([string]$FilePath, [string]$Asset, [string]$BaseUrl)

  if ($env:CONTROLKEEL_SKIP_CHECKSUM -eq "1") {
    Write-Warning "CONTROLKEEL_SKIP_CHECKSUM=1 set; skipping integrity verification"
    return
  }

  $checksumsPath = Join-Path ([System.IO.Path]::GetTempPath()) "controlkeel-checksums.txt"
  try {
    Invoke-WebRequest -Uri "$BaseUrl/controlkeel-checksums.txt" -OutFile $checksumsPath
  }
  catch {
    throw "Could not download checksums for integrity verification. Set `$env:CONTROLKEEL_SKIP_CHECKSUM=1 to bypass (not recommended)."
  }

  $expected = $null
  foreach ($line in Get-Content $checksumsPath) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -eq 2) {
      $name = ($parts[1].Trim() -split '[\\/]')[-1]
      if ($name -eq $Asset) { $expected = $parts[0].Trim(); break }
    }
  }

  if (-not $expected) {
    throw "No checksum entry for $Asset; refusing to install."
  }

  $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
  if ($actual -ine $expected) {
    throw "Checksum mismatch for $Asset.`n  expected: $expected`n  actual:   $actual"
  }

  Write-Host "Verified $Asset (sha256 $actual)"
}

New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null

$TempFile = Join-Path ([System.IO.Path]::GetTempPath()) "controlkeel-$([System.Guid]::NewGuid().ToString('N')).exe"
try {
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempFile
  Confirm-Checksum -FilePath $TempFile -Asset $AssetName -BaseUrl $BaseUrl
  Move-Item -Path $TempFile -Destination $Destination -Force
}
finally {
  if (Test-Path $TempFile) { Remove-Item $TempFile -Force -ErrorAction SilentlyContinue }
}

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $UserPath) {
  $UserPath = ""
}

if (-not (($UserPath -split ";") -contains $DestinationRoot)) {
  $UpdatedPath = if ([string]::IsNullOrWhiteSpace($UserPath)) {
    $DestinationRoot
  }
  else {
    "$UserPath;$DestinationRoot"
  }

  [Environment]::SetEnvironmentVariable("Path", $UpdatedPath, "User")
  Write-Host "Added $DestinationRoot to the user PATH. Open a new shell to pick it up."
}

Write-Host "Installed ControlKeel to $Destination"
Write-Host ""
Write-Host "Next steps — wire ControlKeel into your agent host:"
Write-Host ""
Write-Host "  1. Attach to the agent you use (one or more):"
Write-Host "       controlkeel attach claude-code"
Write-Host "       controlkeel attach cursor"
Write-Host "       controlkeel attach codex-cli"
Write-Host "       controlkeel attach opencode"
Write-Host "       controlkeel attach copilot"
Write-Host ""
Write-Host "  2. Optional - sync governance evidence to a control plane:"
Write-Host "       controlkeel cloud connect --enroll https://controlkeel.com"
Write-Host "     (or your self-host URL, e.g. https://govern.acme.com)"
Write-Host ""
Write-Host "  3. Verify everything is healthy:"
Write-Host "       controlkeel cloud doctor"
Write-Host ""
Write-Host "Run 'controlkeel --help' for the full surface."
