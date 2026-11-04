// Translation tool: extracts the embedded script and dictionary to the user's data folder
// and runs Windows PowerShell. No dependency beyond the .NET Framework that ships with Windows.
// People use it through the window of the Start menu (Window.cs) and through the installer, both without a console.
//
// Elevated stage: nothing from the user's folder is executed or read as administrator. The exe
// reopens itself elevated, extracts script and dictionary into a new, administrators-only folder, checks the hash
// of every file against the embedded resource and only then runs. Data of the elevated stage (backup and state)
// lives in a folder only administrators can write.
//
// The SIMULATE_UAC symbol only exists in the test build (scripts\build.ps1 -SimulateUac): it swaps the
// real administrator request for an ordinary run, to test the whole path without the Windows
// prompt. None of this goes into the published executable.
//
// Uninstall: opening the exe registers an entry in the Windows apps list, pointing to a copy of the exe kept in
// the data folder. That entry restores the originals, deletes the data folder and deletes itself.
//
// Installer: a copy installed by the wizard sits next to unins000.exe and leaves the entry to the wizard. The wizard
// runs this exe without a window, with --wizard: nothing asks for a key press, the reason for a failure goes out through
// the output and the exit code, and the administrator stage has no window either.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

internal static class Launcher
{
    private const string ResourcePrefix = "app/";
    private const string Script = "titanfall-ptbr.ps1";
    private const string ElevatedArgument = "--elevated";
    private const string UninstallArgument = "--uninstall";
    private const string WizardArgument = "--wizard";
    private const string RemoveAnywayArgument = "--remove-anyway";
    private const string CleanupAction = "Cleanup";
    private const string RestoreUninstallingAction = "RestoreUninstalling";
    private const string ExeName = "Titanfall2VR-PTBR.exe";
    private const string WindowExeName = "Titanfall2VR-PTBR-Window.exe";
    private const string ProductName = "Tradução PT-BR do mod Titanfall 2 VR";
    private const string RepositoryUrl = "https://github.com/scarletmodder/titanfall2-vr-ptbr";
    private const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\Titanfall2VR-PTBR";
    // Backup folder name of the on-disk format: its presence means there may be something to restore.
    private const string BackupFolder = "backup";
    private const string RequestFile = "elevation-request.txt";
    // What the hidden administrator stage said, in the administrators' data folder, which users can read.
    private const string ElevatedOutputFile = "elevated-output.txt";
    private const long ElevatedOutputLimit = 1024 * 1024;
    private const int ExitNeedsElevation = 20;
    private const int ExitNoPermission = 3;
    private const int ExitVirtualized = 4;
    private const int ErrorCancelledByUser = 1223;
    // Write, permission and owner rights, besides GENERIC_ALL and GENERIC_WRITE.
    private const int WriteRights = (int)(FileSystemRights.WriteData | FileSystemRights.AppendData
        | FileSystemRights.WriteExtendedAttributes | FileSystemRights.WriteAttributes | FileSystemRights.Delete
        | FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership) | 0x50000000;

    private static bool wizard;

    private static int Main(string[] args)
    {
        wizard = HasArgument(args, WizardArgument);
        args = Without(args, WizardArgument);
        if (args.Length == 0 && !wizard)
        {
            return OpenWindow();
        }
        bool elevated = args.Length > 0 && args[0] == ElevatedArgument;
        try
        {
            Console.OutputEncoding = Encoding.UTF8;
        }
        catch (IOException)
        {
        }
        try
        {
            if (args.Length > 0 && args[0] == UninstallArgument)
            {
                string[] rest = new string[args.Length - 1];
                Array.Copy(args, 1, rest, 0, rest.Length);
                return UninstallStage(rest);
            }
            return elevated ? ElevatedStage(args) : NormalStage(args);
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("Não consegui iniciar a ferramenta: " + error.Message);
            if (elevated && wizard)
            {
                KeepElevatedFailure(error.Message);
            }
            if (elevated && !wizard)
            {
                Console.Error.WriteLine("Aperte Enter para fechar.");
                Console.ReadLine();
            }
            return 1;
        }
    }

    // Opened by hand, with nothing to do: this is the program with the window.
    private static int OpenWindow()
    {
        string window = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), WindowExeName);
        if (!File.Exists(window))
        {
            Console.Error.WriteLine("Não achei " + WindowExeName + " nesta pasta. Instale de novo para trazê-lo de volta.");
            return 1;
        }
        Process.Start(window).Dispose();
        return 0;
    }

    private static int NormalStage(string[] args)
    {
        string data = DataDir(args);
        string version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
        string app = Path.Combine(Path.Combine(data, "app"), version);
        Extract(app);
        CleanOldVersions(Path.Combine(data, "app"), version);
        if (ShouldRegister(args))
        {
            string virtualCopy = VirtualizedCopy(data);
            if (virtualCopy != null)
            {
                return RefuseVirtualized(virtualCopy);
            }
            if (!IsManaged())
            {
                Register(data, version);
            }
        }

        int code = RunNormal(Path.Combine(app, Script), data, args);
        return code == ExitNeedsElevation ? RequestElevation(data) : code;
    }

    private static bool ShouldRegister(string[] args)
    {
#if SIMULATE_UAC
        return !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("TF2VR_TEST_UNINSTALL_KEY"));
#else
        return !HasArgument(args, "-DataDir");
#endif
    }

    // The wizard's own entry and uninstaller take over from what the exe would register by itself.
    private static bool IsManaged()
    {
        string folder = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        return wizard || File.Exists(Path.Combine(folder, "unins000.exe"));
    }

    private static string RegistryKey()
    {
#if SIMULATE_UAC
        return Environment.GetEnvironmentVariable("TF2VR_TEST_UNINSTALL_KEY");
#else
        return UninstallKey;
#endif
    }

    // A process started from inside a Store app can have its writes silently redirected to that app's private
    // area, unseen by Explorer and by Settings: the uninstall entry would never show up. The package APIs do not
    // reveal this in child processes, so a probe file shows where the write really went.
    private static string VirtualizedCopy(string data)
    {
#if SIMULATE_UAC
        return null;
#else
        string localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string packages = Path.Combine(localData, "Packages");
        if (!Directory.Exists(packages) || !data.StartsWith(localData + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }
        string relative = data.Substring(localData.Length + 1);
        string probeName = "probe-" + Guid.NewGuid().ToString("N");
        string probe = Path.Combine(data, probeName);
        File.WriteAllBytes(probe, new byte[0]);
        try
        {
            foreach (string package in Directory.GetDirectories(packages))
            {
                string candidate = Path.Combine(Path.Combine(Path.Combine(Path.Combine(package, "LocalCache"), "Local"), relative), "");
                if (File.Exists(Path.Combine(candidate, probeName)))
                {
                    return candidate;
                }
            }
            return null;
        }
        finally
        {
            File.Delete(probe);
        }
#endif
    }

    private static int RefuseVirtualized(string copy)
    {
        // What this launch just extracted goes away. A copy holding a backup is someone's data and stays.
        if (!Directory.Exists(Path.Combine(copy, BackupFolder)))
        {
            DeleteWithoutFollowing(copy);
            string parent = Path.GetDirectoryName(copy);
            if (Directory.GetFileSystemEntries(parent).Length == 0)
            {
                Directory.Delete(parent);
            }
        }
        Console.WriteLine("Este programa foi aberto de dentro de outro aplicativo, e o Windows guardaria os dados numa área");
        Console.WriteLine("separada, onde a desinstalação não os encontraria. Nada foi alterado no jogo.");
        Console.WriteLine("Abra pelo menu Iniciar do Windows.");
        return ExitVirtualized;
    }

    private static void Register(string data, string version)
    {
        try
        {
            string folder = Path.Combine(data, "uninstall");
            string installed = Path.Combine(folder, ExeName);
            string current = Assembly.GetExecutingAssembly().Location;
            if (!string.Equals(Path.GetFullPath(current), installed, StringComparison.OrdinalIgnoreCase))
            {
                Directory.CreateDirectory(folder);
                File.Copy(current, installed, true);
            }
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RegistryKey()))
            {
                key.SetValue("DisplayName", ProductName);
                key.SetValue("DisplayVersion", version);
                key.SetValue("Publisher", "Scarlet Modder");
                key.SetValue("DisplayIcon", installed);
                key.SetValue("InstallLocation", data);
                key.SetValue("URLInfoAbout", RepositoryUrl);
                key.SetValue("UninstallString", "\"" + installed + "\" " + UninstallArgument);
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
        }
        catch (Exception error)
        {
            if (!(error is IOException || error is UnauthorizedAccessException || error is System.Security.SecurityException))
            {
                throw;
            }
            Console.WriteLine("Aviso: não consegui criar a entrada na lista de aplicativos do Windows: " + error.Message);
        }
    }

    // Everything is removed only after the originals are back. Any failure keeps the entry, so it can be run again.
    private static int UninstallStage(string[] args)
    {
        string data = DataDir(args);
        bool interactive = !wizard && !HasArgument(args, "-NonInteractive") && !Console.IsInputRedirected;
        bool removeAnyway = HasArgument(args, RemoveAnywayArgument);
        args = Without(args, RemoveAnywayArgument);
        int code = 0;
        if (!removeAnyway && (Directory.Exists(Path.Combine(data, BackupFolder)) || HasAdminLeftovers()))
        {
            string version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
            string app = Path.Combine(Path.Combine(data, "app"), version);
            Extract(app);
            List<string> restore = new List<string>(new string[] { "-Action", "Restore", "-Uninstalling" });
            restore.AddRange(args);
            code = RunNormal(Path.Combine(app, Script), data, restore.ToArray());
            if (code == ExitNeedsElevation)
            {
                code = RequestElevation(data, true);
            }
        }
        if (code != 0 && !ConfirmRemoveAnyway(interactive))
        {
            Console.WriteLine();
            Console.WriteLine("A desinstalação não terminou: nada foi removido. Resolva o aviso acima e desinstale de novo.");
            WaitToClose(interactive);
            return code;
        }
        if (HasAdminLeftovers())
        {
            int cleanup = StartElevated(CleanupAction, "-");
            if (cleanup != 0)
            {
                Console.WriteLine("A pasta de administradores da ferramenta não foi removida. Desinstale de novo para tentar outra vez.");
                WaitToClose(interactive);
                return cleanup;
            }
        }
        Registry.CurrentUser.DeleteSubKeyTree(RegistryKey(), false);
        DeleteAfterExit(data);
        Console.WriteLine();
        Console.WriteLine("Tradução desinstalada: textos originais de volta e dados da ferramenta removidos.");
        Console.WriteLine("O arquivo que você baixou não é apagado: pode mandar para a Lixeira.");
        WaitToClose(interactive);
        return 0;
    }

    // The parent folder is shared with other tools of the same author, so only what belongs to this one counts.
    private static bool HasAdminLeftovers()
    {
        return Directory.Exists(AdminDataDir())
            || (Directory.Exists(AdminRoot()) && Directory.GetDirectories(AdminRoot(), "run-*").Length > 0);
    }

    private static bool ConfirmRemoveAnyway(bool interactive)
    {
        if (!interactive)
        {
            return false;
        }
        Console.WriteLine();
        Console.WriteLine("Não consegui devolver os textos originais.");
        Console.WriteLine("Se o jogo já foi desinstalado, digite REMOVER para apagar só os dados desta ferramenta.");
        Console.WriteLine("Com o jogo instalado, aperte Enter: remover agora perderia a cópia dos originais.");
        return string.Equals((Console.ReadLine() ?? "").Trim(), "REMOVER", StringComparison.OrdinalIgnoreCase);
    }

    private static void WaitToClose(bool interactive)
    {
        if (interactive)
        {
            Console.WriteLine("Aperte Enter para fechar.");
            Console.ReadLine();
        }
    }

    // Everything goes now, except the folder of the running copy. A detached shell removes that one after this
    // process ends, unless a new translation was made meanwhile: its backup is then the only copy of the originals.
    private static void DeleteAfterExit(string data)
    {
        foreach (string entry in Directory.GetFileSystemEntries(data))
        {
            if (string.Equals(Path.GetFileName(entry), "uninstall", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            try
            {
                if (Directory.Exists(entry))
                {
                    DeleteWithoutFollowing(entry);
                }
                else
                {
                    if (!IsLink(entry))
                    {
                        File.SetAttributes(entry, FileAttributes.Normal);
                    }
                    File.Delete(entry);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
        string parent = Path.GetDirectoryName(data);
        string command = "Wait-Process -Id " + Process.GetCurrentProcess().Id + " -ErrorAction SilentlyContinue; "
            + "$d = " + QuoteForPowerShell(data) + "; "
            + "if (-not (Test-Path -LiteralPath (Join-Path $d '" + BackupFolder + "')) -and -not (Test-Path -LiteralPath (Join-Path $d 'estado.json'))) { "
            + "foreach ($i in 1..30) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue; "
            + "if (-not (Test-Path -LiteralPath $d)) { break }; Start-Sleep 1 } }";
        if (string.Equals(Path.GetFileName(parent), "ScarletModder", StringComparison.OrdinalIgnoreCase))
        {
            command += "; [IO.Directory]::Delete(" + QuoteForPowerShell(parent) + ")";
        }
        string system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        ProcessStartInfo startInfo = new ProcessStartInfo(
            Path.Combine(Path.Combine(Path.Combine(system, "WindowsPowerShell"), "v1.0"), "powershell.exe"),
            "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"" + command + "\"");
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.WorkingDirectory = system;
        Process.Start(startInfo).Dispose();
    }

    private static string QuoteForPowerShell(string text)
    {
        // PowerShell also takes the typographic single quotes as string delimiters.
        foreach (string quote in new string[] { "'", "‘", "’", "‚", "‛" })
        {
            text = text.Replace(quote, quote + quote);
        }
        return "'" + text + "'";
    }

    private static string DataDir(string[] args)
    {
        for (int i = 0; i + 1 < args.Length; i++)
        {
            if (string.Equals(args[i], "-DataDir", StringComparison.OrdinalIgnoreCase))
            {
                return Path.GetFullPath(args[i + 1]);
            }
        }
        string localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(Path.Combine(localData, "ScarletModder"), "Titanfall2VR-PTBR");
    }

    private static string AdminRoot()
    {
#if SIMULATE_UAC
        return Path.Combine(Environment.GetEnvironmentVariable("TF2VR_TEST_ROOT"), "ScarletModder");
#else
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "ScarletModder");
#endif
    }

    private static string AdminDataDir()
    {
        return Path.Combine(AdminRoot(), "Titanfall2VR-PTBR");
    }

    private static Dictionary<string, byte[]> Resources()
    {
        Dictionary<string, byte[]> resources = new Dictionary<string, byte[]>();
        Assembly assembly = Assembly.GetExecutingAssembly();
        foreach (string name in assembly.GetManifestResourceNames())
        {
            if (!name.StartsWith(ResourcePrefix, StringComparison.Ordinal))
            {
                continue;
            }
            string relative = name.Substring(ResourcePrefix.Length).Replace('/', Path.DirectorySeparatorChar);
            using (Stream source = assembly.GetManifestResourceStream(name))
            using (MemoryStream memory = new MemoryStream())
            {
                source.CopyTo(memory);
                resources[relative] = memory.ToArray();
            }
        }
        return resources;
    }

    private static void Extract(string target)
    {
        foreach (KeyValuePair<string, byte[]> resource in Resources())
        {
            string path = Path.Combine(target, resource.Key);
            if (File.Exists(path) && SameContent(File.ReadAllBytes(path), resource.Value))
            {
                continue;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllBytes(path, resource.Value);
        }
    }

    private static void Verify(string target)
    {
        Dictionary<string, byte[]> resources = Resources();
        foreach (KeyValuePair<string, byte[]> resource in resources)
        {
            string path = Path.Combine(target, resource.Key);
            if (!File.Exists(path) || !SameContent(File.ReadAllBytes(path), resource.Value))
            {
                throw new InvalidOperationException("o arquivo extraído não confere com o executável: " + resource.Key);
            }
        }
        if (Directory.GetFiles(target, "*", SearchOption.AllDirectories).Length != resources.Count)
        {
            throw new InvalidOperationException("a pasta extraída tem arquivos a mais");
        }
    }

    private static bool SameContent(byte[] a, byte[] b)
    {
        using (SHA256 sha = SHA256.Create())
        {
            return Convert.ToBase64String(sha.ComputeHash(a)) == Convert.ToBase64String(sha.ComputeHash(b));
        }
    }

    // Only deletes subfolders named like a version: -DataDir may point to a folder that already has an app of its own.
    private static void CleanOldVersions(string root, string current)
    {
        try
        {
            foreach (string dir in Directory.GetDirectories(root))
            {
                string name = Path.GetFileName(dir);
                if (Regex.IsMatch(name, @"^\d+\.\d+\.\d+$") && !string.Equals(name, current, StringComparison.OrdinalIgnoreCase))
                {
                    DeleteWithoutFollowing(dir);
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static bool IsLink(string path)
    {
        return (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;
    }

    // Deletes the folder without ever entering a junction or symbolic link: the link goes away, the target stays.
    private static void DeleteWithoutFollowing(string dir)
    {
        if (!IsLink(dir))
        {
            foreach (string file in Directory.GetFiles(dir))
            {
                if (!IsLink(file))
                {
                    File.SetAttributes(file, FileAttributes.Normal);
                }
                File.Delete(file);
            }
            foreach (string child in Directory.GetDirectories(dir))
            {
                DeleteWithoutFollowing(child);
            }
        }
        Directory.Delete(dir, false);
    }

    private static int RunNormal(string script, string data, string[] args)
    {
        List<string> arguments = new List<string>();
        arguments.AddRange(new string[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script });
        arguments.AddRange(args);
        if (!HasArgument(args, "-DataDir"))
        {
            arguments.Add("-DataDir");
            arguments.Add(data);
        }
        if (!HasArgument(args, "-AdminDataDir"))
        {
            arguments.Add("-AdminDataDir");
            arguments.Add(AdminDataDir());
        }
        arguments.Add("-ViaExe");
        if (wizard)
        {
            arguments.Add("-NoPrompt");
        }
        return RunPowerShell(arguments, null);
    }

    private static int RunPowerShell(List<string> arguments, string workingDir, string outputFile = null)
    {
        string system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        string powershell = Path.Combine(system, @"WindowsPowerShell\v1.0\powershell.exe");
        ProcessStartInfo startInfo = new ProcessStartInfo(powershell, CommandLine.Join(arguments));
        startInfo.UseShellExecute = false;
                // Started from PowerShell 7, the exe would inherit modules that Windows PowerShell does not load.
        startInfo.EnvironmentVariables.Remove("PSModulePath");
        if (workingDir != null)
        {
            startInfo.WorkingDirectory = workingDir;
        }
        if (outputFile != null)
        {
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            startInfo.StandardOutputEncoding = Encoding.UTF8;
            startInfo.StandardErrorEncoding = Encoding.UTF8;
        }
        using (Process process = Process.Start(startInfo))
        {
            if (outputFile != null)
            {
                KeepOutput(process, outputFile);
            }
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static void KeepOutput(Process process, string outputFile)
    {
        StringBuilder errors = new StringBuilder();
        process.ErrorDataReceived += delegate (object sender, DataReceivedEventArgs line)
        {
            if (line.Data != null)
            {
                lock (errors)
                {
                    errors.AppendLine(line.Data);
                }
            }
        };
        process.BeginErrorReadLine();
        string output = process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        lock (errors)
        {
            WriteElevatedOutput(outputFile, output + errors);
        }
    }

    private static void WriteElevatedOutput(string outputFile, string text)
    {
        try
        {
            File.WriteAllText(outputFile, text, new UTF8Encoding(false));
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    // What stopped the hidden stage before its script said anything. In a folder that cannot be trusted nothing is
    // written, and the normal stage only has the exit code to show.
    private static void KeepElevatedFailure(string reason)
    {
        string file = Path.Combine(AdminDataDir(), ElevatedOutputFile);
        try
        {
            if (IsTrustedOutput(file))
            {
                WriteElevatedOutput(file, reason + Environment.NewLine);
                FixOwner(AdminDataDir());
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private static bool IsTrustedOutput(string file)
    {
        string dir = Path.GetDirectoryName(file);
        return Directory.Exists(dir) && IsTrustedEntry(dir) && (!File.Exists(file) || IsTrustedEntry(file));
    }

    // The window of that stage is hidden, so what it said about the result is brought here. A file older than this run
    // is from another run, and one that an ordinary process could have prepared is not believed: neither is repeated.
    private static void RepeatElevatedOutput(DateTime startedUtc)
    {
        string file = Path.Combine(AdminDataDir(), ElevatedOutputFile);
        try
        {
            if (File.Exists(file) && IsTrustedOutput(file) && new FileInfo(file).Length <= ElevatedOutputLimit && File.GetLastWriteTimeUtc(file) >= startedUtc)
            {
                Console.Write(File.ReadAllText(file, Encoding.UTF8));
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    // The normal script says what needs permission; here the exe reopens itself as administrator.
    private static int RequestElevation(string data, bool uninstalling = false)
    {
        string file = Path.Combine(data, RequestFile);
        string[] request = File.ReadAllLines(file, new UTF8Encoding(false));
        File.Delete(file);
        if (request.Length < 2)
        {
            throw new InvalidOperationException("pedido de permissão incompleto");
        }
        string action = uninstalling && request[0] == "Restore" ? RestoreUninstallingAction : request[0];
        return StartElevated(action, request[1]);
    }

    private static int StartElevated(string action, string game)
    {
        List<string> arguments = new List<string>(new string[] { ElevatedArgument, action, game });
        if (wizard)
        {
            arguments.Add(WizardArgument);
        }
        ProcessStartInfo startInfo = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location, CommandLine.Join(arguments));
        DateTime startedUtc = DateTime.UtcNow.AddSeconds(-2);
#if SIMULATE_UAC
        startInfo.UseShellExecute = false;
        if (Environment.GetEnvironmentVariable("TF2VR_TEST_REFUSE") == "1")
        {
            Console.WriteLine("A permissão de administrador foi recusada. Nada foi alterado.");
            return ExitNoPermission;
        }
#else
        startInfo.UseShellExecute = true;
        startInfo.Verb = "runas";
        if (wizard)
        {
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;
        }
#endif
        try
        {
            using (Process process = Process.Start(startInfo))
            {
                process.WaitForExit();
                if (wizard)
                {
                    RepeatElevatedOutput(startedUtc);
                    if (process.ExitCode != 0)
                    {
                        Console.WriteLine("A etapa com permissão de administrador falhou (código " + process.ExitCode + ").");
                    }
                }
                return process.ExitCode;
            }
        }
        catch (Win32Exception error)
        {
            if (error.NativeErrorCode != ErrorCancelledByUser)
            {
                throw;
            }
            Console.WriteLine("A permissão de administrador foi recusada. Nada foi alterado.");
            return ExitNoPermission;
        }
    }

    private static int ElevatedStage(string[] args)
    {
        if (args.Length != 3 || (args[1] != "Translate" && args[1] != "Restore" && args[1] != RestoreUninstallingAction && args[1] != CleanupAction))
        {
            throw new ArgumentException("pedido de permissão inválido");
        }
        if (!IsAdministrator())
        {
            throw new UnauthorizedAccessException("esta etapa só roda como administrador");
        }
        if (args[1] == CleanupAction)
        {
            CleanAdminFolder();
            return 0;
        }
        bool uninstalling = args[1] == RestoreUninstallingAction;
        string game = args[2];
        if (!File.Exists(Path.Combine(game, "Titanfall2.exe")))
        {
            throw new ArgumentException("a pasta informada não tem o Titanfall2.exe");
        }
#if SIMULATE_UAC
        foreach (string file in Directory.GetFiles(game, "*", SearchOption.AllDirectories))
        {
            File.SetAttributes(file, FileAttributes.Normal);
        }
#endif
        AdminOnlyFolder(AdminRoot(), true);
        CleanOldRuns();
        string data = AdminDataDir();
        AdminOnlyFolder(data, true);
        string runDir = Path.Combine(AdminRoot(), "run-" + Guid.NewGuid().ToString("N"));
        AdminOnlyFolder(runDir, false);
        string outputFile = wizard ? Path.Combine(data, ElevatedOutputFile) : null;
        try
        {
            Extract(runDir);
#if SIMULATE_UAC
            if (Environment.GetEnvironmentVariable("TF2VR_TEST_TAMPER") == "1")
            {
                File.AppendAllText(Path.Combine(runDir, Script), "# tampered");
            }
#endif
            Verify(runDir);
            List<string> arguments = new List<string>(new string[] {
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(runDir, Script),
                "-Action", uninstalling ? "Restore" : args[1], "-GameDir", game, "-DataDir", data, "-Elevated" });
            if (uninstalling)
            {
                arguments.Add("-Uninstalling");
            }
#if !SIMULATE_UAC
            else if (!wizard)
            {
                arguments.Add("-Pause");
            }
#endif
            if (wizard)
            {
                arguments.Add("-NoPrompt");
            }
            int code = RunPowerShell(arguments, runDir, outputFile);
#if !SIMULATE_UAC
            // This window closes on its own: the reason for the failure must be read before that.
            if (uninstalling && code != 0 && !wizard)
            {
                Console.WriteLine("Aperte Enter para fechar.");
                Console.ReadLine();
            }
#endif
            return code;
        }
        finally
        {
            FixOwner(data);
            try
            {
                DeleteWithoutFollowing(runDir);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    // Removes only what belongs to this tool. The parent goes only when nothing else lives there.
    private static void CleanAdminFolder()
    {
        if (!Directory.Exists(AdminRoot()))
        {
            return;
        }
        AdminOnlyFolder(AdminRoot(), true);
        if (Directory.Exists(AdminDataDir()))
        {
            DeleteWithoutFollowing(AdminDataDir());
        }
        CleanOldRuns();
        if (Directory.GetFileSystemEntries(AdminRoot()).Length == 0)
        {
            Directory.Delete(AdminRoot());
        }
    }

    // A window closed in the middle leaves the run folder behind; the next elevated stage cleans it.
    private static void CleanOldRuns()
    {
        foreach (string old in Directory.GetDirectories(AdminRoot(), "run-*"))
        {
            try
            {
                if (IsTrustedEntry(old))
                {
                    DeleteWithoutFollowing(old);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    // Depending on the Windows policy, the owner of what the script creates may be the account, not the
    // administrators group. The next elevated stage would refuse those files, so the owner is fixed here.
    private static void FixOwner(string data)
    {
#if !SIMULATE_UAC
        try
        {
            SecurityIdentifier administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
            foreach (string entry in Directory.GetFileSystemEntries(data))
            {
                if (IsLink(entry))
                {
                    continue;
                }
                if (Directory.Exists(entry))
                {
                    DirectorySecurity owner = new DirectorySecurity();
                    owner.SetOwner(administrators);
                    Directory.SetAccessControl(entry, owner);
                }
                else
                {
                    FileSecurity owner = new FileSecurity();
                    owner.SetOwner(administrators);
                    File.SetAccessControl(entry, owner);
                }
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
#endif
    }

    private static bool IsAdministrator()
    {
#if SIMULATE_UAC
        return true;
#else
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        }
#endif
    }

    // Folder with inheritance off: only administrators and the system can write. A folder from before that is not
    // theirs, or is a link, may have been prepared by an ordinary process and is discarded.
    private static void AdminOnlyFolder(string dir, bool usuariosLeem)
    {
        SecurityIdentifier administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        SecurityIdentifier system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        if (Directory.Exists(dir) && !IsTrustedEntry(dir))
        {
            DeleteWithoutFollowing(dir);
        }
        DirectorySecurity security = new DirectorySecurity();
        security.SetAccessRuleProtection(true, false);
        Allow(security, administrators, FileSystemRights.FullControl);
        Allow(security, system, FileSystemRights.FullControl);
        if (usuariosLeem)
        {
            Allow(security, new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null), FileSystemRights.ReadAndExecute);
        }
#if SIMULATE_UAC
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            Allow(security, identity.User, FileSystemRights.FullControl);
        }
        Directory.CreateDirectory(dir);
        Directory.SetAccessControl(dir, security);
        Console.WriteLine("acl " + Path.GetFileName(dir) + " " + Directory.GetAccessControl(dir).GetSecurityDescriptorSddlForm(AccessControlSections.Access));
#else
        security.SetOwner(administrators);
        Directory.CreateDirectory(dir, security);
        Directory.SetAccessControl(dir, security);
#endif
                // A window closed in the middle skips the finally: the owner of the files already stored is fixed here.
        FixOwner(dir);
        Revalidate(dir);
    }

    // Between deleting and creating, another process may have recreated the folder. It only proceeds if it and its direct children
    // are right now; otherwise nothing runs.
    private static void Revalidate(string dir)
    {
        if (!IsTrustedEntry(dir) || !Directory.GetAccessControl(dir).AreAccessRulesProtected)
        {
            throw new InvalidOperationException("a pasta de administradores não é confiável: " + Path.GetFileName(dir));
        }
        foreach (string entry in Directory.GetFileSystemEntries(dir))
        {
            if (!IsTrustedEntry(entry))
            {
                throw new InvalidOperationException("a pasta de administradores não é confiável: " + Path.GetFileName(entry));
            }
        }
    }

    private static void Allow(DirectorySecurity security, IdentityReference who, FileSystemRights rights)
    {
        security.AddAccessRule(new FileSystemAccessRule(who, rights,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
    }

    // Trusted: not a link, owned by administrators or the system, and only they have write rights.
    private static bool IsTrustedEntry(string path)
    {
        if (IsLink(path))
        {
            return false;
        }
        FileSystemSecurity security;
        if (Directory.Exists(path))
        {
            security = Directory.GetAccessControl(path, AccessControlSections.Owner | AccessControlSections.Access);
        }
        else
        {
            security = File.GetAccessControl(path, AccessControlSections.Owner | AccessControlSections.Access);
        }
#if !SIMULATE_UAC
        if (!CanWrite(security.GetOwner(typeof(SecurityIdentifier))))
        {
            return false;
        }
#endif
        foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
        {
            if (rule.AccessControlType == AccessControlType.Allow && (((int)rule.FileSystemRights) & WriteRights) != 0 && !CanWrite(rule.IdentityReference))
            {
                return false;
            }
        }
        return true;
    }

    private static bool CanWrite(IdentityReference who)
    {
        SecurityIdentifier sid = who as SecurityIdentifier;
        if (sid == null)
        {
            return false;
        }
#if SIMULATE_UAC
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            if (sid.Equals(identity.User))
            {
                return true;
            }
        }
#endif
        return sid.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid) || sid.IsWellKnown(WellKnownSidType.LocalSystemSid);
    }

    private static bool HasArgument(string[] args, string name)
    {
        foreach (string a in args)
        {
            if (string.Equals(a, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private static string[] Without(string[] args, string name)
    {
        List<string> rest = new List<string>();
        foreach (string a in args)
        {
            if (!string.Equals(a, name, StringComparison.OrdinalIgnoreCase))
            {
                rest.Add(a);
            }
        }
        return rest.ToArray();
    }
}
