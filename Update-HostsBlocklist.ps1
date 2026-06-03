param(
    [switch]$Force
)

# Update-HostsBlocklist.ps1
# Downloads a HOSTS blocklist from GitHub, backs up the current hosts file,
# downloads editable blocked/allowed domain lists from your GitHub repo,
# applies local policy entries, then flushes DNS.
# Startup runs are skipped unless the last successful update was 7+ days ago.
# Manual forced run:
# powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\HostsBlocklist\Update-HostsBlocklist.ps1 -Force

$ErrorActionPreference = "Stop"

$MinimumDaysBetweenRuns = 7

# Upstream source: StevenBlack hosts alternate list.
$RepoOwner = "StevenBlack"
$RepoName = "hosts"
$Category = -join ([char[]](112,111,114,110))

$SourceUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/master/alternates/$Category/hosts"
$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

$BaseDir = "C:\ProgramData\HostsBlocklist"
$BackupDir = Join-Path $BaseDir "Backups"
$DownloadPath = Join-Path $BaseDir "HOSTS.download.txt"
$LogPath = Join-Path $BaseDir "update.log"
$LastSuccessPath = Join-Path $BaseDir "last_success.txt"

$BlockedDomainsFile = Join-Path $BaseDir "blocked-domains.txt"
$AllowedDomainsFile = Join-Path $BaseDir "allowed-domains.txt"

$RemoteBlockedDomainsUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/blocked-domains.txt"
$RemoteAllowedDomainsUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/allowed-domains.txt"

$LocalStartMarker = "# BEGIN MANAGED LOCAL HOSTS POLICY"
$LocalEndMarker   = "# END MANAGED LOCAL HOSTS POLICY"

$BlockStartMarker = "# BEGIN MANAGED HOSTS BLOCKLIST"
$BlockEndMarker   = "# END MANAGED HOSTS BLOCKLIST"

$OldWord = -join ([char[]](80,111,114,110))
$OldStartMarker = "# BEGIN MANAGED ANTI-$OldWord HOSTS BLOCK"
$OldEndMarker   = "# END MANAGED ANTI-$OldWord HOSTS BLOCK"

function Write-Log {
    param([string]$Message)

    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$stamp  $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-ManagedBlock {
    param(
        [string]$Text,
        [string]$Start,
        [string]$End
    )

    $escapedStart = [regex]::Escape($Start)
    $escapedEnd = [regex]::Escape($End)
    $pattern = "(?s)\r?\n?$escapedStart.*?$escapedEnd\r?\n?"

    return [regex]::Replace($Text, $pattern, "`r`n")
}

function Normalize-Domain {
    param([string]$Text)

    if ($null -eq $Text) {
        return $null
    }

    $domain = $Text.Trim().ToLower()

    if ($domain -eq "") {
        return $null
    }

    if ($domain.StartsWith("#")) {
        return $null
    }

    $domain = $domain -replace '^https?://', ''
    $domain = $domain.Split('/')[0]
    $domain = $domain.Split(':')[0]
    $domain = $domain.Trim().TrimEnd('.')

    if ($domain -match '^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$') {
        return $domain
    }

    return $null
}

function Ensure-BlockedDomainsFile {
    param([string]$Path)

    if (Test-Path $Path) {
        return
    }

    $DefaultLines = @(
        "# One blocked domain per line.",
        "# Blank lines and lines starting with # are ignored.",
        "# Do not include 0.0.0.0 here. The script adds that automatically.",
        "",
        "duckduckgo.com",
        "www.duckduckgo.com",
        "start.duckduckgo.com"
    )

    $DefaultLines | Set-Content -Path $Path -Encoding ASCII -Force
}

function Ensure-AllowedDomainsFile {
    param([string]$Path)

    if (Test-Path $Path) {
        return
    }

    $DefaultLines = @(
        "# One allowed domain per line.",
        "# Blank lines and lines starting with # are ignored.",
        "# If you add example.com, the script also allows subdomains like www.example.com.",
        "",
        "# Add allowlist exceptions below this line:"
    )

    $DefaultLines | Set-Content -Path $Path -Encoding ASCII -Force
}

function Download-RemoteListFile {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$FriendlyName
    )

    $tempPath = "$DestinationPath.tmp"

    try {
        Write-Log "Downloading remote $FriendlyName list."
        Invoke-WebRequest -Uri $Url -OutFile $tempPath -UseBasicParsing -TimeoutSec 90

        if (-not (Test-Path $tempPath)) {
            throw "Remote $FriendlyName list download did not create a file."
        }

        $size = (Get-Item $tempPath).Length

        if ($size -lt 5) {
            throw "Remote $FriendlyName list looks too small: $size bytes."
        }

        Move-Item -Path $tempPath -Destination $DestinationPath -Force
        Write-Log "Remote $FriendlyName list updated locally."
    }
    catch {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        Write-Log "WARNING: Could not update remote $FriendlyName list. Keeping existing local file. Error: $($_.Exception.Message)"

        if (-not (Test-Path $DestinationPath)) {
            throw "Remote $FriendlyName list failed and no local fallback file exists."
        }
    }
}

function Read-DomainFile {
    param([string]$Path)

    $results = @()

    if (-not (Test-Path $Path)) {
        return $results
    }

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $domain = Normalize-Domain -Text $line

        if ($null -ne $domain) {
            $results += $domain
        }
    }

    return @($results | Select-Object -Unique)
}

function Build-DomainLookup {
    param([string[]]$Domains)

    $lookup = @{}

    foreach ($domain in $Domains) {
        if (-not $lookup.ContainsKey($domain)) {
            $lookup[$domain] = $true
        }
    }

    return $lookup
}

function Test-DomainAllowed {
    param(
        [string]$Domain,
        [hashtable]$AllowedLookup
    )

    if ($null -eq $Domain -or $Domain -eq "") {
        return $false
    }

    $domainLower = $Domain.Trim().ToLower()

    if ($AllowedLookup.ContainsKey($domainLower)) {
        return $true
    }

    $parts = $domainLower.Split('.')

    for ($i = 1; $i -lt $parts.Count; $i++) {
        $suffix = ($parts[$i..($parts.Count - 1)] -join ".")

        if ($AllowedLookup.ContainsKey($suffix)) {
            return $true
        }
    }

    return $false
}

function Read-BlockedDomainsFile {
    param(
        [string]$Path,
        [hashtable]$AllowedLookup
    )

    $results = @()
    $skippedAllowed = 0

    if (-not (Test-Path $Path)) {
        return @{
            Lines = $results
            SkippedAllowed = $skippedAllowed
        }
    }

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $domain = Normalize-Domain -Text $line

        if ($null -eq $domain) {
            continue
        }

        if (Test-DomainAllowed -Domain $domain -AllowedLookup $AllowedLookup) {
            $skippedAllowed++
            continue
        }

        $results += "0.0.0.0 $domain"
    }

    return @{
        Lines = @($results | Select-Object -Unique)
        SkippedAllowed = $skippedAllowed
    }
}

function Should-Skip-Update {
    if ($Force) {
        return $false
    }

    if (-not (Test-Path $LastSuccessPath)) {
        return $false
    }

    $raw = [System.IO.File]::ReadAllText($LastSuccessPath).Trim()

    if ($raw -eq "") {
        return $false
    }

    $lastRun = [datetime]::Parse($raw)
    $nextAllowedRun = $lastRun.AddDays($MinimumDaysBetweenRuns)

    if ((Get-Date) -lt $nextAllowedRun) {
        Write-Log "Skipped update. Last successful update was $lastRun. Next allowed update is $nextAllowedRun."
        return $true
    }

    return $false
}

try {
    New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

    Write-Log "Starting hosts update."

    if (-not (Test-IsAdmin)) {
        throw "This script must be run as Administrator."
    }

    Ensure-BlockedDomainsFile -Path $BlockedDomainsFile
    Ensure-AllowedDomainsFile -Path $AllowedDomainsFile

    if (Should-Skip-Update) {
        exit 0
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Download-RemoteListFile -Url $RemoteBlockedDomainsUrl -DestinationPath $BlockedDomainsFile -FriendlyName "blocked domains"
    Download-RemoteListFile -Url $RemoteAllowedDomainsUrl -DestinationPath $AllowedDomainsFile -FriendlyName "allowed domains"

    $AllowedDomains = Read-DomainFile -Path $AllowedDomainsFile
    $AllowedLookup = Build-DomainLookup -Domains $AllowedDomains

    Write-Log "Downloading upstream HOSTS file from GitHub."
    Invoke-WebRequest -Uri $SourceUrl -OutFile $DownloadPath -UseBasicParsing -TimeoutSec 180

    if (-not (Test-Path $DownloadPath)) {
        throw "Download failed. File was not created."
    }

    $downloadSize = (Get-Item $DownloadPath).Length

    if ($downloadSize -lt 100000) {
        throw "Downloaded file looks too small: $downloadSize bytes. Refusing to update hosts file."
    }

    $validHostLines = @()
    $skippedDownloadedAllowed = 0

    foreach ($line in [System.IO.File]::ReadLines($DownloadPath)) {
        $trimmed = $line.Trim()

        if ($trimmed -eq "") {
            continue
        }

        if ($trimmed.StartsWith("#")) {
            continue
        }

        if ($trimmed -match '^(0\.0\.0\.0|127\.0\.0\.1|::1)\s+([A-Za-z0-9._-]+)(?:\s|$)') {
            $ip = $Matches[1]
            $domain = $Matches[2].Trim().ToLower()

            if (Test-DomainAllowed -Domain $domain -AllowedLookup $AllowedLookup) {
                $skippedDownloadedAllowed++
                continue
            }

            $validHostLines += "$ip $domain"
        }
    }

    $validHostLines = @($validHostLines | Select-Object -Unique)

    if ($validHostLines.Count -lt 1000) {
        throw "Parsed too few valid hosts entries: $($validHostLines.Count). Refusing to update hosts file."
    }

    $ForcedSearchLines = @(
        "216.239.38.120 www.google.com",
        "216.239.38.120 www.google.ca",
        "216.239.38.120 www.google.co.uk",
        "216.239.38.120 www.google.com.au",
        "216.239.38.120 www.google.co.in",
        "216.239.38.120 www.google.ae",
        "216.239.38.120 www.google.pk",
        "",
        "204.79.197.220 www.bing.com",
        "204.79.197.220 bing.com",
        "204.79.197.220 edgeservices.bing.com",
        "",
        "216.239.38.119 www.youtube.com",
        "216.239.38.119 m.youtube.com",
        "216.239.38.119 youtubei.googleapis.com",
        "216.239.38.119 youtube.googleapis.com",
        "216.239.38.119 www.youtube-nocookie.com"
    )

    $ForcedSearchEntryCount = @($ForcedSearchLines | Where-Object { $_.Trim() -ne "" }).Count

    $BlockedResult = Read-BlockedDomainsFile -Path $BlockedDomainsFile -AllowedLookup $AllowedLookup
    $BlockedSearchLines = $BlockedResult.Lines
    $skippedCustomAllowed = $BlockedResult.SkippedAllowed

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupPath = Join-Path $BackupDir "hosts_$timestamp.bak"

    Write-Log "Backing up current hosts file to $backupPath."
    Copy-Item -Path $HostsPath -Destination $backupPath -Force

    Write-Log "Reading current hosts file safely."
    $currentHosts = [System.IO.File]::ReadAllText($HostsPath)

    $currentHosts = Remove-ManagedBlock -Text $currentHosts -Start $LocalStartMarker -End $LocalEndMarker
    $currentHosts = Remove-ManagedBlock -Text $currentHosts -Start $BlockStartMarker -End $BlockEndMarker
    $currentHosts = Remove-ManagedBlock -Text $currentHosts -Start $OldStartMarker -End $OldEndMarker

    $localPolicyBlock = @"
$LocalStartMarker
# Purpose: apply local search and video filtering policy entries from editable domain files.
# Blocked domains source: $BlockedDomainsFile
# Allowed domains source: $AllowedDomainsFile
# Updated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

# Forced SafeSearch and YouTube Moderate Restricted Mode
$($ForcedSearchLines -join "`r`n")

# Custom blocked domains
$($BlockedSearchLines -join "`r`n")
$LocalEndMarker
"@

    $downloadedBlock = @"
$BlockStartMarker
# Source: GitHub HOSTS blocklist
# Updated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Allowlist exclusions from downloaded source: $skippedDownloadedAllowed
$($validHostLines -join "`r`n")
$BlockEndMarker
"@

    Write-Log "Writing updated hosts file safely."
    $newHosts = $currentHosts.TrimEnd() + "`r`n`r`n" + $localPolicyBlock + "`r`n`r`n" + $downloadedBlock + "`r`n"

    $ascii = New-Object System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllText($HostsPath, $newHosts, $ascii)

    Write-Log "Flushing DNS cache."
    ipconfig /flushdns | Out-Null

    $successStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    [System.IO.File]::WriteAllText($LastSuccessPath, $successStamp)

    Write-Log "Hosts update completed successfully. Blocklist entries applied: $($validHostLines.Count). Forced entries: $ForcedSearchEntryCount. Custom blocked entries: $($BlockedSearchLines.Count). Allowed domains: $($AllowedDomains.Count). Downloaded allowed skips: $skippedDownloadedAllowed. Custom allowed skips: $skippedCustomAllowed."
    Write-Output "SUCCESS: Hosts file updated. Blocklist entries applied: $($validHostLines.Count). Forced entries: $ForcedSearchEntryCount. Custom blocked entries: $($BlockedSearchLines.Count). Allowed domains: $($AllowedDomains.Count). Downloaded allowed skips: $skippedDownloadedAllowed. Custom allowed skips: $skippedCustomAllowed."
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Error $_.Exception.Message
    exit 1
}
