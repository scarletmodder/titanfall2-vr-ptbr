# Tests of the tool with a synthetic mod and dictionary, in a temporary folder.
# Usage: powershell -File tests\test.ps1   or   pwsh -File tests\test.ps1
# Runs the tool in the same PowerShell that runs the test. Exits with the number of failures.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot 'synthetic.ps1')

$ROOT = Split-Path $PSScriptRoot -Parent
$CURRENT_SHELL = (Get-Process -Id $PID).ProcessName
$SCRIPT = Join-Path $ROOT 'tool\titanfall-ptbr.ps1'
$LAB = Join-Path ([IO.Path]::GetTempPath()) ("tf2vr ptbr test " + [guid]::NewGuid().ToString('N'))
$GAME = Join-Path $LAB 'game with space'
$DATA = Join-Path $LAB 'data'
$DIC = Join-Path $LAB 'dic'
$MARK = 'titanfall2-vr-ptbr'

$script:failures = 0
$script:total = 0
$script:lastOutput = ''
function Check($cond, $msg) {
    $script:total++
    if ($cond) { Write-Host "  OK    $msg" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:failures++
        if ($script:lastOutput) { Write-Host ($script:lastOutput.Trim()) -ForegroundColor DarkGray }
    }
}
function Run($action, [string[]]$extra = @(), $dictionary = $script:DIC, $inputText = $null) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SCRIPT, '-Action', $action, '-DataDir', $DATA, '-NoColor') + $extra
    if ($dictionary) { $a += @('-DictionaryDir', $dictionary) }
    if ($extra -notcontains '-GameProcesses') { $a += @('-GameProcesses', 'process-that-does-not-exist') }
    # Guard: without -GameDir and without a folder saved in this test, the tool would look for the real game.
    if ($extra -notcontains '-GameDir') {
        $cfg = Join-Path $DATA 'config.json'
        if (-not (Test-Path -LiteralPath $cfg) -or -not ([IO.File]::ReadAllText($cfg)).Contains('tf2vr ptbr test')) {
            throw 'Test without -GameDir and without a saved test folder: aborted so the real game is not touched.'
        }
    }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        if ($null -eq $inputText) { $a += '-NonInteractive'; $out = & $CURRENT_SHELL @a 6>&1 2>&1 | Out-String }
        else { $out = $inputText | & $CURRENT_SHELL @a 6>&1 2>&1 | Out-String }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $eap }
    $script:lastOutput = $out
    return @{ Code = $code; Out = $out }
}
function G([string[]]$extra = @()) { return @('-GameDir', $GAME) + $extra }
function P($rel) { Join-Path $GAME $rel }
function HashOf($rel) { (Get-FileHash -LiteralPath (P $rel) -Algorithm SHA256).Hash }
function TextOf($rel) { [IO.File]::ReadAllText((P $rel)) }
function BackupPath($rel) { Join-Path $DATA "backup\$rel" }
function IsTranslated($rel) { (TextOf $rel).Contains($MARK) }
function CopyDic($name) {
    $d = Join-Path $LAB $name
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Copy-Item -Path (Join-Path ($DIC -replace '([\[\]])', '`$1') '*') -Destination $d
    return $d
}
function ReadJson($p) { [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function ClearData { if (Test-Path -LiteralPath $DATA) { Remove-Item -LiteralPath $DATA -Recurse -Force } }
function ResetMod {
    foreach ($rel in $ALL_FILES) { if (Test-Path -LiteralPath (P $rel)) { Set-ItemProperty -LiteralPath (P $rel) -Name IsReadOnly -Value $false } }
    Build-Mod $GAME
}
function BytesEqual($a, $b) {
    $x = [IO.File]::ReadAllBytes($a); $y = [IO.File]::ReadAllBytes($b)
    if ($x.Length -ne $y.Length) { return $false }
    for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { return $false } }
    return $true
}

New-Item -ItemType Directory -Force -Path $DIC | Out-Null
Build-Dictionary $DIC
Build-Mod $GAME
$PURE_MOD = Join-Path $LAB 'pure mod'
Build-Mod $PURE_MOD
function AllOriginal {
    foreach ($rel in $ALL_FILES) { if (-not (BytesEqual (P $rel) (Join-Path $PURE_MOD $rel))) { return $false } }
    return $true
}

try {
    Write-Host "Running on $CURRENT_SHELL $($PSVersionTable.PSVersion)"

    Write-Host "`n[1] Initial status"
    $r = Run 'Status' (G)
    Check ($r.Code -eq 0) 'status exits with 0'
    Check ($r.Out -match 'em inglês') 'files show as originals'

    Write-Host "`n[2] First translation"
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 0) "translate exits with 0 (exited $($r.Code))"
    Check ($r.Out -cmatch 'Tradução aplicada' -and $r.Out -cnotmatch 'Ã|Â') 'output with correct accents'
    Check ((TextOf $TOK).Contains('"XT_ENGAGE" "Ativar fluxo"')) 'token translated, keeping the original space between quotes'
    Check ((TextOf $TOK).Contains('||Segure %use% para quarks azuis')) '|| separator and variable preserved'
    Check ((TextOf $TOK).Contains('"XT_ICON" "%$vgui/test_icon%"')) 'icon-only token stays as it was and is not pending'
    Check ((TextOf $NUT).Contains('return "Aperte a " + lever + " para virar o quark"')) 'literals replaced in the real mod line'
    Check ((TextOf $NUT).Contains('"MainLabel" ), "NORTE"')) 'null keeps the original literal'
    Check ((TextOf $NUT).Contains('"alavanca de múon"')) 'accent written in UTF-8'
    Check ((TextOf $NUT).Contains('return "Mova a mão " + ( Test_Gestures()[hand] == "north" ? "para o norte" : ( Test_Gestures()[hand] == "south" ? "para o sul" : Test_Gestures()[hand] ) ) + ": " + Localize( hint.name )')) 'template rebuilds the line with the code read from the mod'
    Check ((TextOf $NUT).Contains('return [ "north", "south" ]')) 'internal list intact'
    Check ((TextOf $PANEL).Contains('"ABRIR COFRE ZORBLAT"')) 'script with scan false applies the known lines'
    Check ((TextOf $PANEL).Contains('Other words that are never scanned')) 'scan false leaves the rest alone'
    Check ([IO.File]::ReadAllBytes((P $TOK))[0] -eq 0xFF) 'tokens remain UTF-16 with BOM'
    Check ([IO.File]::ReadAllBytes((P $NUT))[0] -ne 0xEF) 'script without BOM'
    foreach ($rel in $ALL_FILES) { Check (BytesEqual (BackupPath $rel) (Join-Path $PURE_MOD $rel)) "backup of $(Split-Path $rel -Leaf) identical to the original" }
    Check (-not (Get-ChildItem -LiteralPath $GAME -Recurse -Filter '*.tmp-ptbr')) 'no temporary file left behind'

    Write-Host "`n[3] Second translation without changes"
    $before = (Get-Item -LiteralPath (P $TOK)).LastWriteTimeUtc
    $r = Run 'Translate' (G)
    Check ($r.Out -match 'Tudo atualizado' -and $r.Code -eq 0) 'says everything is up to date'
    Check ((Get-Item -LiteralPath (P $TOK)).LastWriteTimeUtc -eq $before) 'did not rewrite the file'

    Write-Host "`n[4] Restore"
    $r = Run 'Restore' (G)
    Check ($r.Code -eq 0) 'restore exits with 0'
    Check (AllOriginal) 'files byte-identical to the original'
    $r = Run 'Restore' (G)
    Check ($r.Out -match 'Nada a restaurar') 'second restore does nothing'

    Write-Host "`n[5] Simulated mod update (new text, changed text, new line)"
    $r = Run 'Translate' (G)
    $t = (Get-TokensText).Replace('"XT_ENGAGE" "Engage flux"', '"XT_ENGAGE" "Engage flux now"').Replace('"XT_EMPTY" ""', "`"XT_EMPTY`" `"`"`r`n        `"XT_NEW`" `"Brand new zorblat`"")
    Write-TestFile (P $TOK) $t $UTF16
    $n = ((Get-NutLines) -join "`r`n").Replace('	return "Zorblat is empty"', "	return `"Zorblat is empty`"`r`n	return `"Recharging`"")
    Write-TestFile (P $NUT) $n $UTF8
    Write-TestFile (P $REG) '{"version":"9.9.2","files":[]}' $UTF8
    $hTok2 = HashOf $TOK; $hNut2 = HashOf $NUT
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 10) "signals pending items (exited $($r.Code))"
    Check ($r.Out -match 'abra uma issue') 'tells the user to open an issue'
    $pend = ReadJson (Join-Path $DATA 'pendentes.json')
    Check (@($pend.itens).Count -eq 3) "3 pending items, including a single word ($(@($pend.itens).Count))"
    Check (@($pend.itens | Where-Object { $_.enHash -cmatch '^[0-9a-f]{64}$' }).Count -eq 3) 'pending item carries the hash for whoever translates'
    Check ((TextOf $TOK).Contains('"Brand new zorblat"') -and (TextOf $TOK).Contains('"Engage flux now"')) 'new texts stayed in English'
    Check ((TextOf $TOK).Contains('PAINEL ZORBLAT')) 'the rest is still translated'
    Check ((ReadJson (BackupPath 'backup.json')).versaoMod -eq '9.9.2') 'backup became the new version'
    Check ((Get-FileHash -LiteralPath (BackupPath $TOK) -Algorithm SHA256).Hash -eq $hTok2) 'backup equals the new original'
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 10 -and $r.Out -match 'Tudo atualizado' -and $r.Out -match 'token XT_NEW') 'running again keeps reporting the pending items'
    Check ($r.Out -notmatch 'Brand new zorblat|Engage flux now|Recharging') 'the output to paste in the issue has no mod text'
    Check ($r.Out -match 'sha256:[0-9a-f]{64}' -and $r.Out -match 'linha \d+ de test_hints\.nut') 'the output shows key, line and hash'
    $raw = [IO.File]::ReadAllText((Join-Path $DATA 'pendentes.json')) + [IO.File]::ReadAllText((Join-Path $DATA 'pendentes-para-issue.txt'))
    Check ($raw -notmatch 'Brand new zorblat|Engage flux now|Recharging') 'the pending files have no mod text'

    Write-Host "`n[6] Restore goes back to the NEW original"
    $r = Run 'Restore' (G)
    Check ((HashOf $TOK) -eq $hTok2 -and (HashOf $NUT) -eq $hNut2) 'restored the new mod version'

    Write-Host "`n[7] Dictionary gains the new translations and reapplies from the backup"
    $r = Run 'Translate' (G)
    $d2 = CopyDic 'd2'
    $o = ReadJson (Join-Path $d2 'tokens.json')
    ($o.tokens | Where-Object { $_.key -eq 'XT_ENGAGE' }).enHash = (Sha 'Engage flux now')
    $o.tokens += [pscustomobject]@{ key = 'XT_NEW'; enHash = (Sha 'Brand new zorblat'); pt = 'Zorblat novinho' }
    Write-TestJson (Join-Path $d2 'tokens.json') $o
    $o = ReadJson (Join-Path $d2 'hints.json')
    $o.lines += [pscustomobject]@{ enHash = (Sha 'return "Recharging"'); texts = @('Recarregando') }
    Write-TestJson (Join-Path $d2 'hints.json') $o
    $r = Run 'Status' (G) $d2
    Check ($r.Out -match 'traduções novas') 'status says the dictionary has new translations'
    $r = Run 'Translate' (G) $d2
    Check ($r.Code -eq 0) "reapplied without pending items (exited $($r.Code))"
    Check ((TextOf $TOK).Contains('"Zorblat novinho"') -and (TextOf $NUT).Contains('"Recarregando"')) 'new translations applied'
    Check (([regex]::Matches((TextOf $NUT), $MARK)).Count -eq 1) 'marker did not duplicate'
    Check ((Get-FileHash -LiteralPath (BackupPath $TOK) -Algorithm SHA256).Hash -eq $hTok2) 'backup is still the original'
    $r = Run 'Restore' (G) $d2
    ResetMod; ClearData

    Write-Host "`n[8] Entries that would touch the code become pending items"
    $d3 = CopyDic 'd3'
    $o = ReadJson (Join-Path $d3 'tokens.json')
    ($o.tokens | Where-Object { $_.key -eq 'XT_HOLD' }).pt = 'Segure perto da escotilha'
    ($o.tokens | Where-Object { $_.key -eq 'XT_ENGAGE' }).pt = "Ati`nvar"
    ($o.tokens | Where-Object { $_.key -eq 'XT_TITLE' }).pt = 'PAINEL "ZORBLAT'
    Write-TestJson (Join-Path $d3 'tokens.json') $o
    $h = @{}
    $dicLines = @(
        # quotes in the text would change the line's code
        [pscustomobject]@{ enHash = (Sha 'return "Zorblat is empty"'); texts = @('Vazio" + TestBad() + "') }
        # internal name used as an argument must not change
        [pscustomobject]@{ enHash = (Sha 'Test_Command( "test_internal_command" )'); texts = @('kill') }
        # wrong number of literals
        [pscustomobject]@{ enHash = (Sha 'return "Tap " + lever + " to flip the quark"'); texts = @('Só um') }
        # template that tries to call new code
        [pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Test_Gestures()[hand] + " for " + Localize( hint.name )'); template = '{0} TestBad() + {1} + {2}' }
        # line break inside the text
        [pscustomobject]@{ enHash = (Sha 'string lever = hand == 0 ? "quark lever" : "muon lever"'); texts = @("ala`nvanca", 'outra') }
    )
    Write-TestJson (Join-Path $d3 'hints.json') ([pscustomobject]@{ file = $NUT; name = 'dicas de teste'; lines = $dicLines })
    $r = Run 'Translate' (G) $d3
    Check ($r.Code -eq 10) "become pending items (exited $($r.Code))"
    Check ((TextOf $TOK).Contains('"Keep %use% down near the quark hatch"')) 'token that lost %use% stayed original'
    Check ((TextOf $TOK).Contains('"XT_ENGAGE" "Engage flux"')) 'token with a line break stayed original'
    Check ((TextOf $TOK).Contains('"ZORBLAT PANEL"')) 'token with quotes stayed original'
    Check (-not (TextOf $NUT).Contains('TestBad')) 'code injected by text or template did not reach the mod'
    Check ((TextOf $NUT).Contains('Test_Command( "test_internal_command" )') -and -not (TextOf $NUT).Contains('"kill"')) 'internal code name was not replaced'
    Check ((TextOf $NUT).Contains('return "Tap " + lever + " to flip the quark"')) 'wrong number of literals stayed original'
    Check ((TextOf $NUT).Contains('"quark lever"')) 'line break in the line stayed original'
    $r = Run 'Restore' (G) $d3
    Check (AllOriginal) 'restoring after that returns the original'

    Write-Host "`n[9] Template missing a piece of the original code is refused"
    $d4 = CopyDic 'd4'
    $dicLines = @([pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Test_Gestures()[hand] + " for " + Localize( hint.name )'); template = '{0} "Sem nome " + {1}' })
    Write-TestJson (Join-Path $d4 'hints.json') ([pscustomobject]@{ file = $NUT; name = 'dicas de teste'; lines = $dicLines })
    $r = Run 'Translate' (G) $d4
    Check ((TextOf $NUT).Contains('"Sweep hand "')) 'line stayed original'
    $r = Run 'Restore' (G) $d4

    Write-Host "`n[10] Faulty dictionary is refused without writing anything"
    $d5 = CopyDic 'd5'
    $o = ReadJson (Join-Path $d5 'hints.json'); $o.file = 'Titanfall2.exe'; Write-TestJson (Join-Path $d5 'hints.json') $o
    $r = Run 'Translate' (G) $d5
    Check ($r.Code -eq 1 -and $r.Out -match 'não permitido') 'path outside the mod texts'
    $d6 = CopyDic 'd6'
    $o = ReadJson (Join-Path $d6 'tokens.json')
    $o.tokens[0] | Add-Member -NotePropertyName en -NotePropertyValue 'Mod text'
    Write-TestJson (Join-Path $d6 'tokens.json') $o
    $r = Run 'Translate' (G) $d6
    Check ($r.Code -eq 1 -and $r.Out -match "campo 'en'") 'entry with the en field'
    $d7 = CopyDic 'd7'
    $o = ReadJson (Join-Path $d7 'tokens.json'); $o.tokens[0].enHash = 'abc'; Write-TestJson (Join-Path $d7 'tokens.json') $o
    $r = Run 'Translate' (G) $d7
    Check ($r.Code -eq 1 -and $r.Out -match "enHash") 'invalid hash'
    $d8 = CopyDic 'd8'
    $o = ReadJson (Join-Path $d8 'tokens.json'); $o.tokens[0].PSObject.Properties.Remove('pt'); Write-TestJson (Join-Path $d8 'tokens.json') $o
    $r = Run 'Translate' (G) $d8
    Check ($r.Code -eq 1 -and $r.Out -match "sem o campo 'pt'") 'entry without pt'
    $d9 = CopyDic 'd9'
    Copy-Item -LiteralPath (Join-Path $d9 'hints.json') -Destination (Join-Path $d9 'hints - Copia.json')
    $r = Run 'Translate' (G) $d9
    Check ($r.Code -eq 1 -and $r.Out -match 'mesmo script') 'forgotten copy in the dictionary'
    Check (AllOriginal) 'nothing was written'

    Write-Host "`n[11] A case-only change in the code does not match the dictionary"
    Write-TestFile (P $NUT) (((Get-NutLines) -join "`r`n").Replace('return "Tap " + lever', 'return "Tap " + Lever')) $UTF8
    $r = Run 'Translate' (G)
    Check ((TextOf $NUT).Contains('return "Tap " + Lever + " to flip the quark"')) 'different line was not replaced'
    Check ($r.Code -eq 10) 'and became a pending item'
    $r = Run 'Restore' (G); ResetMod

    Write-Host "`n[12] An already translated file without the marker does not become a backup"
    $r = Run 'Translate' (G)
    $noMark = ((TextOf $NUT) -split "`r`n" | Where-Object { $_ -notmatch $MARK }) -join "`r`n"
    $backupHash = (Get-FileHash -LiteralPath (BackupPath $NUT) -Algorithm SHA256).Hash
    Write-TestFile (P $NUT) $noMark $UTF8
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 1) "refuses with an error (exited $($r.Code))"
    Check ((Get-FileHash -LiteralPath (BackupPath $NUT) -Algorithm SHA256).Hash -eq $backupHash) 'backup was not overwritten'
    ResetMod; ClearData

    Write-Host "`n[13] Old translation package installed"
    $oldCopy = "$(P $NUT).orig-ptbr"
    Write-TestFile $oldCopy 'x' $UTF8
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 1 -and $r.Out -match 'pacote antigo') '.orig-ptbr copy: refuses and explains'
    $r = Run 'Status' (G)
    Check ($r.Out -match 'pacote antigo') 'status warns'
    Remove-Item -LiteralPath $oldCopy
    $oldDir = P 'TF2VR\mods\TF2VR.PTBR'
    New-Item -ItemType Directory -Force -Path $oldDir | Out-Null
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 1 -and $r.Out -match 'pacote antigo') 'old mod folder: refuses and explains'
    Remove-Item -LiteralPath $oldDir -Recurse
    Check (AllOriginal) 'nothing was written'

    Write-Host "`n[14] Open game blocks writing"
    $r = Run 'Translate' (G @('-GameProcesses', $CURRENT_SHELL))
    Check ($r.Code -eq 1 -and $r.Out -match 'aberto') 'refuses with the game open'
    Check (AllOriginal) 'nothing was written'

    Write-Host "`n[15] No write permission"
    $file = Get-Item -LiteralPath (P $NUT); $file.IsReadOnly = $true
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 3) "exits with code 3 (exited $($r.Code))"
    $r2 = Run 'Translate' (G @('-Elevated')) $DIC "`n"
    Check ($r2.Code -eq 3 -and $r2.Out -match 'Nem como administrador') 'elevated window does not open another'
    $file.IsReadOnly = $false
    Check (AllOriginal) 'did not translate halfway'

    Write-Host "`n[16] Failure in the middle of the write undoes everything"
    $lock = [IO.File]::Open((P $NUT), 'Open', 'Read', 'ReadWrite')
    try { $r = Run 'Translate' (G) } finally { $lock.Close() }
    Check ($r.Code -eq 1) "fails with an error (exited $($r.Code))"
    Check (AllOriginal) 'files written before the failure went back to the original'
    Check (-not (Get-ChildItem -LiteralPath $GAME -Recurse -Filter '*.tmp-ptbr')) 'no temporary file left behind'
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 0) 'after unlocking, translates normally'
    $r = Run 'Restore' (G)

    Write-Host "`n[17] File open in another program does not ask for administrator"
    $lock = [IO.File]::Open((P $NUT), 'Open', 'Read', 'Read')
    try { $r = Run 'Translate' (G) } finally { $lock.Close() }
    Check ($r.Code -eq 1 -and $r.Out -match 'aberto em outro programa') 'explains that another program is using it'
    Check (AllOriginal) 'nothing was written'

    Write-Host "`n[18] Remembered folder and the status line of the window"
    $r = Run 'Status' (G)
    $r = Run 'Status'
    Check ($r.Out.Contains($GAME)) 'without -GameDir, uses the saved folder'
    function StatusLine([string[]]$extra = @()) {
        $r = Run 'Status' (@('-Json') + $extra)
        $line = @($r.Out -split "`n" | Where-Object { $_ -like 'TF2VR_STATUS:*' })
        if ($line.Count -ne 1) { return $null }
        return ($line[0].Substring(13).Trim() | ConvertFrom-Json)
    }
    $s = StatusLine
    Check ($s -and $s.gameDir -ceq $GAME) 'the status line has the saved folder'
    Check ($s -and $s.modInstalled -eq $true -and @($s.files).Count -eq $ALL_FILES.Count) 'and every file of the mod'
    Check (($r = Run 'Status' @('-Json')).Out -cmatch '^[\x00-\x7F\r\n]*$') 'the status line is plain ASCII'
    $s = StatusLine @('-GameDir', (Join-Path $LAB 'folder that does not exist'))
    Check ($s -and $s.error -match 'Titanfall2.exe' -and $s.gameDir -eq $null) 'a wrong folder comes back as an error in the line'
    $r = Run 'Status'
    Check ($r.Out.Contains($GAME)) 'the previous folder is still saved'

    Write-Host "`n[19] Restore without a backup: refuses without damage"
    $r = Run 'Translate' (G)
    Remove-Item -LiteralPath (BackupPath $NUT)
    $before = HashOf $NUT
    $r = Run 'Restore' (G)
    Check ($r.Code -eq 1) 'fails with a clear error'
    Check ((HashOf $NUT) -eq $before) 'file was not changed'
    ResetMod; ClearData

    Write-Host "`n[20] Target file missing in a new mod version"
    Remove-Item -LiteralPath (P $PANEL)
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 0 -and $r.Out -match 'foi pulado') 'skips the missing file and warns'
    Check ((TextOf $TOK).Contains('PAINEL ZORBLAT')) 'translates the rest normally'
    $r = Run 'Restore' (G); ResetMod; ClearData

    Write-Host "`n[22] Tampered backup is refused"
    $r = Run 'Translate' (G)
    $b = [IO.File]::ReadAllBytes((BackupPath $NUT)); $b[3] = $b[3] -bxor 1; [IO.File]::WriteAllBytes((BackupPath $NUT), $b)
    $before = HashOf $NUT
    $r = Run 'Restore' (G)
    Check ($r.Code -eq 1 -and $r.Out -match 'não confere') 'restore refuses'
    Check ((HashOf $NUT) -eq $before) 'restore wrote nothing'
    $d10 = CopyDic 'd10'
    $o = ReadJson (Join-Path $d10 'tokens.json'); ($o.tokens | Where-Object { $_.key -eq 'XT_TITLE' }).pt = 'PAINEL NOVO'; Write-TestJson (Join-Path $d10 'tokens.json') $o
    $r = Run 'Translate' (G) $d10
    Check ($r.Code -eq 1 -and $r.Out -match 'não confere') 'translate refuses'
    Check ((HashOf $NUT) -eq $before) 'translate wrote nothing'
    Remove-Item -LiteralPath (Join-Path $DATA 'backup\backup.json')
    $r = Run 'Restore' (G)
    Check ($r.Code -eq 1 -and (HashOf $NUT) -eq $before) 'without backup.json it also refuses'
    ResetMod; ClearData

    Write-Host "`n[23] Temporary files from a window closed midway are cleaned"
    $t1 = "$(P $NUT).tmp-ptbr"; $t2 = Join-Path (Split-Path (P $NUT)) '.ptbr-teste-abc'; $t3 = Join-Path (Split-Path (P $NUT)) 'other.txt'
    foreach ($t in $t1, $t2, $t3) { Write-TestFile $t 'x' $UTF8 }
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 0 -and -not (Test-Path -LiteralPath $t1) -and -not (Test-Path -LiteralPath $t2)) 'the tool''s temporary files are gone'
    Check (Test-Path -LiteralPath $t3) 'file from another source stayed'
    Remove-Item -LiteralPath $t3
    $r = Run 'Restore' (G); ResetMod; ClearData

    Write-Host "`n[24] Template without an internal name in the clear"
    $d11 = CopyDic 'd11'
    $dicLines = @([pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Test_Gestures()[hand] + " for " + Localize( hint.name )'); template = ('{0} "Mova " + ( {1} == {=' + (Sha 'name-that-does-not-exist') + '} ? "x" : {1} ) + {2}') })
    Write-TestJson (Join-Path $d11 'hints.json') ([pscustomobject]@{ file = $NUT; name = 'dicas de teste'; lines = $dicLines })
    $r = Run 'Translate' (G) $d11
    Check ((TextOf $NUT).Contains('"Sweep hand "') -and $r.Code -eq 10) 'name that does not exist in the file: line stays original and becomes pending'
    $r = Run 'Restore' (G) $d11; ResetMod; ClearData

    Write-Host "`n[25] Elevation: the script only asks, and the elevated data stays apart"
    $ADMIN = Join-Path $LAB 'admin data'
    $file = Get-Item -LiteralPath (P $NUT); $file.IsReadOnly = $true
    $r = Run 'Translate' (G) $DIC ''
    Check ($r.Code -eq 3 -and $r.Out -match 'Titanfall2VR-PTBR\.exe') 'running the script directly: elevates nothing and points to the exe'
    $r = Run 'Translate' (G @('-ViaExe')) $DIC ''
    Check ($r.Code -eq 20) "through the exe: returns the request (exited $($r.Code))"
    $request = [IO.File]::ReadAllText((Join-Path $DATA 'elevation-request.txt')) -split "`n"
    Check ($request[0] -ceq 'Translate' -and $request[1] -ceq $GAME) 'request with the action and the game folder'
    $file.IsReadOnly = $false
    Check (AllOriginal) 'nothing was written before permission'
    $DATA_NORMAL = $DATA; $DATA = $ADMIN
    $r = Run 'Translate' (G @('-Elevated')) $DIC ''
    $DATA = $DATA_NORMAL
    Check ($r.Code -eq 0 -and (IsTranslated $NUT)) 'elevated stage translates with its own data'
    Check (Test-Path -LiteralPath (Join-Path $ADMIN 'backup\backup.json')) 'backup in the administrators folder'
    Check (-not (Test-Path -LiteralPath (Join-Path $DATA 'backup'))) 'no backup in the user folder'
    $r = Run 'Status' (G @('-AdminDataDir', $ADMIN))
    Check ($r.Out -match 'em português' -and $r.Out.Contains($ADMIN)) 'normal stage reads the elevated state'
    $r = Run 'Translate' (G @('-AdminDataDir', $ADMIN))
    Check ($r.Out -match 'Tudo atualizado') 'nothing to do: does not ask for permission'
    $r = Run 'Restore' (G @('-AdminDataDir', $ADMIN, '-ViaExe')) $DIC ''
    Check ($r.Code -eq 20) 'restore requires the elevated stage, even with a writable folder'
    $DATA = $ADMIN
    $r = Run 'Restore' (G @('-Elevated')) $DIC ''
    $DATA = $DATA_NORMAL
    Check ($r.Code -eq 0 -and (AllOriginal)) 'elevated stage restores byte for byte'
    [IO.File]::WriteAllText((Join-Path $ADMIN 'jogo.txt'), 'other folder')
    $r = Run 'Status' (G @('-AdminDataDir', $ADMIN))
    Check (-not $r.Out.Contains($ADMIN)) 'elevated data of another game is ignored'
    ClearData

    Write-Host "`n[26] A backup from one game folder does not serve another"
    $GAME2 = Join-Path $LAB 'other game'
    Build-Mod $GAME2
    $target2 = Join-Path $GAME2 $NUT
    $r = Run 'Translate' (G)
    $info = [IO.File]::ReadAllText((Join-Path $DATA 'backup\backup.json'))
    Check ($info.Contains('jogo')) 'backup.json records the game folder'
    $backupBefore = (Get-FileHash -LiteralPath (BackupPath $NUT)).Hash; $h2 = (Get-FileHash -LiteralPath $target2).Hash
    $r = Run 'Translate' @('-GameDir', $GAME2)
    Check ($r.Code -eq 1 -and $r.Out -match 'outra pasta') 'translate other folder: refuses'
    $r = Run 'Restore' @('-GameDir', ($GAME2 + '/'))
    Check ($r.Code -eq 1 -and $r.Out -match 'outra pasta') 'restore other folder: refuses'
    Check ((Get-FileHash -LiteralPath $target2).Hash -eq $h2) 'the other folder stayed as it was'
    Check ((Get-FileHash -LiteralPath (BackupPath $NUT)).Hash -eq $backupBefore) 'the backup is still the same'
    $r = Run 'Status' (G @()) ; $r = Run 'Restore' @('-GameDir', ($GAME + '/'))
    Check ($r.Code -eq 0 -and (AllOriginal)) 'same folder, written with a trailing slash: restores'
    $r = Run 'Translate' @('-GameDir', $GAME2)
    Check ($r.Code -eq 0 -and [IO.File]::ReadAllText($target2).Contains($MARK)) 'after restoring, the other folder can be translated'
    Remove-Item -LiteralPath (Join-Path $GAME2 'Titanfall2.exe')
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 0) 'a registered installation that disappeared does not hold the backup'
    $r = Run 'Restore' (G); ResetMod; ClearData
    Remove-Item -LiteralPath $GAME2 -Recurse -Force

    Write-Host "`n[27] Target with a junction in the path is refused"
    $targetDir = Split-Path (P $NUT)
    $outside = Join-Path $LAB 'outside the game'
    Copy-Item -LiteralPath $targetDir -Destination $outside -Recurse
    Rename-Item -LiteralPath $targetDir -NewName 'real folder'
    $realDir = Join-Path (Split-Path $targetDir) 'real folder'
    New-Item -ItemType Junction -Path $targetDir -Target $outside | Out-Null
    $hOutside = (Get-FileHash -LiteralPath (Join-Path $outside (Split-Path $NUT -Leaf))).Hash
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 1 -and $r.Out -match 'junction') 'refuses, with a clear error'
    Check ((Get-FileHash -LiteralPath (Join-Path $outside (Split-Path $NUT -Leaf))).Hash -eq $hOutside) 'nothing was written at the link target'
    [IO.Directory]::Delete($targetDir, $false)
    Rename-Item -LiteralPath $realDir -NewName (Split-Path $targetDir -Leaf)
    Remove-Item -LiteralPath $outside -Recurse -Force
    ResetMod; ClearData

    Write-Host "`n[21] No calls to external translation tools"
    $code = [IO.File]::ReadAllText($SCRIPT)
    $a = Run 'Status' (G @(('-Sem' + 'Cla' + 'ude')))
    Check ($a.Code -ne 0 -or $a.Out -match 'parameter|parâmetro') 'old parameter no longer exists'
    Check (-not ($code -match 'Start-Job|Invoke-WebRequest|Invoke-RestMethod|DownloadString|Net\.WebClient')) 'script downloads nothing and opens no background job'

    Write-Host "`n[28] Files and state written by v1.0.0 are recognised"
    # Hand-built fixture in the exact v1.0.0 on-disk layout (literal names, not read from the tool).
    ResetMod; ClearData
    $v1Marker = '// titanfall2-vr-ptbr traduzido para PT-BR. O original esta no backup da ferramenta.'
    $pureText = [IO.File]::ReadAllText((Join-Path $PURE_MOD $NUT))
    Write-TestFile (P $NUT) ($v1Marker + "`r`n" + $pureText) $UTF8
    New-Item -ItemType Directory -Force -Path (Split-Path (BackupPath $NUT)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $PURE_MOD $NUT) -Destination (BackupPath $NUT)
    $v1Files = @{}; $v1Files[$NUT] = (Get-FileHash -LiteralPath (P $NUT) -Algorithm SHA256).Hash
    $v1Backup = @{}; $v1Backup[$NUT] = (Get-FileHash -LiteralPath (BackupPath $NUT) -Algorithm SHA256).Hash
    Write-TestJson (Join-Path $DATA 'estado.json') ([pscustomobject]@{ versaoMod = '9.9.1'; aplicadoEm = '2026-11-03'; hashDicionario = 'v1-dictionary-hash'; arquivos = $v1Files })
    Write-TestJson (BackupPath 'backup.json') ([pscustomobject]@{ data = '2026-11-03'; versaoMod = '9.9.1'; jogo = $GAME; arquivos = $v1Backup })
    Write-TestJson (Join-Path $DATA 'config.json') ([pscustomobject]@{ pastaJogo = $GAME; origem = 'informada no comando'; salvoEm = '2026-11-03' })
    $r = Run 'Status' (G)
    Check ($r.Code -eq 0 -and $r.Out -match 'em português') 'status recognises the v1.0.0 translated file and state'
    Check ($r.Out -match 'mod v9\.9\.1, de 2026-11-03') 'status reads the v1.0.0 backup record'
    $r = Run 'Restore' (G)
    Check ($r.Code -eq 0 -and (AllOriginal)) 'restore from a v1.0.0 backup is byte-identical'
    $r = Run 'Translate' (G)
    Check ($r.Code -eq 0 -and (IsTranslated $NUT)) 'translate works over the v1.0.0 data folder'
    $r = Run 'Restore' (G)
    Check ($r.Code -eq 0 -and (AllOriginal)) 'and restores again'
} finally {
    Set-Location -LiteralPath $ROOT
    Get-ChildItem -LiteralPath $LAB -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.IsReadOnly } | ForEach-Object { $_.IsReadOnly = $false }
    Remove-Item -LiteralPath $LAB -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:failures -eq 0) { Write-Host "ALL $($script:total) TESTS PASSED on $CURRENT_SHELL" -ForegroundColor Green }
else { Write-Host "$($script:failures) FAILURE(S) of $($script:total) on $CURRENT_SHELL" -ForegroundColor Red }
exit $script:failures
