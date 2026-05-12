@echo off
setlocal

title Hosts Blocklist Installer

echo Starting Hosts Blocklist installer...
echo.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Administrator permission is required.
    echo Requesting Administrator permission now...
    echo.

    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"

    exit /b
)

echo Running as Administrator.
echo.

set "INSTALLER_URL=https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Install-HostsBlocklist.ps1"
set "TEMP_INSTALLER=%TEMP%\Install-HostsBlocklist.ps1"

echo Downloading installer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%INSTALLER_URL%' -OutFile '%TEMP_INSTALLER%' -UseBasicParsing"

if not exist "%TEMP_INSTALLER%" (
    echo.
    echo ERROR: Failed to download installer.
    echo.
    pause
    exit /b 1
)

echo.
echo Running installer...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%TEMP_INSTALLER%"

echo.
echo Installer finished.
echo.
pause
exit /b
