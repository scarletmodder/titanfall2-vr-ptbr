# Tests the window of the Start menu by pressing its buttons, with the synthetic mod and a test dictionary.
# It needs a Windows session with an open desktop: without one the window never shows.
# Usage: powershell -File tests\test-window.ps1 [-Window dist\Titanfall2VR-PTBR-Window.exe]
[CmdletBinding()]
param([string]$Window)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot 'synthetic.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -ReferencedAssemblies Accessibility @'
using System;
using System.Runtime.InteropServices;
public static class WindowButtons {
    [DllImport("oleacc.dll")] private static extern int AccessibleObjectFromWindow(IntPtr window, uint id, ref Guid iid, [MarshalAs(UnmanagedType.IDispatch)] out object accessible);
    // What a screen reader uses: a flat button ignores a click message unless it is uncovered under the mouse.
    public static void Press(IntPtr button) {
        Guid iid = typeof(Accessibility.IAccessible).GUID;
        object accessible;
        Marshal.ThrowExceptionForHR(AccessibleObjectFromWindow(button, 0xFFFFFFFC, ref iid, out accessible));
        ((Accessibility.IAccessible)accessible).accDoDefaultAction(0);
    }
}
'@

$ROOT = Split-Path $PSScriptRoot -Parent
if (-not $Window) { $Window = Join-Path $ROOT 'dist\Titanfall2VR-PTBR-Window.exe' }
$Window = (Resolve-Path -LiteralPath $Window).Path
$Tool = Join-Path (Split-Path $Window) 'Titanfall2VR-PTBR.exe'
$LAB = Join-Path ([IO.Path]::GetTempPath()) ('tf2vr window ' + [guid]::NewGuid().ToString('N'))
$GAME = Join-Path $LAB 'game with space'
$PURE = Join-Path $LAB 'pure'
$DATA = Join-Path $LAB 'test data'
$DIC = Join-Path $LAB 'dic'
$TOOL_ARGS = @('-DataDir', $DATA, '-DictionaryDir', $DIC, '-GameProcesses', 'process-that-does-not-exist')
$WAIT_SECONDS = 60

$script:failures = 0
$script:total = 0
$script:app = $null
function Check($cond, $msg) {
    $script:total++
    if ($cond) { Write-Host "  OK    $msg" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:failures++
        if ($script:app) { Write-Host "        Status: $(Read-Label 'statusTitle')`n        Result: $(Read-Result)" }
    }
}
function BytesEqual($a, $b) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b)) }
function Originals { foreach ($rel in $ALL_FILES) { if (-not (BytesEqual (Join-Path $GAME $rel) (Join-Path $PURE $rel))) { return $false } }; return $true }

# Windows Forms controls reach UI Automation as plain panes with no usable id: each is found by what it says or by its
# place after a fixed text.
function Find-Part([string]$id) {
    $root = [Windows.Automation.AutomationElement]::FromHandle($script:app.MainWindowHandle)
    $all = @($root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition))
    function After([string]$text, [int]$steps) {
        for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i].Current.Name -ceq $text) { return $all[$i + $steps] } }
        throw "No control says: $text"
    }
    function Saying([string]$pattern) {
        foreach ($e in $all) { if ($e.Current.Name -cmatch $pattern) { return $e } }
        throw "No control matches: $pattern"
    }
    switch ($id) {
        'statusTitle' { return After ([string][char]0x25CF) 1 }
        'folderBox' { return After 'Pasta do jogo' 2 }
        'resultText' { return After 'Devolve os textos originais do mod, sem desinstalar nada.' 3 }
        'translateButton' { return Saying '^(Traduzir para português|Reaplicar a tradução)$' }
        'restoreButton' { return Saying '^Voltar ao inglês$' }
        'folderButton' { return Saying '^Trocar pasta' }
        'closeButton' { return Saying '^Fechar$' }
        'copyButton' { return Saying '^Copiar textos' }
    }
    throw "Unknown control: $id"
}
function Read-Label([string]$id) { return [string](Find-Part $id).Current.Name }
function Read-Result { return Read-Label 'resultText' }
function Press([string]$id) { [WindowButtons]::Press([IntPtr](Find-Part $id).Current.NativeWindowHandle) }
function Wait-Idle {
    foreach ($i in 1..($WAIT_SECONDS * 4)) {
        Start-Sleep -Milliseconds 250
        if ((Find-Part 'closeButton').Current.IsEnabled) { return $true }
    }
    return $false
}
function Open-Window {
    $arguments = @($TOOL_ARGS | ForEach-Object { if ($_ -match ' ') { "`"$_`"" } else { $_ } })
    $script:app = Start-Process -FilePath $Window -ArgumentList $arguments -PassThru
    foreach ($i in 1..($WAIT_SECONDS * 4)) {
        Start-Sleep -Milliseconds 250
        $script:app.Refresh()
        if ($script:app.MainWindowHandle -ne [IntPtr]::Zero) { break }
    }
    if ($script:app.MainWindowHandle -eq [IntPtr]::Zero) { throw 'The window did not open.' }
    return (Wait-Idle)
}
function Close-Window {
    Press 'closeButton'
    if (-not $script:app.WaitForExit(10000)) { $script:app.Kill(); Check $false 'the Close button closes the window' }
    $script:app = $null
}

try {
    New-Item -ItemType Directory -Force -Path $DIC | Out-Null
    Build-Dictionary $DIC
    Build-Mod $GAME
    Build-Mod $PURE

    Write-Host '[1] No game known: says so, and only the folder can be changed'
    $elsewhere = @('-DataDir', (Join-Path $LAB 'other data'), '-DictionaryDir', $DIC)
    # On a machine with the game installed the tool finds it, so there is nothing to see here.
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $found = (& $Tool @('-Action', 'Status', '-Json', '-NonInteractive', '-NoColor') @elsewhere 2>&1 | Out-String)
    $ErrorActionPreference = $eap
    if ($found -match '"gameDir":\s*null') {
        $keep = $TOOL_ARGS; $TOOL_ARGS = $elsewhere
        Check (Open-Window) 'the window opens and settles'
        Check ((Read-Label 'statusTitle') -match 'Não encontrei o jogo') 'it says the game was not found'
        Check (-not (Find-Part 'translateButton').Current.IsEnabled) 'translating is off'
        Check ((Find-Part 'folderButton').Current.IsEnabled) 'changing the folder is on'
        Close-Window
        $TOOL_ARGS = $keep
    }

    Write-Host '[2] Saved folder, game in English'
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $Tool @('-Action', 'Status', '-NonInteractive', '-NoColor', '-GameDir', $GAME) @TOOL_ARGS 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    Check (Open-Window) 'the window opens and settles'
    Check ((Read-Label 'statusTitle') -match 'em inglês') 'it says the game is in English'
    Check ((Read-Label 'folderBox') -ceq $GAME) 'it shows the folder'
    Check (-not (Find-Part 'restoreButton').Current.IsEnabled) 'going back to English is off'

    Write-Host '[3] Translate, and the window does not close in the middle'
    Press 'translateButton'
    Start-Sleep -Milliseconds 200
    [void]$script:app.CloseMainWindow()
    Start-Sleep -Milliseconds 200
    Check (-not $script:app.HasExited) 'asked to close while working, it stays open'
    Check ((Read-Result) -match 'Espere terminar') 'and it says why'
    Check (Wait-Idle) 'it finishes'
    Check (-not (Originals)) 'the files were translated'
    Check ((Read-Result) -match 'Tradução aplicada') "it says so with its accents: $(Read-Result)"
    Check ((Read-Label 'statusTitle') -match 'em português') 'the status changes'
    Check ((Read-Label 'translateButton') -match 'Reaplicar') 'the button now offers to reapply'

    Write-Host '[4] Reapply with nothing to do'
    Press 'translateButton'
    Check (Wait-Idle) 'it finishes'
    Check ((Read-Result) -match 'nenhum arquivo foi alterado') 'it says nothing changed'

    Write-Host '[5] A second copy does not open'
    $second = Start-Process -FilePath $Window -PassThru
    Check ($second.WaitForExit(10000)) 'the second copy leaves at once'

    Write-Host '[6] Back to English'
    Press 'restoreButton'
    Check (Wait-Idle) 'it finishes'
    Check (Originals) 'the originals are back, byte by byte'
    Check ((Read-Result) -match 'voltaram ao inglês') 'it says so'
    Check ((Read-Label 'statusTitle') -match 'em inglês') 'the status changes'

    Write-Host '[7] A failure shows the reason'
    Close-Window
    $TOOL_ARGS = @('-DataDir', $DATA, '-DictionaryDir', $DIC, '-GameProcesses', (Get-Process -Id $PID).ProcessName)
    Check (Open-Window) 'the window opens and settles'
    Press 'translateButton'
    Check (Wait-Idle) 'it finishes'
    Check ((Read-Result) -match 'O Titanfall 2 está aberto') 'game open: it says so, in Portuguese'
    Check ((Read-Result) -notmatch '\[\d/\d\]') 'without the numbered steps'
    Check (Originals) 'nothing was written'
    Close-Window

    Write-Host '[8] Texts with no translation: says how many and offers the list'
    $TOOL_ARGS = @('-DataDir', $DATA, '-DictionaryDir', $DIC, '-GameProcesses', 'process-that-does-not-exist')
    $tokens = (Get-TokensText).Replace('"XT_EMPTY" ""', "`"XT_EMPTY`" `"`"`r`n        `"XT_NEW`" `"Brand new zorblat`"")
    Write-TestFile (Join-Path $GAME $TOK) $tokens $UTF16
    Check (Open-Window) 'the window opens and settles'
    Press 'translateButton'
    Check (Wait-Idle) 'it finishes'
    Check ((Read-Result) -match '^Tradução aplicada\. 1 texto\(s\) do mod ainda não têm tradução') "it says how many: $(Read-Result)"
    Press 'copyButton'
    Start-Sleep -Milliseconds 500
    Check ((Read-Result) -match '^Lista copiada') 'the list is copied'
    Close-Window
} finally {
    if ($script:app -and -not $script:app.HasExited) { $script:app.Kill() }
    Remove-Item -LiteralPath $LAB -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:failures -eq 0) { Write-Host "ALL $($script:total) WINDOW TESTS PASSED" -ForegroundColor Green }
else { Write-Host "$($script:failures) FAILURE(S) of $($script:total) in the window" -ForegroundColor Red }
exit $script:failures
