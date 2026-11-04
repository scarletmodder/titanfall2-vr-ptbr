// The program of the Start menu: a window over the same tool the installer runs. Status, translating, going back to
// English and changing the game folder all go through Titanfall2VR-PTBR.exe, with no window of its own, so what writes
// to the game exists in one place only. This file reads and shows; it never touches the game.
//
// Arguments given to this program go to every run of the tool. That only exists for the tests, which use an invented
// mod with an invented dictionary (tests\test-window.ps1).
using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class WindowProgram
{
    // The installer looks for this name to know the program is open: it also appears in installer\titanfall2-vr-ptbr.iss.
    private const string RunningMutex = "ScarletModder.Titanfall2VRPTBR.Window";

    private const int RestoreWindow = 9;

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr window, int command);

    [STAThread]
    private static void Main(string[] args)
    {
        Mutex running;
        try
        {
            running = new Mutex(false, RunningMutex);
        }
        catch (UnauthorizedAccessException)
        {
            // Opened as administrator, the other copy keeps its name out of reach of this one.
            BringOpenWindowForward();
            return;
        }
        using (running)
        {
            bool first;
            try
            {
                first = running.WaitOne(0);
            }
            catch (AbandonedMutexException)
            {
                first = true;
            }
            if (!first)
            {
                BringOpenWindowForward();
                return;
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainWindow(args));
        }
    }

    private static void BringOpenWindowForward()
    {
        using (Process current = Process.GetCurrentProcess())
        {
            foreach (Process other in Process.GetProcessesByName(current.ProcessName))
            {
                if (other.Id != current.Id && other.MainWindowHandle != IntPtr.Zero)
                {
                    if (IsIconic(other.MainWindowHandle))
                    {
                        ShowWindow(other.MainWindowHandle, RestoreWindow);
                    }
                    SetForegroundWindow(other.MainWindowHandle);
                }
                other.Dispose();
            }
        }
    }
}

// Follows the Windows choice between light and dark apps.
internal sealed class Palette
{
    public readonly bool Dark;
    public readonly Color Page, Card, Line, Text, Muted, Accent, OnAccent, Good, Warning, Bad, Neutral;

    public Palette(bool dark)
    {
        Dark = dark;
        Page = dark ? Color.FromArgb(0x1E, 0x1E, 0x22) : Color.FromArgb(0xF6, 0xF6, 0xF8);
        Card = dark ? Color.FromArgb(0x2A, 0x2A, 0x30) : Color.White;
        Line = dark ? Color.FromArgb(0x45, 0x45, 0x4E) : Color.FromArgb(0xD5, 0xD5, 0xDC);
        Text = dark ? Color.FromArgb(0xF0, 0xF0, 0xF3) : Color.FromArgb(0x1F, 0x23, 0x28);
        Muted = dark ? Color.FromArgb(0xB4, 0xB4, 0xBE) : Color.FromArgb(0x5A, 0x5F, 0x68);
        Accent = dark ? Color.FromArgb(0x2F, 0x6F, 0xDB) : Color.FromArgb(0x25, 0x63, 0xEB);
        OnAccent = Color.White;
        Good = dark ? Color.FromArgb(0x4C, 0xC3, 0x8A) : Color.FromArgb(0x1E, 0x7F, 0x46);
        Warning = dark ? Color.FromArgb(0xF2, 0xA5, 0x16) : Color.FromArgb(0xB4, 0x6A, 0x00);
        Bad = dark ? Color.FromArgb(0xFF, 0x8A, 0x7A) : Color.FromArgb(0xC0, 0x28, 0x1E);
        Neutral = dark ? Color.FromArgb(0x7D, 0xA8, 0xF5) : Color.FromArgb(0x2F, 0x63, 0xC7);
    }

    public static Palette FromWindows()
    {
        object light = Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1);
        return new Palette(light is int && (int)light == 0);
    }
}

internal sealed class ToolResult
{
    public bool Started;
    public int Code;
    public string Output = "";
}

internal sealed class MainWindow : Form
{
    private const string ToolExe = "Titanfall2VR-PTBR.exe";
    private const string ProductTitle = "Tradução PT-BR do mod Titanfall 2 VR";
    private const string RepositoryUrl = "https://github.com/scarletmodder/titanfall2-vr-ptbr";
    private const string ModInstallerUrl = "https://github.com/CircuitLord/CircuitLordVRModInstaller";
    private const string StatusPrefix = "TF2VR_STATUS:";
    private const int ExitPending = 10;
    private const int PageWidth = 640;
    private const int Gutter = 24;
    private const int ResultHeight = 172;
    private const int ResultHeightWithCopy = 130;

    private readonly string[] toolArguments;
    private readonly Palette palette = Palette.FromWindows();
    private readonly Label statusDot = new Label();
    private readonly Label statusTitle = new Label();
    private readonly Label statusDetail = new Label();
    private readonly TextBox folderBox = new TextBox();
    private readonly Button folderButton = new Button();
    private readonly Button translateButton = new Button();
    private readonly Button restoreButton = new Button();
    private readonly Panel resultCard = new Panel();
    private readonly Panel resultStripe = new Panel();
    private readonly TextBox resultText = new TextBox();
    private readonly ProgressBar progress = new ProgressBar();
    private readonly Button copyButton = new Button();
    private readonly LinkLabel reportLink = new LinkLabel();
    private readonly LinkLabel modLink = new LinkLabel();
    private readonly Button closeButton = new Button();

    private bool busy;
    private string gameDir;
    private string issueListPath;
    private int pendingCount;

    public MainWindow(string[] arguments)
    {
        toolArguments = arguments;
        AutoScaleDimensions = new SizeF(96F, 96F);
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Segoe UI", 10F);
        Text = ProductTitle;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = palette.Page;
        ForeColor = palette.Text;
        ClientSize = new Size(PageWidth, 610);
        Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
        BuildHeader();
        BuildStatus();
        BuildFolder();
        BuildActions();
        BuildResult();
        BuildFooter();
        CancelButton = closeButton;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        if (palette.Dark)
        {
            int on = 1;
            try
            {
                DwmSetWindowAttribute(Handle, DarkTitleBarAttribute, ref on, sizeof(int));
            }
            catch (DllNotFoundException)
            {
            }
            resultText.HandleCreated += delegate { SetWindowTheme(resultText.Handle, "DarkMode_Explorer", null); };
        }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        RunBusy("Conferindo o jogo...", () => RefreshStatus(null, true));
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // Closing now would leave the tool running with no one to say how it ended. A close asked from outside, as by the
        // taskbar, arrives under another reason, so only the end of the Windows session gets through.
        if (busy && e.CloseReason != CloseReason.WindowsShutDown)
        {
            e.Cancel = true;
            ShowResult("Espere terminar: o programa está mexendo nos arquivos do jogo.", palette.Warning);
        }
        base.OnFormClosing(e);
    }

    // ============================================================
    //  Building the window
    // ============================================================
    // The frames of the icon are PNG files, and System.Drawing.Icon only reads the older format: this takes the PNG out.
    private static Image LoadIconFrame(int size)
    {
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("scarlet.ico"))
        using (BinaryReader reader = new BinaryReader(stream))
        {
            stream.Position = 4;
            int frames = reader.ReadUInt16();
            for (int i = 0; i < frames; i++)
            {
                stream.Position = 6 + 16 * i;
                int width = reader.ReadByte();
                stream.Position = 6 + 16 * i + 8;
                int length = reader.ReadInt32();
                int offset = reader.ReadInt32();
                if (width == size)
                {
                    stream.Position = offset;
                    using (MemoryStream frame = new MemoryStream(reader.ReadBytes(length)))
                    using (Bitmap decoded = new Bitmap(frame))
                    {
                        // A bitmap keeps reading the stream it came from: this copy no longer needs it.
                        return new Bitmap(decoded);
                    }
                }
            }
        }
        throw new InvalidOperationException("The icon has no frame of size " + size + ".");
    }

    private Label AddLabel(Control parent, string text, int x, int y, int width, int height, Font font, Color color)
    {
        Label label = new Label();
        label.Text = text;
        label.Bounds = new Rectangle(x, y, width, height);
        label.Font = font;
        label.ForeColor = color;
        label.BackColor = Color.Transparent;
        label.UseMnemonic = false;
        parent.Controls.Add(label);
        return label;
    }

    private void StyleButton(Button button, string name, string text, Rectangle bounds, bool primary)
    {
        button.Name = name;
        button.Text = text;
        button.Bounds = bounds;
        button.FlatStyle = FlatStyle.Flat;
        button.UseVisualStyleBackColor = false;
        button.BackColor = primary ? palette.Accent : palette.Card;
        button.ForeColor = primary ? palette.OnAccent : palette.Text;
        button.FlatAppearance.BorderColor = primary ? palette.Accent : palette.Line;
        button.UseMnemonic = false;
        button.Paint += PaintDisabledText;
        Controls.Add(button);
    }

    // Windows draws the text of a disabled flat button in a color that nearly disappears on the dark page.
    private void PaintDisabledText(object sender, PaintEventArgs e)
    {
        Button button = (Button)sender;
        if (button.Enabled)
        {
            return;
        }
        e.Graphics.Clear(palette.Page);
        using (Pen pen = new Pen(palette.Line))
        {
            e.Graphics.DrawRectangle(pen, 0, 0, button.Width - 1, button.Height - 1);
        }
        TextRenderer.DrawText(e.Graphics, button.Text, button.Font, button.ClientRectangle, palette.Muted,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix);
    }

    private void BuildHeader()
    {
        Panel header = new Panel();
        header.Bounds = new Rectangle(0, 0, PageWidth, 84);
        header.BackColor = palette.Card;
        Controls.Add(header);
        Panel line = new Panel();
        line.Bounds = new Rectangle(0, 83, PageWidth, 1);
        line.BackColor = palette.Line;
        header.Controls.Add(line);
        PictureBox picture = new PictureBox();
        picture.Bounds = new Rectangle(Gutter, 18, 48, 48);
        picture.SizeMode = PictureBoxSizeMode.Zoom;
        picture.BackColor = Color.Transparent;
        picture.Image = LoadIconFrame(48);
        header.Controls.Add(picture);
        AddLabel(header, ProductTitle, 84, 16, PageWidth - 84 - Gutter, 28, new Font("Segoe UI Semibold", 13F), palette.Text);
        AddLabel(header, "Projeto de fã, sem vínculo com EA, Respawn ou CircuitLord.",
            84, 46, PageWidth - 84 - Gutter, 24, new Font("Segoe UI", 8.5F), palette.Muted);
    }

    private void BuildStatus()
    {
        Panel card = new Panel();
        card.Bounds = new Rectangle(Gutter, 100, PageWidth - 2 * Gutter, 74);
        card.BackColor = palette.Card;
        card.Paint += PaintCardBorder;
        Controls.Add(card);
        statusDot.Text = "●";
        statusDot.Bounds = new Rectangle(14, 10, 24, 28);
        statusDot.Font = new Font("Segoe UI", 13F);
        statusDot.ForeColor = palette.Muted;
        statusDot.BackColor = Color.Transparent;
        card.Controls.Add(statusDot);
        statusTitle.Name = "statusTitle";
        statusTitle.Bounds = new Rectangle(40, 10, card.Width - 54, 28);
        statusTitle.Font = new Font("Segoe UI Semibold", 13F);
        statusTitle.ForeColor = palette.Text;
        statusTitle.BackColor = Color.Transparent;
        statusTitle.UseMnemonic = false;
        card.Controls.Add(statusTitle);
        statusDetail.Name = "statusDetail";
        statusDetail.Bounds = new Rectangle(40, 40, card.Width - 54, 24);
        statusDetail.Font = new Font("Segoe UI", 9F);
        statusDetail.ForeColor = palette.Muted;
        statusDetail.BackColor = Color.Transparent;
        statusDetail.UseMnemonic = false;
        card.Controls.Add(statusDetail);
    }

    private void PaintCardBorder(object sender, PaintEventArgs e)
    {
        Control card = (Control)sender;
        using (Pen pen = new Pen(palette.Line))
        {
            e.Graphics.DrawRectangle(pen, 0, 0, card.Width - 1, card.Height - 1);
        }
    }

    private void BuildFolder()
    {
        AddLabel(this, "Pasta do jogo", Gutter, 186, 300, 22, new Font("Segoe UI Semibold", 10F), palette.Text);
        Panel frame = new Panel();
        frame.Bounds = new Rectangle(Gutter, 208, 434, 32);
        frame.BackColor = palette.Card;
        frame.Paint += PaintCardBorder;
        Controls.Add(frame);
        folderBox.Name = "folderBox";
        folderBox.Bounds = new Rectangle(8, 7, frame.Width - 16, 20);
        folderBox.ReadOnly = true;
        folderBox.TabStop = false;
        folderBox.BackColor = palette.Card;
        folderBox.ForeColor = palette.Text;
        folderBox.BorderStyle = BorderStyle.None;
        frame.Controls.Add(folderBox);
        StyleButton(folderButton, "folderButton", "Trocar pasta...", new Rectangle(Gutter + 444, 208, 148, 32), false);
        folderButton.Click += OnChangeFolder;
    }

    private void BuildActions()
    {
        AddLabel(this, "O que você quer fazer?", Gutter, 252, 400, 22, new Font("Segoe UI Semibold", 10F), palette.Text);
        StyleButton(translateButton, "translateButton", "Traduzir para português", new Rectangle(Gutter, 276, 290, 44), true);
        translateButton.Font = new Font("Segoe UI Semibold", 10.5F);
        translateButton.Click += OnTranslate;
        StyleButton(restoreButton, "restoreButton", "Voltar ao inglês", new Rectangle(Gutter + 302, 276, 290, 44), false);
        restoreButton.Font = new Font("Segoe UI Semibold", 10.5F);
        restoreButton.Click += OnRestore;
        Font hint = new Font("Segoe UI", 8.5F);
        AddLabel(this, "Aplica a tradução, e a refaz depois de uma atualização do mod.", Gutter, 324, 290, 36, hint, palette.Muted);
        AddLabel(this, "Devolve os textos originais do mod, sem desinstalar nada.", Gutter + 302, 324, 290, 36, hint, palette.Muted);
    }

    private void BuildResult()
    {
        Panel card = resultCard;
        card.Bounds = new Rectangle(Gutter, 366, PageWidth - 2 * Gutter, ResultHeight);
        card.BackColor = palette.Card;
        card.Paint += PaintCardBorder;
        Controls.Add(card);
        resultStripe.Bounds = new Rectangle(0, 0, 5, card.Height);
        resultStripe.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Bottom;
        resultStripe.BackColor = palette.Neutral;
        card.Controls.Add(resultStripe);
        resultText.Name = "resultText";
        resultText.Bounds = new Rectangle(16, 10, card.Width - 26, card.Height - 20);
        resultText.Multiline = true;
        resultText.ReadOnly = true;
        resultText.TabStop = false;
        resultText.BorderStyle = BorderStyle.None;
        resultText.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top | AnchorStyles.Bottom;
        resultText.BackColor = palette.Card;
        resultText.ForeColor = palette.Text;
        card.Controls.Add(resultText);
        progress.Name = "progress";
        progress.Bounds = new Rectangle(Gutter, 546, PageWidth - 2 * Gutter, 5);
        progress.Style = ProgressBarStyle.Marquee;
        progress.MarqueeAnimationSpeed = 30;
        progress.Visible = false;
        Controls.Add(progress);
    }

    private void BuildFooter()
    {
        StyleButton(copyButton, "copyButton", "Copiar textos sem tradução", new Rectangle(Gutter, 504, 230, 32), false);
        copyButton.Visible = false;
        copyButton.Click += OnCopyPending;
        reportLink.Name = "reportLink";
        reportLink.Text = "Avisar sobre um problema";
        reportLink.Bounds = new Rectangle(Gutter, 568, 190, 24);
        reportLink.LinkClicked += delegate { OpenPage(RepositoryUrl + "/issues"); };
        StyleLink(reportLink);
        modLink.Name = "modLink";
        modLink.Text = "Instalador do mod";
        modLink.Bounds = new Rectangle(Gutter + 200, 568, 150, 24);
        modLink.LinkClicked += delegate { OpenPage(ModInstallerUrl); };
        StyleLink(modLink);
        StyleButton(closeButton, "closeButton", "Fechar", new Rectangle(PageWidth - Gutter - 120, 560, 120, 34), false);
        closeButton.Click += delegate { Close(); };
    }

    private void StyleLink(LinkLabel link)
    {
        link.BackColor = Color.Transparent;
        link.LinkColor = palette.Neutral;
        link.ActiveLinkColor = palette.Neutral;
        link.VisitedLinkColor = palette.Neutral;
        link.Font = new Font("Segoe UI", 9F);
        Controls.Add(link);
    }

    private void OpenPage(string url)
    {
        try
        {
            Process.Start(url).Dispose();
        }
        catch (Win32Exception error)
        {
            ShowResult("Não consegui abrir o navegador: " + error.Message + Environment.NewLine + url, palette.Bad);
        }
    }

    // ============================================================
    //  Running the tool
    // ============================================================
    private ToolResult RunTool(params string[] arguments)
    {
        List<string> all = new List<string>(new string[] { "--wizard", "-NoColor" });
        all.AddRange(arguments);
        all.AddRange(toolArguments);
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        ProcessStartInfo info = new ProcessStartInfo(Path.Combine(folder, ToolExe), CommandLine.Join(all));
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        info.WorkingDirectory = folder;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.StandardOutputEncoding = Encoding.UTF8;
        info.StandardErrorEncoding = Encoding.UTF8;
        ToolResult result = new ToolResult();
        try
        {
            using (Process process = new Process())
            {
                StringBuilder errors = new StringBuilder();
                process.StartInfo = info;
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
                process.Start();
                result.Started = true;
                process.BeginErrorReadLine();
                string output = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                result.Code = process.ExitCode;
                lock (errors)
                {
                    result.Output = output + errors;
                }
            }
        }
        catch (Win32Exception error)
        {
            result.Output = error.Message;
        }
        return result;
    }

    // Everything that runs the tool goes through here, so that nothing unexpected leaves the window stuck and impossible
    // to close. Whatever goes wrong is shown, and the person can still change the folder or close.
    private async void RunBusy(string working, Func<Task> work)
    {
        if (busy)
        {
            return;
        }
        SetBusy(true);
        ShowResult(working, palette.Neutral);
        try
        {
            await work();
        }
        catch (Exception error)
        {
            ShowResult("Algo inesperado aconteceu: " + error.Message, palette.Bad);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetBusy(bool value)
    {
        busy = value;
        progress.Visible = value;
        folderButton.Enabled = !value;
        closeButton.Enabled = !value;
        if (value)
        {
            translateButton.Enabled = false;
            restoreButton.Enabled = false;
        }
    }

    private void ShowResult(string text, Color color)
    {
        resultText.Text = text;
        resultStripe.BackColor = color;
        FitResultText();
    }

    private void ShowCopyButton(bool visible)
    {
        copyButton.Visible = visible;
        resultCard.Height = visible ? ResultHeightWithCopy : ResultHeight;
        FitResultText();
    }

    private void FitResultText()
    {
        Size needed = TextRenderer.MeasureText(resultText.Text, resultText.Font, new Size(resultText.Width, int.MaxValue), TextFormatFlags.WordBreak);
        resultText.ScrollBars = needed.Height > resultText.Height ? ScrollBars.Vertical : ScrollBars.None;
    }

    // The lines a person should read: no numbered steps, no drawn boxes and no symbol at the start of the line.
    private static List<string> ReadableLines(string output)
    {
        List<string> lines = new List<string>();
        foreach (string raw in output.Replace("\uFEFF", "").Split('\n'))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line.StartsWith(StatusPrefix, StringComparison.Ordinal)
                || Regex.IsMatch(line, @"^\[\d+/\d+\]") || Regex.IsMatch(line, @"^[+|╭│╰]"))
            {
                continue;
            }
            lines.Add(line);
        }
        return lines;
    }

    private static string CleanSymbol(string line)
    {
        return Regex.Replace(line, @"^[x!*✖▲●] ", "");
    }

    private static string FailureText(ToolResult result)
    {
        if (!result.Started)
        {
            return "Não consegui abrir o programa da tradução: um antivírus pode ter levado o arquivo. Instale de novo para trazê-lo de volta. Nada foi alterado no jogo."
                + Environment.NewLine + Environment.NewLine + result.Output;
        }
        List<string> lines = new List<string>();
        foreach (string line in ReadableLines(result.Output))
        {
            lines.Add(CleanSymbol(line));
        }
        if (lines.Count == 0)
        {
            return "O programa da tradução parou com o código " + result.Code + ".";
        }
        return string.Join(Environment.NewLine, lines);
    }

    // On success only the warnings matter: the missing file skipped, the mod installer left open.
    private static string WarningsOf(string output)
    {
        StringBuilder warnings = new StringBuilder();
        foreach (string line in ReadableLines(output))
        {
            if (Regex.IsMatch(line, @"^[!▲] ") && !line.Contains("ainda não têm tradução"))
            {
                warnings.Append(Environment.NewLine).Append(Environment.NewLine).Append(CleanSymbol(line));
            }
        }
        return warnings.ToString();
    }

    // ============================================================
    //  Status
    // ============================================================
    private async Task RefreshStatus(string chosenFolder, bool showFinding)
    {
        List<string> arguments = new List<string>(new string[] { "-Action", "Status", "-Json", "-NonInteractive" });
        if (chosenFolder != null)
        {
            arguments.Add("-GameDir");
            arguments.Add(chosenFolder);
        }
        ToolResult result = await Task.Run(() => RunTool(arguments.ToArray()));
        Dictionary<string, object> status = ParseStatus(result.Output);
        if (status == null)
        {
            gameDir = null;
            folderBox.Text = "";
            ShowStatus("Não consegui ler a situação do jogo", "Veja o aviso abaixo.", palette.Bad);
            ShowCopyButton(false);
            translateButton.Enabled = false;
            restoreButton.Enabled = false;
            ShowResult(FailureText(result), palette.Bad);
            return;
        }
        ApplyStatus(status, showFinding);
    }

    private static Dictionary<string, object> ParseStatus(string output)
    {
        foreach (string line in output.Split('\n'))
        {
            string text = line.Trim();
            if (text.StartsWith(StatusPrefix, StringComparison.Ordinal))
            {
                try
                {
                    return new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(text.Substring(StatusPrefix.Length));
                }
                catch (ArgumentException)
                {
                    return null;
                }
                catch (InvalidOperationException)
                {
                    return null;
                }
            }
        }
        return null;
    }

    private static string StringOf(Dictionary<string, object> status, string key)
    {
        object value;
        return status.TryGetValue(key, out value) && value != null ? value.ToString() : "";
    }

    private void ShowStatus(string title, string detail, Color color)
    {
        statusTitle.Text = title;
        statusDetail.Text = detail;
        statusDot.ForeColor = color;
    }

    private void ApplyStatus(Dictionary<string, object> status, bool showFinding)
    {
        gameDir = StringOf(status, "gameDir");
        folderBox.Text = gameDir;
        folderBox.SelectionStart = folderBox.Text.Length;
        issueListPath = StringOf(status, "issueListPath");
        translateButton.Text = "Traduzir para português";
        translateButton.Enabled = false;
        restoreButton.Enabled = false;
        ShowCopyButton(false);

        string problem = StringOf(status, "error");
        if (problem.Length > 0)
        {
            bool noGame = gameDir.Length == 0 && problem.StartsWith("Não encontrei o Titanfall 2", StringComparison.Ordinal);
            ShowStatus(noGame ? "Não encontrei o jogo" : "Não consegui ler a situação do jogo",
                noGame ? "Use \"Trocar pasta...\" e escolha a pasta que tem o Titanfall2.exe." : "Veja o aviso abaixo.", palette.Bad);
            string suggestion = StringOf(status, "suggestion");
            ShowResult(noGame ? "Clique em \"Trocar pasta...\". No EA app ou na Steam, a opção \"Procurar arquivos locais\" abre a pasta do jogo."
                : problem + Environment.NewLine + suggestion, palette.Warning);
            return;
        }

        int translated = 0, stale = 0, original = 0;
        object[] files = status["files"] is ArrayList ? ((ArrayList)status["files"]).ToArray() : new object[0];
        foreach (object entry in files)
        {
            switch (StringOf((Dictionary<string, object>)entry, "status"))
            {
                case "translated":
                    translated++;
                    break;
                case "new-dictionary":
                case "modified-externally":
                    stale++;
                    break;
                case "original":
                    original++;
                    break;
            }
        }

        string modVersion = StringOf(status, "modVersion");
        string version = "Tradução v" + StringOf(status, "version");
        string detail = (modVersion.Length > 0 ? "Mod VR v" + modVersion + "  ·  " : "") + version;
        string backupDate = StringOf(status, "backupDate");
        if (backupDate.Length > 0)
        {
            DateTime saved;
            if (DateTime.TryParseExact(backupDate, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out saved))
            {
                backupDate = saved.ToString("dd/MM/yyyy", CultureInfo.InvariantCulture);
            }
            detail += "  ·  Original guardado em " + backupDate;
        }

        if (!(bool)status["modInstalled"])
        {
            ShowStatus("O mod não está instalado nesta pasta", version, palette.Bad);
            if (showFinding)
            {
                ShowResult("Instale o mod pelo instalador do CircuitLord (link abaixo) ou troque a pasta do jogo.", palette.Warning);
            }
            return;
        }

        translateButton.Enabled = true;
        restoreButton.Enabled = translated + stale > 0;
        string finding;
        Color findingColor = palette.Neutral;
        if (translated > 0 && stale == 0 && original == 0)
        {
            ShowStatus("O jogo está em português", detail, palette.Good);
            translateButton.Text = "Reaplicar a tradução";
            finding = "Tudo certo. Se o mod for atualizado, volte aqui e reaplique a tradução.";
        }
        else if (translated + stale > 0)
        {
            ShowStatus("A tradução precisa ser refeita", detail, palette.Warning);
            translateButton.Text = "Reaplicar a tradução";
            finding = "O mod mudou ou há traduções novas. Clique em \"Reaplicar a tradução\".";
            findingColor = palette.Warning;
        }
        else
        {
            ShowStatus("O jogo está em inglês", detail, palette.Neutral);
            finding = "Feche o jogo e clique em \"Traduzir para português\".";
        }

        pendingCount = Convert.ToInt32(status["pendingCount"]);
        ShowCopyButton(pendingCount > 0);
        if ((bool)status["oldPackage"])
        {
            finding = "Há um pacote antigo de tradução neste jogo. Desinstale em Configurações do Windows, Aplicativos, antes de traduzir.";
            findingColor = palette.Warning;
        }
        else if (pendingCount > 0)
        {
            finding = PendingText(pendingCount);
            findingColor = palette.Warning;
        }
        if (showFinding)
        {
            ShowResult(finding, findingColor);
        }
    }

    private static string PendingText(int pending)
    {
        return pending + " texto(s) do mod ainda não têm tradução e aparecem em inglês no jogo. O jogo já pode ser aberto. "
            + "Para ajudar, copie a lista e cole em \"Avisar sobre um problema\": ela só tem chave e hash, sem texto do mod.";
    }

    // ============================================================
    //  Actions
    // ============================================================
    private void OnTranslate(object sender, EventArgs e)
    {
        RunBusy("Aplicando a tradução. Se o Windows pedir permissão de administrador, confirme.", () => RunAction("Translate"));
    }

    private void OnRestore(object sender, EventArgs e)
    {
        RunBusy("Devolvendo os textos originais. Se o Windows pedir permissão de administrador, confirme.", () => RunAction("Restore"));
    }

    private async Task RunAction(string action)
    {
        string folder = gameDir;
        ToolResult result = await Task.Run(() => RunTool("-Action", action, "-GameDir", folder));
        bool succeeded = result.Started && (result.Code == 0 || result.Code == ExitPending);
        await RefreshStatus(null, false);
        if (!succeeded)
        {
            ShowResult(FailureText(result), palette.Bad);
        }
        else if (result.Code == ExitPending)
        {
            ShowResult("Tradução aplicada. " + PendingText(pendingCount) + WarningsOf(result.Output), palette.Warning);
        }
        else if (action == "Translate")
        {
            string said = result.Output.Contains("Tudo atualizado")
                ? "A tradução já estava aplicada e nada mudou: nenhum arquivo foi alterado."
                : "Tradução aplicada. Abra o jogo pelo botão \"Launch in VR\" do instalador do mod.";
            ShowResult(said + WarningsOf(result.Output), palette.Good);
        }
        else
        {
            string said = result.Output.Contains("Nada a restaurar")
                ? "Os textos já eram os originais em inglês: nenhum arquivo foi alterado."
                : "Os textos do mod voltaram ao inglês, exatamente como eram antes da tradução.";
            ShowResult(said, palette.Good);
        }
    }

    private void OnChangeFolder(object sender, EventArgs e)
    {
        if (busy)
        {
            return;
        }
        string chosen;
        try
        {
            chosen = FolderPicker.Pick(Handle, "Escolha a pasta que tem o Titanfall2.exe", gameDir);
        }
        catch (Exception error)
        {
            // Windows failures reach here under many exception types.
            ShowResult("Não consegui abrir a escolha de pasta: " + error.Message, palette.Bad);
            return;
        }
        if (chosen == null)
        {
            return;
        }
        if (!File.Exists(Path.Combine(chosen, "Titanfall2.exe")))
        {
            ShowResult("Não achei o Titanfall2.exe nesta pasta. A pasta do jogo continua a mesma."
                + Environment.NewLine + chosen, palette.Bad);
            return;
        }
        RunBusy("Conferindo a pasta escolhida...", () => RefreshStatus(chosen, true));
    }

    private void OnCopyPending(object sender, EventArgs e)
    {
        try
        {
            Clipboard.SetText(File.ReadAllText(issueListPath, Encoding.UTF8));
            ShowResult("Lista copiada. Abra \"Avisar sobre um problema\" e cole no texto do aviso.", palette.Good);
        }
        catch (Exception error)
        {
            if (!(error is IOException || error is UnauthorizedAccessException || error is ArgumentException || error is ExternalException))
            {
                throw;
            }
            ShowResult("Não consegui copiar a lista: " + error.Message, palette.Bad);
        }
    }

    private const int DarkTitleBarAttribute = 20;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr window, string appName, string idList);
}

// The folder dialog of current Windows, with the address bar where a copied path can be pasted.
internal static class FolderPicker
{
    private const uint PickFolders = 0x20;
    private const uint ForceFileSystem = 0x40;
    private const uint FileSystemPath = 0x80058000;
    private const int Cancelled = unchecked((int)0x800704C7);

    public static string Pick(IntPtr owner, string title, string startFolder)
    {
        IFileOpenDialog dialog = (IFileOpenDialog)new FileOpenDialogObject();
        try
        {
            uint options;
            dialog.GetOptions(out options);
            dialog.SetOptions(options | PickFolders | ForceFileSystem);
            dialog.SetTitle(title);
            if (!string.IsNullOrEmpty(startFolder) && Directory.Exists(startFolder))
            {
                IShellItem start;
                Guid item = typeof(IShellItem).GUID;
                if (SHCreateItemFromParsingName(startFolder, IntPtr.Zero, ref item, out start) == 0)
                {
                    dialog.SetFolder(start);
                }
            }
            int shown = dialog.Show(owner);
            if (shown == Cancelled)
            {
                return null;
            }
            Marshal.ThrowExceptionForHR(shown);
            IShellItem result;
            dialog.GetResult(out result);
            IntPtr path;
            result.GetDisplayName(FileSystemPath, out path);
            try
            {
                return Marshal.PtrToStringUni(path);
            }
            finally
            {
                Marshal.FreeCoTaskMem(path);
            }
        }
        finally
        {
            Marshal.ReleaseComObject(dialog);
        }
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHCreateItemFromParsingName(string path, IntPtr context, ref Guid id, out IShellItem item);

    [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
    private class FileOpenDialogObject
    {
    }

    // Only the order of the methods matters to Windows: the ones not used here keep their place with no parameters.
    [ComImport, Guid("D57C7288-D4AD-4768-BE02-9D969532D960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog
    {
        [PreserveSig]
        int Show(IntPtr owner);
        void SetFileTypes();
        void SetFileTypeIndex();
        void GetFileTypeIndex();
        void Advise();
        void Unadvise();
        void SetOptions(uint options);
        void GetOptions(out uint options);
        void SetDefaultFolder();
        void SetFolder(IShellItem item);
        void GetFolder();
        void GetCurrentSelection();
        void SetFileName();
        void GetFileName();
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
        void SetOkButtonLabel();
        void SetFileNameLabel();
        void GetResult(out IShellItem item);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler();
        void GetParent();
        void GetDisplayName(uint kind, out IntPtr name);
    }
}
