# Tests the executable end to end with the synthetic mod, in a temporary folder with a space in its name.
# Usage: powershell -File tests\test-exe.ps1 [-Exe dist\Titanfall2VR-PTBR.exe]
[CmdletBinding()]
param([string]$Exe)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot 'synthetic.ps1')

$ROOT = Split-Path $PSScriptRoot -Parent
if (-not $Exe) { $Exe = Join-Path $ROOT 'dist\Titanfall2VR-PTBR.exe' }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$LAB = Join-Path ([IO.Path]::GetTempPath()) ('tf2vr exe ' + [guid]::NewGuid().ToString('N'))
$GAME = Join-Path $LAB 'game with space'
$PURE = Join-Path $LAB 'pure'
$DATA = Join-Path $LAB 'test data'
$DIC = Join-Path $LAB 'dic'
$defaultDir = Join-Path $env:LOCALAPPDATA 'ScarletModder\Titanfall2VR-PTBR'
$defaultDirExisted = Test-Path -LiteralPath $defaultDir
$adminDefault = Join-Path $env:ProgramData 'ScarletModder'
$adminDefaultExisted = Test-Path -LiteralPath $adminDefault
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$script:failures = 0
$script:total = 0
function Check($cond, $msg) {
    $script:total++
    if ($cond) { Write-Host "  OK    $msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $msg" -ForegroundColor Red; $script:failures++; if ($script:lastOutput) { Write-Host $script:lastOutput } }
}
$script:lastOutput = ''
function Run([string[]]$extra) {
    $a = @('-NonInteractive', '-NoColor', '-GameDir', $GAME, '-DataDir', $DATA, '-GameProcesses', 'process-that-does-not-exist') + $extra
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @a 6>&1 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $eap }
    $script:lastOutput = $out
    return @{ Code = $code; Out = $out }
}
function BytesEqual($a, $b) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b)) }
function Originals { foreach ($rel in $ALL_FILES) { if (-not (BytesEqual (Join-Path $GAME $rel) (Join-Path $PURE $rel))) { return $false } }; return $true }

try {
    New-Item -ItemType Directory -Force -Path $DIC | Out-Null
    Build-Dictionary $DIC
    Build-Mod $GAME
    Build-Mod $PURE

    Write-Host '[1] Metadata and scan'
    $info = (Get-Item -LiteralPath $Exe).VersionInfo
    $version = ([IO.File]::ReadAllText((Join-Path $ROOT 'VERSION'))).Trim()
    Check ($info.CompanyName -ceq 'Scarlet Modder') 'author in the file'
    Check ($info.FileVersion -ceq "$version.0") "version in the file ($($info.FileVersion))"
    $raw = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($Exe))
    Check ($raw.Contains('asInvoker') -and -not $raw.Contains('requireAdministrator')) 'asInvoker manifest'
    Check (-not $raw.Contains('.pdb')) 'no PDB reference'
    # Strings in the exe can start at an odd offset, so both alignments are searched.
    $exeBytes = [IO.File]::ReadAllBytes($Exe)
    $utf16 = [Text.Encoding]::Unicode.GetString($exeBytes) + [Text.Encoding]::Unicode.GetString($exeBytes, 1, $exeBytes.Length - 1)
    Check (-not $utf16.Contains('TF2VR_TEST') -and -not $raw.Contains('TF2VR_TEST')) 'simulation code absent from the published exe'
    Check ($utf16.Contains('runas')) 'published exe asks for the real Windows permission'

    Write-Host '[2] Extraction'
    $r = Run @('-Action', 'Status')
    Check ($r.Code -eq 0) "status exits with 0 (exited $($r.Code))"
    Check ($r.Out.Contains($GAME)) 'path with space and accent reaches the script whole'
    $app = Join-Path $DATA "app\$version"
    Check (BytesEqual (Join-Path $app 'titanfall-ptbr.ps1') (Join-Path $ROOT 'tool\titanfall-ptbr.ps1')) 'extracted script equals the repository one'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $ROOT 'tool\translations') -File) {
        Check (BytesEqual (Join-Path $app "translations\$($f.Name)") $f.FullName) "$($f.Name) extracted equal to the repository one"
    }
    Check ((Test-Path -LiteralPath $defaultDir) -eq $defaultDirExisted) 'with -DataDir, nothing was created in the default folder'

    Write-Host '[3] Embedded dictionary on a mod it does not know'
    $r = Run @('-Action', 'Translate')
    Check ($r.Code -eq 10) "everything becomes pending, code 10 (exited $($r.Code))"
    Check ($r.Out -match 'abra uma issue') 'tells the user to open an issue'
    $r = Run @('-Action', 'Restore')
    Check (Originals) 'restore returns the original byte for byte'

    Write-Host '[4] Translate and restore with the test dictionary'
    $r = Run @('-Action', 'Translate', '-DictionaryDir', $DIC)
    Check ($r.Code -eq 0) "translates, code 0 (exited $($r.Code))"
    Check ([IO.File]::ReadAllText((Join-Path $GAME $NUT)).Contains('O Zorblat está vazio')) 'translation written with accent'
    $r = Run @('-Action', 'Restore', '-DictionaryDir', $DIC)
    Check (Originals) 'restore returns the original byte for byte'

    Write-Host '[5] Error code reaches the caller'
    $r = Run @('-Action', 'Translate', '-DictionaryDir', (Join-Path $LAB 'does-not-exist'))
    Check ($r.Code -eq 1) "error exits with 1 (exited $($r.Code))"

    Write-Host '[6] Extracted old version is cleaned'
    $oldDir = Join-Path $DATA 'app\0.0.1'
    $foreign = Join-Path $DATA 'app\someone-elses-project'
    New-Item -ItemType Directory -Force -Path $oldDir, $foreign | Out-Null
    $r = Run @('-Action', 'Status')
    Check (-not (Test-Path -LiteralPath $oldDir)) 'previous version folder removed'
    Check (Test-Path -LiteralPath $foreign) 'folder without a version name stays'
    $oldDir = Join-Path $DATA 'app\0.0.2'
    $canary = Join-Path $LAB 'canary'
    New-Item -ItemType Directory -Force -Path $oldDir, $canary | Out-Null
    [IO.File]::WriteAllText((Join-Path $canary 'x.txt'), 'x')
    New-Item -ItemType Junction -Path (Join-Path $oldDir 'link') -Target $canary | Out-Null
    $r = Run @('-Action', 'Status')
    Check (-not (Test-Path -LiteralPath $oldDir) -and (Test-Path -LiteralPath (Join-Path $canary 'x.txt'))) 'cleanup removes the junction and does not enter it'

    Write-Host '[7] Elevated stage refuses non-administrators and an invalid request'
    if ($isAdmin) { Write-Host '  SKIPPED: this test runs as administrator' }
    else {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = '' | & $Exe '--elevated' 'Translate' $GAME 2>&1 | Out-String; $code = $LASTEXITCODE
        $ErrorActionPreference = $eap
        Check ($code -eq 1 -and $out -match 'administrador') 'without being administrator, refuses'
        Check (Originals) 'nothing was written'
    }
    Check ((Test-Path -LiteralPath $adminDefault) -eq $adminDefaultExisted) 'nothing created in the administrators folder'

    Write-Host '[8] Whole elevated path, with the test build that simulates the Windows prompt'
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ROOT 'scripts\build.ps1') -Output 'dist\test' -SimulateUac 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    $RealExe = $Exe
    $Exe = Join-Path $ROOT 'dist\test\Titanfall2VR-PTBR.exe'
    $ADMIN_ROOT = Join-Path $LAB 'admin root'
    $env:TF2VR_TEST_ROOT = $ADMIN_ROOT
    $ADMIN_DATA = Join-Path $ADMIN_ROOT 'ScarletModder\Titanfall2VR-PTBR'
    function RunSim([string[]]$extra) {
        $a = @('-NoColor', '-GameDir', $GAME, '-DataDir', $DATA, '-GameProcesses', 'process-that-does-not-exist') + $extra
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = '' | & $Exe @a 6>&1 2>&1 | Out-String; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $eap }
        $script:lastOutput = $out
        return @{ Code = $code; Out = $out }
    }
    function AdminOnly([string]$name) { return @(Get-ChildItem -LiteralPath (Join-Path $ADMIN_ROOT 'ScarletModder') -Directory -Filter $name) }
    function Lock { foreach ($rel in $ALL_FILES) { (Get-Item -LiteralPath (Join-Path $GAME $rel)).IsReadOnly = $true } }
    Remove-Item -LiteralPath (Join-Path $DATA 'estado.json'), (Join-Path $DATA 'backup') -Recurse -Force -ErrorAction SilentlyContinue
    Lock

    $env:TF2VR_TEST_REFUSE = '1'
    $r = RunSim @('-Action', 'Translate')
    $env:TF2VR_TEST_REFUSE = ''
    Check ($r.Code -eq 3 -and $r.Out -match 'recusada') 'permission refused: code 3'
    Check (Originals) 'nothing was written'

    $env:TF2VR_TEST_TAMPER = '1'
    $r = RunSim @('-Action', 'Translate')
    $env:TF2VR_TEST_TAMPER = ''
    Check ($r.Code -eq 1 -and $r.Out -match 'confere') 'tampered extracted file: does not run'
    Check (Originals) 'nothing was written'
    Check (@(AdminOnly 'run-*').Count -eq 0) 'run folder deleted'

    Lock
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -eq 10) "translates through the elevated stage, with the embedded dictionary (exited $($r.Code))"
    Check (@(AdminOnly 'run-*').Count -eq 0) 'run folder deleted at the end'
    $acl = @($r.Out -split "`n" | Where-Object { $_ -match '^acl run-' })
    Check ($acl.Count -eq 1 -and $acl[0] -match 'D:P' -and $acl[0] -match ';BA\)' -and $acl[0] -match ';SY\)' -and $acl[0] -notmatch ';(BU|WD|AU)\)') 'run folder without inheritance, without Users or Everyone'
    $acl = @($r.Out -split "`n" | Where-Object { $_ -match '^acl Titanfall2VR-PTBR' })
    Check ($acl.Count -eq 1 -and $acl[0] -match 'D:P' -and $acl[0] -match 'FA;;;BA\)' -and $acl[0] -match '\(A;OICI;0x1200a9;;;BU\)') 'data folder: Users can only read'
    Check (Test-Path -LiteralPath (Join-Path $ADMIN_DATA 'backup\backup.json')) 'backup in the administrators folder'
    Check (-not (Test-Path -LiteralPath (Join-Path $DATA 'backup'))) 'no backup in the user folder'
    Check (-not (Test-Path -LiteralPath (Join-Path $DATA 'elevation-request.txt'))) 'request consumed'

    $r = RunSim @('-Action', 'Status')
    Check ($r.Out -match 'em português' -and $r.Out.Contains($ADMIN_DATA)) 'normal stage sees the elevated state'
    $r = RunSim @('-Action', 'Restore')
    Check ($r.Code -eq 0 -and (Originals)) 'restoring through the elevated stage returns the original byte for byte'

    $r = RunSim @('-Action', 'Translate')
    $bk = @(Get-ChildItem -LiteralPath (Join-Path $ADMIN_DATA 'backup') -Recurse -File | Where-Object { $_.Name -ne 'backup.json' })[0].FullName
    $b = [IO.File]::ReadAllBytes($bk); $b[3] = $b[3] -bxor 1; [IO.File]::WriteAllBytes($bk, $b)
    $r = RunSim @('-Action', 'Restore')
    Check ($r.Code -eq 1 -and $r.Out -match 'não confere') 'elevated stage refuses a tampered backup'
    $b[3] = $b[3] -bxor 1; [IO.File]::WriteAllBytes($bk, $b)
    $r = RunSim @('-Action', 'Restore')
    Check ($r.Code -eq 0 -and (Originals)) 'with the right backup, restores'

    $ADMIN_SM = Join-Path $ADMIN_ROOT 'ScarletModder'
    $oldRun = Join-Path $ADMIN_SM 'run-old'
    New-Item -ItemType Directory -Force -Path $oldRun | Out-Null
    [IO.File]::WriteAllText((Join-Path $oldRun 'titanfall-ptbr.ps1'), 'x')
    (Get-Item -LiteralPath (Join-Path $oldRun 'titanfall-ptbr.ps1')).IsReadOnly = $true
    New-Item -ItemType Junction -Path (Join-Path $oldRun 'link') -Target $canary | Out-Null
    Lock
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -eq 10 -and -not (Test-Path -LiteralPath $oldRun)) 'old run folder is swept at the start'
    Check (Test-Path -LiteralPath (Join-Path $canary 'x.txt')) 'the sweep does not enter a junction'
    $r = RunSim @('-Action', 'Restore')
    Check ($r.Code -eq 0 -and (Originals)) 'restores after the sweep'

    $link = Join-Path $ADMIN_SM 'planted'
    New-Item -ItemType Junction -Path $link -Target $canary | Out-Null
    Lock
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -eq 1 -and $r.Out -match 'confi.{1,2}vel') 'junction in the administrators folder: refuses without running'
    Check (Originals) 'nothing was written'
    [IO.Directory]::Delete($link, $false)

    $mark = Join-Path $ADMIN_DATA 'jogo.txt'
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & icacls $mark /grant '*S-1-1-0:M' 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    Lock
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -eq 1 -and $r.Out -match 'confi.{1,2}vel') 'child writable by Everyone: refuses without running'
    Check (Originals) 'nothing was written'
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & icacls $mark /remove '*S-1-1-0' 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    Lock
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -eq 10) 'without the problem, translates again'
    $r = RunSim @('-Action', 'Restore')
    Check ($r.Code -eq 0 -and (Originals)) 'and restores'

    Write-Host '[9] Failure saving the state after the write does not claim it was undone'
    foreach ($rel in $ALL_FILES) { (Get-Item -LiteralPath (Join-Path $GAME $rel)).IsReadOnly = $false }
    $env:TF2VR_TEST_ROOT = Join-Path $LAB 'admin root 2'
    $DATA = Join-Path $LAB 'state data'
    $r = RunSim @('-Action', 'Translate')
    $r = RunSim @('-Action', 'Restore')
    $stateFile = Join-Path $DATA 'estado.json'
    (Get-Item -LiteralPath $stateFile).IsReadOnly = $true
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -eq 1 -and $r.Out -match 'foi gravada') 'says the translation was written'
    (Get-Item -LiteralPath $stateFile).IsReadOnly = $false
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -in 0, 10) 'running again finishes'
    $r = RunSim @('-Action', 'Restore')
    Check ($r.Code -eq 0 -and (Originals)) 'and the originals still come back'

    Write-Host '[10] Uninstall through the Windows apps list'
    $env:TF2VR_TEST_ROOT = Join-Path $LAB 'admin root 3'
    $DATA = Join-Path $LAB 'uninstall data'
    $regKey = 'Software\tf2vr-test-' + [guid]::NewGuid().ToString('N')
    $regPath = "HKCU:\$regKey"
    $env:TF2VR_TEST_UNINSTALL_KEY = $regKey
    function RunUninstall([string]$process) {
        $a = @('--uninstall', '-NoColor', '-GameDir', $GAME, '-DataDir', $DATA, '-GameProcesses', $process)
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = '' | & $Exe @a 6>&1 2>&1 | Out-String; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $eap }
        $script:lastOutput = $out
        return @{ Code = $code; Out = $out }
    }
    $r = RunSim @('-Action', 'Translate')
    Check ($r.Code -in 0, 10) 'translates'
    Check (Test-Path -LiteralPath $regPath) 'the apps list entry exists'
    $entry = Get-ItemProperty -LiteralPath $regPath
    $installed = Join-Path $DATA 'uninstall\Titanfall2VR-PTBR.exe'
    Check ($entry.UninstallString -ceq "`"$installed`" --uninstall") 'the entry points to the copy kept in the data folder'
    Check (Test-Path -LiteralPath $installed) 'that copy exists'
    $r = RunUninstall ((Get-Process -Id $PID).ProcessName)
    Check ($r.Code -ne 0 -and -not (Originals)) 'game open: does not uninstall'
    Check ((Test-Path -LiteralPath $regPath) -and (Test-Path -LiteralPath (Join-Path $DATA 'backup'))) 'game open: entry and backup stay'
    # The entry's own copy, left open waiting for Enter and then closed by the window button: the worst case for leftovers.
    $open = Start-Process -FilePath $installed -ArgumentList @('--uninstall', '-NoColor', '-GameDir', "`"$GAME`"", '-DataDir', "`"$DATA`"", '-GameProcesses', 'process-that-does-not-exist') -WindowStyle Hidden -PassThru
    foreach ($i in 1..60) { if (-not (Test-Path -LiteralPath $regPath)) { break }; Start-Sleep -Milliseconds 500 }
    Check ((-not (Test-Path -LiteralPath $regPath)) -and (Originals)) 'originals back byte by byte and entry removed'
    Start-Sleep -Seconds 3
    Check (-not $open.HasExited) 'the window stays open waiting for Enter'
    Stop-Process -Id $open.Id -Force
    foreach ($i in 1..30) { if (-not (Test-Path -LiteralPath $DATA)) { break }; Start-Sleep -Milliseconds 500 }
    Check (-not (Test-Path -LiteralPath $DATA)) 'data folder removed after the window closes'

    # Translating again while the old window is still open: the new backup cannot be lost when it closes.
    $r = RunSim @('-Action', 'Translate')
    $open = Start-Process -FilePath $installed -ArgumentList @('--uninstall', '-NoColor', '-GameDir', "`"$GAME`"", '-DataDir', "`"$DATA`"", '-GameProcesses', 'process-that-does-not-exist') -WindowStyle Hidden -PassThru
    foreach ($i in 1..60) { if (-not (Test-Path -LiteralPath $regPath)) { break }; Start-Sleep -Milliseconds 500 }
    Check (Test-Path -LiteralPath $installed) 'the running copy stays while its window is open'
    Check (-not (Test-Path -LiteralPath (Join-Path $DATA 'backup'))) 'the rest of the data is already gone'
    $r = RunSim @('-Action', 'Translate')
    Stop-Process -Id $open.Id -Force
    Start-Sleep -Seconds 5
    Check (Test-Path -LiteralPath (Join-Path $DATA 'backup')) 'new translation with the old window open: backup survives'
    $r = RunUninstall 'process-that-does-not-exist'
    foreach ($i in 1..30) { if (-not (Test-Path -LiteralPath $DATA)) { break }; Start-Sleep -Milliseconds 500 }
    Check ($r.Code -eq 0 -and (Originals) -and -not (Test-Path -LiteralPath $DATA)) 'and uninstalling again removes it all'

    Write-Host '[11] Uninstall with data in the administrators folder'
    $env:TF2VR_TEST_ROOT = Join-Path $LAB 'admin root 4'
    $adminRoot = Join-Path $env:TF2VR_TEST_ROOT 'ScarletModder'
    function TranslateAsAdmin([string]$name) {
        $script:DATA = Join-Path $LAB $name
        Lock
        return RunSim @('-Action', 'Translate')
    }
    function WaitDataGone { foreach ($i in 1..30) { if (-not (Test-Path -LiteralPath $DATA)) { break }; Start-Sleep -Milliseconds 500 } }
    $r = TranslateAsAdmin 'uninstall admin data 1'
    Check ($r.Code -in 0, 10 -and (Test-Path -LiteralPath (Join-Path $adminRoot 'Titanfall2VR-PTBR\backup'))) 'backup in the administrators folder'
    $r = RunUninstall 'process-that-does-not-exist'
    WaitDataGone
    Check ($r.Code -eq 0 -and (Originals)) 'originals back'
    Check ($r.Out -notmatch 'opção 1') 'does not suggest translating again'
    Check (-not (Test-Path -LiteralPath $DATA)) 'common data removed'
    Check (-not (Test-Path -LiteralPath $adminRoot)) 'empty administrators parent removed'

    $r = TranslateAsAdmin 'uninstall admin data 2'
    $sibling = Join-Path $adminRoot 'OtherTool\keep.bin'
    New-Item -ItemType Directory -Force (Split-Path $sibling) | Out-Null
    [IO.File]::WriteAllBytes($sibling, [byte[]](1, 2, 3))
    $r = RunUninstall 'process-that-does-not-exist'
    WaitDataGone
    Check ($r.Code -eq 0 -and (Originals)) 'with another tool beside it: originals back'
    Check (Test-Path -LiteralPath $sibling) 'the other tool stays'
    Check (-not (Test-Path -LiteralPath (Join-Path $adminRoot 'Titanfall2VR-PTBR'))) 'this tool is gone'
    Check (@(Get-ChildItem -LiteralPath $adminRoot -Filter 'run-*').Count -eq 0) 'no run folder left'

    $script:DATA = Join-Path $LAB 'uninstall admin data 3'
    $r = RunSim @('-Action', 'Translate')
    $env:TF2VR_TEST_REFUSE = '1'
    $r = RunUninstall 'process-that-does-not-exist'
    $env:TF2VR_TEST_REFUSE = ''
    WaitDataGone
    Check ($r.Code -eq 0 -and $r.Out -notmatch 'recusada') 'another tool alone does not ask for permission'
    Check (Originals) 'and the originals are back'
    $Exe = $RealExe

    Write-Host '[12] Run by the wizard: asks nothing, and the reason for a failure comes out'
    $wizardData = Join-Path $LAB 'wizard data'
    # The sections above change the mod on purpose, so this one starts from a clean copy.
    $GAME = Join-Path $LAB 'wizard game'
    Copy-Item -LiteralPath $PURE -Destination $GAME -Recurse
    function RunWizard([string[]]$extra) {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $out = & $Exe @('--wizard') @extra @('-NoColor', '-DataDir', $wizardData, '-GameProcesses', 'process-that-does-not-exist') 6>&1 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally { $ErrorActionPreference = $eap }
        $script:lastOutput = $out
        return @{ Code = $code; Out = $out }
    }
    $r = RunWizard @('-Action', 'Translate', '-GameDir', $GAME, '-DictionaryDir', $DIC)
    Check ($r.Code -eq 0 -and -not (Originals)) 'translates'
    $r = RunWizard @('--uninstall', '-GameDir', (Join-Path $LAB 'folder that does not exist'))
    Check ($r.Code -ne 0 -and $r.Out -match 'Titanfall2.exe' -and (Test-Path -LiteralPath (Join-Path $wizardData 'backup'))) 'a failed restore says why and removes nothing'
    $r = RunWizard @('--uninstall', '-GameDir', $GAME, '-DictionaryDir', $DIC)
    Check ($r.Code -eq 0 -and (Originals)) 'restores on the next try'
    $r = RunWizard @('-Action', 'Translate', '-GameDir', $GAME, '-DictionaryDir', $DIC)
    $r = RunWizard @('--uninstall', '--remove-anyway', '-GameDir', (Join-Path $LAB 'folder that does not exist'))
    Check ($r.Code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $wizardData 'backup'))) 'removing anyway only removes the data of the tool'
} finally {
    $env:TF2VR_TEST_ROOT = ''
    $env:TF2VR_TEST_REFUSE = ''
    if ($env:TF2VR_TEST_UNINSTALL_KEY) { Remove-Item -LiteralPath "HKCU:\$env:TF2VR_TEST_UNINSTALL_KEY" -Recurse -Force -ErrorAction SilentlyContinue }
    $env:TF2VR_TEST_UNINSTALL_KEY = ''
    $simDir = Join-Path $ROOT 'dist\test'
    if (Test-Path -LiteralPath $simDir) { Remove-Item -LiteralPath $simDir -Recurse -Force }
    Remove-Item -LiteralPath $LAB -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if ($script:failures -eq 0) { Write-Host "ALL $($script:total) EXE TESTS PASSED" -ForegroundColor Green }
else { Write-Host "$($script:failures) FAILURE(S) of $($script:total) in the exe" -ForegroundColor Red }
exit $script:failures
