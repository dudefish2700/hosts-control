# Build-HostsInstallerExe.ps1
# Builds a no-console EXE installer that downloads your GitHub installer and runs it silently as admin.

$ErrorActionPreference = "Stop"

$BuildDir = "C:\Temp\HostsBlocklistExe"
$SourcePath = Join-Path $BuildDir "HostsBlocklistInstaller.cs"
$ExePath = Join-Path $BuildDir "HostsBlocklistInstaller.exe"

$InstallerUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Install-HostsBlocklist.ps1"

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

$sourceCode = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Security.Principal;
using System.Windows.Forms;

class HostsBlocklistInstaller
{
    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            if (!IsAdministrator())
            {
                ProcessStartInfo elevate = new ProcessStartInfo();
                elevate.FileName = Process.GetCurrentProcess().MainModule.FileName;
                elevate.UseShellExecute = true;
                elevate.Verb = "runas";

                Process.Start(elevate);
                return 0;
            }

            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;

            string installerUrl = "__INSTALLER_URL__";
            string tempDir = Path.Combine(Path.GetTempPath(), "HostsBlocklistInstaller");
            Directory.CreateDirectory(tempDir);

            string installerPath = Path.Combine(tempDir, "Install-HostsBlocklist.ps1");

            using (WebClient client = new WebClient())
            {
                client.DownloadFile(installerUrl, installerPath);
            }

            if (!File.Exists(installerPath))
            {
                throw new Exception("Installer download failed. File was not created.");
            }

            FileInfo installerInfo = new FileInfo(installerPath);

            if (installerInfo.Length < 5)
            {
                throw new Exception("Installer download looks too small.");
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + installerPath + "\" -Silent";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = tempDir;

            Process p = Process.Start(psi);
            p.WaitForExit();

            if (p.ExitCode != 0)
            {
                throw new Exception("Installer exited with code: " + p.ExitCode);
            }

            MessageBox.Show(
                "Hosts blocklist setup completed successfully.",
                "Hosts Blocklist Installer",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information
            );

            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Install failed:\n\n" + ex.Message + "\n\nCheck:\nC:\\ProgramData\\HostsBlocklist\\update.log",
                "Hosts Blocklist Installer Error",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error
            );

            return 1;
        }
    }

    static bool IsAdministrator()
    {
        WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }
}
'@

$sourceCode = $sourceCode.Replace("__INSTALLER_URL__", $InstallerUrl)

Set-Content -Path $SourcePath -Value $sourceCode -Encoding ASCII -Force

$cscCandidates = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

$csc = $null

foreach ($candidate in $cscCandidates) {
    if (Test-Path $candidate) {
        $csc = $candidate
        break
    }
}

if ($null -eq $csc) {
    throw "Could not find csc.exe. .NET Framework compiler was not found on this PC."
}

if (Test-Path $ExePath) {
    Remove-Item $ExePath -Force
}

Write-Host "Compiling no-console EXE..." -ForegroundColor Cyan

& $csc /nologo /target:winexe /platform:anycpu /reference:System.Windows.Forms.dll /out:$ExePath $SourcePath

if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed."
}

if (-not (Test-Path $ExePath)) {
    throw "EXE was not created."
}

Write-Host ""
Write-Host "No-console EXE created successfully:" -ForegroundColor Green
Write-Host $ExePath