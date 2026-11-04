# Tests the installer end to end with the synthetic mod: install, translate, uninstall, originals back.
# It touches the real profile and the real apps list of the account, so it only runs on the CI machine.
# Usage: powershell -File tests\test-installer.ps1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
if (-not $env:GITHUB_ACTIONS) { throw 'This test changes the real profile and only runs on the CI machine.' }
. (Join-Path $PSScriptRoot 'synthetic.ps1')

$ROOT = Split-Path $PSScriptRoot -Parent
$version = ([IO.File]::ReadAllText((Join-Path $ROOT 'VERSION'))).Trim()
$SETUP = Join-Path $ROOT "dist\Instalador-Traducao-PTBR-Mod-Titanfall2VR-v$version.exe"
$OLD_EXE = Join-Path $ROOT 'dist\Titanfall2VR-PTBR.exe'
$LAB = Join-Path ([IO.Path]::GetTempPath()) ('tf2vr setup ' + [guid]::NewGuid().ToString('N'))
$GAME = Join-Path $LAB 'game with space'
$PURE = Join-Path $LAB 'pure'
$NOMOD = Join-Path $LAB 'no mod'
$DIC = Join-Path ([IO.Path]::GetTempPath()) ('tf2vr-dic-' + [guid]::NewGuid().ToString('N'))
$LOG = Join-Path $LAB 'setup.log'
$APP = Join-Path $env:LOCALAPPDATA 'Programs\Titanfall2VR-PTBR'
$DATA = Join-Path $env:LOCALAPPDATA 'ScarletModder\Titanfall2VR-PTBR'
$ENTRY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{7B0E5C1A-3D42-4F6B-9A58-2C8D1E7F4A36}_is1'
$LEGACY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Titanfall2VR-PTBR'
$UNINSTALLER = Join-Path $APP 'unins000.exe'
$WAIT_SECONDS = 120

$script:failures = 0
$script:total = 0
function Check($cond, $msg) {
    $script:total++
    if ($cond) { Write-Host "  OK    $msg" -ForegroundColor Green }
    else {
        Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:failures++
        Write-Host "        Apps list: $((Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) -join ', ')"
        if (Test-Path -LiteralPath $LOG) { Get-Content -LiteralPath $LOG -Encoding UTF8 | Select-Object -Last 25 | ForEach-Object { Write-Host "        $_" } }
    }
}
function BytesEqual($a, $b) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b)) }
function Originals { foreach ($rel in $ALL_FILES) { if (-not (BytesEqual (Join-Path $GAME $rel) (Join-Path $PURE $rel))) { return $false } }; return $true }
function BackupHashes { return (Get-ChildItem -LiteralPath (Join-Path $DATA 'backup') -Recurse -File | Sort-Object FullName | Get-FileHash | ForEach-Object { $_.Hash }) -join ',' }
function Install([string]$gameDir) {
    $p = Start-Process -FilePath $SETUP -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', "/LOG=`"$LOG`"", "/GAMEDIR=`"$gameDir`"", "/TOOLARGS=`"-DictionaryDir $DIC`"") -PassThru
    if (-not $p.WaitForExit($WAIT_SECONDS * 1000)) { $p.Kill(); throw 'The installer did not finish: it may be waiting for an answer.' }
    return $p.ExitCode
}
# The uninstaller reopens itself from a temporary copy and returns at once, so the wait is on its effect.
function Uninstall {
    Start-Process -FilePath $UNINSTALLER -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', "/LOG=`"$LOG`"", "/TOOLARGS=`"-DictionaryDir $DIC`"") -Wait
    foreach ($i in 1..$WAIT_SECONDS) {
        if (-not (Get-Process -Name '_iu*' -ErrorAction SilentlyContinue) -and -not (Get-Process -Name 'Titanfall2VR-PTBR' -ErrorAction SilentlyContinue)) { break }
        Start-Sleep 1
    }
}
function WaitGone($path) {
    foreach ($i in 1..$WAIT_SECONDS) { if (-not (Test-Path -LiteralPath $path)) { return $true }; Start-Sleep 1 }
    return $false
}

try {
    New-Item -ItemType Directory -Force -Path $LAB | Out-Null
    New-Item -ItemType Directory -Force -Path $DIC | Out-Null
    Build-Dictionary $DIC
    Build-Mod $GAME
    Build-Mod $PURE
    New-Item -ItemType Directory -Force -Path $NOMOD | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $NOMOD 'Titanfall2.exe'), [byte[]]@(0))

    # Inno Setup pads these strings with spaces.
    Write-Host '[1] Metadata'
    $info = (Get-Item -LiteralPath $SETUP).VersionInfo
    Check ($info.CompanyName.Trim() -ceq 'Scarlet Modder') 'author in the file'
    Check ($info.FileVersion.Trim() -ceq "$version.0") "version in the file ($($info.FileVersion))"
    Check ($info.ProductName.Trim() -ceq 'Tradução PT-BR do mod Titanfall 2 VR') 'product name in the file'

    Write-Host '[2] Install over what an older version left behind'
    # The exe on its own is what the older versions were: it registers itself and keeps a copy in the data folder.
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $OLD_EXE -NonInteractive -NoColor -Action Translate -GameDir $GAME -DictionaryDir $DIC -GameProcesses process-that-does-not-exist 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    $legacyCopy = Join-Path $DATA 'uninstall'
    Check (Test-Path -LiteralPath $LEGACY) 'the older version registered its entry'
    Check (Test-Path -LiteralPath $legacyCopy) 'the older version kept its copy'
    $oldBackup = BackupHashes
    Check ($oldBackup -ne '') 'the older version made its backup'
    $code = Install $GAME
    Check ($code -eq 0) "installer exits 0 (it exited $code)"
    Check (-not (Originals)) 'the translation was applied'
    Check ((BackupHashes) -ceq $oldBackup) 'the backup of the older version stays as it was'
    Check (-not (Test-Path -LiteralPath $LEGACY)) 'the entry of the older version is gone'
    Check (-not (Test-Path -LiteralPath $legacyCopy)) 'the copy of the older version is gone'

    Write-Host '[3] Entry in the Windows apps list'
    $listed = Get-ItemProperty -LiteralPath $ENTRY
    Check ($listed.DisplayName -ceq 'Tradução PT-BR do mod Titanfall 2 VR') 'name in the list'
    Check ($listed.Publisher -ceq 'Scarlet Modder') 'publisher in the list'
    Check ($listed.DisplayVersion -ceq $version) 'version in the list'
    $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Tradução PT-BR do mod Titanfall 2 VR.lnk'
    Check (Test-Path -LiteralPath $shortcut) 'shortcut in the Start menu'
    Check ((New-Object -ComObject WScript.Shell).CreateShortcut($shortcut).TargetPath -ieq (Join-Path $APP 'Titanfall2VR-PTBR-Window.exe')) 'it opens the window'
    Check (Test-Path -LiteralPath (Join-Path $APP 'Titanfall2VR-PTBR-Window.exe')) 'the window is installed'
    Check (Test-Path -LiteralPath (Join-Path $APP 'LICENSE.txt')) 'the license is installed'

    Write-Host '[4] Installing again changes nothing in the backup'
    $before = (Get-FileHash -LiteralPath (Join-Path $GAME $ALL_FILES[0])).Hash
    $code = Install "$GAME\"
    Check ($code -eq 0 -and (Get-FileHash -LiteralPath (Join-Path $GAME $ALL_FILES[0])).Hash -ceq $before) 'second install, folder ending in a backslash, keeps the translation'
    Check (-not (Test-Path -LiteralPath $LEGACY)) 'the installed copy registers no entry of its own'
    Check (Test-Path -LiteralPath $ENTRY) 'the entry of the installer is still there'

    Write-Host '[4b] The installed program keeps the options of the older versions'
    $installed = Join-Path $APP 'Titanfall2VR-PTBR.exe'
    $tool = @('-NonInteractive', '-NoColor', '-GameDir', $GAME, '-DictionaryDir', $DIC, '-GameProcesses', 'process-that-does-not-exist')
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $said = (& $installed @tool -Action Translate 2>&1 | Out-String)
    Check ($LASTEXITCODE -eq 0 -and $said -match 'Tudo atualizado') 'reapply with nothing to do says so'
    & $installed @tool -Action Restore 2>&1 | Out-Null
    Check ($LASTEXITCODE -eq 0 -and (Originals)) 'back to English without uninstalling'
    & $installed @tool -Action Translate 2>&1 | Out-Null
    Check ($LASTEXITCODE -eq 0 -and -not (Originals)) 'reapply translates again'
    $ErrorActionPreference = $eap
    Check (Test-Path -LiteralPath $ENTRY) 'the entry of the installer is still there'

    Write-Host '[4c] With the window open, the installer and the uninstaller stop'
    $open = Start-Process -FilePath (Join-Path $APP 'Titanfall2VR-PTBR-Window.exe') -ArgumentList @('-DictionaryDir', "`"$DIC`"", '-GameProcesses', 'process-that-does-not-exist') -PassThru
    Start-Sleep 5
    $before = (Get-Item -LiteralPath $UNINSTALLER).LastWriteTimeUtc
    $code = Install $GAME
    Check ($code -eq 1) "installer stops, code 1 (it exited $code)"
    Check ((Get-Item -LiteralPath $UNINSTALLER).LastWriteTimeUtc -eq $before) 'and changes nothing'
    Uninstall
    Check (Test-Path -LiteralPath $ENTRY) 'the uninstaller stops too, and the entry stays'
    Check (-not (Originals)) 'the translation stays'
    $open.Kill(); [void]$open.WaitForExit(10000)

    Write-Host '[5] Uninstall with the game gone: nothing is removed'
    Rename-Item -LiteralPath $GAME -NewName 'game moved'
    Uninstall
    Check (Test-Path -LiteralPath $ENTRY) 'the entry stays'
    Check (Test-Path -LiteralPath $UNINSTALLER) 'the uninstaller stays'
    Check (Test-Path -LiteralPath (Join-Path $DATA 'backup')) 'the backup stays'
    Rename-Item -LiteralPath (Join-Path $LAB 'game moved') -NewName 'game with space'

    Write-Host '[5b] Uninstall with the program gone: nothing is removed when the answer is no'
    $program = Join-Path $APP 'Titanfall2VR-PTBR.exe'
    Rename-Item -LiteralPath $program -NewName 'taken.bin'
    Uninstall
    Check (Test-Path -LiteralPath $ENTRY) 'the entry stays'
    Check (Test-Path -LiteralPath (Join-Path $DATA 'backup')) 'the backup stays'
    Check ((Get-Content -LiteralPath $LOG -Encoding UTF8 -Raw) -match 'antivírus') 'it says the program could not be opened'
    Rename-Item -LiteralPath (Join-Path $APP 'taken.bin') -NewName 'Titanfall2VR-PTBR.exe'

    Write-Host '[6] Uninstall'
    Uninstall
    Check (Originals) 'the originals are back, byte by byte'
    Check (WaitGone $DATA) 'the data folder is gone'
    Check (WaitGone $ENTRY) 'the entry is gone'
    Check (WaitGone (Join-Path $APP 'Titanfall2VR-PTBR.exe')) 'the program is gone'
    Check (WaitGone (Join-Path $APP 'Titanfall2VR-PTBR-Window.exe')) 'the window is gone'
    Check (-not (Test-Path -LiteralPath $LEGACY)) 'no other entry was left'

    Write-Host '[7] Game folder without the mod: says so, and the program stays to try again'
    $code = Install $NOMOD
    Check ($code -eq 30) "installer exits 30 (it exited $code)"
    Check ((Get-Content -LiteralPath $LOG -Encoding UTF8 -Raw) -match 'não está instalado') 'the reason keeps its accents'
    Check (Test-Path -LiteralPath $ENTRY) 'the entry exists to uninstall'
    Uninstall
    Check (WaitGone $ENTRY) 'and it uninstalls with nothing to restore'
} finally {
    Remove-Item -LiteralPath $LAB, $DIC -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "$($script:total - $script:failures) of $($script:total) checks passed"
if ($script:failures -gt 0) { exit 1 }
