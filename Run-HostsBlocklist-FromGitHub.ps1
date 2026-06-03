param(
    [switch]$ForceUpdate
)

# Run-HostsBlocklist-FromGitHub.ps1
# Bootstrapper.
# Downloads the latest GitHub copies of the updater and domain lists.
# If any file changed, it runs the updater with -Force.
# If ForceUpdate is used, it also runs the updater with -Force.
# If nothing changed, it runs the updater normally.

$ErrorActionPreference = "Stop"

$BaseDir = "C:\ProgramData\HostsBlocklist"
$LogPath = Join-Path $BaseDir "bootstrap.log"

$UpdaterPath = Join-Path $BaseDir "Update-HostsBlocklist.ps1"
$BlockedPath = Join-Path $BaseDir "blocked-domains.txt"
$AllowedPath = Join-Path $BaseDir "allowed-domains.txt"

$UpdaterUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Update-HostsBlocklist.ps1"
$BlockedUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/blocked-domains.txt"
$AllowedUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/allowed-domains.txt"

function Write-BootstrapLog {
    param([string]$Message)

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$stamp  $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

function Get-FileSha256 {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function Download-IfChanged {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$Name
    )

    $tempPath = "$DestinationPath.tmp"

    Write-BootstrapLog "Checking latest $Name from GitHub."

    Invoke-WebRequest -Uri $Url -OutFile $tempPath -UseBasicParsing -TimeoutSec 90

    if (-not (Test-Path $tempPath)) {
        throw "Download failed for $Name."
    }

    $size = (Get-Item $tempPath).Length

    if ($size -lt 5) {
        throw "Downloaded $Name looks too small."
    }

    $oldHash = Get-FileSha256 -Path $DestinationPath
    $newHash = Get-FileSha256 -Path $tempPath

    if ($oldHash -eq $newHash) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        Write-BootstrapLog "$Name is already current."
        return $false
    }

    Move-Item -Path $tempPath -Destination $DestinationPath -Force
    Write-BootstrapLog "$Name updated from GitHub."
    return $true
}

try {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null

    Write-BootstrapLog "Starting bootstrap run."

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $changed = $false

    if (Download-IfChanged -Url $UpdaterUrl -DestinationPath $UpdaterPath -Name "updater script") {
        $changed = $true
    }

    if (Download-IfChanged -Url $BlockedUrl -DestinationPath $BlockedPath -Name "blocked domains list") {
        $changed = $true
    }

    if (Download-IfChanged -Url $AllowedUrl -DestinationPath $AllowedPath -Name "allowed domains list") {
        $changed = $true
    }

    if ($ForceUpdate -or $changed) {
        Write-BootstrapLog "Force update requested or GitHub file changes found. Running updater with -Force."

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $UpdaterPath -Force

        if ($LASTEXITCODE -ne 0) {
            throw "Updater failed with exit code $LASTEXITCODE."
        }
    }
    else {
        Write-BootstrapLog "No GitHub file changes found. Running updater normally."

        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $UpdaterPath

        if ($LASTEXITCODE -ne 0) {
            throw "Updater failed with exit code $LASTEXITCODE."
        }
    }

    Write-BootstrapLog "Bootstrap run completed successfully."
    exit 0
}
catch {
    Write-BootstrapLog "ERROR: $($_.Exception.Message)"
    exit 1
}
