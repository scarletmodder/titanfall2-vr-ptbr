# Local test against a COPY of the mod, only for people who have the mod installed. The copy never enters the
# repository or the CI. Translates, restores and checks the restore byte for byte.
#
#   pwsh -File tests\test-mod-copy.ps1 -CopyDir <copy> [-Exe dist\Titanfall2VR-PTBR.exe]
#
# The copy must have an EMPTY Titanfall2.exe: it is the guard against running on the real game installation.
# Exits with 0 if the translation is complete and the restore identical.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CopyDir,
    [string]$Exe
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$exeMark = Join-Path $CopyDir 'Titanfall2.exe'
if (-not (Test-Path -LiteralPath $exeMark) -or (Get-Item -LiteralPath $exeMark).Length -ne 0) {
    throw 'This folder does not look like a test copy: Titanfall2.exe must exist and be empty.'
}
$ROOT = Split-Path $PSScriptRoot -Parent
$CURRENT_SHELL = (Get-Process -Id $PID).ProcessName
$SCRIPT = Join-Path $ROOT 'tool\titanfall-ptbr.ps1'
$LAB = Join-Path ([IO.Path]::GetTempPath()) ('tf2vr copy ' + [guid]::NewGuid().ToString('N'))
$GAME = Join-Path $LAB 'game'
$DATA = Join-Path $LAB 'data'
New-Item -ItemType Directory -Force -Path $LAB | Out-Null
Copy-Item -LiteralPath $CopyDir -Destination $GAME -Recurse

function Run($action) {
    $common = @('-Action', $action, '-NonInteractive', '-NoColor', '-GameDir', $GAME, '-DataDir', $DATA, '-GameProcesses', 'process-that-does-not-exist')
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        if ($Exe) { $out = & $Exe @common 6>&1 2>&1 | Out-String }
        else { $out = & $CURRENT_SHELL -NoProfile -ExecutionPolicy Bypass -File $SCRIPT @common 6>&1 2>&1 | Out-String }
        return @{ Code = $LASTEXITCODE; Out = $out }
    } finally { $ErrorActionPreference = $eap }
}
function Get-Hashes($dir) {
    $h = @{}
    foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File) {
        $h[$f.FullName.Substring($dir.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    return $h
}

$failures = 0
try {
    $before = Get-Hashes $GAME
    $r = Run 'Translate'
    Write-Host $r.Out
    if ($r.Code -ne 0) { Write-Host "FAIL: translate exited with $($r.Code)"; $failures++ }
    $pend = @()
    $pendFile = Join-Path $DATA 'pendentes.json'
    if (Test-Path -LiteralPath $pendFile) {
        $pend = @(([IO.File]::ReadAllText($pendFile, [Text.Encoding]::UTF8) | ConvertFrom-Json).itens | Where-Object { $_ })
    }
    Write-Host "Pending items: $($pend.Count)"
    $middle = Get-Hashes $GAME
    $changed = @($before.Keys | Where-Object { $middle[$_] -ne $before[$_] })
    Write-Host "Translated files: $($changed.Count)"

    $r = Run 'Restore'
    if ($r.Code -ne 0) { Write-Host "FAIL: restore exited with $($r.Code)"; Write-Host $r.Out; $failures++ }
    $after = Get-Hashes $GAME
    foreach ($k in $before.Keys) {
        if ($after[$k] -ne $before[$k]) { Write-Host "FAIL: $k differs from the original after restoring"; $failures++ }
        elseif (-not $Exe) {
            # Equal hashes are enough; the direct comparison confirms byte for byte.
            $x = [IO.File]::ReadAllBytes((Join-Path $GAME $k)); $y = [IO.File]::ReadAllBytes((Join-Path $CopyDir $k))
            if ([Convert]::ToBase64String($x) -cne [Convert]::ToBase64String($y)) { Write-Host "FAIL: $k differs in bytes"; $failures++ }
        }
    }
    foreach ($k in $after.Keys) { if (-not $before.ContainsKey($k)) { Write-Host "FAIL: $k was left behind"; $failures++ } }
    if ($failures -eq 0) { Write-Host "RESTORE IDENTICAL in $($before.Count) files ($CURRENT_SHELL$(if ($Exe) { ', via the exe' }))" }
} finally {
    Remove-Item -LiteralPath $LAB -Recurse -Force -ErrorAction SilentlyContinue
}
exit $failures
