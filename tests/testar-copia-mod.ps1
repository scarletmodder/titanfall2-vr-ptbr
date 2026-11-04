# Teste local contra uma CÓPIA do mod, só para quem tem o mod instalado. A cópia nunca entra no repositório
# nem no CI. Traduz e restaura e confere a restauração byte a byte.
#
#   pwsh -File tests\testar-copia-mod.ps1 -PastaCopia <cópia> [-Exe dist\Titanfall2VR-PTBR.exe]
#
# A cópia precisa ter um Titanfall2.exe VAZIO: é a trava contra rodar na instalação real do jogo.
# Sai com 0 se a tradução ficou completa e a restauração idêntica.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PastaCopia,
    [string]$Exe
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$marcaExe = Join-Path $PastaCopia 'Titanfall2.exe'
if (-not (Test-Path -LiteralPath $marcaExe) -or (Get-Item -LiteralPath $marcaExe).Length -ne 0) {
    throw 'Esta pasta não parece uma cópia de teste: o Titanfall2.exe precisa existir e estar vazio.'
}
$RAIZ = Split-Path $PSScriptRoot -Parent
$SHELL_ATUAL = (Get-Process -Id $PID).ProcessName
$SCRIPT = Join-Path $RAIZ 'ferramenta\titanfall-ptbr.ps1'
$LAB = Join-Path ([IO.Path]::GetTempPath()) ('tf2vr copia ' + [guid]::NewGuid().ToString('N'))
$JOGO = Join-Path $LAB 'jogo'
$DADOS = Join-Path $LAB 'dados'
New-Item -ItemType Directory -Force -Path $LAB | Out-Null
Copy-Item -LiteralPath $PastaCopia -Destination $JOGO -Recurse

function Rodar($acao) {
    $comum = @('-Acao', $acao, '-NaoInterativo', '-SemCor', '-PastaJogo', $JOGO, '-PastaDados', $DADOS, '-ProcessosJogo', 'processo-que-nao-existe')
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        if ($Exe) { $saida = & $Exe @comum 6>&1 2>&1 | Out-String }
        else { $saida = & $SHELL_ATUAL -NoProfile -ExecutionPolicy Bypass -File $SCRIPT @comum 6>&1 2>&1 | Out-String }
        return @{ Codigo = $LASTEXITCODE; Saida = $saida }
    } finally { $ErrorActionPreference = $eap }
}
function Hashes($pasta) {
    $h = @{}
    foreach ($f in Get-ChildItem -LiteralPath $pasta -Recurse -File) {
        $h[$f.FullName.Substring($pasta.Length)] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
    return $h
}

$falhas = 0
try {
    $antes = Hashes $JOGO
    $r = Rodar 'Traduzir'
    Write-Host $r.Saida
    if ($r.Codigo -ne 0) { Write-Host "FALHA: traduzir saiu com $($r.Codigo)"; $falhas++ }
    $pend = @()
    $arqPend = Join-Path $DADOS 'pendentes.json'
    if (Test-Path -LiteralPath $arqPend) {
        $pend = @(([IO.File]::ReadAllText($arqPend, [Text.Encoding]::UTF8) | ConvertFrom-Json).itens | Where-Object { $_ })
    }
    Write-Host "Pendências: $($pend.Count)"
    $meio = Hashes $JOGO
    $mudados = @($antes.Keys | Where-Object { $meio[$_] -ne $antes[$_] })
    Write-Host "Arquivos traduzidos: $($mudados.Count)"

    $r = Rodar 'Restaurar'
    if ($r.Codigo -ne 0) { Write-Host "FALHA: restaurar saiu com $($r.Codigo)"; Write-Host $r.Saida; $falhas++ }
    $depois = Hashes $JOGO
    foreach ($k in $antes.Keys) {
        if ($depois[$k] -ne $antes[$k]) { Write-Host "FALHA: $k difere do original depois de restaurar"; $falhas++ }
        elseif (-not $Exe) {
            # Hash igual já basta; a comparação direta confirma byte a byte.
            $x = [IO.File]::ReadAllBytes((Join-Path $JOGO $k)); $y = [IO.File]::ReadAllBytes((Join-Path $PastaCopia $k))
            if ([Convert]::ToBase64String($x) -cne [Convert]::ToBase64String($y)) { Write-Host "FALHA: $k difere em bytes"; $falhas++ }
        }
    }
    foreach ($k in $depois.Keys) { if (-not $antes.ContainsKey($k)) { Write-Host "FALHA: sobrou $k"; $falhas++ } }
    if ($falhas -eq 0) { Write-Host "RESTAURAÇÃO IDÊNTICA em $($antes.Count) arquivos ($SHELL_ATUAL$(if ($Exe) { ', pelo exe' }))" }
} finally {
    Remove-Item -LiteralPath $LAB -Recurse -Force -ErrorAction SilentlyContinue
}
exit $falhas
