using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDirectory, "MonitorModeConsole.ps1");
            if (!File.Exists(scriptPath))
            {
                MessageBox.Show("找不到界面脚本：\n" + scriptPath, "显示模式控制台",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (!IsAdministrator())
            {
                var elevate = new ProcessStartInfo
                {
                    FileName = Application.ExecutablePath,
                    Arguments = JoinArguments(args),
                    UseShellExecute = true,
                    Verb = "runas",
                    WorkingDirectory = baseDirectory
                };
                Process.Start(elevate);
                return;
            }

            string extra = args.Length > 0 && args[0] == "--test" ? " -TestMode" : string.Empty;
            var info = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + scriptPath + "\"" + extra,
                WorkingDirectory = baseDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };
            using (Process process = Process.Start(info))
            {
                var outputTask = process.StandardOutput.ReadToEndAsync();
                var errorTask = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                string output = outputTask.GetAwaiter().GetResult();
                string error = errorTask.GetAwaiter().GetResult();
                if (process.ExitCode != 0)
                {
                    string details = string.IsNullOrWhiteSpace(error) ? output : error;
                    string logPath = WriteCrashLog(process.ExitCode, details);
                    string summary = LastLines(details, 8);
                    string message = "程序异常退出，代码：" + process.ExitCode;
                    if (!string.IsNullOrWhiteSpace(summary)) message += "\n\n" + summary;
                    if (!string.IsNullOrWhiteSpace(logPath)) message += "\n\n诊断日志：" + logPath;
                    MessageBox.Show(message, "显示模式控制台",
                        MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }
        catch (System.ComponentModel.Win32Exception ex)
        {
            if (ex.NativeErrorCode != 1223)
                MessageBox.Show(ex.Message, "显示模式控制台", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "显示模式控制台", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static string JoinArguments(string[] args)
    {
        if (args == null || args.Length == 0) return string.Empty;
        string[] quoted = new string[args.Length];
        for (int i = 0; i < args.Length; i++)
            quoted[i] = "\"" + args[i].Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        return string.Join(" ", quoted);
    }

    private static string LastLines(string text, int count)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        string[] lines = text.Trim().Split(new[] { "\r\n", "\n" }, StringSplitOptions.None);
        int start = Math.Max(0, lines.Length - count);
        return string.Join(Environment.NewLine, lines, start, lines.Length - start);
    }

    private static string WriteCrashLog(int exitCode, string details)
    {
        try
        {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "MonitorModeConsole");
            Directory.CreateDirectory(root);
            string path = Path.Combine(root, "crash.log");
            File.AppendAllText(path,
                "[" + DateTime.Now.ToString("o") + "] PowerShell exit code " + exitCode + Environment.NewLine +
                details + Environment.NewLine + Environment.NewLine,
                new UTF8Encoding(false));
            return path;
        }
        catch { return string.Empty; }
    }

    private static bool IsAdministrator()
    {
        WindowsIdentity identity = WindowsIdentity.GetCurrent();
        WindowsPrincipal principal = new WindowsPrincipal(identity);
        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }
}
