@echo off
setlocal

echo Starting Hosts Blocklist installer...
echo.
echo This will ask for Administrator permission.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command ""$temp = Join-Path $env:TEMP ''Install-HostsBlocklist.ps1''; Invoke-WebRequest -Uri ''https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Install-HostsBlocklist.ps1'' -OutFile $temp -UseBasicParsing; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temp""'"

exit /b
