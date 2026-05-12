@echo off
setlocal

echo Starting Hosts Blocklist installer...
echo.
echo This will download the installer from GitHub and ask for Administrator permission.
echo.

set "INSTALLER_URL=https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Install-HostsBlocklist.ps1"
set "TEMP_INSTALLER=%TEMP%\Install-HostsBlocklist.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%INSTALLER_URL%' -OutFile '%TEMP_INSTALLER%' -UseBasicParsing"

if not exist "%TEMP_INSTALLER%" (
    echo Failed to download installer.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File ""%TEMP_INSTALLER%""'"

echo.
echo Installer launched. Check the new Administrator PowerShell window.
echo.
pause
exit /b
