param(
    [switch]$Silent
)

# Install-HostsBlocklist.ps1
# Installs the local files, startup task, and GitHub bootstrap workflow.

$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\HostsBlocklist"
$BackupDir = Join-Path $BaseDir "Backups"

$UpdaterPath = Join-Path $BaseDir "Update-HostsBlocklist.ps1"
$BootstrapPath = Join-Path $BaseDir "Run-HostsBlocklist-FromGitHub.ps1"
$BlockedPath = Join-Path $BaseDir "blocked-domains.txt"
$AllowedPath = Join-Path $BaseDir "allowed-domains.txt"
$VbsPath = Join-Path $BaseDir "Run-HostsBlocklist-Silent.vbs"

$TaskName = "Update Hosts Blocklist At Startup"

$UpdaterUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Update-HostsBlocklist.ps1"
$BootstrapUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Run-HostsBlocklist-FromGitHub.ps1"
$BlockedUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/blocked-domains.txt"
$AllowedUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/allowed-domains.txt"

function Write-Step {
    param([string]$Message)

    if (-not $Silent) {
        Write-Host $Message
    }
}

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Download-RequiredFile {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$Name
    )

    $tempPath = "$DestinationPath.tmp"

    Write-Step "Downloading $Name..."

    Invoke-WebRequest -Uri $Url -OutFile $tempPath -UseBasicParsing -TimeoutSec 90

    if (-not (Test-Path $tempPath)) {
        throw "Download failed for $Name."
    }

    $size = (Get-Item $tempPath).Length

    if ($size -lt 5) {
        throw "Downloaded $Name looks too small."
    }

    Move-Item -Path $tempPath -Destination $DestinationPath -Force
}

function Remove-ScheduledTaskIfExists {
    param([string]$Name)

    cmd.exe /c "schtasks /Query /TN `"$Name`" >nul 2>nul"

    if ($LASTEXITCODE -eq 0) {
        cmd.exe /c "schtasks /Delete /TN `"$Name`" /F >nul 2>nul"
    }
}

try {
    if (-not (Test-IsAdmin)) {
        throw "This installer must be run as Administrator."
    }

    Write-Step ""
    Write-Step "Installing hosts blocklist workflow..."
    Write-Step ""

    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Download-RequiredFile -Url $UpdaterUrl -DestinationPath $UpdaterPath -Name "updater script"
    Download-RequiredFile -Url $BootstrapUrl -DestinationPath $BootstrapPath -Name "GitHub bootstrapper"
    Download-RequiredFile -Url $BlockedUrl -DestinationPath $BlockedPath -Name "blocked domains list"
    Download-RequiredFile -Url $AllowedUrl -DestinationPath $AllowedPath -Name "allowed domains list"

    Write-Step "Creating silent launcher..."

    $vbs = @'
Set shell = CreateObject("WScript.Shell")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\ProgramData\HostsBlocklist\Run-HostsBlocklist-FromGitHub.ps1"" -ForceUpdate"
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
'@

    Set-Content -Path $VbsPath -Value $vbs -Encoding ASCII -Force

    Write-Step "Creating scheduled startup task..."

    Remove-ScheduledTaskIfExists -Name $TaskName

    cmd.exe /c "schtasks /Create /TN `"$TaskName`" /SC ONSTART /DELAY 0005:00 /RU SYSTEM /RL HIGHEST /TR `"wscript.exe C:\ProgramData\HostsBlocklist\Run-HostsBlocklist-Silent.vbs`" /F"

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create scheduled task."
    }

    Write-Step "Running first update..."

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $BootstrapPath -ForceUpdate

    if ($LASTEXITCODE -ne 0) {
        throw "First update failed with exit code $LASTEXITCODE."
    }

    Write-Step ""
    Write-Step "Install completed successfully."
    Write-Step ""
    Write-Step "Installed folder:"
    Write-Step $BaseDir
    Write-Step ""
    Write-Step "Scheduled task:"
    Write-Step $TaskName

    if (-not $Silent) {
        Write-Step ""
        Write-Step "Press Enter to close."
        Read-Host
    }

    exit 0
}
catch {
    Write-Error $_.Exception.Message

    if (-not $Silent) {
        Write-Host ""
        Write-Host "Install failed."
        Write-Host $_.Exception.Message
        Write-Host ""
        Write-Host "Press Enter to close."
        Read-Host
    }

    exit 1
}
