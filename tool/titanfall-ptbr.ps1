# titanfall-ptbr.ps1
# PT-BR translation of the texts of the Titanfall 2 VR mod (by CircuitLord). Fan project, not affiliated with the mod.
#
#   Translate : if the mod changed (or the dictionary did), keeps the mod's original as a backup and
#               applies the translation. If nothing changed, it only says everything is up to date.
#   Restore   : puts the original (English) texts of the installed mod version back.
#   Status    : shows the state, changing nothing.
#
# One backup only: always the original of the last mod version this tool has seen.
# A translated file carries a line with the identifier $MARKER_ID. NEVER change that identifier:
# it is what stops a translated file from being mistaken for the original and becoming a backup.
#
# The dictionary (.\translations) contains no text from the mod: each entry stores the SHA-256 of the
# English text and the translation. The real line always comes from the mod installed on the user's machine.
# Data (chosen game folder, backup, state) lives in -DataDir.
# When the game requires administrator rights, the executable does the elevation: it reopens itself
# elevated and runs a verified copy of this script, with data in a folder only administrators can write
# (-AdminDataDir).
# Works on PowerShell 7 and Windows PowerShell 5.1. This file must be UTF-8 with BOM.

[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Translate', 'Restore', 'Status')]
    [string]$Action = 'Menu',
    [string]$GameDir,
    [string]$DataDir = (Join-Path $env:LOCALAPPDATA 'ScarletModder\Titanfall2VR-PTBR'),
    [string]$DictionaryDir,
    [string]$AdminDataDir,
    [switch]$NonInteractive,
    [switch]$NoColor,
    [string[]]$GameProcesses = @('Titanfall2', 'Titanfall2VRLauncher'),
    [string[]]$InstallerProcesses = @('CircuitLordVRModInstaller'),
    [switch]$Pause,
    [switch]$Elevated,
    [switch]$Uninstalling,
    [switch]$ViaExe,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
# On Windows PowerShell 5.1, $PSScriptRoot is still empty in the param() default values.
if (-not $DictionaryDir) { $DictionaryDir = Join-Path $PSScriptRoot 'translations' }

# ============================================================
#  Constants
# ============================================================
$VERSION = '1.0.1'
$EXIT_NEEDS_ELEVATION = 20

# On-disk format written by v1.0.0 (Portuguese literals on purpose). Newer builds must keep recognising
# what v1.0.0 wrote, so these values must never change:
#   - the marker id and the full marker line written into translated files;
#   - the temporary and probe file names, and the leftovers of the old translation package;
#   - the file and folder names inside the data folder;
#   - the JSON field names inside config.json, estado.json, pendentes.json and backup.json
#     (pastaJogo, origem, salvoEm, versaoMod, aplicadoEm, hashDicionario, arquivos, data, jogo,
#     itens, tipo, chave, linha, enHash, motivo), read and written as literal strings below.
$MARKER_ID = 'titanfall2-vr-ptbr'
$MARKER = "// $MARKER_ID traduzido para PT-BR. O original esta no backup da ferramenta."
$TEMP_SUFFIX = '.tmp-ptbr'
$PROBE_PREFIX = '.ptbr-teste-'
$LEGACY_COPY_SUFFIX = '.orig-ptbr'
$CONFIG_FILE_NAME = 'config.json'
$STATE_FILE_NAME = 'estado.json'
$PENDING_FILE_NAME = 'pendentes.json'
$ISSUE_LIST_FILE_NAME = 'pendentes-para-issue.txt'
$BACKUP_DIR_NAME = 'backup'
$BACKUP_INFO_FILE_NAME = 'backup.json'
$ADMIN_GAME_MARK_FILE_NAME = 'jogo.txt'

$RE_TOKEN = '^(\s*)"([A-Za-z0-9_]+)"(\s+)"((?:[^"\\]|\\.)*)"(\s*)$'
$RE_LITERAL = '"((?:[^"\\]|\\.)*)"'
$RE_LITERAL_CONTENT = '^(?:[^"\\]|\\.)*\z'
$RE_MARKS = '%[^%\s]*%|%s\d|\|\||\\n'
$REL_MOD = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\'
$REL_TOKENS = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\resource\tf2vr_english.txt'
$REL_MOD_REGISTRY = '.circuitlord-vr-mods\Titanfall2VR.json'
$REL_OLD_PACKAGE = 'TF2VR\mods\TF2VR.PTBR'
$URL_INSTALLER = 'https://github.com/CircuitLord/CircuitLordVRModInstaller'
$URL_ISSUES = 'https://github.com/scarletmodder/titanfall2-vr-ptbr/issues'
$UTF8_NO_BOM = New-Object System.Text.UTF8Encoding($false)
$UTF16_BOM = New-Object System.Text.UnicodeEncoding($false, $true)

# ============================================================
#  Terminal interface
# ============================================================
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Output = -not [Console]::IsOutputRedirected
$script:Color = -not ($NoColor -or $env:NO_COLOR -or $env:TERM -eq 'dumb')
$script:Animate = $script:Output -and -not $NonInteractive
$script:Unicode = [bool]($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode')

if ($script:Unicode) {
    $S = @{ ok = [string][char]0x2714; error = [string][char]0x2716; warn = [string][char]0x25B2; info = [string][char]0x25CF
            arrow = [string][char]0x203A; bullet = [string][char]0x2022
            h = [string][char]0x2500; v = [string][char]0x2502; tl = [string][char]0x256D; tr = [string][char]0x256E; bl = [string][char]0x2570; br = [string][char]0x256F
            spin = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F | ForEach-Object { [string][char]$_ }) }
} else {
    $S = @{ ok = '+'; error = 'x'; warn = '!'; info = '*'; arrow = '>'; bullet = '-'
            h = '-'; v = '|'; tl = '+'; tr = '+'; bl = '+'; br = '+'; spin = @('|', '/', '-', '\') }
}

function W([string]$text, [string]$color = 'Gray', [switch]$n) {
    if ($script:Color) { Write-Host $text -ForegroundColor $color -NoNewline:$n }
    else { Write-Host $text -NoNewline:$n }
}

function Write-Line([string]$symbol, [string]$symbolColor, [string]$text, [string]$color = 'Gray') {
    W "  $symbol " $symbolColor -n; W $text $color
}

function Ok($t) { Write-Line $S.ok 'Green' $t }
function Warn($t) { Write-Line $S.warn 'Yellow' $t 'Yellow' }
function Fail($t) { Write-Line $S.error 'Red' $t 'Red' }
function Info($t) { Write-Line $S.info 'DarkCyan' $t }
function Hint($t) { W "    $t" 'DarkGray' }

function Show-Header {
    if ($script:Output -and -not $NonInteractive) { try { Clear-Host } catch { } }
    $title = 'TITANFALL 2 VR  ' + $S.bullet + '  TRADUÇÃO PT-BR'
    $sub = 'textos do mod VR do CircuitLord em português do Brasil'
    $width = [Math]::Max($title.Length, $sub.Length) + 6
    W ''
    W ('  ' + $S.tl + ($S.h * $width) + $S.tr) 'DarkCyan'
    W ('  ' + $S.v) 'DarkCyan' -n; W ('   ' + $title.PadRight($width - 3)) 'Cyan' -n; W $S.v 'DarkCyan'
    W ('  ' + $S.v) 'DarkCyan' -n; W ('   ' + $sub.PadRight($width - 3)) 'DarkGray' -n; W $S.v 'DarkCyan'
    W ('  ' + $S.bl + ($S.h * $width) + $S.br) 'DarkCyan'
    W ''
}

function Write-SectionTitle([string]$t) {
    W ''
    W ('  ' + $t.ToUpper()) 'White'
    W ('  ' + ($S.h * $t.Length)) 'DarkGray'
}

function Write-Field([string]$label, [string]$value, [string]$color = 'White') {
    W ('  ' + $label.PadRight(21)) 'DarkGray' -n; W $value $color
}

function Write-Box([string]$title, [string[]]$lines, [string]$color = 'Green') {
    $width = ($lines + @($title) | Measure-Object -Property Length -Maximum).Maximum + 4
    W ''
    W ('  ' + $S.tl + $S.h + ' ') $color -n; W $title $color -n; W (' ' + ($S.h * [Math]::Max(1, $width - $title.Length - 3)) + $S.tr) $color
    foreach ($l in $lines) { W ('  ' + $S.v + '  ') $color -n; W $l.PadRight($width - 2) 'White' -n; W $S.v $color }
    W ('  ' + $S.bl + ($S.h * $width) + $S.br) $color
}

# Numbered step: spinner while preparing, replaced by the result (and the time) when done.
$script:StepTotal = 0
$script:StepCurrent = 0
function Steps([int]$total) { $script:StepTotal = $total; $script:StepCurrent = 0 }
function Step([string]$text, [scriptblock]$block) {
    $script:StepCurrent++
    $prefix = "  [$($script:StepCurrent)/$($script:StepTotal)] "
    $clear = "`r" + (' ' * ($prefix.Length + $text.Length + 8)) + "`r"
    if ($script:Animate) {
        foreach ($f in ($S.spin | Select-Object -First 6)) {
            W ("`r" + $prefix) 'DarkGray' -n; W "$f " 'Cyan' -n; W "$text..." 'Gray' -n
            Start-Sleep -Milliseconds 35
        }
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $result = & $block
    } catch {
        if ($script:Animate) { W $clear -n }
        W $prefix 'DarkGray' -n; W "$($S.error) " 'Red' -n; W $text 'Red'
        throw
    }
    $detail = if ($result -is [string] -and $result) { $result } else { '' }
    if ($script:Animate) { W $clear -n }
    W $prefix 'DarkGray' -n; W "$($S.ok) " 'Green' -n; W $text 'Gray' -n
    if ($detail) { W "  $detail" 'DarkGray' -n }
    W ("  $($clock.ElapsedMilliseconds) ms") 'DarkGray'
}

# Returns $null when there is no more input (window closed, redirected input already at the end).
function Ask([string]$text) {
    # Run by the wizard there is no window to answer in: a question counts as left unanswered.
    if ($NoPrompt) { return $null }
    W ''
    W "  $($S.arrow) " 'Cyan' -n; W $text 'White' -n; W ' ' -n
    $r = Read-Host
    if ($null -eq $r) { W ''; return $null }
    return $r.Trim()
}

function Wait-Enter {
    if ($NonInteractive -or -not $script:Output) { return }
    W ''
    W '  Aperte Enter para continuar' 'DarkGray' -n
    Read-Host | Out-Null
}

# Expected error: a message for humans, with what to do next.
function Throw-FriendlyError([string]$message, [string]$suggestion) {
    $e = New-Object System.Exception($message)
    $e.Data['sugestao'] = $suggestion
    throw $e
}

function Get-VersionLabel($v) { if ($v) { return "v$v" } else { return 'versão desconhecida' } }

# ============================================================
#  Files
# ============================================================
function Read-Json($path, [string]$suggestion = 'Apague esse arquivo e rode a ferramenta de novo.') {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
    catch { Throw-FriendlyError "O arquivo $path está corrompido." $suggestion }
}

function Write-Json($path, $object) {
    Replace-File $path ($UTF8_NO_BOM.GetBytes(($object | ConvertTo-Json -Depth 8)))
}

# Writes to a temporary file in the same folder and swaps in one go (Windows ReplaceFile): the target
# is never left half written or missing, even if the swap fails.
function Replace-File($path, [byte[]]$bytes) {
    $tmp = "$path$TEMP_SUFFIX"
    try {
        [IO.File]::WriteAllBytes($tmp, $bytes)
        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value, $true) }
        else { [IO.File]::Move($tmp, $path) }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Get-TextBytes($text, $encoding) {
    $preamble = $encoding.GetPreamble()
    $body = $encoding.GetBytes($text)
    if ($preamble.Length -eq 0) { return $body }
    $out = New-Object byte[] ($preamble.Length + $body.Length)
    [Array]::Copy($preamble, $out, $preamble.Length)
    [Array]::Copy($body, 0, $out, $preamble.Length, $body.Length)
    return $out
}

# Decodes honouring the BOM (UTF-16 in the texts file, UTF-8 in the scripts).
function Get-TextFromBytes([byte[]]$bytes) {
    $reader = New-Object IO.StreamReader((New-Object IO.MemoryStream(, $bytes)), $UTF8_NO_BOM, $true)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Get-BytesHash([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

# Lowercase hexadecimal SHA-256 of the UTF-8 text: this is the dictionary's enHash.
function Get-TextHash([string]$text) { return (Get-BytesHash ($UTF8_NO_BOM.GetBytes($text))).ToLowerInvariant() }

function Get-FileSha($path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

function Split-Lines($text) {
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    return @{ Lines = $text -split [regex]::Escape($nl); NL = $nl }
}

function Test-HasMarker($path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    return ([IO.File]::ReadAllText($path)).Contains($MARKER_ID)
}

function Get-Prop($object, [string]$name) {
    if ($null -eq $object) { return $null }
    $p = $object.PSObject.Properties[$name]
    if ($p) { return $p.Value } else { return $null }
}

function Count-Char([string]$text, [char]$c) { return @($text.ToCharArray() | Where-Object { $_ -eq $c }).Count }

# Tests what writing really does: create a file in the folder and swap the target file.
# Returns 'ok', 'permission' (needs administrator or is read-only) or 'in-use' (another program has
# the file open: administrator does not help).
function Test-CanWrite($path) {
    $probe = Join-Path (Split-Path $path) ($PROBE_PREFIX + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force
    } catch {
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
        return 'permission'
    }
    try { $fs = [IO.File]::Open($path, 'Open', 'ReadWrite', 'Read'); $fs.Close(); return 'ok' }
    catch [System.UnauthorizedAccessException] { return 'permission' }
    catch { return 'in-use' }
}

# Writes a batch of files. If any of them fails, puts ALL of them back to their content from before the batch.
# Each item: @{ Path; Bytes; Before (bytes from before the batch) }.
function Write-Batch($items) {
    $done = @(); $current = $null
    try {
        foreach ($i in $items) {
            $current = $i.Path
            if ((Get-FileSha $i.Path) -ne (Get-BytesHash $i.Before)) {
                Throw-FriendlyError "O arquivo $(Split-Path $i.Path -Leaf) mudou enquanto a ferramenta trabalhava." 'O instalador do mod pode estar atualizando. Espere ele terminar e rode de novo. Nada foi alterado.'
            }
            $done += $i
            Replace-File $i.Path $i.Bytes
        }
    } catch {
        $originalError = $_
        $notUndone = @()
        foreach ($i in $done) {
            try {
                if ((Get-FileSha $i.Path) -ne (Get-BytesHash $i.Before)) { Replace-File $i.Path $i.Before }
            } catch { $notUndone += $i.Path }
        }
        if ($notUndone.Count -gt 0) {
            Throw-FriendlyError "ATENÇÃO: a gravação falhou e não consegui desfazer em: $($notUndone -join ', ')" 'Use a opção de voltar aos originais ou reinstale o mod pelo instalador antes de jogar.'
        }
        if ($originalError.Exception.Data.Contains('sugestao')) { throw $originalError }
        $detail = $originalError.Exception.Message
        if ($originalError.Exception.InnerException) { $detail = $originalError.Exception.InnerException.Message }
        Throw-FriendlyError "Não consegui gravar $(Split-Path $current -Leaf): o arquivo está em uso ou bloqueado. ($detail)" 'Feche o EA app, o instalador do mod ou o que estiver usando o arquivo (às vezes o antivírus) e tente de novo. Nada foi alterado no jogo.'
    }
}

function Test-GameRunning { return [bool](Get-Process -Name $GameProcesses -ErrorAction SilentlyContinue) }

# ============================================================
#  Finding the game (same sources as the mod installer, and a few more)
# ============================================================
function Read-RegistryValue($key, $value) {
    try { return [string](Get-Prop (Get-ItemProperty -LiteralPath $key -ErrorAction Stop) $value) }
    catch { return $null }
}

function Test-ValidGameDir($dir) { return ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'Titanfall2.exe'))) }
function Test-ModInstalled($dir) { return (Test-Path -LiteralPath (Join-Path $dir $REL_TOKENS)) }

function Get-SteamLibraries {
    $root = Read-RegistryValue 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if (-not $root) { $root = Read-RegistryValue 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath' }
    if (-not $root -and ${env:ProgramFiles(x86)}) {
        $default = Join-Path ${env:ProgramFiles(x86)} 'Steam'
        if (Test-Path -LiteralPath $default) { $root = $default }
    }
    if (-not $root -or -not (Test-Path -LiteralPath $root)) { return @() }
    $libs = @($root)
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"(.+?)"')) {
            $p = $m.Groups[1].Value.Replace('\\', '\')
            if (Test-Path -LiteralPath $p) { $libs += $p }
        }
    }
    return $libs
}

function Find-Game {
    $found = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $add = {
        param($dir, $source)
        if (-not (Test-ValidGameDir $dir)) { return }
        $full = (Resolve-Path -LiteralPath $dir).Path.TrimEnd('\')
        if ($seen.ContainsKey($full.ToLowerInvariant())) { return }
        $seen[$full.ToLowerInvariant()] = $true
        $found.Add([pscustomobject]@{ Dir = $full; Source = $source; WithMod = (Test-ModInstalled $full) })
    }
    foreach ($key in 'HKLM:\SOFTWARE\Respawn\Titanfall2', 'HKLM:\SOFTWARE\WOW6432Node\Respawn\Titanfall2') {
        & $add (Read-RegistryValue $key 'Install Dir') 'EA app / Origin (registro)'
    }
    foreach ($lib in Get-SteamLibraries) { & $add (Join-Path $lib 'steamapps\common\Titanfall2') 'Steam' }
    $drives = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName }
    foreach ($d in $drives) {
        & $add (Join-Path $d 'Program Files\EA Games\Titanfall2') 'EA app'
        & $add (Join-Path $d 'EA Games\Titanfall2') 'EA app'
        & $add (Join-Path $d 'Program Files (x86)\Origin Games\Titanfall2') 'Origin'
        foreach ($name in 'Titanfall 2', 'Titanfall2') {
            & $add (Join-Path $d "XboxGames\$name\Content") 'Xbox / Microsoft Store'
            & $add (Join-Path $d "XboxGames\$name") 'Xbox / Microsoft Store'
        }
    }
    return $found.ToArray()
}

function Normalize-PathText([string]$text) {
    $p = $text.Trim().Trim('"').Trim("'").Trim()
    if ($p -match '(?i)titanfall2\.exe$') { $p = Split-Path $p }
    return $p
}

function Ask-GameDir {
    Write-SectionTitle 'Onde está o Titanfall 2?'
    Hint 'Cole o caminho da pasta que tem o Titanfall2.exe.'
    Hint 'Dica: no EA app ou na Steam, use "Procurar arquivos locais" e copie o endereço da janela.'
    Hint 'Deixe em branco e aperte Enter para cancelar.'
    while ($true) {
        $txt = Ask 'Pasta do jogo:'
        if (-not $txt) { return $null }
        $p = Normalize-PathText $txt
        if (Test-ValidGameDir $p) { return (Resolve-Path -LiteralPath $p).Path.TrimEnd('\') }
        Fail "Não achei o Titanfall2.exe em: $p"
    }
}

function Save-GameDir($dir, $source) {
    Write-Json $CONFIG_FILE ([pscustomobject]@{ pastaJogo = $dir; origem = $source; salvoEm = (Get-Date -Format 'yyyy-MM-dd') })
}

function Select-GameDir([switch]$Force) {
    $cfg = Read-Json $CONFIG_FILE
    $saved = Get-Prop $cfg 'pastaJogo'
    if (-not $Force -and (Test-ValidGameDir $saved)) { return @{ Dir = $saved; Source = (Get-Prop $cfg 'origem') } }

    $found = @(Find-Game)
    $choice = $null
    if ($found.Count -eq 1 -and -not $Force) {
        $choice = $found[0]
    } elseif ($found.Count -ge 1) {
        if ($NonInteractive) {
            $withMod = @($found | Where-Object WithMod)
            $choice = if ($withMod.Count -gt 0) { $withMod[0] } else { $found[0] }
        } else {
            Write-SectionTitle 'Instalações encontradas'
            for ($i = 0; $i -lt $found.Count; $i++) {
                $a = $found[$i]
                W "  [$($i + 1)] " 'Cyan' -n; W $a.Dir 'White'
                $mod = if ($a.WithMod) { 'mod VR instalado' } else { 'sem o mod VR' }
                Hint "      $($a.Source), $mod"
            }
            W '  [M] ' 'Cyan' -n; W 'Digitar outra pasta' 'White'
            while (-not $choice) {
                $r = Ask 'Qual delas?'
                if ($null -eq $r -or $r -match '^[mM]$') { break }
                $n = 0
                if ([int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $found.Count) { $choice = $found[$n - 1] }
                else { Fail "Digite um número de 1 a $($found.Count), ou M." }
            }
        }
    }
    if (-not $choice) {
        if ($NonInteractive) { Throw-FriendlyError 'Não encontrei o Titanfall 2 neste computador.' 'Rode de novo com -GameDir "<pasta do jogo>".' }
        if ($NoPrompt) { Throw-FriendlyError 'Não achei o Titanfall2.exe na pasta do jogo.' 'Confira se o jogo continua instalado nessa pasta.' }
        $p = Ask-GameDir
        if (-not $p) { Throw-FriendlyError 'Nenhuma pasta escolhida.' 'Rode a ferramenta de novo quando souber onde o jogo está.' }
        $choice = [pscustomobject]@{ Dir = $p; Source = 'informada por você' }
    }
    Save-GameDir $choice.Dir $choice.Source
    return @{ Dir = $choice.Dir; Source = $choice.Source }
}

# ============================================================
#  Dictionary
# ============================================================
function Normalize-Rel([string]$rel) { return $rel.Replace('/', '\').Trim() }

# Only the mod's text files can be targets: the texts file and the mod's own .nut scripts.
function Test-AllowedRel([string]$rel, [string]$type) {
    if (-not $rel -or $rel -match '(^|\\)\.\.(\\|$)' -or [IO.Path]::IsPathRooted($rel)) { return $false }
    if ($type -eq 'tokens') { return ($rel -ieq $REL_TOKENS) }
    return ($rel.StartsWith($REL_MOD, [StringComparison]::OrdinalIgnoreCase) -and $rel -match '(?i)\.nut$')
}

# Returns what is wrong with a dictionary entry, or $null. The 'en' field is refused on purpose:
# mod text must not enter the public dictionary.
function Get-EntryError($e, [string]$type) {
    if ($null -eq $e) { return 'está vazia' }
    if ($e.PSObject.Properties['en']) { return "tem o campo 'en', que não existe no formato público" }
    $hash = Get-Prop $e 'enHash'
    if (-not ($hash -is [string]) -or $hash -cnotmatch '^[0-9a-f]{64}$') { return "está sem o campo 'enHash' válido" }
    if ($type -eq 'tokens') {
        foreach ($c in 'key', 'pt') {
            if (-not ((Get-Prop $e $c) -is [string])) { return "está sem o campo '$c'" }
        }
        return $null
    }
    $pTexts = $e.PSObject.Properties['texts']
    $pTemplate = $e.PSObject.Properties['template']
    if ([bool]$pTexts -eq [bool]$pTemplate) { return "precisa de 'texts' ou de 'template', e só de um deles" }
    if ($pTemplate) {
        if (-not ($pTemplate.Value -is [string])) { return "tem 'template' que não é texto" }
        return $null
    }
    foreach ($t in @($pTexts.Value)) {
        if ($null -ne $t -and -not ($t -is [string])) { return "tem item de 'texts' que não é texto nem null" }
    }
    return $null
}

function Load-Dictionary([string]$dir = $DictionaryDir) {
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'tokens.json'))) {
        Throw-FriendlyError "Dicionário não encontrado em $dir" 'A pasta "translations" precisa ficar ao lado deste script.'
    }
    $hint = 'O dicionário da ferramenta está danificado. Baixe a ferramenta de novo.'
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
    $targets = @(); $hasTokens = $false
    $allText = ''
    foreach ($f in $files) {
        $allText += [IO.File]::ReadAllText($f.FullName)
        $d = Read-Json $f.FullName $hint
        $rel = Normalize-Rel ([string](Get-Prop $d 'file'))
        $type = if ($f.Name -eq 'tokens.json') { 'tokens' } else { 'lines' }
        if (-not (Test-AllowedRel $rel $type)) { Throw-FriendlyError "Caminho não permitido no dicionário ($($f.Name)): '$rel'" $hint }
        $duplicate = @($targets | Where-Object { $_.Rel -ieq $rel })
        if ($duplicate.Count -gt 0) {
            Throw-FriendlyError "Dois arquivos do dicionário apontam para o mesmo script: $($duplicate[0].File) e $($f.Name)." "Apague a cópia que sobrou em $dir (por exemplo, um '... - Copia.json')."
        }
        $map = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        $n = 0
        foreach ($e in @(Get-Prop $d $type)) {
            $n++
            $err = Get-EntryError $e $type
            if ($err) { Throw-FriendlyError "Entrada $n de $($f.Name) $err." $hint }
            $k = if ($type -eq 'tokens') { [string]$e.key } else { [string]$e.enHash }
            $map[$k] = $e
        }
        $name = [string](Get-Prop $d 'name'); if (-not $name) { $name = Split-Path $rel -Leaf }
        $scan = Get-Prop $d 'scan'; if ($null -eq $scan) { $scan = $true }
        $targets += @{ Rel = $rel; Type = $type; Name = $name; Dic = $map; Scan = [bool]$scan; File = $f.Name }
        if ($type -eq 'tokens') { $hasTokens = $true }
    }
    if (-not $hasTokens) { Throw-FriendlyError 'O dicionário não tem o tokens.json.' $hint }
    return @{ Targets = $targets; Hash = (Get-BytesHash ($UTF8_NO_BOM.GetBytes($allText))) }
}

function Get-Skeleton([string]$line) { return [regex]::Replace($line.Trim(), $RE_LITERAL, '""') }

function Test-BalancedCode([string]$line) {
    $bare = [regex]::Replace($line, $RE_LITERAL, '""')
    if ((Count-Char $bare '"') % 2 -ne 0) { return $false }
    foreach ($pair in @('(', ')'), @('[', ']'), @('{', '}')) {
        if ((Count-Char $bare $pair[0]) -ne (Count-Char $bare $pair[1])) { return $false }
    }
    return $true
}

# Variables, icons and separators that must survive the translation (%use%, %s1, ||, \n).
function Get-Marks([string]$t) { return ((@([regex]::Matches($t, $RE_MARKS) | ForEach-Object { $_.Value }) | Sort-Object) -join ' ') }

# Player-facing text: a string with letters that is not a token (#), an icon (%$), a variable (%x%) or a
# code identifier. An identifier is a single lowercase word ("norte", "som_foco"), with an inner capital
# ("AoFechar", "MenuPrincipal"), an underscore or a digit ("Escolha1").
# A single capitalised word ("Carregando") or an all-caps one ("VIDA") counts as text.
function Test-Identifier([string]$v) {
    if ($v -match '\s') { return $false }
    return ($v -cmatch '^[a-z]' -or $v -cmatch '[a-z][A-Z]' -or $v -match '[_0-9.]' -or $v -cmatch '^#[A-Z][A-Z0-9_]*$')
}

# An internal name used as an argument, index or comparison (Function( "x" ), == "norte") is code,
# even between quotes: the translation must keep it identical.
function Test-ProtectedEqual([string]$en, [string]$pt) {
    $le = @([regex]::Matches($en, $RE_LITERAL) | ForEach-Object { $_.Groups[1].Value })
    $lp = @([regex]::Matches($pt, $RE_LITERAL) | ForEach-Object { $_.Groups[1].Value })
    if ($le.Count -ne $lp.Count) { return $false }
    for ($i = 0; $i -lt $le.Count; $i++) {
        $m = [regex]::Matches($en, $RE_LITERAL)[$i]
        $before = $en.Substring(0, $m.Index).TrimEnd()
        if ((Test-Identifier $le[$i]) -and $before -match '(\(|,|\[|=)$' -and $lp[$i] -cne $le[$i]) { return $false }
    }
    return $true
}

function Test-HasLineBreak([string]$t) { return ($t.Contains("`n") -or $t.Contains("`r")) }

function Test-HasVisibleText([string]$line) {
    if ($line -match '^\s*(printt|print|Assert|CodeWarning|Warning|DevPrint)\s*\(') { return $false }
    foreach ($m in [regex]::Matches($line, $RE_LITERAL)) {
        $v = $m.Groups[1].Value
        if ($v.StartsWith('%$') -or (Test-Identifier $v)) { continue }
        if ($v -match '^#') { $v = $v -replace '^#\S*', '' }
        $v = $v -replace '%[^%\s]*%', ''
        if ($v -match '[A-Za-z]{2,}') { return $true }
    }
    return $false
}

# ============================================================
#  Translation (pure: original text in, translated text + pending items out)
# ============================================================
# Text without letters (empty, space, only an icon or variable) has nothing to translate and is not pending.
function Test-NoText([string]$en) { return (($en -replace '%[^%\s]*%', '') -notmatch '[A-Za-z]{2,}') }

function Translate-Tokens($original, $target) {
    $s = Split-Lines $original
    $out = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.List[object]
    $marked = $false; $n = 0
    foreach ($line in $s.Lines) {
        $m = [regex]::Match($line, $RE_TOKEN)
        if (-not $m.Success -or $m.Groups[2].Value -eq 'Language') { $out.Add($line); continue }
        if (-not $marked) { $out.Add($m.Groups[1].Value + $MARKER); $marked = $true }
        $key = $m.Groups[2].Value; $en = $m.Groups[4].Value
        if (Test-NoText $en) { $out.Add($line); continue }
        $hash = Get-TextHash $en
        $item = $null; $pt = $null; $reason = 'texto novo'
        if ($target.Dic.TryGetValue($key, [ref]$item)) {
            $reason = 'o texto em inglês mudou'
            if ([string]$item.enHash -ceq $hash) {
                $cand = [string]$item.pt
                if ($cand -match '(?<!\\)"' -or $cand.EndsWith('\')) { $reason = 'tradução com aspas inválidas' }
                elseif (Test-HasLineBreak $cand) { $reason = 'tradução com quebra de linha' }
                elseif ((Get-Marks $cand) -cne (Get-Marks $en)) { $reason = 'tradução perdeu variáveis como %use% ou ||' }
                else { $pt = $cand }
            }
        }
        if ($null -ne $pt) {
            $n++
            $out.Add($m.Groups[1].Value + '"' + $key + '"' + $m.Groups[3].Value + '"' + $pt + '"' + $m.Groups[5].Value)
        } else {
            $pending.Add([pscustomobject]@{ arquivo = $target.Rel; tipo = 'token'; chave = $key; enHash = $hash; motivo = $reason })
            $out.Add($line)
        }
    }
    return @{ Text = ($out -join $s.NL); Pending = $pending; Count = $n }
}

# Replaces only the literals of the mod's REAL line with the dictionary texts, in order. null keeps the
# original literal (an internal name, for example) without having to copy it into the dictionary.
function Apply-Texts([string]$line, $texts) {
    $ms = [regex]::Matches($line, $RE_LITERAL)
    $list = @($texts)
    if ($ms.Count -ne $list.Count) { return $null }
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $m = $ms[$i]
        [void]$sb.Append($line.Substring($pos, $m.Index - $pos))
        if ($null -eq $list[$i]) { [void]$sb.Append($m.Value) }
        else {
            if ([string]$list[$i] -cnotmatch $RE_LITERAL_CONTENT) { return $null }
            [void]$sb.Append('"').Append([string]$list[$i]).Append('"')
        }
        $pos = $m.Index + $m.Length
    }
    [void]$sb.Append($line.Substring($pos))
    return $sb.ToString()
}

# Internal names of the real file, by hash. Only builds the table if some template of the file needs it.
function Get-FileLiterals([string]$text, $target) {
    $needed = $false
    foreach ($item in $target.Dic.Values) {
        if ($item.PSObject.Properties['template'] -and ([string]$item.template).Contains('{=')) { $needed = $true; break }
    }
    if (-not $needed) { return $null }
    $table = @{}
    foreach ($m in [regex]::Matches($text, $RE_LITERAL)) {
        $v = $m.Groups[1].Value
        if (Test-Identifier $v) { $table[(Get-TextHash $v)] = $v }
    }
    return $table
}

# Code fragments of the real line, between the literals, without whitespace and without the edge + signs.
function Get-CodeParts([string]$line) {
    $parts = [regex]::Split($line, '"(?:[^"\\]|\\.)*"')
    return @($parts | ForEach-Object { $_.Trim().Trim('+').Trim() })
}

# Template: when the translation needs new logic (a gesture in Portuguese, for example). It stores only what was
# written for the translation; {0}, {1}... are the code fragments of the real line, read from the installed mod.
# {=hash} is an internal name of the mod, between quotes, found in the file itself by SHA-256: the dictionary
# does not store the name in the clear. Outside the quotes the template only accepts operators, so the
# dictionary can never call new code, and every fragment of the original line must still be present.
function Apply-Template([string]$line, [string]$template, $literals) {
    $codeParts = Get-CodeParts $line
    $used = @{}
    $invalid = $false
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    $pieces = @()
    foreach ($m in [regex]::Matches($template, $RE_LITERAL)) {
        $pieces += ,@($template.Substring($pos, $m.Index - $pos), $m.Value)
        $pos = $m.Index + $m.Length
    }
    $pieces += ,@($template.Substring($pos), '')
    foreach ($p in $pieces) {
        $code = [string]$p[0]
        if (($code -replace '\{\d+\}|\{=[0-9a-f]{64}\}', '') -cnotmatch '^[\s+()?:=]*$') { return $null }
        $last = 0
        foreach ($c in [regex]::Matches($code, '\{(\d+)\}|\{=([0-9a-f]{64})\}')) {
            [void]$sb.Append($code.Substring($last, $c.Index - $last))
            if ($c.Groups[2].Success) {
                if (-not $literals -or -not $literals.ContainsKey($c.Groups[2].Value)) { $invalid = $true; break }
                [void]$sb.Append('"').Append([string]$literals[$c.Groups[2].Value]).Append('"')
            } else {
                $i = [int]$c.Groups[1].Value
                if ($i -ge $codeParts.Count) { $invalid = $true; break }
                $used[$i] = $true
                [void]$sb.Append([string]$codeParts[$i])
            }
            $last = $c.Index + $c.Length
        }
        if ($invalid) { return $null }
        [void]$sb.Append($code.Substring($last)).Append([string]$p[1])
    }
    for ($i = 0; $i -lt $codeParts.Count; $i++) {
        if ([string]$codeParts[$i] -and -not $used.ContainsKey($i)) { return $null }
    }
    return $sb.ToString()
}

# Translated line built from the mod's real line, or $null if the entry would touch the code or the variables.
function Get-TranslatedLine([string]$clean, $item, $literals) {
    if ($item.PSObject.Properties['template']) {
        $pt = Apply-Template $clean ([string]$item.template) $literals
        if ($null -eq $pt -or -not (Test-BalancedCode $pt)) { return $null }
    } else {
        $pt = Apply-Texts $clean $item.PSObject.Properties['texts'].Value
        if ($null -eq $pt -or (Get-Skeleton $pt) -cne (Get-Skeleton $clean) -or -not (Test-ProtectedEqual $clean $pt)) { return $null }
    }
    if ((Test-HasLineBreak $pt) -or (Get-Marks $pt) -cne (Get-Marks $clean)) { return $null }
    return $pt
}

function Translate-Lines($original, $target) {
    $s = Split-Lines $original
    $out = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.List[object]
    $out.Add($MARKER); $n = 0; $lineNo = 0
    $literals = Get-FileLiterals $original $target
    foreach ($line in $s.Lines) {
        $lineNo++
        $clean = $line.Trim()
        $hash = if ($clean) { Get-TextHash $clean } else { '' }
        $item = $null
        if ($clean -and $target.Dic.TryGetValue($hash, [ref]$item)) {
            $pt = Get-TranslatedLine $clean $item $literals
            if ($null -ne $pt) {
                $indent = $line.Substring(0, $line.Length - $line.TrimStart().Length)
                $out.Add($indent + $pt); $n++; continue
            }
            $pending.Add([pscustomobject]@{ arquivo = $target.Rel; tipo = 'linha'; chave = ''; linha = $lineNo; enHash = $hash; motivo = 'a tradução mexe no código ou nas variáveis, foi ignorada' })
            $out.Add($line); continue
        }
        if ($target.Scan -and (Test-HasVisibleText $clean) -and $clean -notmatch '^(case |//|return \[)') {
            $pending.Add([pscustomobject]@{ arquivo = $target.Rel; tipo = 'linha'; chave = ''; linha = $lineNo; enHash = $hash; motivo = 'linha nova ou alterada' })
        }
        $out.Add($line)
    }
    return @{ Text = ($out -join $s.NL); Pending = $pending; Count = $n }
}

function Test-Translation($target, $original, $translated) {
    if ($target.Type -eq 'tokens') {
        $a = [regex]::Matches($original, $RE_TOKEN, 'Multiline').Count
        $b = [regex]::Matches($translated, $RE_TOKEN, 'Multiline').Count
        if ($a -ne $b) { throw "Validação falhou em $($target.Rel): $a textos no original, $b no traduzido." }
        foreach ($c in '{', '}') {
            if ((Count-Char $original $c) -ne (Count-Char $translated $c)) { throw "Validação falhou em $($target.Rel): chaves '$c' desbalanceadas." }
        }
    } else {
        $a = (Split-Lines $original).Lines.Count
        $b = (Split-Lines $translated).Lines.Count
        if ($b -ne $a + 1) { throw "Validação falhou em $($target.Rel): $a linhas no original, $b no traduzido." }
    }
}

# Second guard against a wrong backup: an "original" that already contains translated phrases is not an original.
function Test-LooksTranslated($target, $text) {
    foreach ($item in $target.Dic.Values) {
        if ($target.Type -eq 'tokens') {
            $pt = [string]$item.pt
            if ($pt -ceq '' -or (Get-TextHash $pt) -ceq [string]$item.enHash) { continue }
            if ($pt.Length -gt 12 -and $text.Contains('"' + $pt + '"')) { return $true }
        } elseif ($item.PSObject.Properties['texts']) {
            foreach ($t in @($item.PSObject.Properties['texts'].Value)) {
                if ($null -ne $t -and ([string]$t).Length -gt 12 -and $text.Contains('"' + [string]$t + '"')) { return $true }
            }
        }
    }
    return $false
}

# ============================================================
#  State
# ============================================================
function Read-State {
    $e = Read-Json $STATE_FILE
    $files = @{}
    $p = Get-Prop $e 'arquivos'
    if ($p) { foreach ($x in $p.PSObject.Properties) { $files[$x.Name] = [string]$x.Value } }
    return @{ ModVersion = (Get-Prop $e 'versaoMod'); AppliedAt = (Get-Prop $e 'aplicadoEm')
              DicHash = (Get-Prop $e 'hashDicionario'); Files = $files }
}

function Write-State($state) {
    Write-Json $STATE_FILE ([pscustomobject]@{ versaoMod = $state.ModVersion; aplicadoEm = $state.AppliedAt
                                               hashDicionario = $state.DicHash; arquivos = $state.Files })
}

function Get-ModVersion {
    $reg = Read-Json (Join-Path $script:Game $REL_MOD_REGISTRY) 'O registro do instalador do mod está ilegível. Reinstale o mod pelo instalador.'
    $v = Get-Prop $reg 'version'
    if ($v) { return [string]$v } else { return $null }
}

function Get-FileStatus($target, $state) {
    if (-not (Test-Path -LiteralPath $target.FilePath)) { return 'missing' }
    if (-not (Test-HasMarker $target.FilePath)) { return 'original' }
    if ((Get-FileSha $target.FilePath) -ne $state.Files[$target.Rel]) { return 'modified-externally' }
    if ($state.DicHash -ne $script:Dic.Hash) { return 'new-dictionary' }
    return 'translated'
}

function Get-NormalPath([string]$c) { return [IO.Path]::GetFullPath($c).TrimEnd('\', '/') }

# Backup and state have a single slot. While another game folder is still translated, the backup is its.
function Assert-BackupGameDir {
    $info = Read-Json $BACKUP_INFO_FILE
    if (-not $info) { return }
    $registered = [string](Get-Prop $info 'jogo')
    if (-not $registered) { return }
    if ((Get-NormalPath $registered) -ieq (Get-NormalPath $script:Game)) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $registered 'Titanfall2.exe'))) { return }
    $active = $false
    foreach ($a in $script:Targets) {
        $c = Join-Path $registered $a.Rel
        if ((Test-Path -LiteralPath $c) -and (Test-HasMarker $c)) { $active = $true; break }
    }
    if (-not $active) { return }
    Throw-FriendlyError 'O backup guardado é de outra pasta do jogo, que continua traduzida. Nada foi alterado.' "Restaure os originais na outra pasta antes: $registered"
}

# A junction or symbolic link in the path would send the write outside the game folder.
function Assert-NoLink($paths) {
    $base = Get-NormalPath $script:Game
    foreach ($c in $paths) {
        $current = Get-NormalPath $c
        while ($current.Length -gt $base.Length -and $current.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
            if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Throw-FriendlyError "O caminho de $(Split-Path $c -Leaf) passa por um link ou junction. Nada foi alterado." "Reinstale o mod numa pasta comum: $current"
            }
            $current = Split-Path $current
        }
    }
}

# The backup is only used if it matches the hash recorded when it was created.
function Assert-Backup($a) {
    $expected = Get-Prop (Get-Prop (Read-Json $BACKUP_INFO_FILE) 'arquivos') $a.Rel
    if (-not $expected -or (Get-FileSha $a.BackupPath) -ne $expected) {
        Throw-FriendlyError "O backup de $($a.Name) não confere com o que foi guardado. Nada foi alterado." 'Reinstale o mod pelo instalador do CircuitLord: isso devolve os textos originais.'
    }
}

function Read-Pending { return @(Get-Prop (Read-Json $PENDING_FILE) 'itens' | Where-Object { $_ }) }

function Get-IssueLine($p) {
    $label = if ($p.chave) { "token $($p.chave)" } else { "linha $($p.linha) de $(Split-Path $p.arquivo -Leaf)" }
    return "- $label sha256:$($p.enHash)"
}

function Show-Pending($pending) {
    W ''
    Warn "$($pending.Count) texto(s) do mod ainda não têm tradução e aparecem em inglês no jogo."
    Hint 'O jogo já pode ser aberto. Esses textos ficam em inglês até o dicionário ganhar a tradução.'
    Hint "Para ajudar, abra uma issue em $URL_ISSUES e cole o texto abaixo. Ele só tem chave e hash, sem texto do mod:"
    W ''
    W "Pendências do mod $(Get-VersionLabel (Get-ModVersion)), ferramenta ${script:VERSION}:"
    foreach ($p in ($pending | Select-Object -First 10)) { W (Get-IssueLine $p) }
    if ($pending.Count -gt 10) {
        W "... e mais $($pending.Count - 10)"
        W ''
        Hint "A lista inteira, para colar, está em $(Join-Path $script:DATA_DIR $ISSUE_LIST_FILE_NAME)"
    }
}

# ============================================================
#  Common setup
# ============================================================
function Initialize-Run([switch]$ChangeDir) {
    if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Force -Path $DataDir | Out-Null }
    if ($script:FixedGameDir -and -not $ChangeDir) {
        $p = Normalize-PathText $script:FixedGameDir
        if (-not (Test-ValidGameDir $p)) { Throw-FriendlyError "Não achei o Titanfall2.exe em: $p" 'Confira o caminho passado em -GameDir.' }
        $script:Game = (Resolve-Path -LiteralPath $p).Path.TrimEnd('\'); $script:Source = 'informada no comando'
        $cfg = Read-Json $CONFIG_FILE
        if ((Get-Prop $cfg 'pastaJogo') -eq $script:Game) { $script:Source = [string](Get-Prop $cfg 'origem') }
        else { Save-GameDir $script:Game $script:Source }
    } else {
        $r = Select-GameDir -Force:$ChangeDir
        $script:Game = $r.Dir; $script:Source = $r.Source
        $script:FixedGameDir = $null
    }
    Load-Targets
}

function Set-DataPaths([string]$dir) {
    $script:DATA_DIR = $dir
    $script:STATE_FILE = Join-Path $dir $STATE_FILE_NAME
    $script:PENDING_FILE = Join-Path $dir $PENDING_FILE_NAME
    $script:BACKUP_DIR = Join-Path $dir $BACKUP_DIR_NAME
    $script:BACKUP_INFO_FILE = Join-Path $script:BACKUP_DIR $BACKUP_INFO_FILE_NAME
}

# If this game was already translated as administrator, backup and state are in the administrators' folder.
function Select-Data {
    $script:AdminData = $false
    Set-DataPaths $DataDir
    if ($Elevated -or -not $AdminDataDir) { return }
    $mark = Join-Path $AdminDataDir $ADMIN_GAME_MARK_FILE_NAME
    if ((Test-Path -LiteralPath $mark) -and [IO.File]::ReadAllText($mark).Trim() -eq $script:Game) {
        Set-DataPaths $AdminDataDir
        $script:AdminData = $true
    }
}

function Load-Targets {
    Select-Data
    $script:Dic = Load-Dictionary
    foreach ($a in $script:Dic.Targets) {
        $a.FilePath = Join-Path $script:Game $a.Rel
        $a.BackupPath = Join-Path $BACKUP_DIR $a.Rel
    }
    $script:Targets = $script:Dic.Targets
}

function Assert-Mod {
    if (-not (Test-ModInstalled $script:Game)) {
        Throw-FriendlyError 'O mod Titanfall 2 VR não está instalado nesta pasta.' "Instale pelo CircuitLord VR Mod Installer ($URL_INSTALLER) e rode a ferramenta de novo."
    }
}

# Earlier translation package, installed another way: swaps the same texts and leaves .orig-ptbr copies.
function Test-OldPackage {
    if (Test-Path -LiteralPath (Join-Path $script:Game $REL_OLD_PACKAGE)) { return $true }
    foreach ($a in $script:Targets) {
        if (Test-Path -LiteralPath "$($a.FilePath)$LEGACY_COPY_SUFFIX") { return $true }
    }
    return $false
}

# A window closed in the middle of a write can leave this tool's temporary files next to the files.
function Clear-Temps($paths) {
    foreach ($c in $paths) {
        $dir = Split-Path $c
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force -Filter "$PROBE_PREFIX*") + @(Get-ChildItem -LiteralPath $dir -File -Force -Filter "*$TEMP_SUFFIX")) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Assert-Writable($paths) {
    if (Test-GameRunning) {
        Throw-FriendlyError 'O Titanfall 2 está aberto.' 'Feche o jogo e tente de novo. Com o jogo aberto ele não vê a mudança e o arquivo pode estar em uso.'
    }
    if (Get-Process -Name $InstallerProcesses -ErrorAction SilentlyContinue) { $script:InstallerWarning = $true }
    Assert-NoLink $paths
    # Backup and state of this installation can only change as administrator.
    if ($script:AdminData -and -not $Elevated) { throw "NO_PERMISSION:$(@($paths)[0])" }
    Clear-Temps $paths
    foreach ($c in $paths) {
        switch (Test-CanWrite $c) {
            'permission' { throw "NO_PERMISSION:$c" }
            'in-use' { Throw-FriendlyError "O arquivo $(Split-Path $c -Leaf) está aberto em outro programa." 'Feche o EA app, a Steam ou o instalador do mod se estiverem verificando ou atualizando o jogo, e tente de novo. Nada foi alterado.' }
        }
    }
}

# ============================================================
#  STATUS
# ============================================================
function Capitalize([string]$t) { return $t.Substring(0, 1).ToUpper() + $t.Substring(1) }

function Show-Panel {
    $state = Read-State
    $info = Read-Json $BACKUP_INFO_FILE
    Write-SectionTitle 'Situação'
    Write-Field 'Versão da tradução' $VERSION 'Gray'
    Write-Field 'Pasta do jogo' $script:Game
    Write-Field 'Encontrada via' $script:Source 'Gray'
    if (Test-ModInstalled $script:Game) { Write-Field 'Mod VR' (Get-VersionLabel (Get-ModVersion)) } else { Write-Field 'Mod VR' 'não instalado nesta pasta' 'Yellow' }
    foreach ($a in $script:Targets) {
        $label = Capitalize $a.Name
        switch (Get-FileStatus $a $state) {
            'translated' { Write-Field $label 'em português' 'Green' }
            'new-dictionary' { Write-Field $label 'em português (há traduções novas: use a opção 1)' 'Yellow' }
            'modified-externally' { Write-Field $label 'em português, mas mexido fora da ferramenta (use a opção 1)' 'Yellow' }
            'original' { Write-Field $label 'em inglês (original do mod)' 'Yellow' }
            default { Write-Field $label 'arquivo não encontrado nesta versão do mod' 'Red' }
        }
    }
    if ($info) { Write-Field 'Backup do original' "mod $(Get-VersionLabel (Get-Prop $info 'versaoMod')), de $(Get-Prop $info 'data')" 'Gray' }
    else { Write-Field 'Backup do original' 'ainda não existe (é criado na primeira tradução)' 'DarkGray' }
    $pending = @(Read-Pending)
    if ($pending.Count -gt 0) { Write-Field 'Sem tradução' "$($pending.Count) texto(s) do mod ficaram em inglês" 'Yellow' }
    if (Test-OldPackage) { Write-Field 'Atenção' 'há um pacote antigo de tradução instalado: desinstale antes de traduzir' 'Yellow' }
    Write-Field 'Dados da ferramenta' $script:DATA_DIR 'DarkGray'
}

# ============================================================
#  TRANSLATE
# ============================================================
function Invoke-Translate {
    Assert-Mod
    if (Test-OldPackage) {
        Throw-FriendlyError 'Este jogo tem um pacote antigo de tradução instalado ("Titanfall 2 VR em Português").' 'Desinstale em Configurações do Windows, Aplicativos, e rode de novo. Se o aplicativo não aparecer lá, reinstale o mod pelo instalador do CircuitLord. Nada foi alterado.'
    }
    Assert-BackupGameDir
    $state = Read-State
    $modVersion = Get-ModVersion
    Steps 5
    W ''

    $script:plan = @(); $script:missing = @()
    Step 'Comparando com a última tradução' {
        foreach ($a in $script:Targets) {
            if (-not (Test-Path -LiteralPath $a.FilePath)) { $script:missing += $a; continue }
            $before = [IO.File]::ReadAllBytes($a.FilePath)
            if ((Get-TextFromBytes $before).Contains($MARKER_ID)) {
                if ((Get-BytesHash $before) -eq $state.Files[$a.Rel] -and $state.DicHash -eq $script:Dic.Hash) { continue }
                if (-not (Test-Path -LiteralPath $a.BackupPath) -or (Test-HasMarker $a.BackupPath)) {
                    Throw-FriendlyError "O arquivo de $($a.Name) está traduzido, mas o backup do original sumiu ou está errado." 'Reinstale o mod pelo instalador (isso traz o original de volta) e rode a ferramenta de novo.'
                }
                Assert-Backup $a
                $script:plan += @{ Target = $a; Source = 'backup'; Before = $before; Original = [IO.File]::ReadAllBytes($a.BackupPath) }
            } else {
                $script:plan += @{ Target = $a; Source = 'game'; Before = $before; Original = $before }
            }
        }
        if ($script:missing.Count -eq $script:Targets.Count) {
            Throw-FriendlyError 'Nenhum dos arquivos de texto que a ferramenta conhece existe nesta versão do mod.' "O mod mudou de estrutura. Veja se há versão nova da ferramenta ou avise em $URL_ISSUES."
        }
        if ($script:plan.Count -eq 0) { return 'nada mudou' } else { return "$($script:plan.Count) arquivo(s) para traduzir" }
    }
    $plan = $script:plan
    foreach ($a in $script:missing) {
        Warn "O arquivo de $($a.Name) não existe nesta versão do mod e foi pulado."
        Hint 'Os outros arquivos seguem normalmente. Uma versão nova da ferramenta resolve.'
    }
    if ($plan.Count -eq 0) {
        Write-Box 'Tudo atualizado' @("A tradução já está aplicada no mod $(Get-VersionLabel $modVersion).", "Aplicada em $($state.AppliedAt). Nenhum arquivo foi alterado.")
        $pending = @(Read-Pending)
        if ($pending.Count -gt 0) { Show-Pending $pending; return 10 }
        return 0
    }

    Step 'Conferindo permissões e se o jogo está fechado' { Assert-Writable @($plan | ForEach-Object { $_.Target.FilePath }); return '' }

    $script:results = @()
    $script:allPending = New-Object System.Collections.Generic.List[object]
    Step 'Traduzindo e validando em memória' {
        foreach ($item in $plan) {
            $a = $item.Target
            $original = Get-TextFromBytes $item.Original
            if ($item.Source -eq 'game' -and (Test-LooksTranslated $a $original)) {
                Throw-FriendlyError "O arquivo de $($a.Name) parece já ter tradução, mas sem a marca desta ferramenta." 'Reinstale o mod pelo instalador para voltar ao original e rode de novo. Nada foi alterado.'
            }
            $r = if ($a.Type -eq 'tokens') { Translate-Tokens $original $a } else { Translate-Lines $original $a }
            Test-Translation $a $original $r.Text
            foreach ($p in $r.Pending) { $script:allPending.Add($p) }
            $enc = if ($a.Type -eq 'tokens') { $UTF16_BOM } else { $UTF8_NO_BOM }
            $script:results += @{ Item = $item; Bytes = (Get-TextBytes $r.Text $enc); Count = $r.Count }
        }
        return "$(($script:results | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) textos prontos"
    }
    $results = $script:results

    $script:newBackup = $false
    Step 'Guardando backup do original do mod' {
        $fresh = @($plan | Where-Object { $_.Source -eq 'game' })
        if ($fresh.Count -eq 0) { return 'o backup atual continua valendo' }
        $info = Read-Json $BACKUP_INFO_FILE
        $hashes = @{}
        $ph = Get-Prop $info 'arquivos'
        if ($ph) { foreach ($x in $ph.PSObject.Properties) { $hashes[$x.Name] = $x.Value } }
        foreach ($item in $fresh) {
            $a = $item.Target
            New-Item -ItemType Directory -Force -Path (Split-Path $a.BackupPath) | Out-Null
            Replace-File $a.BackupPath $item.Original
            $h = Get-FileSha $a.BackupPath
            if ($h -ne (Get-BytesHash $item.Original)) { throw "O backup de $($a.Rel) não confere. Nada foi alterado no jogo." }
            $hashes[$a.Rel] = $h
        }
        Write-Json $BACKUP_INFO_FILE ([pscustomobject]@{ data = (Get-Date -Format 'yyyy-MM-dd'); versaoMod = $modVersion; jogo = $script:Game; arquivos = $hashes })
        $script:newBackup = $true
        return "mod $(Get-VersionLabel $modVersion)"
    }

    Step 'Gravando a tradução no jogo' {
        Write-Batch @($results | ForEach-Object { @{ Path = $_.Item.Target.FilePath; Bytes = $_.Bytes; Before = $_.Item.Before } })
        # From here on the mod is already translated: a failure must not claim that everything was undone.
        try {
            # First: without this mark the backup in the administrators folder cannot be used again.
            if ($Elevated) { [IO.File]::WriteAllText((Join-Path $script:DATA_DIR $ADMIN_GAME_MARK_FILE_NAME), $script:Game, $UTF8_NO_BOM) }
            foreach ($res in $results) { $state.Files[$res.Item.Target.Rel] = Get-BytesHash $res.Bytes }
            $state.ModVersion = $modVersion; $state.AppliedAt = (Get-Date -Format 'yyyy-MM-dd'); $state.DicHash = $script:Dic.Hash
            Write-State $state
            # Keeps the pending items of the files that were not part of this round.
            $rels = @($plan | ForEach-Object { $_.Target.Rel })
            $oldItems = @(Read-Pending | Where-Object { $rels -notcontains $_.arquivo })
            $pendingItems = @($oldItems + $script:allPending.ToArray())
            Write-Json $PENDING_FILE ([pscustomobject]@{ versaoMod = $modVersion; data = (Get-Date -Format 'yyyy-MM-dd'); itens = $pendingItems })
            $issueText = (@("Pendências do mod $(Get-VersionLabel $modVersion), ferramenta ${script:VERSION}:") + @($pendingItems | ForEach-Object { Get-IssueLine $_ })) -join "`n"
            Replace-File (Join-Path $script:DATA_DIR $ISSUE_LIST_FILE_NAME) ($UTF8_NO_BOM.GetBytes($issueText + "`n"))
        } catch {
            Throw-FriendlyError "A tradução foi gravada, mas não consegui salvar os dados da ferramenta ($($_.Exception.Message))." 'Rode a opção 1 de novo para terminar. O backup do original continua guardado.'
        }
        return ''
    }

    $lines = @()
    foreach ($res in $results) {
        $q = $res.Count
        $word = if ($q -eq 1) { 'texto traduzido' } else { 'textos traduzidos' }
        $lines += "$q $word em $($res.Item.Target.Name)"
    }
    if ($script:newBackup) { $lines += "Original do mod $(Get-VersionLabel $modVersion) guardado como backup." }
    Write-Box 'Tradução aplicada' $lines
    if ($script:InstallerWarning) {
        W ''
        Warn 'O instalador do mod está aberto. Se ele atualizar o mod, rode esta ferramenta de novo depois.'
    }
    $pending = @(Read-Pending)
    if ($pending.Count -gt 0) { Show-Pending $pending; return 10 }
    W ''
    Info 'Próximo passo: abra o jogo pelo botão "Launch in VR" do instalador do mod.'
    return 0
}

# ============================================================
#  RESTORE
# ============================================================
function Invoke-Restore {
    Assert-BackupGameDir
    $state = Read-State
    Steps 3
    W ''
    $script:todo = @()
    Step 'Verificando quais arquivos estão traduzidos' {
        foreach ($a in $script:Targets) {
            if (-not (Test-HasMarker $a.FilePath)) { continue }
            if (-not (Test-Path -LiteralPath $a.BackupPath) -or (Test-HasMarker $a.BackupPath)) {
                Throw-FriendlyError "Não há backup válido de $($a.Name)." 'Reinstale o mod pelo instalador do CircuitLord: isso devolve os textos originais.'
            }
            Assert-Backup $a
            $script:todo += @{ Target = $a; Before = [IO.File]::ReadAllBytes($a.FilePath); Bytes = [IO.File]::ReadAllBytes($a.BackupPath) }
        }
        return "$($script:todo.Count) arquivo(s)"
    }
    $todo = $script:todo
    if ($todo.Count -eq 0) {
        Write-Box 'Nada a restaurar' @("Os textos já são os originais (inglês) do mod $(Get-VersionLabel (Get-ModVersion)).") 'Cyan'
        return 0
    }
    Step 'Conferindo permissões e se o jogo está fechado' { Assert-Writable @($todo | ForEach-Object { $_.Target.FilePath }); return '' }
    Step 'Devolvendo os textos originais' {
        Write-Batch @($todo | ForEach-Object { @{ Path = $_.Target.FilePath; Bytes = $_.Bytes; Before = $_.Before } })
        # From here on the originals are already back: a failure must not claim that everything was undone.
        try {
            foreach ($f in $todo) { $state.Files.Remove($f.Target.Rel) }
            Write-State $state
        } catch {
            Throw-FriendlyError "Os originais voltaram, mas não consegui salvar os dados da ferramenta ($($_.Exception.Message))." 'Rode a opção 2 de novo para terminar.'
        }
        return ''
    }
    $restoredLines = @('Os textos do mod voltaram para o inglês.')
    if (-not $Uninstalling) { $restoredLines += 'Para traduzir de novo, use a opção 1.' }
    Write-Box 'Originais restaurados' $restoredLines 'Cyan'
    return 0
}

# ============================================================
#  Execution
# ============================================================
$CONFIG_FILE = Join-Path $DataDir $CONFIG_FILE_NAME
$script:AdminData = $false
Set-DataPaths $DataDir
$script:Game = $null; $script:Source = $null; $script:Targets = @(); $script:Dic = $null
$script:InstallerWarning = $false; $script:FixedGameDir = $GameDir

# The executable does the elevation, never this script: running a file from the user's folder as
# administrator would let any ordinary program swap what runs. Here we only leave the request, and the exe takes over.
function Request-Elevation($action) {
    W ''
    Warn 'Para gravar na pasta do jogo, o Windows exige permissão de administrador.'
    Hint 'O aviso do Windows mostra o nome Titanfall2VR-PTBR.exe, com editor desconhecido, porque o programa não tem assinatura digital. Abre outra janela, e esta espera.'
    [IO.File]::WriteAllText((Join-Path $DataDir 'elevation-request.txt'), "$action`n$($script:Game)`n", $UTF8_NO_BOM)
    return $EXIT_NEEDS_ELEVATION
}

function Invoke-Action($action) {
    try {
        switch ($action) {
            'Status' { Show-Panel; return 0 }
            'Restore' { return (Invoke-Restore) }
            'Translate' { return (Invoke-Translate) }
        }
    } catch {
        $ex = $_.Exception
        if ($ex.Message -like 'NO_PERMISSION:*') {
            $path = $ex.Message.Substring(14)
            if ($Elevated) {
                W ''; Fail "Nem como administrador o Windows deixou gravar em $path."
                Hint 'Confira se o arquivo não está marcado como "Somente leitura" (botão direito, Propriedades) e tente de novo.'
                return 3
            }
            if ($NonInteractive) { W ''; Fail "Sem permissão de escrita em $path"; Hint 'Rode a ferramenta sem -NonInteractive para ela pedir permissão de administrador.'; return 3 }
            if ($ViaExe) { return (Request-Elevation $action) }
            W ''; Fail "Sem permissão de escrita em $path"
            Hint 'Use o Titanfall2VR-PTBR.exe, que pede a permissão de administrador do jeito seguro.'
            return 3
        }
        W ''
        Fail $ex.Message
        if ($ex.Data.Contains('sugestao')) { Hint $ex.Data['sugestao'] }
        else { Hint 'Erro inesperado. Se algo foi gravado, a ferramenta devolveu os arquivos ao estado de antes.' }
        return 1
    }
}

try {
    if ($Action -ne 'Menu') {
        if ($Action -ne 'Status' -and -not $NonInteractive) { Show-Header }
        Initialize-Run
        $code = Invoke-Action $Action
        if ($Pause) { Wait-Enter }
        exit $code
    }

    Show-Header
    Initialize-Run
    $msg = $null
    while ($true) {
        try { Load-Targets } catch { $msg = $_.Exception.Message }
        Show-Panel
        Write-SectionTitle 'O que você quer fazer?'
        W '  [1] ' 'Cyan' -n; W 'Traduzir para português' 'White'
        W '  [2] ' 'Cyan' -n; W 'Voltar aos textos originais (inglês)' 'White'
        W '  [3] ' 'Cyan' -n; W 'Trocar a pasta do jogo' 'White'
        W '  [0] ' 'DarkGray' -n; W 'Sair' 'DarkGray'
        if ($msg) { W ''; Warn $msg; $msg = $null }
        $op = Ask 'Opção:'
        if ($null -eq $op) { exit 0 }
        switch ($op) {
            '1' { Show-Header; Write-SectionTitle 'Traduzindo'; if (@(Invoke-Action 'Translate')[-1] -eq $EXIT_NEEDS_ELEVATION) { exit $EXIT_NEEDS_ELEVATION }; Wait-Enter; Show-Header }
            '2' { Show-Header; Write-SectionTitle 'Restaurando os originais'; if (@(Invoke-Action 'Restore')[-1] -eq $EXIT_NEEDS_ELEVATION) { exit $EXIT_NEEDS_ELEVATION }; Wait-Enter; Show-Header }
            '3' {
                Show-Header
                $previous = @{ Game = $script:Game; Source = $script:Source }
                try { Initialize-Run -ChangeDir }
                catch {
                    $reason = $_.Exception.Message
                    $script:Game = $previous.Game; $script:Source = $previous.Source
                    Save-GameDir $script:Game $script:Source
                    Load-Targets
                    $msg = "Troca cancelada ($reason). A pasta continua: $($script:Game)"
                }
                Show-Header
            }
            '0' { W ''; exit 0 }
            default { Show-Header; $msg = "Opção inválida: '$op'. Digite 1, 2, 3 ou 0." }
        }
    }
} catch {
    W ''
    Fail $_.Exception.Message
    if ($_.Exception.Data.Contains('sugestao')) { Hint $_.Exception.Data['sugestao'] }
    if ($Pause -or $Action -eq 'Menu') { Wait-Enter }
    exit 1
}
