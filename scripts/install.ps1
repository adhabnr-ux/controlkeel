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

$DestinationRoot = Get-DefaultInstallDir
$Destination = Join-Path $DestinationRoot "controlkeel.exe"
$DownloadUrl = "$(Get-ReleaseBaseUrl)/controlkeel-windows-x86_64.exe"

New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null
Invoke-WebRequest -Uri $DownloadUrl -OutFile $Destination

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
