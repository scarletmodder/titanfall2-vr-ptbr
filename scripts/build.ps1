# Builds dist\Titanfall2VR-PTBR.exe with the csc of the Windows .NET Framework, wraps it in the Inno Setup installer and generates SHA256SUMS.txt.
# Builds from the root with relative paths and without a PDB, so no local path enters the binary.
# The exe and the installed files carry a fixed date: the build time and time zone are not recorded.
[CmdletBinding()]
param([string]$Output = 'dist', [switch]$SimulateUac, [string]$Iscc)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $root

$version = ([IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
if ($version -cnotmatch '^\d+\.\d+\.\d+$') { throw "Invalid VERSION: $version" }
$inScript = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'tool\titanfall-ptbr.ps1')), "\`$VERSION = '([^']+)'").Groups[1].Value
if ($inScript -cne $version) { throw "VERSION ($version) differs from the version in the script ($inScript)." }

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "Compiler not found at $csc" }

$obj = Join-Path $Output 'obj'
New-Item -ItemType Directory -Force -Path $obj | Out-Null
$generated = Join-Path $obj 'Version.g.cs'
$attributes = @(
    'using System.Reflection;'
    '[assembly: AssemblyTitle("Titanfall 2 VR, PT-BR translation")]'
    '[assembly: AssemblyProduct("Titanfall 2 VR, PT-BR translation")]'
    '[assembly: AssemblyDescription("Fan project, not affiliated with EA, Respawn or CircuitLord")]'
    '[assembly: AssemblyCompany("Scarlet Modder")]'
    '[assembly: AssemblyCopyright("Scarlet Modder, MIT license")]'
    "[assembly: AssemblyVersion(`"$version.0`")]"
    "[assembly: AssemblyFileVersion(`"$version.0`")]"
    "[assembly: AssemblyInformationalVersion(`"$version`")]"
)
[IO.File]::WriteAllText((Join-Path $root $generated), (($attributes -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))

if ((Get-Content -Raw -LiteralPath (Join-Path $root 'src\app.manifest')) -notmatch "assemblyIdentity version=`"$([regex]::Escape($version))\.0`"") { throw "src\app.manifest differs from VERSION $version" }

$exe = Join-Path $Output 'Titanfall2VR-PTBR.exe'
$resources = @('/resource:tool\titanfall-ptbr.ps1,app/titanfall-ptbr.ps1')
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $root 'tool\translations') -File | Sort-Object Name) {
    $resources += "/resource:tool\translations\$($f.Name),app/translations/$($f.Name)"
}
# Test build: swaps the real Windows prompt for an ordinary run. Never published.
$symbols = @()
if ($SimulateUac) { $symbols = @('/define:SIMULATE_UAC') }
$cscArgs = @('/nologo', '/target:exe', '/platform:anycpu', '/optimize+', '/debug-', '/codepage:65001', '/warn:4', '/warnaserror+',
    '/win32manifest:src\app.manifest', "/out:$exe") + $symbols + $resources + @('src\Launcher.cs', $generated)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "csc failed with code $LASTEXITCODE" }

if ($SimulateUac) {
    Remove-Item -LiteralPath (Join-Path $root $obj) -Recurse -Force
    Write-Host "Built for testing: $exe"
    exit 0
}

# Fixed date in the PE header: the build time is not recorded in the file.
$exePath = Join-Path $root $exe
$bytes = [IO.File]::ReadAllBytes($exePath)
$pe = [BitConverter]::ToInt32($bytes, 0x3C)
[Array]::Copy([BitConverter]::GetBytes([int]1767225600), 0, $bytes, $pe + 8, 4)
[IO.File]::WriteAllBytes($exePath, $bytes)

# What users download is the installer, which carries the executable and the license.
if (-not $Iscc) {
    $Iscc = @((Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Iscc) { throw 'Inno Setup 6 not found: install it or pass -Iscc' }
& $Iscc '/Qp' "/DAppVersion=$version" 'installer\titanfall2-vr-ptbr.iss'
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with code $LASTEXITCODE" }

$setupName = "Instalador-Traducao-PTBR-Mod-Titanfall2VR-v$version.exe"
$setupPath = Join-Path $root (Join-Path $Output $setupName)
$setupHash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $root (Join-Path $Output 'SHA256SUMS.txt')), "$setupHash  $setupName`n", (New-Object Text.UTF8Encoding($false)))
Remove-Item -LiteralPath (Join-Path $root $obj) -Recurse -Force
Write-Host "Built: $setupPath"
Write-Host "Installer SHA-256: $setupHash"
