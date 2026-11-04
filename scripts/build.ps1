# Compila dist\Titanfall2VR-PTBR.exe com o csc do .NET Framework do Windows, monta o zip e gera SHA256SUMS.txt.
# Compila a partir da raiz com caminhos relativos e sem PDB, para nenhum caminho local entrar no binário.
# Exe e zip levam data fixa: a hora e o fuso da compilação não ficam registrados.
[CmdletBinding()]
param([string]$Saida = 'dist', [switch]$SimularUac)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$raiz = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $raiz

$versao = ([IO.File]::ReadAllText((Join-Path $raiz 'VERSION'))).Trim()
if ($versao -cnotmatch '^\d+\.\d+\.\d+$') { throw "VERSION inválido: $versao" }
$noScript = [regex]::Match([IO.File]::ReadAllText((Join-Path $raiz 'ferramenta\titanfall-ptbr.ps1')), "\`$VERSAO = '([^']+)'").Groups[1].Value
if ($noScript -cne $versao) { throw "VERSION ($versao) diferente da versão no script ($noScript)." }

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "Não achei o compilador em $csc" }

$obj = Join-Path $Saida 'obj'
New-Item -ItemType Directory -Force -Path $obj | Out-Null
$gerado = Join-Path $obj 'Versao.g.cs'
$atributos = @(
    'using System.Reflection;'
    '[assembly: AssemblyTitle("Titanfall 2 VR, tradução PT-BR")]'
    '[assembly: AssemblyProduct("Titanfall 2 VR, tradução PT-BR")]'
    '[assembly: AssemblyDescription("Projeto de fã, sem vínculo com EA, Respawn ou CircuitLord")]'
    '[assembly: AssemblyCompany("Scarlet Modder")]'
    '[assembly: AssemblyCopyright("Scarlet Modder, licença MIT")]'
    "[assembly: AssemblyVersion(`"$versao.0`")]"
    "[assembly: AssemblyFileVersion(`"$versao.0`")]"
    "[assembly: AssemblyInformationalVersion(`"$versao`")]"
)
[IO.File]::WriteAllText((Join-Path $raiz $gerado), (($atributos -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))

$exe = Join-Path $Saida 'Titanfall2VR-PTBR.exe'
$recursos = @('/resource:ferramenta\titanfall-ptbr.ps1,app/titanfall-ptbr.ps1')
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $raiz 'ferramenta\traducao') -File | Sort-Object Name) {
    $recursos += "/resource:ferramenta\traducao\$($f.Name),app/traducao/$($f.Name)"
}
# Compilação de teste: troca o aviso real do Windows por uma execução comum. Nunca é publicada.
$simbolos = @()
if ($SimularUac) { $simbolos = @('/define:SIMULAR_UAC') }
$argumentos = @('/nologo', '/target:exe', '/platform:anycpu', '/optimize+', '/debug-', '/codepage:65001', '/warn:4', '/warnaserror+',
    '/win32manifest:src\app.manifest', "/out:$exe") + $simbolos + $recursos + @('src\Launcher.cs', $gerado)
& $csc @argumentos
if ($LASTEXITCODE -ne 0) { throw "csc falhou com código $LASTEXITCODE" }

if ($SimularUac) {
    Remove-Item -LiteralPath (Join-Path $raiz $obj) -Recurse -Force
    Write-Host "Compilado para teste: $exe"
    exit 0
}

# Data fixa no cabeçalho PE: a hora da compilação não fica registrada no arquivo.
$caminhoExe = Join-Path $raiz $exe
$bytes = [IO.File]::ReadAllBytes($caminhoExe)
$pe = [BitConverter]::ToInt32($bytes, 0x3C)
[Array]::Copy([BitConverter]::GetBytes([int]1767225600), 0, $bytes, $pe + 8, 4)
[IO.File]::WriteAllBytes($caminhoExe, $bytes)

# O pacote só leva o que quem usa precisa: o executável e a licença.
Add-Type -AssemblyName System.IO.Compression
$dataFixa = New-Object DateTimeOffset(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
$nomeZip = "Titanfall2VR-PTBR-v$versao.zip"
$caminhoZip = Join-Path $raiz (Join-Path $Saida $nomeZip)
if (Test-Path -LiteralPath $caminhoZip) { Remove-Item -LiteralPath $caminhoZip }
$fluxo = [IO.File]::Open($caminhoZip, [IO.FileMode]::CreateNew)
$zip = New-Object IO.Compression.ZipArchive($fluxo, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($par in @(@('Titanfall2VR-PTBR.exe', $caminhoExe), @('LICENSE.txt', (Join-Path $raiz 'LICENSE')))) {
        $entrada = $zip.CreateEntry($par[0], [IO.Compression.CompressionLevel]::Optimal)
        $entrada.LastWriteTime = $dataFixa
        $destino = $entrada.Open()
        try { $b = [IO.File]::ReadAllBytes($par[1]); $destino.Write($b, 0, $b.Length) } finally { $destino.Dispose() }
    }
} finally { $zip.Dispose(); $fluxo.Dispose() }

$hash = (Get-FileHash -LiteralPath $caminhoExe -Algorithm SHA256).Hash.ToLowerInvariant()
$hashZip = (Get-FileHash -LiteralPath $caminhoZip -Algorithm SHA256).Hash.ToLowerInvariant()
$soma = "$hash  Titanfall2VR-PTBR.exe`n$hashZip  $nomeZip`n"
[IO.File]::WriteAllText((Join-Path $raiz (Join-Path $Saida 'SHA256SUMS.txt')), $soma, (New-Object Text.UTF8Encoding($false)))
Remove-Item -LiteralPath (Join-Path $raiz $obj) -Recurse -Force
Write-Host "Compilado: $exe"
Write-Host "SHA-256 do exe: $hash"
Write-Host "SHA-256 do zip: $hashZip"
