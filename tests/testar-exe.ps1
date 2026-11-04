# Testa o executável de ponta a ponta com o mod sintético, em pasta temporária com espaço no nome.
# Uso: powershell -File tests\testar-exe.ps1 [-Exe dist\Titanfall2VR-PTBR.exe]
[CmdletBinding()]
param([string]$Exe)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot 'sintetico.ps1')

$RAIZ = Split-Path $PSScriptRoot -Parent
if (-not $Exe) { $Exe = Join-Path $RAIZ 'dist\Titanfall2VR-PTBR.exe' }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$LAB = Join-Path ([IO.Path]::GetTempPath()) ('tf2vr exe ' + [guid]::NewGuid().ToString('N'))
$JOGO = Join-Path $LAB 'jogo com espaço'
$PURO = Join-Path $LAB 'puro'
$DADOS = Join-Path $LAB 'dados do teste'
$DIC = Join-Path $LAB 'dic'
$padrao = Join-Path $env:LOCALAPPDATA 'ScarletModder\Titanfall2VR-PTBR'
$padraoExistia = Test-Path -LiteralPath $padrao
$padraoAdmin = Join-Path $env:ProgramData 'ScarletModder'
$padraoAdminExistia = Test-Path -LiteralPath $padraoAdmin
$sou_admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$script:falhas = 0
$script:total = 0
function Conferir($cond, $msg) {
    $script:total++
    if ($cond) { Write-Host "  OK    $msg" -ForegroundColor Green }
    else { Write-Host "  FALHA $msg" -ForegroundColor Red; $script:falhas++; if ($script:ultima) { Write-Host $script:ultima } }
}
$script:ultima = ''
function Rodar([string[]]$extra) {
    $a = @('-NaoInterativo', '-SemCor', '-PastaJogo', $JOGO, '-PastaDados', $DADOS, '-ProcessosJogo', 'processo-que-nao-existe') + $extra
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $saida = & $Exe @a 6>&1 2>&1 | Out-String
        $codigo = $LASTEXITCODE
    } finally { $ErrorActionPreference = $eap }
    $script:ultima = $saida
    return @{ Codigo = $codigo; Saida = $saida }
}
function IguaisByte($a, $b) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($a)) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes($b)) }
function Originais { foreach ($rel in $TODOS) { if (-not (IguaisByte (Join-Path $JOGO $rel) (Join-Path $PURO $rel))) { return $false } }; return $true }

try {
    New-Item -ItemType Directory -Force -Path $DIC | Out-Null
    Montar-Dicionario $DIC
    Montar-Mod $JOGO
    Montar-Mod $PURO

    Write-Host '[1] Metadados e varredura'
    $info = (Get-Item -LiteralPath $Exe).VersionInfo
    $versao = ([IO.File]::ReadAllText((Join-Path $RAIZ 'VERSION'))).Trim()
    Conferir ($info.CompanyName -ceq 'Scarlet Modder') 'autor no arquivo'
    Conferir ($info.FileVersion -ceq "$versao.0") "versão no arquivo ($($info.FileVersion))"
    $bruto = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($Exe))
    Conferir ($bruto.Contains('asInvoker') -and -not $bruto.Contains('requireAdministrator')) 'manifesto asInvoker'
    Conferir (-not $bruto.Contains('.pdb')) 'sem referência a PDB'
    $utf16 = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($Exe))
    Conferir (-not $utf16.Contains('TF2VR_TESTE') -and -not $bruto.Contains('TF2VR_TESTE')) 'código de simulação fora do exe publicado'
    Conferir ($utf16.Contains('runas')) 'exe publicado pede a permissão real do Windows'

    Write-Host '[2] Extração'
    $r = Rodar @('-Acao', 'Status')
    Conferir ($r.Codigo -eq 0) "status sai com 0 (saiu $($r.Codigo))"
    Conferir ($r.Saida.Contains($JOGO)) 'caminho com espaço e acento chega inteiro ao script'
    $app = Join-Path $DADOS "app\$versao"
    Conferir (IguaisByte (Join-Path $app 'titanfall-ptbr.ps1') (Join-Path $RAIZ 'ferramenta\titanfall-ptbr.ps1')) 'script extraído igual ao do repositório'
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $RAIZ 'ferramenta\traducao') -File) {
        Conferir (IguaisByte (Join-Path $app "traducao\$($f.Name)") $f.FullName) "$($f.Name) extraído igual ao do repositório"
    }
    Conferir ((Test-Path -LiteralPath $padrao) -eq $padraoExistia) 'com -PastaDados, nada foi criado na pasta padrão'

    Write-Host '[3] Dicionário embutido num mod que ele não conhece'
    $r = Rodar @('-Acao', 'Traduzir')
    Conferir ($r.Codigo -eq 10) "tudo vira pendência, código 10 (saiu $($r.Codigo))"
    Conferir ($r.Saida -match 'abra uma issue') 'orienta abrir uma issue'
    $r = Rodar @('-Acao', 'Restaurar')
    Conferir (Originais) 'restaurar devolve o original byte a byte'

    Write-Host '[4] Traduzir e restaurar com o dicionário de teste'
    $r = Rodar @('-Acao', 'Traduzir', '-PastaDicionario', $DIC)
    Conferir ($r.Codigo -eq 0) "traduz, código 0 (saiu $($r.Codigo))"
    Conferir ([IO.File]::ReadAllText((Join-Path $JOGO $NUT)).Contains('O Zorblat está vazio')) 'tradução gravada com acento'
    $r = Rodar @('-Acao', 'Restaurar', '-PastaDicionario', $DIC)
    Conferir (Originais) 'restaurar devolve o original byte a byte'

    Write-Host '[5] Código de erro chega a quem chamou'
    $r = Rodar @('-Acao', 'Traduzir', '-PastaDicionario', (Join-Path $LAB 'nao-existe'))
    Conferir ($r.Codigo -eq 1) "erro sai com 1 (saiu $($r.Codigo))"

    Write-Host '[6] Versão antiga extraída é limpa'
    $velha = Join-Path $DADOS 'app\0.0.1'
    $alheia = Join-Path $DADOS 'app\projeto-de-outra-pessoa'
    New-Item -ItemType Directory -Force -Path $velha, $alheia | Out-Null
    $r = Rodar @('-Acao', 'Status')
    Conferir (-not (Test-Path -LiteralPath $velha)) 'pasta da versão anterior removida'
    Conferir (Test-Path -LiteralPath $alheia) 'pasta que não tem nome de versão fica'
    $velha = Join-Path $DADOS 'app\0.0.2'
    $canario = Join-Path $LAB 'canario'
    New-Item -ItemType Directory -Force -Path $velha, $canario | Out-Null
    [IO.File]::WriteAllText((Join-Path $canario 'x.txt'), 'x')
    New-Item -ItemType Junction -Path (Join-Path $velha 'link') -Target $canario | Out-Null
    $r = Rodar @('-Acao', 'Status')
    Conferir (-not (Test-Path -LiteralPath $velha) -and (Test-Path -LiteralPath (Join-Path $canario 'x.txt'))) 'limpeza some com a junction e não entra nela'

    Write-Host '[7] Etapa elevada recusa quem não é administrador e pedido inválido'
    if ($sou_admin) { Write-Host '  PULADO: este teste roda como administrador' }
    else {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $saida = '' | & $Exe '--elevado' 'Traduzir' $JOGO 2>&1 | Out-String; $cod = $LASTEXITCODE
        $ErrorActionPreference = $eap
        Conferir ($cod -eq 1 -and $saida -match 'administrador') 'sem ser administrador, recusa'
        Conferir (Originais) 'nada foi gravado'
    }
    Conferir ((Test-Path -LiteralPath $padraoAdmin) -eq $padraoAdminExistia) 'nada criado na pasta dos administradores'

    Write-Host '[8] Caminho elevado inteiro, com a compilação de teste que simula o aviso do Windows'
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RAIZ 'scripts\build.ps1') -Saida 'dist\teste' -SimularUac 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    $ExeReal = $Exe
    $Exe = Join-Path $RAIZ 'dist\teste\Titanfall2VR-PTBR.exe'
    $RAIZ_ADMIN = Join-Path $LAB 'raiz admin'
    $env:TF2VR_TESTE_RAIZ = $RAIZ_ADMIN
    $DADOS_ADMIN = Join-Path $RAIZ_ADMIN 'ScarletModder\Titanfall2VR-PTBR'
    function RodarSim([string[]]$extra) {
        $a = @('-SemCor', '-PastaJogo', $JOGO, '-PastaDados', $DADOS, '-ProcessosJogo', 'processo-que-nao-existe') + $extra
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $saida = '' | & $Exe @a 6>&1 2>&1 | Out-String; $codigo = $LASTEXITCODE } finally { $ErrorActionPreference = $eap }
        $script:ultima = $saida
        return @{ Codigo = $codigo; Saida = $saida }
    }
    function SoAdmin([string]$pasta) { return @(Get-ChildItem -LiteralPath (Join-Path $RAIZ_ADMIN 'ScarletModder') -Directory -Filter $pasta) }
    function Travar { foreach ($rel in $TODOS) { (Get-Item -LiteralPath (Join-Path $JOGO $rel)).IsReadOnly = $true } }
    Remove-Item -LiteralPath (Join-Path $DADOS 'estado.json'), (Join-Path $DADOS 'backup') -Recurse -Force -ErrorAction SilentlyContinue
    Travar

    $env:TF2VR_TESTE_RECUSAR = '1'
    $r = RodarSim @('-Acao', 'Traduzir')
    $env:TF2VR_TESTE_RECUSAR = ''
    Conferir ($r.Codigo -eq 3 -and $r.Saida -match 'recusada') 'permissão recusada: código 3'
    Conferir (Originais) 'nada foi gravado'

    $env:TF2VR_TESTE_ADULTERAR = '1'
    $r = RodarSim @('-Acao', 'Traduzir')
    $env:TF2VR_TESTE_ADULTERAR = ''
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'nao confere') 'arquivo extraído adulterado: não roda'
    Conferir (Originais) 'nada foi gravado'
    Conferir (@(SoAdmin 'run-*').Count -eq 0) 'pasta de execução apagada'

    Travar
    $r = RodarSim @('-Acao', 'Traduzir')
    Conferir ($r.Codigo -eq 10) "traduz pela etapa elevada, com o dicionário embutido (saiu $($r.Codigo))"
    Conferir (@(SoAdmin 'run-*').Count -eq 0) 'pasta de execução apagada ao final'
    $acl = @($r.Saida -split "`n" | Where-Object { $_ -match '^acl run-' })
    Conferir ($acl.Count -eq 1 -and $acl[0] -match 'D:P' -and $acl[0] -match ';BA\)' -and $acl[0] -match ';SY\)' -and $acl[0] -notmatch ';(BU|WD|AU)\)') 'pasta de execução sem herança, sem Usuários nem Todos'
    $acl = @($r.Saida -split "`n" | Where-Object { $_ -match '^acl Titanfall2VR-PTBR' })
    Conferir ($acl.Count -eq 1 -and $acl[0] -match 'D:P' -and $acl[0] -match 'FA;;;BA\)' -and $acl[0] -match '\(A;OICI;0x1200a9;;;BU\)') 'pasta de dados: Usuários só leem'
    Conferir (Test-Path -LiteralPath (Join-Path $DADOS_ADMIN 'backup\backup.json')) 'backup na pasta dos administradores'
    Conferir (-not (Test-Path -LiteralPath (Join-Path $DADOS 'backup'))) 'nada de backup na pasta do usuário'
    Conferir (-not (Test-Path -LiteralPath (Join-Path $DADOS 'pedido-elevacao.txt'))) 'pedido consumido'

    $r = RodarSim @('-Acao', 'Status')
    Conferir ($r.Saida -match 'em português' -and $r.Saida.Contains($DADOS_ADMIN)) 'etapa comum enxerga o estado elevado'
    $r = RodarSim @('-Acao', 'Restaurar')
    Conferir ($r.Codigo -eq 0 -and (Originais)) 'restaurar pela etapa elevada devolve o original byte a byte'

    $r = RodarSim @('-Acao', 'Traduzir')
    $bk = @(Get-ChildItem -LiteralPath (Join-Path $DADOS_ADMIN 'backup') -Recurse -File | Where-Object { $_.Name -ne 'backup.json' })[0].FullName
    $b = [IO.File]::ReadAllBytes($bk); $b[3] = $b[3] -bxor 1; [IO.File]::WriteAllBytes($bk, $b)
    $r = RodarSim @('-Acao', 'Restaurar')
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'não confere') 'etapa elevada recusa backup adulterado'
    $b[3] = $b[3] -bxor 1; [IO.File]::WriteAllBytes($bk, $b)
    $r = RodarSim @('-Acao', 'Restaurar')
    Conferir ($r.Codigo -eq 0 -and (Originais)) 'com o backup certo, restaura'

    $RAIZ_SM = Join-Path $RAIZ_ADMIN 'ScarletModder'
    $velhaRun = Join-Path $RAIZ_SM 'run-velha'
    New-Item -ItemType Directory -Force -Path $velhaRun | Out-Null
    [IO.File]::WriteAllText((Join-Path $velhaRun 'titanfall-ptbr.ps1'), 'x')
    (Get-Item -LiteralPath (Join-Path $velhaRun 'titanfall-ptbr.ps1')).IsReadOnly = $true
    New-Item -ItemType Junction -Path (Join-Path $velhaRun 'link') -Target $canario | Out-Null
    Travar
    $r = RodarSim @('-Acao', 'Traduzir')
    Conferir ($r.Codigo -eq 10 -and -not (Test-Path -LiteralPath $velhaRun)) 'pasta de execução antiga é varrida no início'
    Conferir (Test-Path -LiteralPath (Join-Path $canario 'x.txt')) 'a varredura não entra em junction'
    $r = RodarSim @('-Acao', 'Restaurar')
    Conferir ($r.Codigo -eq 0 -and (Originais)) 'restaura depois da varredura'

    $link = Join-Path $RAIZ_SM 'plantado'
    New-Item -ItemType Junction -Path $link -Target $canario | Out-Null
    Travar
    $r = RodarSim @('-Acao', 'Traduzir')
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'nao e confiavel') 'junction na pasta dos administradores: recusa sem rodar'
    Conferir (Originais) 'nada foi gravado'
    [IO.Directory]::Delete($link, $false)

    $marca = Join-Path $DADOS_ADMIN 'jogo.txt'
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & icacls $marca /grant '*S-1-1-0:M' 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    Travar
    $r = RodarSim @('-Acao', 'Traduzir')
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'nao e confiavel') 'filho com escrita para Todos: recusa sem rodar'
    Conferir (Originais) 'nada foi gravado'
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & icacls $marca /remove '*S-1-1-0' 2>&1 | Out-Null
    $ErrorActionPreference = $eap
    Travar
    $r = RodarSim @('-Acao', 'Traduzir')
    Conferir ($r.Codigo -eq 10) 'sem o problema, volta a traduzir'
    $r = RodarSim @('-Acao', 'Restaurar')
    Conferir ($r.Codigo -eq 0 -and (Originais)) 'e restaura'
    $Exe = $ExeReal
} finally {
    $env:TF2VR_TESTE_RAIZ = ''
    $pastaSim = Join-Path $RAIZ 'dist\teste'
    if (Test-Path -LiteralPath $pastaSim) { Remove-Item -LiteralPath $pastaSim -Recurse -Force }
    Remove-Item -LiteralPath $LAB -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if ($script:falhas -eq 0) { Write-Host "TODOS OS $($script:total) TESTES DO EXE PASSARAM" -ForegroundColor Green }
else { Write-Host "$($script:falhas) FALHA(S) de $($script:total) no exe" -ForegroundColor Red }
exit $script:falhas
