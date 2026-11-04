# titanfall-ptbr.ps1
# Tradução PT-BR dos textos do mod Titanfall 2 VR (CircuitLord). Projeto de fã, sem vínculo com o mod.
#
#   Traduzir  : se o mod mudou (ou o dicionário), guarda o original do mod como backup e aplica a
#               tradução. Se nada mudou, só avisa que está tudo atualizado.
#   Restaurar : devolve os textos originais (inglês) da versão instalada do mod.
#   Status    : mostra o estado, sem alterar nada.
#
# Um backup só: sempre o original da última versão do mod vista por esta ferramenta.
# Arquivo traduzido leva uma linha com o identificador $ID_MARCADOR. NUNCA mude esse identificador:
# é ele que impede um arquivo traduzido de ser confundido com o original e virar backup.
#
# O dicionário (.\traducao) não contém nenhum texto do mod: cada entrada guarda o SHA-256 do texto
# em inglês e a tradução. A linha real vem sempre do mod instalado na máquina de quem usa.
# Dados (pasta do jogo escolhida, backup, estado) ficam em -PastaDados.
# Quando o jogo exige administrador, quem eleva é o executável: ele se reabre elevado e roda uma cópia
# conferida deste script, com dados numa pasta em que só administradores gravam (-PastaDadosAdmin).
# Funciona no PowerShell 7 e no Windows PowerShell 5.1. Este arquivo precisa ser UTF-8 com BOM.

[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Traduzir', 'Restaurar', 'Status')]
    [string]$Acao = 'Menu',
    [string]$PastaJogo,
    [string]$PastaDados = (Join-Path $env:LOCALAPPDATA 'ScarletModder\Titanfall2VR-PTBR'),
    [string]$PastaDicionario,
    [string]$PastaDadosAdmin,
    [switch]$NaoInterativo,
    [switch]$SemCor,
    [string[]]$ProcessosJogo = @('Titanfall2', 'Titanfall2VRLauncher'),
    [string[]]$ProcessosInstalador = @('CircuitLordVRModInstaller'),
    [switch]$Pausar,
    [switch]$Elevado,
    [switch]$ViaExe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
# No Windows PowerShell 5.1 o $PSScriptRoot ainda está vazio nos valores padrão do param().
if (-not $PastaDicionario) { $PastaDicionario = Join-Path $PSScriptRoot 'traducao' }

# ============================================================
#  Constantes
# ============================================================
$VERSAO = '1.0.0'
$COD_PEDE_ELEVACAO = 20
$ID_MARCADOR = 'titanfall2-vr-ptbr'
$MARCADOR = "// $ID_MARCADOR traduzido para PT-BR. O original esta no backup da ferramenta."
$RE_TOKEN = '^(\s*)"([A-Za-z0-9_]+)"(\s+)"((?:[^"\\]|\\.)*)"(\s*)$'
$RE_LITERAL = '"((?:[^"\\]|\\.)*)"'
$RE_CONTEUDO_LITERAL = '^(?:[^"\\]|\\.)*\z'
$RE_MARCAS = '%[^%\s]*%|%s\d|\|\||\\n'
$REL_MOD = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\'
$REL_TOKENS = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\resource\tf2vr_english.txt'
$REL_REGISTRO_MOD = '.circuitlord-vr-mods\Titanfall2VR.json'
$REL_PACOTE_ANTIGO = 'TF2VR\mods\TF2VR.PTBR'
$URL_INSTALADOR = 'https://github.com/CircuitLord/CircuitLordVRModInstaller'
$URL_ISSUES = 'https://github.com/scarletmodder/titanfall2-vr-ptbr/issues'
$UTF8_SEM_BOM = New-Object System.Text.UTF8Encoding($false)
$UTF16_COM_BOM = New-Object System.Text.UnicodeEncoding($false, $true)

# ============================================================
#  Interface de terminal
# ============================================================
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Saida = -not [Console]::IsOutputRedirected
$script:Cor = -not ($SemCor -or $env:NO_COLOR -or $env:TERM -eq 'dumb')
$script:Animar = $script:Saida -and -not $NaoInterativo
$script:Unicode = [bool]($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode')

if ($script:Unicode) {
    $S = @{ ok = [string][char]0x2714; erro = [string][char]0x2716; aviso = [string][char]0x25B2; info = [string][char]0x25CF
            seta = [string][char]0x203A; bullet = [string][char]0x2022
            h = [string][char]0x2500; v = [string][char]0x2502; tl = [string][char]0x256D; tr = [string][char]0x256E; bl = [string][char]0x2570; br = [string][char]0x256F
            spin = @(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F | ForEach-Object { [string][char]$_ }) }
} else {
    $S = @{ ok = '+'; erro = 'x'; aviso = '!'; info = '*'; seta = '>'; bullet = '-'
            h = '-'; v = '|'; tl = '+'; tr = '+'; bl = '+'; br = '+'; spin = @('|', '/', '-', '\') }
}

function W([string]$texto, [string]$cor = 'Gray', [switch]$n) {
    if ($script:Cor) { Write-Host $texto -ForegroundColor $cor -NoNewline:$n }
    else { Write-Host $texto -NoNewline:$n }
}

function Linha([string]$simbolo, [string]$corSimbolo, [string]$texto, [string]$cor = 'Gray') {
    W "  $simbolo " $corSimbolo -n; W $texto $cor
}

function Ok($t) { Linha $S.ok 'Green' $t }
function Aviso($t) { Linha $S.aviso 'Yellow' $t 'Yellow' }
function Falha($t) { Linha $S.erro 'Red' $t 'Red' }
function Info($t) { Linha $S.info 'DarkCyan' $t }
function Dica($t) { W "    $t" 'DarkGray' }

function Cabecalho {
    if ($script:Saida -and -not $NaoInterativo) { try { Clear-Host } catch { } }
    $titulo = 'TITANFALL 2 VR  ' + $S.bullet + '  TRADUÇÃO PT-BR'
    $sub = 'textos do mod VR do CircuitLord em português do Brasil'
    $larg = [Math]::Max($titulo.Length, $sub.Length) + 6
    W ''
    W ('  ' + $S.tl + ($S.h * $larg) + $S.tr) 'DarkCyan'
    W ('  ' + $S.v) 'DarkCyan' -n; W ('   ' + $titulo.PadRight($larg - 3)) 'Cyan' -n; W $S.v 'DarkCyan'
    W ('  ' + $S.v) 'DarkCyan' -n; W ('   ' + $sub.PadRight($larg - 3)) 'DarkGray' -n; W $S.v 'DarkCyan'
    W ('  ' + $S.bl + ($S.h * $larg) + $S.br) 'DarkCyan'
    W ''
}

function Titulo-Secao([string]$t) {
    W ''
    W ('  ' + $t.ToUpper()) 'White'
    W ('  ' + ($S.h * $t.Length)) 'DarkGray'
}

function Campo([string]$rotulo, [string]$valor, [string]$cor = 'White') {
    W ('  ' + $rotulo.PadRight(21)) 'DarkGray' -n; W $valor $cor
}

function Caixa([string]$titulo, [string[]]$linhas, [string]$cor = 'Green') {
    $larg = ($linhas + @($titulo) | Measure-Object -Property Length -Maximum).Maximum + 4
    W ''
    W ('  ' + $S.tl + $S.h + ' ') $cor -n; W $titulo $cor -n; W (' ' + ($S.h * [Math]::Max(1, $larg - $titulo.Length - 3)) + $S.tr) $cor
    foreach ($l in $linhas) { W ('  ' + $S.v + '  ') $cor -n; W $l.PadRight($larg - 2) 'White' -n; W $S.v $cor }
    W ('  ' + $S.bl + ($S.h * $larg) + $S.br) $cor
}

# Etapa numerada: spinner enquanto prepara, troca pelo resultado (e o tempo) quando termina.
$script:EtapaTotal = 0
$script:EtapaAtual = 0
function Etapas([int]$total) { $script:EtapaTotal = $total; $script:EtapaAtual = 0 }
function Etapa([string]$texto, [scriptblock]$bloco) {
    $script:EtapaAtual++
    $pre = "  [$($script:EtapaAtual)/$($script:EtapaTotal)] "
    $limpar = "`r" + (' ' * ($pre.Length + $texto.Length + 8)) + "`r"
    if ($script:Animar) {
        foreach ($f in ($S.spin | Select-Object -First 6)) {
            W ("`r" + $pre) 'DarkGray' -n; W "$f " 'Cyan' -n; W "$texto..." 'Gray' -n
            Start-Sleep -Milliseconds 35
        }
    }
    $relogio = [Diagnostics.Stopwatch]::StartNew()
    try {
        $resultado = & $bloco
    } catch {
        if ($script:Animar) { W $limpar -n }
        W $pre 'DarkGray' -n; W "$($S.erro) " 'Red' -n; W $texto 'Red'
        throw
    }
    $detalhe = if ($resultado -is [string] -and $resultado) { $resultado } else { '' }
    if ($script:Animar) { W $limpar -n }
    W $pre 'DarkGray' -n; W "$($S.ok) " 'Green' -n; W $texto 'Gray' -n
    if ($detalhe) { W "  $detalhe" 'DarkGray' -n }
    W ("  $($relogio.ElapsedMilliseconds) ms") 'DarkGray'
}

# Devolve $null quando não há mais entrada (janela fechada, entrada redirecionada já no fim).
function Perguntar([string]$texto) {
    W ''
    W "  $($S.seta) " 'Cyan' -n; W $texto 'White' -n; W ' ' -n
    $r = Read-Host
    if ($null -eq $r) { W ''; return $null }
    return $r.Trim()
}

function Esperar-Enter {
    if ($NaoInterativo -or -not $script:Saida) { return }
    W ''
    W '  Aperte Enter para continuar' 'DarkGray' -n
    Read-Host | Out-Null
}

# Erro esperado: mensagem para humanos, com o que fazer em seguida.
function Erro-Amigavel([string]$mensagem, [string]$sugestao) {
    $e = New-Object System.Exception($mensagem)
    $e.Data['sugestao'] = $sugestao
    throw $e
}

function Rotulo-Versao($v) { if ($v) { return "v$v" } else { return 'versão desconhecida' } }

# ============================================================
#  Arquivos
# ============================================================
function Ler-Json($caminho, [string]$sugestao = 'Apague esse arquivo e rode a ferramenta de novo.') {
    if (-not (Test-Path -LiteralPath $caminho)) { return $null }
    try { return ([IO.File]::ReadAllText($caminho, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
    catch { Erro-Amigavel "O arquivo $caminho está corrompido." $sugestao }
}

function Gravar-Json($caminho, $objeto) {
    Substituir-Arquivo $caminho ($UTF8_SEM_BOM.GetBytes(($objeto | ConvertTo-Json -Depth 8)))
}

# Grava num temporário na mesma pasta e troca de uma vez (ReplaceFile do Windows): o destino
# nunca fica pela metade nem some, mesmo se a troca falhar.
function Substituir-Arquivo($caminho, [byte[]]$bytes) {
    $tmp = "$caminho.tmp-ptbr"
    try {
        [IO.File]::WriteAllBytes($tmp, $bytes)
        if (Test-Path -LiteralPath $caminho) { [IO.File]::Replace($tmp, $caminho, [NullString]::Value, $true) }
        else { [IO.File]::Move($tmp, $caminho) }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Bytes-Texto($texto, $codificacao) {
    $pre = $codificacao.GetPreamble()
    $corpo = $codificacao.GetBytes($texto)
    if ($pre.Length -eq 0) { return $corpo }
    $saida = New-Object byte[] ($pre.Length + $corpo.Length)
    [Array]::Copy($pre, $saida, $pre.Length)
    [Array]::Copy($corpo, 0, $saida, $pre.Length, $corpo.Length)
    return $saida
}

# Decodifica respeitando o BOM (UTF-16 no arquivo de textos, UTF-8 nos scripts).
function Texto-De([byte[]]$bytes) {
    $leitor = New-Object IO.StreamReader((New-Object IO.MemoryStream(, $bytes)), $UTF8_SEM_BOM, $true)
    try { return $leitor.ReadToEnd() } finally { $leitor.Dispose() }
}

function Hash-Bytes([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

# SHA-256 em hexadecimal minúsculo do texto em UTF-8: é o enHash do dicionário.
function Hash-Texto([string]$texto) { return (Hash-Bytes ($UTF8_SEM_BOM.GetBytes($texto))).ToLowerInvariant() }

function Hash-Arquivo($caminho) {
    if (-not (Test-Path -LiteralPath $caminho)) { return $null }
    return (Get-FileHash -LiteralPath $caminho -Algorithm SHA256).Hash
}

function Separar-Linhas($texto) {
    $nl = if ($texto.Contains("`r`n")) { "`r`n" } else { "`n" }
    return @{ Linhas = $texto -split [regex]::Escape($nl); NL = $nl }
}

function Tem-Marcador($caminho) {
    if (-not (Test-Path -LiteralPath $caminho)) { return $false }
    return ([IO.File]::ReadAllText($caminho)).Contains($ID_MARCADOR)
}

function Propriedade($objeto, [string]$nome) {
    if ($null -eq $objeto) { return $null }
    $p = $objeto.PSObject.Properties[$nome]
    if ($p) { return $p.Value } else { return $null }
}

function Contar([string]$texto, [char]$c) { return @($texto.ToCharArray() | Where-Object { $_ -eq $c }).Count }

# Testa o que a gravação realmente faz: criar um arquivo na pasta e trocar o arquivo-alvo.
# Devolve 'ok', 'permissao' (precisa de administrador ou é Somente leitura) ou 'em-uso' (outro
# programa está com o arquivo aberto: administrador não resolve).
function Pode-Gravar($caminho) {
    $teste = Join-Path (Split-Path $caminho) ('.ptbr-teste-' + [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText($teste, 'x')
        Remove-Item -LiteralPath $teste -Force
    } catch {
        if (Test-Path -LiteralPath $teste) { Remove-Item -LiteralPath $teste -Force -ErrorAction SilentlyContinue }
        return 'permissao'
    }
    try { $fs = [IO.File]::Open($caminho, 'Open', 'ReadWrite', 'Read'); $fs.Close(); return 'ok' }
    catch [System.UnauthorizedAccessException] { return 'permissao' }
    catch { return 'em-uso' }
}

# Grava um lote de arquivos. Se qualquer um falhar, devolve TODOS ao conteúdo de antes do lote.
# Cada item: @{ Caminho; Bytes; Antes (bytes de antes do lote) }.
function Gravar-Lote($itens) {
    $feitos = @(); $atual = $null
    try {
        foreach ($i in $itens) {
            $atual = $i.Caminho
            if ((Hash-Arquivo $i.Caminho) -ne (Hash-Bytes $i.Antes)) {
                Erro-Amigavel "O arquivo $(Split-Path $i.Caminho -Leaf) mudou enquanto a ferramenta trabalhava." 'O instalador do mod pode estar atualizando. Espere ele terminar e rode de novo. Nada foi alterado.'
            }
            $feitos += $i
            Substituir-Arquivo $i.Caminho $i.Bytes
        }
    } catch {
        $erroOriginal = $_
        $naoDesfeitos = @()
        foreach ($i in $feitos) {
            try {
                if ((Hash-Arquivo $i.Caminho) -ne (Hash-Bytes $i.Antes)) { Substituir-Arquivo $i.Caminho $i.Antes }
            } catch { $naoDesfeitos += $i.Caminho }
        }
        if ($naoDesfeitos.Count -gt 0) {
            Erro-Amigavel "ATENÇÃO: a gravação falhou e não consegui desfazer em: $($naoDesfeitos -join ', ')" 'Use a opção de voltar aos originais ou reinstale o mod pelo instalador antes de jogar.'
        }
        if ($erroOriginal.Exception.Data.Contains('sugestao')) { throw $erroOriginal }
        $detalhe = $erroOriginal.Exception.Message
        if ($erroOriginal.Exception.InnerException) { $detalhe = $erroOriginal.Exception.InnerException.Message }
        Erro-Amigavel "Não consegui gravar $(Split-Path $atual -Leaf): o arquivo está em uso ou bloqueado. ($detalhe)" 'Feche o EA app, o instalador do mod ou o que estiver usando o arquivo (às vezes o antivírus) e tente de novo. Nada foi alterado no jogo.'
    }
}

function Jogo-Aberto { return [bool](Get-Process -Name $ProcessosJogo -ErrorAction SilentlyContinue) }

# ============================================================
#  Localizar o jogo (mesmas fontes do instalador do mod, e mais algumas)
# ============================================================
function Ler-Registro($chave, $valor) {
    try { return [string](Propriedade (Get-ItemProperty -LiteralPath $chave -ErrorAction Stop) $valor) }
    catch { return $null }
}

function Jogo-Valido($pasta) { return ($pasta -and (Test-Path -LiteralPath (Join-Path $pasta 'Titanfall2.exe'))) }
function Mod-Instalado($pasta) { return (Test-Path -LiteralPath (Join-Path $pasta $REL_TOKENS)) }

function Bibliotecas-Steam {
    $raiz = Ler-Registro 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if (-not $raiz) { $raiz = Ler-Registro 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath' }
    if (-not $raiz -and ${env:ProgramFiles(x86)}) {
        $padrao = Join-Path ${env:ProgramFiles(x86)} 'Steam'
        if (Test-Path -LiteralPath $padrao) { $raiz = $padrao }
    }
    if (-not $raiz -or -not (Test-Path -LiteralPath $raiz)) { return @() }
    $libs = @($raiz)
    $vdf = Join-Path $raiz 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"(.+?)"')) {
            $p = $m.Groups[1].Value.Replace('\\', '\')
            if (Test-Path -LiteralPath $p) { $libs += $p }
        }
    }
    return $libs
}

function Procurar-Jogo {
    $achados = New-Object System.Collections.Generic.List[object]
    $vistos = @{}
    $add = {
        param($pasta, $origem)
        if (-not (Jogo-Valido $pasta)) { return }
        $cheia = (Resolve-Path -LiteralPath $pasta).Path.TrimEnd('\')
        if ($vistos.ContainsKey($cheia.ToLowerInvariant())) { return }
        $vistos[$cheia.ToLowerInvariant()] = $true
        $achados.Add([pscustomobject]@{ Pasta = $cheia; Origem = $origem; ComMod = (Mod-Instalado $cheia) })
    }
    foreach ($ch in 'HKLM:\SOFTWARE\Respawn\Titanfall2', 'HKLM:\SOFTWARE\WOW6432Node\Respawn\Titanfall2') {
        & $add (Ler-Registro $ch 'Install Dir') 'EA app / Origin (registro)'
    }
    foreach ($lib in Bibliotecas-Steam) { & $add (Join-Path $lib 'steamapps\common\Titanfall2') 'Steam' }
    $discos = [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName }
    foreach ($d in $discos) {
        & $add (Join-Path $d 'Program Files\EA Games\Titanfall2') 'EA app'
        & $add (Join-Path $d 'EA Games\Titanfall2') 'EA app'
        & $add (Join-Path $d 'Program Files (x86)\Origin Games\Titanfall2') 'Origin'
        foreach ($nome in 'Titanfall 2', 'Titanfall2') {
            & $add (Join-Path $d "XboxGames\$nome\Content") 'Xbox / Microsoft Store'
            & $add (Join-Path $d "XboxGames\$nome") 'Xbox / Microsoft Store'
        }
    }
    return $achados.ToArray()
}

function Normalizar-Caminho([string]$texto) {
    $p = $texto.Trim().Trim('"').Trim("'").Trim()
    if ($p -match '(?i)titanfall2\.exe$') { $p = Split-Path $p }
    return $p
}

function Pedir-Pasta {
    Titulo-Secao 'Onde está o Titanfall 2?'
    Dica 'Cole o caminho da pasta que tem o Titanfall2.exe.'
    Dica 'Dica: no EA app ou na Steam, use "Procurar arquivos locais" e copie o endereço da janela.'
    Dica 'Deixe em branco e aperte Enter para cancelar.'
    while ($true) {
        $txt = Perguntar 'Pasta do jogo:'
        if (-not $txt) { return $null }
        $p = Normalizar-Caminho $txt
        if (Jogo-Valido $p) { return (Resolve-Path -LiteralPath $p).Path.TrimEnd('\') }
        Falha "Não achei o Titanfall2.exe em: $p"
    }
}

function Salvar-Pasta($pasta, $origem) {
    Gravar-Json $ARQ_CONFIG ([pscustomobject]@{ pastaJogo = $pasta; origem = $origem; salvoEm = (Get-Date -Format 'yyyy-MM-dd') })
}

function Escolher-Pasta([switch]$Forcar) {
    $cfg = Ler-Json $ARQ_CONFIG
    $salva = Propriedade $cfg 'pastaJogo'
    if (-not $Forcar -and (Jogo-Valido $salva)) { return @{ Pasta = $salva; Origem = (Propriedade $cfg 'origem') } }

    $achados = @(Procurar-Jogo)
    $escolha = $null
    if ($achados.Count -eq 1 -and -not $Forcar) {
        $escolha = $achados[0]
    } elseif ($achados.Count -ge 1) {
        if ($NaoInterativo) {
            $comMod = @($achados | Where-Object ComMod)
            $escolha = if ($comMod.Count -gt 0) { $comMod[0] } else { $achados[0] }
        } else {
            Titulo-Secao 'Instalações encontradas'
            for ($i = 0; $i -lt $achados.Count; $i++) {
                $a = $achados[$i]
                W "  [$($i + 1)] " 'Cyan' -n; W $a.Pasta 'White'
                $mod = if ($a.ComMod) { 'mod VR instalado' } else { 'sem o mod VR' }
                Dica "      $($a.Origem), $mod"
            }
            W '  [M] ' 'Cyan' -n; W 'Digitar outra pasta' 'White'
            while (-not $escolha) {
                $r = Perguntar 'Qual delas?'
                if ($null -eq $r -or $r -match '^[mM]$') { break }
                $n = 0
                if ([int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $achados.Count) { $escolha = $achados[$n - 1] }
                else { Falha "Digite um número de 1 a $($achados.Count), ou M." }
            }
        }
    }
    if (-not $escolha) {
        if ($NaoInterativo) { Erro-Amigavel 'Não encontrei o Titanfall 2 neste computador.' 'Rode de novo com -PastaJogo "<pasta do jogo>".' }
        $p = Pedir-Pasta
        if (-not $p) { Erro-Amigavel 'Nenhuma pasta escolhida.' 'Rode a ferramenta de novo quando souber onde o jogo está.' }
        $escolha = [pscustomobject]@{ Pasta = $p; Origem = 'informada por você' }
    }
    Salvar-Pasta $escolha.Pasta $escolha.Origem
    return @{ Pasta = $escolha.Pasta; Origem = $escolha.Origem }
}

# ============================================================
#  Dicionário
# ============================================================
function Rel-Normal([string]$rel) { return $rel.Replace('/', '\').Trim() }

# Só os arquivos de texto do mod podem ser alvo: o arquivo de textos e scripts .nut do próprio mod.
function Rel-Permitido([string]$rel, [string]$tipo) {
    if (-not $rel -or $rel -match '(^|\\)\.\.(\\|$)' -or [IO.Path]::IsPathRooted($rel)) { return $false }
    if ($tipo -eq 'tokens') { return ($rel -ieq $REL_TOKENS) }
    return ($rel.StartsWith($REL_MOD, [StringComparison]::OrdinalIgnoreCase) -and $rel -match '(?i)\.nut$')
}

# Devolve o que há de errado numa entrada do dicionário, ou $null. O campo 'en' é recusado de propósito:
# texto do mod não pode entrar no dicionário público.
function Erro-Entrada($e, [string]$tipo) {
    if ($null -eq $e) { return 'está vazia' }
    if ($e.PSObject.Properties['en']) { return "tem o campo 'en', que não existe no formato público" }
    $hash = Propriedade $e 'enHash'
    if (-not ($hash -is [string]) -or $hash -cnotmatch '^[0-9a-f]{64}$') { return "está sem o campo 'enHash' válido" }
    if ($tipo -eq 'tokens') {
        foreach ($c in 'chave', 'pt') {
            if (-not ((Propriedade $e $c) -is [string])) { return "está sem o campo '$c'" }
        }
        return $null
    }
    $pTextos = $e.PSObject.Properties['textos']
    $pMolde = $e.PSObject.Properties['molde']
    if ([bool]$pTextos -eq [bool]$pMolde) { return "precisa de 'textos' ou de 'molde', e só de um deles" }
    if ($pMolde) {
        if (-not ($pMolde.Value -is [string])) { return "tem 'molde' que não é texto" }
        return $null
    }
    foreach ($t in @($pTextos.Value)) {
        if ($null -ne $t -and -not ($t -is [string])) { return "tem item de 'textos' que não é texto nem null" }
    }
    return $null
}

function Carregar-Dicionario([string]$pasta = $PastaDicionario) {
    if (-not (Test-Path -LiteralPath (Join-Path $pasta 'tokens.json'))) {
        Erro-Amigavel "Dicionário não encontrado em $pasta" 'A pasta "traducao" precisa ficar ao lado deste script.'
    }
    $dica = 'O dicionário da ferramenta está danificado. Baixe a ferramenta de novo.'
    $arquivos = @(Get-ChildItem -LiteralPath $pasta -Filter '*.json' | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)
    $alvos = @(); $temTokens = $false
    $textoTudo = ''
    foreach ($f in $arquivos) {
        $textoTudo += [IO.File]::ReadAllText($f.FullName)
        $d = Ler-Json $f.FullName $dica
        $rel = Rel-Normal ([string](Propriedade $d 'arquivo'))
        $tipo = if ($f.Name -eq 'tokens.json') { 'tokens' } else { 'linhas' }
        if (-not (Rel-Permitido $rel $tipo)) { Erro-Amigavel "Caminho não permitido no dicionário ($($f.Name)): '$rel'" $dica }
        $repetido = @($alvos | Where-Object { $_.Rel -ieq $rel })
        if ($repetido.Count -gt 0) {
            Erro-Amigavel "Dois arquivos do dicionário apontam para o mesmo script: $($repetido[0].Arquivo) e $($f.Name)." "Apague a cópia que sobrou em $pasta (por exemplo, um '... - Copia.json')."
        }
        $mapa = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        $n = 0
        foreach ($e in @(Propriedade $d $tipo)) {
            $n++
            $erro = Erro-Entrada $e $tipo
            if ($erro) { Erro-Amigavel "Entrada $n de $($f.Name) $erro." $dica }
            $k = if ($tipo -eq 'tokens') { [string]$e.chave } else { [string]$e.enHash }
            $mapa[$k] = $e
        }
        $nome = [string](Propriedade $d 'nome'); if (-not $nome) { $nome = Split-Path $rel -Leaf }
        $varrer = Propriedade $d 'varrer'; if ($null -eq $varrer) { $varrer = $true }
        $alvos += @{ Rel = $rel; Tipo = $tipo; Nome = $nome; Dic = $mapa; Varrer = [bool]$varrer; Arquivo = $f.Name }
        if ($tipo -eq 'tokens') { $temTokens = $true }
    }
    if (-not $temTokens) { Erro-Amigavel 'O dicionário não tem o tokens.json.' $dica }
    return @{ Alvos = $alvos; Hash = (Hash-Bytes ($UTF8_SEM_BOM.GetBytes($textoTudo))) }
}

function Esqueleto([string]$linha) { return [regex]::Replace($linha.Trim(), $RE_LITERAL, '""') }

function Codigo-Equilibrado([string]$linha) {
    $sem = [regex]::Replace($linha, $RE_LITERAL, '""')
    if ((Contar $sem '"') % 2 -ne 0) { return $false }
    foreach ($par in @('(', ')'), @('[', ']'), @('{', '}')) {
        if ((Contar $sem $par[0]) -ne (Contar $sem $par[1])) { return $false }
    }
    return $true
}

# Variáveis, ícones e separadores que precisam sobreviver à tradução (%use%, %s1, ||, \n).
function Marcas([string]$t) { return ((@([regex]::Matches($t, $RE_MARCAS) | ForEach-Object { $_.Value }) | Sort-Object) -join ' ') }

# Texto para o jogador: string com letras que não é token (#), ícone (%$), variável (%x%) nem
# identificador de código. Identificador é palavra única minúscula ("norte", "som_foco"), com
# maiúscula no meio ("AoFechar", "MenuPrincipal"), sublinhado ou número ("Escolha1").
# Palavra única capitalizada ("Carregando") ou em maiúsculas ("VIDA") conta como texto.
function E-Identificador([string]$v) {
    if ($v -match '\s') { return $false }
    return ($v -cmatch '^[a-z]' -or $v -cmatch '[a-z][A-Z]' -or $v -match '[_0-9.]' -or $v -cmatch '^#[A-Z][A-Z0-9_]*$')
}

# Nome interno usado como argumento, índice ou comparação (Funcao( "x" ), == "norte") é código,
# mesmo estando entre aspas: a tradução precisa manter idêntico.
function Protegidos-Iguais([string]$en, [string]$pt) {
    $le = @([regex]::Matches($en, $RE_LITERAL) | ForEach-Object { $_.Groups[1].Value })
    $lp = @([regex]::Matches($pt, $RE_LITERAL) | ForEach-Object { $_.Groups[1].Value })
    if ($le.Count -ne $lp.Count) { return $false }
    for ($i = 0; $i -lt $le.Count; $i++) {
        $m = [regex]::Matches($en, $RE_LITERAL)[$i]
        $antes = $en.Substring(0, $m.Index).TrimEnd()
        if ((E-Identificador $le[$i]) -and $antes -match '(\(|,|\[|=)$' -and $lp[$i] -cne $le[$i]) { return $false }
    }
    return $true
}

function Tem-Quebra([string]$t) { return ($t.Contains("`n") -or $t.Contains("`r")) }

function Tem-Texto-Visivel([string]$linha) {
    if ($linha -match '^\s*(printt|print|Assert|CodeWarning|Warning|DevPrint)\s*\(') { return $false }
    foreach ($m in [regex]::Matches($linha, $RE_LITERAL)) {
        $v = $m.Groups[1].Value
        if ($v.StartsWith('%$') -or (E-Identificador $v)) { continue }
        if ($v -match '^#') { $v = $v -replace '^#\S*', '' }
        $v = $v -replace '%[^%\s]*%', ''
        if ($v -match '[A-Za-z]{2,}') { return $true }
    }
    return $false
}

# ============================================================
#  Tradução (pura: texto original entra, texto traduzido + pendências saem)
# ============================================================
# Texto sem letras (vazio, espaço, só ícone ou variável) não tem o que traduzir nem vira pendência.
function Sem-Texto([string]$en) { return (($en -replace '%[^%\s]*%', '') -notmatch '[A-Za-z]{2,}') }

function Traduzir-Tokens($original, $alvo) {
    $s = Separar-Linhas $original
    $saida = New-Object System.Collections.Generic.List[string]
    $pend = New-Object System.Collections.Generic.List[object]
    $marcado = $false; $n = 0
    foreach ($linha in $s.Linhas) {
        $m = [regex]::Match($linha, $RE_TOKEN)
        if (-not $m.Success -or $m.Groups[2].Value -eq 'Language') { $saida.Add($linha); continue }
        if (-not $marcado) { $saida.Add($m.Groups[1].Value + $MARCADOR); $marcado = $true }
        $chave = $m.Groups[2].Value; $en = $m.Groups[4].Value
        if (Sem-Texto $en) { $saida.Add($linha); continue }
        $hash = Hash-Texto $en
        $item = $null; $pt = $null; $motivo = 'texto novo'
        if ($alvo.Dic.TryGetValue($chave, [ref]$item)) {
            $motivo = 'o texto em inglês mudou'
            if ([string]$item.enHash -ceq $hash) {
                $cand = [string]$item.pt
                if ($cand -match '(?<!\\)"' -or $cand.EndsWith('\')) { $motivo = 'tradução com aspas inválidas' }
                elseif (Tem-Quebra $cand) { $motivo = 'tradução com quebra de linha' }
                elseif ((Marcas $cand) -cne (Marcas $en)) { $motivo = 'tradução perdeu variáveis como %use% ou ||' }
                else { $pt = $cand }
            }
        }
        if ($null -ne $pt) {
            $n++
            $saida.Add($m.Groups[1].Value + '"' + $chave + '"' + $m.Groups[3].Value + '"' + $pt + '"' + $m.Groups[5].Value)
        } else {
            $pend.Add([pscustomobject]@{ arquivo = $alvo.Rel; tipo = 'token'; chave = $chave; enHash = $hash; motivo = $motivo })
            $saida.Add($linha)
        }
    }
    return @{ Texto = ($saida -join $s.NL); Pendentes = $pend; Itens = $n }
}

# Troca só os literais da linha REAL do mod pelos textos do dicionário, na ordem. null mantém o literal
# original (nome interno, por exemplo), sem precisar copiá-lo para o dicionário.
function Aplicar-Textos([string]$linha, $textos) {
    $ms = [regex]::Matches($linha, $RE_LITERAL)
    $lista = @($textos)
    if ($ms.Count -ne $lista.Count) { return $null }
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $m = $ms[$i]
        [void]$sb.Append($linha.Substring($pos, $m.Index - $pos))
        if ($null -eq $lista[$i]) { [void]$sb.Append($m.Value) }
        else {
            if ([string]$lista[$i] -cnotmatch $RE_CONTEUDO_LITERAL) { return $null }
            [void]$sb.Append('"').Append([string]$lista[$i]).Append('"')
        }
        $pos = $m.Index + $m.Length
    }
    [void]$sb.Append($linha.Substring($pos))
    return $sb.ToString()
}

# Trechos de código da linha real, entre os literais, sem espaço e sem o + das pontas.
# Nomes internos do arquivo real, por hash. Só monta a tabela se algum molde do arquivo precisar dela.
function Literais-Do-Arquivo([string]$texto, $alvo) {
    $precisa = $false
    foreach ($item in $alvo.Dic.Values) {
        if ($item.PSObject.Properties['molde'] -and ([string]$item.molde).Contains('{=')) { $precisa = $true; break }
    }
    if (-not $precisa) { return $null }
    $tabela = @{}
    foreach ($m in [regex]::Matches($texto, $RE_LITERAL)) {
        $v = $m.Groups[1].Value
        if (E-Identificador $v) { $tabela[(Hash-Texto $v)] = $v }
    }
    return $tabela
}

function Trechos-De-Codigo([string]$linha) {
    $partes = [regex]::Split($linha, '"(?:[^"\\]|\\.)*"')
    return @($partes | ForEach-Object { $_.Trim().Trim('+').Trim() })
}

# Molde: quando a tradução precisa de lógica nova (gesto em português, por exemplo). Guarda só o que foi
# escrito para a tradução; {0}, {1}... são os trechos de código da linha real, lidos do mod instalado.
# {=hash} é um nome interno do mod, entre aspas, achado no próprio arquivo pelo SHA-256: o dicionário não
# guarda o nome em claro. Fora das aspas o molde só aceita operadores, então o dicionário nunca consegue
# chamar código novo, e todo trecho da linha original precisa continuar presente.
function Aplicar-Molde([string]$linha, [string]$molde, $literais) {
    $trechos = Trechos-De-Codigo $linha
    $usados = @{}
    $invalido = $false
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    $partes = @()
    foreach ($m in [regex]::Matches($molde, $RE_LITERAL)) {
        $partes += ,@($molde.Substring($pos, $m.Index - $pos), $m.Value)
        $pos = $m.Index + $m.Length
    }
    $partes += ,@($molde.Substring($pos), '')
    foreach ($p in $partes) {
        $codigo = [string]$p[0]
        if (($codigo -replace '\{\d+\}|\{=[0-9a-f]{64}\}', '') -cnotmatch '^[\s+()?:=]*$') { return $null }
        $ultimo = 0
        foreach ($c in [regex]::Matches($codigo, '\{(\d+)\}|\{=([0-9a-f]{64})\}')) {
            [void]$sb.Append($codigo.Substring($ultimo, $c.Index - $ultimo))
            if ($c.Groups[2].Success) {
                if (-not $literais -or -not $literais.ContainsKey($c.Groups[2].Value)) { $invalido = $true; break }
                [void]$sb.Append('"').Append([string]$literais[$c.Groups[2].Value]).Append('"')
            } else {
                $i = [int]$c.Groups[1].Value
                if ($i -ge $trechos.Count) { $invalido = $true; break }
                $usados[$i] = $true
                [void]$sb.Append([string]$trechos[$i])
            }
            $ultimo = $c.Index + $c.Length
        }
        if ($invalido) { return $null }
        [void]$sb.Append($codigo.Substring($ultimo)).Append([string]$p[1])
    }
    for ($i = 0; $i -lt $trechos.Count; $i++) {
        if ([string]$trechos[$i] -and -not $usados.ContainsKey($i)) { return $null }
    }
    return $sb.ToString()
}

# Linha traduzida a partir da linha real do mod, ou $null se a entrada mexeria no código ou nas variáveis.
function Linha-Traduzida([string]$limpa, $item, $literais) {
    if ($item.PSObject.Properties['molde']) {
        $pt = Aplicar-Molde $limpa ([string]$item.molde) $literais
        if ($null -eq $pt -or -not (Codigo-Equilibrado $pt)) { return $null }
    } else {
        $pt = Aplicar-Textos $limpa $item.PSObject.Properties['textos'].Value
        if ($null -eq $pt -or (Esqueleto $pt) -cne (Esqueleto $limpa) -or -not (Protegidos-Iguais $limpa $pt)) { return $null }
    }
    if ((Tem-Quebra $pt) -or (Marcas $pt) -cne (Marcas $limpa)) { return $null }
    return $pt
}

function Traduzir-Linhas($original, $alvo) {
    $s = Separar-Linhas $original
    $saida = New-Object System.Collections.Generic.List[string]
    $pend = New-Object System.Collections.Generic.List[object]
    $saida.Add($MARCADOR); $n = 0; $nLinha = 0
    $literais = Literais-Do-Arquivo $original $alvo
    foreach ($linha in $s.Linhas) {
        $nLinha++
        $limpa = $linha.Trim()
        $hash = if ($limpa) { Hash-Texto $limpa } else { '' }
        $item = $null
        if ($limpa -and $alvo.Dic.TryGetValue($hash, [ref]$item)) {
            $pt = Linha-Traduzida $limpa $item $literais
            if ($null -ne $pt) {
                $recuo = $linha.Substring(0, $linha.Length - $linha.TrimStart().Length)
                $saida.Add($recuo + $pt); $n++; continue
            }
            $pend.Add([pscustomobject]@{ arquivo = $alvo.Rel; tipo = 'linha'; chave = ''; linha = $nLinha; enHash = $hash; motivo = 'a tradução mexe no código ou nas variáveis, foi ignorada' })
            $saida.Add($linha); continue
        }
        if ($alvo.Varrer -and (Tem-Texto-Visivel $limpa) -and $limpa -notmatch '^(case |//|return \[)') {
            $pend.Add([pscustomobject]@{ arquivo = $alvo.Rel; tipo = 'linha'; chave = ''; linha = $nLinha; enHash = $hash; motivo = 'linha nova ou alterada' })
        }
        $saida.Add($linha)
    }
    return @{ Texto = ($saida -join $s.NL); Pendentes = $pend; Itens = $n }
}

function Validar($alvo, $original, $traduzido) {
    if ($alvo.Tipo -eq 'tokens') {
        $a = [regex]::Matches($original, $RE_TOKEN, 'Multiline').Count
        $b = [regex]::Matches($traduzido, $RE_TOKEN, 'Multiline').Count
        if ($a -ne $b) { throw "Validação falhou em $($alvo.Rel): $a textos no original, $b no traduzido." }
        foreach ($c in '{', '}') {
            if ((Contar $original $c) -ne (Contar $traduzido $c)) { throw "Validação falhou em $($alvo.Rel): chaves '$c' desbalanceadas." }
        }
    } else {
        $a = (Separar-Linhas $original).Linhas.Count
        $b = (Separar-Linhas $traduzido).Linhas.Count
        if ($b -ne $a + 1) { throw "Validação falhou em $($alvo.Rel): $a linhas no original, $b no traduzido." }
    }
}

# Segunda trava contra backup errado: um "original" que já contém frases traduzidas não é original.
function Parece-Traduzido($alvo, $texto) {
    foreach ($item in $alvo.Dic.Values) {
        if ($alvo.Tipo -eq 'tokens') {
            $pt = [string]$item.pt
            if ($pt -ceq '' -or (Hash-Texto $pt) -ceq [string]$item.enHash) { continue }
            if ($pt.Length -gt 12 -and $texto.Contains('"' + $pt + '"')) { return $true }
        } elseif ($item.PSObject.Properties['textos']) {
            foreach ($t in @($item.PSObject.Properties['textos'].Value)) {
                if ($null -ne $t -and ([string]$t).Length -gt 12 -and $texto.Contains('"' + [string]$t + '"')) { return $true }
            }
        }
    }
    return $false
}

# ============================================================
#  Estado
# ============================================================
function Ler-Estado {
    $e = Ler-Json $ARQ_ESTADO
    $arquivos = @{}
    $p = Propriedade $e 'arquivos'
    if ($p) { foreach ($x in $p.PSObject.Properties) { $arquivos[$x.Name] = [string]$x.Value } }
    return @{ VersaoMod = (Propriedade $e 'versaoMod'); AplicadoEm = (Propriedade $e 'aplicadoEm')
              HashDic = (Propriedade $e 'hashDicionario'); Arquivos = $arquivos }
}

function Gravar-Estado($estado) {
    Gravar-Json $ARQ_ESTADO ([pscustomobject]@{ versaoMod = $estado.VersaoMod; aplicadoEm = $estado.AplicadoEm
                                                hashDicionario = $estado.HashDic; arquivos = $estado.Arquivos })
}

function Versao-Mod {
    $reg = Ler-Json (Join-Path $script:Jogo $REL_REGISTRO_MOD) 'O registro do instalador do mod está ilegível. Reinstale o mod pelo instalador.'
    $v = Propriedade $reg 'version'
    if ($v) { return [string]$v } else { return $null }
}

function Situacao-Arquivo($alvo, $estado) {
    if (-not (Test-Path -LiteralPath $alvo.Caminho)) { return 'ausente' }
    if (-not (Tem-Marcador $alvo.Caminho)) { return 'original' }
    if ((Hash-Arquivo $alvo.Caminho) -ne $estado.Arquivos[$alvo.Rel]) { return 'alterado-fora' }
    if ($estado.HashDic -ne $script:Dic.Hash) { return 'dicionario-novo' }
    return 'traduzido'
}

function Caminho-Normal([string]$c) { return [IO.Path]::GetFullPath($c).TrimEnd('\', '/') }

# Backup e estado têm um espaço só. Enquanto outra pasta do jogo estiver traduzida, o backup é dela.
function Conferir-Pasta-Do-Backup {
    $info = Ler-Json $ARQ_BACKUP_INFO
    if (-not $info) { return }
    $registrado = [string](Propriedade $info 'jogo')
    if (-not $registrado) { return }
    if ((Caminho-Normal $registrado) -ieq (Caminho-Normal $script:Jogo)) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $registrado 'Titanfall2.exe'))) { return }
    $ativo = $false
    foreach ($a in $script:Alvos) {
        $c = Join-Path $registrado $a.Rel
        if ((Test-Path -LiteralPath $c) -and (Tem-Marcador $c)) { $ativo = $true; break }
    }
    if (-not $ativo) { return }
    Erro-Amigavel 'O backup guardado é de outra pasta do jogo, que continua traduzida. Nada foi alterado.' "Restaure os originais na outra pasta antes: $registrado"
}

# Junction ou link simbólico no caminho levaria a gravação para fora da pasta do jogo.
function Exigir-Sem-Link($caminhos) {
    $base = Caminho-Normal $script:Jogo
    foreach ($c in $caminhos) {
        $atual = Caminho-Normal $c
        while ($atual.Length -gt $base.Length -and $atual.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
            if ((Test-Path -LiteralPath $atual) -and ((Get-Item -LiteralPath $atual -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Erro-Amigavel "O caminho de $(Split-Path $c -Leaf) passa por um link ou junction. Nada foi alterado." "Reinstale o mod numa pasta comum: $atual"
            }
            $atual = Split-Path $atual
        }
    }
}

# O backup só é usado se bater com o hash registrado quando foi criado.
function Conferir-Backup($a) {
    $esperado = Propriedade (Propriedade (Ler-Json $ARQ_BACKUP_INFO) 'arquivos') $a.Rel
    if (-not $esperado -or (Hash-Arquivo $a.Backup) -ne $esperado) {
        Erro-Amigavel "O backup de $($a.Nome) não confere com o que foi guardado. Nada foi alterado." 'Reinstale o mod pelo instalador do CircuitLord: isso devolve os textos originais.'
    }
}

function Ler-Pendentes { return @(Propriedade (Ler-Json $ARQ_PENDENTES) 'itens' | Where-Object { $_ }) }

function Linha-Da-Issue($p) {
    $rotulo = if ($p.chave) { "token $($p.chave)" } else { "linha $($p.linha) de $(Split-Path $p.arquivo -Leaf)" }
    return "- $rotulo sha256:$($p.enHash)"
}

function Listar-Pendentes($pend) {
    W ''
    Aviso "$($pend.Count) texto(s) do mod ainda não têm tradução e aparecem em inglês no jogo."
    Dica 'O jogo já pode ser aberto. Esses textos ficam em inglês até o dicionário ganhar a tradução.'
    Dica "Para ajudar, abra uma issue em $URL_ISSUES e cole o texto abaixo. Ele só tem chave e hash, sem texto do mod:"
    W ''
    W "Pendências do mod $(Rotulo-Versao (Versao-Mod)), ferramenta ${script:VERSAO}:"
    foreach ($p in ($pend | Select-Object -First 10)) { W (Linha-Da-Issue $p) }
    if ($pend.Count -gt 10) {
        W "... e mais $($pend.Count - 10)"
        W ''
        Dica "A lista inteira, para colar, está em $(Join-Path $script:DIR_DADOS 'pendentes-para-issue.txt')"
    }
}

# ============================================================
#  Preparação comum
# ============================================================
function Preparar([switch]$TrocarPasta) {
    if (-not (Test-Path -LiteralPath $PastaDados)) { New-Item -ItemType Directory -Force -Path $PastaDados | Out-Null }
    if ($script:PastaFixa -and -not $TrocarPasta) {
        $p = Normalizar-Caminho $script:PastaFixa
        if (-not (Jogo-Valido $p)) { Erro-Amigavel "Não achei o Titanfall2.exe em: $p" 'Confira o caminho passado em -PastaJogo.' }
        $script:Jogo = (Resolve-Path -LiteralPath $p).Path.TrimEnd('\'); $script:Origem = 'informada no comando'
        $cfg = Ler-Json $ARQ_CONFIG
        if ((Propriedade $cfg 'pastaJogo') -eq $script:Jogo) { $script:Origem = [string](Propriedade $cfg 'origem') }
        else { Salvar-Pasta $script:Jogo $script:Origem }
    } else {
        $r = Escolher-Pasta -Forcar:$TrocarPasta
        $script:Jogo = $r.Pasta; $script:Origem = $r.Origem
        $script:PastaFixa = $null
    }
    Carregar-Alvos
}

function Definir-Dados([string]$pasta) {
    $script:DIR_DADOS = $pasta
    $script:ARQ_ESTADO = Join-Path $pasta 'estado.json'
    $script:ARQ_PENDENTES = Join-Path $pasta 'pendentes.json'
    $script:DIR_BACKUP = Join-Path $pasta 'backup'
    $script:ARQ_BACKUP_INFO = Join-Path $script:DIR_BACKUP 'backup.json'
}

# Se este jogo já foi traduzido como administrador, backup e estado estão na pasta dos administradores.
function Escolher-Dados {
    $script:DadosAdmin = $false
    Definir-Dados $PastaDados
    if ($Elevado -or -not $PastaDadosAdmin) { return }
    $marca = Join-Path $PastaDadosAdmin 'jogo.txt'
    if ((Test-Path -LiteralPath $marca) -and [IO.File]::ReadAllText($marca).Trim() -eq $script:Jogo) {
        Definir-Dados $PastaDadosAdmin
        $script:DadosAdmin = $true
    }
}

function Carregar-Alvos {
    Escolher-Dados
    $script:Dic = Carregar-Dicionario
    foreach ($a in $script:Dic.Alvos) {
        $a.Caminho = Join-Path $script:Jogo $a.Rel
        $a.Backup = Join-Path $DIR_BACKUP $a.Rel
    }
    $script:Alvos = $script:Dic.Alvos
}

function Exigir-Mod {
    if (-not (Mod-Instalado $script:Jogo)) {
        Erro-Amigavel 'O mod Titanfall 2 VR não está instalado nesta pasta.' "Instale pelo CircuitLord VR Mod Installer ($URL_INSTALADOR) e rode a ferramenta de novo."
    }
}

# Pacote de tradução anterior, instalado por outro caminho: troca os mesmos textos e deixa cópias .orig-ptbr.
function Pacote-Antigo {
    if (Test-Path -LiteralPath (Join-Path $script:Jogo $REL_PACOTE_ANTIGO)) { return $true }
    foreach ($a in $script:Alvos) {
        if (Test-Path -LiteralPath "$($a.Caminho).orig-ptbr") { return $true }
    }
    return $false
}

# Janela fechada no meio de uma gravação pode deixar temporários desta ferramenta junto dos arquivos.
function Limpar-Temporarios($caminhos) {
    foreach ($c in $caminhos) {
        $pasta = Split-Path $c
        foreach ($f in @(Get-ChildItem -LiteralPath $pasta -File -Force -Filter '.ptbr-teste-*') + @(Get-ChildItem -LiteralPath $pasta -File -Force -Filter '*.tmp-ptbr')) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Exigir-Gravacao($caminhos) {
    if (Jogo-Aberto) {
        Erro-Amigavel 'O Titanfall 2 está aberto.' 'Feche o jogo e tente de novo. Com o jogo aberto ele não vê a mudança e o arquivo pode estar em uso.'
    }
    if (Get-Process -Name $ProcessosInstalador -ErrorAction SilentlyContinue) { $script:AvisoInstalador = $true }
    Exigir-Sem-Link $caminhos
    # Backup e estado desta instalação só podem mudar como administrador.
    if ($script:DadosAdmin -and -not $Elevado) { throw "SEM_PERMISSAO:$(@($caminhos)[0])" }
    Limpar-Temporarios $caminhos
    foreach ($c in $caminhos) {
        switch (Pode-Gravar $c) {
            'permissao' { throw "SEM_PERMISSAO:$c" }
            'em-uso' { Erro-Amigavel "O arquivo $(Split-Path $c -Leaf) está aberto em outro programa." 'Feche o EA app, a Steam ou o instalador do mod se estiverem verificando ou atualizando o jogo, e tente de novo. Nada foi alterado.' }
        }
    }
}

# ============================================================
#  STATUS
# ============================================================
function Primeira-Maiuscula([string]$t) { return $t.Substring(0, 1).ToUpper() + $t.Substring(1) }

function Painel {
    $estado = Ler-Estado
    $info = Ler-Json $ARQ_BACKUP_INFO
    Titulo-Secao 'Situação'
    Campo 'Versão da tradução' $VERSAO 'Gray'
    Campo 'Pasta do jogo' $script:Jogo
    Campo 'Encontrada via' $script:Origem 'Gray'
    if (Mod-Instalado $script:Jogo) { Campo 'Mod VR' (Rotulo-Versao (Versao-Mod)) } else { Campo 'Mod VR' 'não instalado nesta pasta' 'Yellow' }
    foreach ($a in $script:Alvos) {
        $rotulo = Primeira-Maiuscula $a.Nome
        switch (Situacao-Arquivo $a $estado) {
            'traduzido' { Campo $rotulo 'em português' 'Green' }
            'dicionario-novo' { Campo $rotulo 'em português (há traduções novas: use a opção 1)' 'Yellow' }
            'alterado-fora' { Campo $rotulo 'em português, mas mexido fora da ferramenta (use a opção 1)' 'Yellow' }
            'original' { Campo $rotulo 'em inglês (original do mod)' 'Yellow' }
            default { Campo $rotulo 'arquivo não encontrado nesta versão do mod' 'Red' }
        }
    }
    if ($info) { Campo 'Backup do original' "mod $(Rotulo-Versao (Propriedade $info 'versaoMod')), de $(Propriedade $info 'data')" 'Gray' }
    else { Campo 'Backup do original' 'ainda não existe (é criado na primeira tradução)' 'DarkGray' }
    $pend = @(Ler-Pendentes)
    if ($pend.Count -gt 0) { Campo 'Sem tradução' "$($pend.Count) texto(s) do mod ficaram em inglês" 'Yellow' }
    if (Pacote-Antigo) { Campo 'Atenção' 'há um pacote antigo de tradução instalado: desinstale antes de traduzir' 'Yellow' }
    Campo 'Dados da ferramenta' $script:DIR_DADOS 'DarkGray'
}

# ============================================================
#  TRADUZIR
# ============================================================
function Traduzir {
    Exigir-Mod
    if (Pacote-Antigo) {
        Erro-Amigavel 'Este jogo tem um pacote antigo de tradução instalado ("Titanfall 2 VR em Português").' 'Desinstale em Configurações do Windows, Aplicativos, e rode de novo. Se o aplicativo não aparecer lá, reinstale o mod pelo instalador do CircuitLord. Nada foi alterado.'
    }
    Conferir-Pasta-Do-Backup
    $estado = Ler-Estado
    $versao = Versao-Mod
    Etapas 5
    W ''

    $script:plano = @(); $script:ausentes = @()
    Etapa 'Comparando com a última tradução' {
        foreach ($a in $script:Alvos) {
            if (-not (Test-Path -LiteralPath $a.Caminho)) { $script:ausentes += $a; continue }
            $antes = [IO.File]::ReadAllBytes($a.Caminho)
            if ((Texto-De $antes).Contains($ID_MARCADOR)) {
                if ((Hash-Bytes $antes) -eq $estado.Arquivos[$a.Rel] -and $estado.HashDic -eq $script:Dic.Hash) { continue }
                if (-not (Test-Path -LiteralPath $a.Backup) -or (Tem-Marcador $a.Backup)) {
                    Erro-Amigavel "O arquivo de $($a.Nome) está traduzido, mas o backup do original sumiu ou está errado." 'Reinstale o mod pelo instalador (isso traz o original de volta) e rode a ferramenta de novo.'
                }
                Conferir-Backup $a
                $script:plano += @{ Alvo = $a; Fonte = 'backup'; Antes = $antes; Original = [IO.File]::ReadAllBytes($a.Backup) }
            } else {
                $script:plano += @{ Alvo = $a; Fonte = 'jogo'; Antes = $antes; Original = $antes }
            }
        }
        if ($script:ausentes.Count -eq $script:Alvos.Count) {
            Erro-Amigavel 'Nenhum dos arquivos de texto que a ferramenta conhece existe nesta versão do mod.' "O mod mudou de estrutura. Veja se há versão nova da ferramenta ou avise em $URL_ISSUES."
        }
        if ($script:plano.Count -eq 0) { return 'nada mudou' } else { return "$($script:plano.Count) arquivo(s) para traduzir" }
    }
    $plano = $script:plano
    foreach ($a in $script:ausentes) {
        Aviso "O arquivo de $($a.Nome) não existe nesta versão do mod e foi pulado."
        Dica 'Os outros arquivos seguem normalmente. Uma versão nova da ferramenta resolve.'
    }
    if ($plano.Count -eq 0) {
        Caixa 'Tudo atualizado' @("A tradução já está aplicada no mod $(Rotulo-Versao $versao).", "Aplicada em $($estado.AplicadoEm). Nenhum arquivo foi alterado.")
        $pend = @(Ler-Pendentes)
        if ($pend.Count -gt 0) { Listar-Pendentes $pend; return 10 }
        return 0
    }

    Etapa 'Conferindo permissões e se o jogo está fechado' { Exigir-Gravacao @($plano | ForEach-Object { $_.Alvo.Caminho }); return '' }

    $script:resultados = @()
    $script:todasPend = New-Object System.Collections.Generic.List[object]
    Etapa 'Traduzindo e validando em memória' {
        foreach ($item in $plano) {
            $a = $item.Alvo
            $original = Texto-De $item.Original
            if ($item.Fonte -eq 'jogo' -and (Parece-Traduzido $a $original)) {
                Erro-Amigavel "O arquivo de $($a.Nome) parece já ter tradução, mas sem a marca desta ferramenta." 'Reinstale o mod pelo instalador para voltar ao original e rode de novo. Nada foi alterado.'
            }
            $r = if ($a.Tipo -eq 'tokens') { Traduzir-Tokens $original $a } else { Traduzir-Linhas $original $a }
            Validar $a $original $r.Texto
            foreach ($p in $r.Pendentes) { $script:todasPend.Add($p) }
            $cod = if ($a.Tipo -eq 'tokens') { $UTF16_COM_BOM } else { $UTF8_SEM_BOM }
            $script:resultados += @{ Item = $item; Bytes = (Bytes-Texto $r.Texto $cod); Itens = $r.Itens }
        }
        return "$(($script:resultados | ForEach-Object { $_.Itens } | Measure-Object -Sum).Sum) textos prontos"
    }
    $resultados = $script:resultados

    $script:novoBackup = $false
    Etapa 'Guardando backup do original do mod' {
        $novos = @($plano | Where-Object { $_.Fonte -eq 'jogo' })
        if ($novos.Count -eq 0) { return 'o backup atual continua valendo' }
        $info = Ler-Json $ARQ_BACKUP_INFO
        $hashes = @{}
        $ph = Propriedade $info 'arquivos'
        if ($ph) { foreach ($x in $ph.PSObject.Properties) { $hashes[$x.Name] = $x.Value } }
        foreach ($item in $novos) {
            $a = $item.Alvo
            New-Item -ItemType Directory -Force -Path (Split-Path $a.Backup) | Out-Null
            Substituir-Arquivo $a.Backup $item.Original
            $h = Hash-Arquivo $a.Backup
            if ($h -ne (Hash-Bytes $item.Original)) { throw "O backup de $($a.Rel) não confere. Nada foi alterado no jogo." }
            $hashes[$a.Rel] = $h
        }
        Gravar-Json $ARQ_BACKUP_INFO ([pscustomobject]@{ data = (Get-Date -Format 'yyyy-MM-dd'); versaoMod = $versao; jogo = $script:Jogo; arquivos = $hashes })
        $script:novoBackup = $true
        return "mod $(Rotulo-Versao $versao)"
    }

    Etapa 'Gravando a tradução no jogo' {
        Gravar-Lote @($resultados | ForEach-Object { @{ Caminho = $_.Item.Alvo.Caminho; Bytes = $_.Bytes; Antes = $_.Item.Antes } })
        foreach ($res in $resultados) { $estado.Arquivos[$res.Item.Alvo.Rel] = Hash-Bytes $res.Bytes }
        $estado.VersaoMod = $versao; $estado.AplicadoEm = (Get-Date -Format 'yyyy-MM-dd'); $estado.HashDic = $script:Dic.Hash
        Gravar-Estado $estado
        # Mantém as pendências dos arquivos que não entraram nesta rodada.
        $rels = @($plano | ForEach-Object { $_.Alvo.Rel })
        $antigas = @(Ler-Pendentes | Where-Object { $rels -notcontains $_.arquivo })
        $itensPend = @($antigas + $script:todasPend.ToArray())
        Gravar-Json $ARQ_PENDENTES ([pscustomobject]@{ versaoMod = $versao; data = (Get-Date -Format 'yyyy-MM-dd'); itens = $itensPend })
        $textoIssue = (@("Pendências do mod $(Rotulo-Versao $versao), ferramenta ${script:VERSAO}:") + @($itensPend | ForEach-Object { Linha-Da-Issue $_ })) -join "`n"
        Substituir-Arquivo (Join-Path $script:DIR_DADOS 'pendentes-para-issue.txt') ($UTF8_SEM_BOM.GetBytes($textoIssue + "`n"))
        if ($Elevado) { [IO.File]::WriteAllText((Join-Path $script:DIR_DADOS 'jogo.txt'), $script:Jogo, $UTF8_SEM_BOM) }
        return ''
    }

    $linhas = @()
    foreach ($res in $resultados) {
        $q = $res.Itens
        $palavra = if ($q -eq 1) { 'texto traduzido' } else { 'textos traduzidos' }
        $linhas += "$q $palavra em $($res.Item.Alvo.Nome)"
    }
    if ($script:novoBackup) { $linhas += "Original do mod $(Rotulo-Versao $versao) guardado como backup." }
    Caixa 'Tradução aplicada' $linhas
    if ($script:AvisoInstalador) {
        W ''
        Aviso 'O instalador do mod está aberto. Se ele atualizar o mod, rode esta ferramenta de novo depois.'
    }
    $pend = @(Ler-Pendentes)
    if ($pend.Count -gt 0) { Listar-Pendentes $pend; return 10 }
    W ''
    Info 'Próximo passo: abra o jogo pelo botão "Launch in VR" do instalador do mod.'
    return 0
}

# ============================================================
#  RESTAURAR
# ============================================================
function Restaurar {
    Conferir-Pasta-Do-Backup
    $estado = Ler-Estado
    Etapas 3
    W ''
    $script:fazer = @()
    Etapa 'Verificando quais arquivos estão traduzidos' {
        foreach ($a in $script:Alvos) {
            if (-not (Tem-Marcador $a.Caminho)) { continue }
            if (-not (Test-Path -LiteralPath $a.Backup) -or (Tem-Marcador $a.Backup)) {
                Erro-Amigavel "Não há backup válido de $($a.Nome)." 'Reinstale o mod pelo instalador do CircuitLord: isso devolve os textos originais.'
            }
            Conferir-Backup $a
            $script:fazer += @{ Alvo = $a; Antes = [IO.File]::ReadAllBytes($a.Caminho); Bytes = [IO.File]::ReadAllBytes($a.Backup) }
        }
        return "$($script:fazer.Count) arquivo(s)"
    }
    $fazer = $script:fazer
    if ($fazer.Count -eq 0) {
        Caixa 'Nada a restaurar' @("Os textos já são os originais (inglês) do mod $(Rotulo-Versao (Versao-Mod)).") 'Cyan'
        return 0
    }
    Etapa 'Conferindo permissões e se o jogo está fechado' { Exigir-Gravacao @($fazer | ForEach-Object { $_.Alvo.Caminho }); return '' }
    Etapa 'Devolvendo os textos originais' {
        Gravar-Lote @($fazer | ForEach-Object { @{ Caminho = $_.Alvo.Caminho; Bytes = $_.Bytes; Antes = $_.Antes } })
        foreach ($f in $fazer) { $estado.Arquivos.Remove($f.Alvo.Rel) }
        Gravar-Estado $estado
        return ''
    }
    Caixa 'Originais restaurados' @('Os textos do mod voltaram para o inglês.', 'Para traduzir de novo, use a opção 1.') 'Cyan'
    return 0
}

# ============================================================
#  Execução
# ============================================================
$ARQ_CONFIG = Join-Path $PastaDados 'config.json'
$script:DadosAdmin = $false
Definir-Dados $PastaDados
$script:Jogo = $null; $script:Origem = $null; $script:Alvos = @(); $script:Dic = $null
$script:AvisoInstalador = $false; $script:PastaFixa = $PastaJogo

# Quem eleva é o executável, nunca este script: rodar como administrador um arquivo da pasta do usuário
# deixaria qualquer programa comum trocar o que vai rodar. Aqui só fica o pedido, e o exe assume.
function Pedir-Elevacao($acao) {
    W ''
    Aviso 'Para gravar na pasta do jogo, o Windows exige permissão de administrador.'
    Dica 'O aviso do Windows mostra o nome Titanfall2VR-PTBR.exe, com editor desconhecido, porque o programa não tem assinatura digital. Abre outra janela, e esta espera.'
    [IO.File]::WriteAllText((Join-Path $PastaDados 'pedido-elevacao.txt'), "$acao`n$($script:Jogo)`n", $UTF8_SEM_BOM)
    return $COD_PEDE_ELEVACAO
}

function Executar($acao) {
    try {
        switch ($acao) {
            'Status' { Painel; return 0 }
            'Restaurar' { return (Restaurar) }
            'Traduzir' { return (Traduzir) }
        }
    } catch {
        $ex = $_.Exception
        if ($ex.Message -like 'SEM_PERMISSAO:*') {
            $alvo = $ex.Message.Substring(14)
            if ($Elevado) {
                W ''; Falha "Nem como administrador o Windows deixou gravar em $alvo."
                Dica 'Confira se o arquivo não está marcado como "Somente leitura" (botão direito, Propriedades) e tente de novo.'
                return 3
            }
            if ($NaoInterativo) { W ''; Falha "Sem permissão de escrita em $alvo"; Dica 'Rode a ferramenta sem -NaoInterativo para ela pedir permissão de administrador.'; return 3 }
            if ($ViaExe) { return (Pedir-Elevacao $acao) }
            W ''; Falha "Sem permissão de escrita em $alvo"
            Dica 'Use o Titanfall2VR-PTBR.exe, que pede a permissão de administrador do jeito seguro.'
            return 3
        }
        W ''
        Falha $ex.Message
        if ($ex.Data.Contains('sugestao')) { Dica $ex.Data['sugestao'] }
        else { Dica 'Erro inesperado. Se algo foi gravado, a ferramenta devolveu os arquivos ao estado de antes.' }
        return 1
    }
}

try {
    if ($Acao -ne 'Menu') {
        if ($Acao -ne 'Status' -and -not $NaoInterativo) { Cabecalho }
        Preparar
        $codigo = Executar $Acao
        if ($Pausar) { Esperar-Enter }
        exit $codigo
    }

    Cabecalho
    Preparar
    $msg = $null
    while ($true) {
        try { Carregar-Alvos } catch { $msg = $_.Exception.Message }
        Painel
        Titulo-Secao 'O que você quer fazer?'
        W '  [1] ' 'Cyan' -n; W 'Traduzir para português' 'White'
        W '  [2] ' 'Cyan' -n; W 'Voltar aos textos originais (inglês)' 'White'
        W '  [3] ' 'Cyan' -n; W 'Trocar a pasta do jogo' 'White'
        W '  [0] ' 'DarkGray' -n; W 'Sair' 'DarkGray'
        if ($msg) { W ''; Aviso $msg; $msg = $null }
        $op = Perguntar 'Opção:'
        if ($null -eq $op) { exit 0 }
        switch ($op) {
            '1' { Cabecalho; Titulo-Secao 'Traduzindo'; if (@(Executar 'Traduzir')[-1] -eq $COD_PEDE_ELEVACAO) { exit $COD_PEDE_ELEVACAO }; Esperar-Enter; Cabecalho }
            '2' { Cabecalho; Titulo-Secao 'Restaurando os originais'; if (@(Executar 'Restaurar')[-1] -eq $COD_PEDE_ELEVACAO) { exit $COD_PEDE_ELEVACAO }; Esperar-Enter; Cabecalho }
            '3' {
                Cabecalho
                $anterior = @{ Jogo = $script:Jogo; Origem = $script:Origem }
                try { Preparar -TrocarPasta }
                catch {
                    $motivo = $_.Exception.Message
                    $script:Jogo = $anterior.Jogo; $script:Origem = $anterior.Origem
                    Salvar-Pasta $script:Jogo $script:Origem
                    Carregar-Alvos
                    $msg = "Troca cancelada ($motivo). A pasta continua: $($script:Jogo)"
                }
                Cabecalho
            }
            '0' { W ''; exit 0 }
            default { Cabecalho; $msg = "Opção inválida: '$op'. Digite 1, 2, 3 ou 0." }
        }
    }
} catch {
    W ''
    Falha $_.Exception.Message
    if ($_.Exception.Data.Contains('sugestao')) { Dica $_.Exception.Data['sugestao'] }
    if ($Pausar -or $Acao -eq 'Menu') { Esperar-Enter }
    exit 1
}
