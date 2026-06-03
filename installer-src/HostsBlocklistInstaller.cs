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

            string installerUrl = "https://raw.githubusercontent.com/dudefish2700/hosts-control/refs/heads/main/Install-HostsBlocklist.ps1";
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
