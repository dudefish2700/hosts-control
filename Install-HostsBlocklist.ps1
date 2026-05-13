# Install-HostsBlocklist.ps1
# Downloads the latest hosts-control setup from GitHub,
# installs it to C:\ProgramData\HostsBlocklist,
# creates a silent startup scheduled task,
# and runs the first update.
param(
    [switch]$Silent
)
$ErrorActionPreference = "Stop"

$InstallDir = "C:\ProgramData\HostsBlocklist"
$BackupDir = Join-Path $InstallDir "Backups"

$ScriptDest = Join-Path $InstallDir "Update-HostsBlocklist.ps1"
$BlockedDest = Join-Path $InstallDir "blocked-domains.txt"
$AllowedDest = Join-Path $InstallDir "allowed-domains.txt"
$LauncherDest = Join-Path $InstallDir "Run-HostsBlocklist-Silent.vbs"

$TaskName = "Update Hosts Blocklist At Startup"

$RemoteScriptUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Update-HostsBlocklist.ps1"
$RemoteBlockedUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/blocked-domains.txt"
$RemoteAllowedUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/allowed-domains.txt"

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination
    )

    $temp = "$Destination.tmp"

    Invoke-WebRequest -Uri $Url -OutFile $temp -UseBasicParsing -TimeoutSec 120

    if (-not (Test-Path $temp)) {
        throw "Download failed: $Url"
    }

    $size = (Get-Item $temp).Length

    if ($size -lt 5) {
        throw "Downloaded file is too small: $Url"
    }

    Move-Item -Path $temp -Destination $Destination -Force
}

function Remove-ScheduledTaskIfExists {
    param([string]$Name)

    cmd.exe /c "schtasks /Query /TN `"$Name`" >nul 2>nul"

    if ($LASTEXITCODE -eq 0) {
        cmd.exe /c "schtasks /Delete /TN `"$Name`" /F >nul 2>nul"
    }
}

if (-not (Test-IsAdmin)) {
    throw "This installer must be run as Administrator."
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

Write-Host "Downloading latest setup files..." -ForegroundColor Cyan

Download-File -Url $RemoteScriptUrl -Destination $ScriptDest
Download-File -Url $RemoteBlockedUrl -Destination $BlockedDest
Download-File -Url $RemoteAllowedUrl -Destination $AllowedDest

Write-Host "Creating silent launcher..." -ForegroundColor Cyan

@'
Set shell = CreateObject("WScript.Shell")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""C:\ProgramData\HostsBlocklist\Update-HostsBlocklist.ps1"""
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
'@ | Set-Content -Path $LauncherDest -Encoding ASCII -Force

Write-Host "Creating scheduled task..." -ForegroundColor Cyan

Remove-ScheduledTaskIfExists -Name $TaskName

$OldWord = -join ([char[]](80,111,114,110))
$OldDailyTask = "Update Anti-$OldWord Hosts File"
$OldStartupTask = "Update Anti-$OldWord Hosts File At Startup"

Remove-ScheduledTaskIfExists -Name $OldDailyTask
Remove-ScheduledTaskIfExists -Name $OldStartupTask

cmd.exe /c "schtasks /Create /TN `"$TaskName`" /SC ONSTART /DELAY 0005:00 /RU SYSTEM /RL HIGHEST /TR `"wscript.exe C:\ProgramData\HostsBlocklist\Run-HostsBlocklist-Silent.vbs`" /F"

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create scheduled task."
}

Write-Host "Running first update. This may take a while..." -ForegroundColor Cyan

powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptDest -Force

Write-Host ""
Write-Host "Installed successfully." -ForegroundColor Green
Write-Host ""
Write-Host "Installed files:"
Write-Host $ScriptDest
Write-Host $BlockedDest
Write-Host $AllowedDest
Write-Host $LauncherDest
Write-Host ""
Write-Host "Scheduled task:"
schtasks /Query /TN "$TaskName" /V /FO LIST

Write-Host ""
Write-Host "Recent log:"
Get-Content "C:\ProgramData\HostsBlocklist\update.log" -Tail 10 -ErrorAction SilentlyContinue

if (-not $Silent) {
    Write-Host ""
    Write-Host "Press Enter to close."
    Read-Host
}
