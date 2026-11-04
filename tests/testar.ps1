# Testes da ferramenta com mod e dicionário sintéticos, numa pasta temporária.
# Uso: powershell -File tests\testar.ps1   ou   pwsh -File tests\testar.ps1
# Roda a ferramenta no mesmo PowerShell que roda o teste. Sai com o número de falhas.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot 'sintetico.ps1')

$RAIZ = Split-Path $PSScriptRoot -Parent
$SHELL_ATUAL = (Get-Process -Id $PID).ProcessName
$SCRIPT = Join-Path $RAIZ 'ferramenta\titanfall-ptbr.ps1'
$LAB = Join-Path ([IO.Path]::GetTempPath()) ("tf2vr ptbr teste " + [guid]::NewGuid().ToString('N'))
$JOGO = Join-Path $LAB 'jogo com espaço'
$DADOS = Join-Path $LAB 'dados'
$DIC = Join-Path $LAB 'dic'
$MARCA = 'titanfall2-vr-ptbr'

$script:falhas = 0
$script:total = 0
$script:ultima = ''
function Conferir($cond, $msg) {
    $script:total++
    if ($cond) { Write-Host "  OK    $msg" -ForegroundColor Green }
    else {
        Write-Host "  FALHA $msg" -ForegroundColor Red; $script:falhas++
        if ($script:ultima) { Write-Host ($script:ultima.Trim()) -ForegroundColor DarkGray }
    }
}
function Rodar($acao, [string[]]$extra = @(), $dicionario = $script:DIC, $entrada = $null) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $SCRIPT, '-Acao', $acao, '-PastaDados', $DADOS, '-SemCor') + $extra
    if ($dicionario) { $a += @('-PastaDicionario', $dicionario) }
    if ($extra -notcontains '-ProcessosJogo') { $a += @('-ProcessosJogo', 'processo-que-nao-existe') }
    # Trava: sem -PastaJogo e sem pasta salva neste teste, a ferramenta procuraria o jogo real.
    if ($extra -notcontains '-PastaJogo') {
        $cfg = Join-Path $DADOS 'config.json'
        if (-not (Test-Path -LiteralPath $cfg) -or -not ([IO.File]::ReadAllText($cfg)).Contains('tf2vr ptbr teste')) {
            throw 'Teste sem -PastaJogo e sem pasta de teste salva: abortado para não tocar no jogo real.'
        }
    }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        if ($null -eq $entrada) { $a += '-NaoInterativo'; $saida = & $SHELL_ATUAL @a 6>&1 2>&1 | Out-String }
        else { $saida = $entrada | & $SHELL_ATUAL @a 6>&1 2>&1 | Out-String }
        $codigo = $LASTEXITCODE
    } finally { $ErrorActionPreference = $eap }
    $script:ultima = $saida
    return @{ Codigo = $codigo; Saida = $saida }
}
function J([string[]]$extra = @()) { return @('-PastaJogo', $JOGO) + $extra }
function Cam($rel) { Join-Path $JOGO $rel }
function HashDe($rel) { (Get-FileHash -LiteralPath (Cam $rel) -Algorithm SHA256).Hash }
function TextoDe($rel) { [IO.File]::ReadAllText((Cam $rel)) }
function Backup($rel) { Join-Path $DADOS "backup\$rel" }
function Traduzido($rel) { (TextoDe $rel).Contains($MARCA) }
function CopiarDic($nome) {
    $d = Join-Path $LAB $nome
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Copy-Item -Path (Join-Path ($DIC -replace '([\[\]])', '`$1') '*') -Destination $d
    return $d
}
function LerJson($p) { [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function LimparDados { if (Test-Path -LiteralPath $DADOS) { Remove-Item -LiteralPath $DADOS -Recurse -Force } }
function Repor {
    foreach ($rel in $TODOS) { if (Test-Path -LiteralPath (Cam $rel)) { Set-ItemProperty -LiteralPath (Cam $rel) -Name IsReadOnly -Value $false } }
    Montar-Mod $JOGO
}
function IguaisByte($a, $b) {
    $x = [IO.File]::ReadAllBytes($a); $y = [IO.File]::ReadAllBytes($b)
    if ($x.Length -ne $y.Length) { return $false }
    for ($i = 0; $i -lt $x.Length; $i++) { if ($x[$i] -ne $y[$i]) { return $false } }
    return $true
}

New-Item -ItemType Directory -Force -Path $DIC | Out-Null
Montar-Dicionario $DIC
Montar-Mod $JOGO
$MOLDE_PURO = Join-Path $LAB 'mod puro'
Montar-Mod $MOLDE_PURO
function TodosOriginais {
    foreach ($rel in $TODOS) { if (-not (IguaisByte (Cam $rel) (Join-Path $MOLDE_PURO $rel))) { return $false } }
    return $true
}

try {
    Write-Host "Rodando em $SHELL_ATUAL $($PSVersionTable.PSVersion)"

    Write-Host "`n[1] Status inicial"
    $r = Rodar 'Status' (J)
    Conferir ($r.Codigo -eq 0) 'status sai com 0'
    Conferir ($r.Saida -match 'em inglês') 'arquivos aparecem como originais'

    Write-Host "`n[2] Primeira tradução"
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 0) "traduzir sai com 0 (saiu $($r.Codigo))"
    Conferir ($r.Saida -cmatch 'Tradução aplicada' -and $r.Saida -cnotmatch 'Ã|Â') 'saída com acentos certos'
    Conferir ((TextoDe $TOK).Contains('"XT_LIGAR" "Ativar fluxo"')) 'token traduzido, sem perder o espaço original entre as aspas'
    Conferir ((TextoDe $TOK).Contains('||Segure %use% para quarks azuis')) 'separador || e variável preservados'
    Conferir ((TextoDe $TOK).Contains('"XT_ICONE" "%$vgui/icone_de_teste%"')) 'token só com ícone fica como estava e não vira pendência'
    Conferir ((TextoDe $NUT).Contains('return "Aperte a " + alavanca + " para virar o quark"')) 'literais trocados na linha real do mod'
    Conferir ((TextoDe $NUT).Contains('"RotuloPrincipal" ), "NORTE"')) 'null mantém o literal original'
    Conferir ((TextoDe $NUT).Contains('"alavanca de múon"')) 'acento gravado em UTF-8'
    Conferir ((TextoDe $NUT).Contains('return "Mova a mão " + ( Teste_Gestos()[mao] == "norte" ? "para o norte" : ( Teste_Gestos()[mao] == "sul" ? "para o sul" : Teste_Gestos()[mao] ) ) + ": " + Localize( hint.nome )')) 'molde remonta a linha com o código lido do mod'
    Conferir ((TextoDe $NUT).Contains('return [ "norte", "sul" ]')) 'lista interna intacta'
    Conferir ((TextoDe $PAINEL).Contains('"ABRIR COFRE ZORBLAT"')) 'script com varrer false aplica as linhas conhecidas'
    Conferir ((TextoDe $PAINEL).Contains('Other words that are never scanned')) 'varrer false não mexe no resto'
    Conferir ([IO.File]::ReadAllBytes((Cam $TOK))[0] -eq 0xFF) 'tokens continua UTF-16 com BOM'
    Conferir ([IO.File]::ReadAllBytes((Cam $NUT))[0] -ne 0xEF) 'script sem BOM'
    foreach ($rel in $TODOS) { Conferir (IguaisByte (Backup $rel) (Join-Path $MOLDE_PURO $rel)) "backup de $(Split-Path $rel -Leaf) idêntico ao original" }
    Conferir (-not (Get-ChildItem -LiteralPath $JOGO -Recurse -Filter '*.tmp-ptbr')) 'nenhum temporário largado'

    Write-Host "`n[3] Segunda tradução sem mudanças"
    $antes = (Get-Item -LiteralPath (Cam $TOK)).LastWriteTimeUtc
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Saida -match 'Tudo atualizado' -and $r.Codigo -eq 0) 'avisa que está tudo atualizado'
    Conferir ((Get-Item -LiteralPath (Cam $TOK)).LastWriteTimeUtc -eq $antes) 'não regravou o arquivo'

    Write-Host "`n[4] Restaurar"
    $r = Rodar 'Restaurar' (J)
    Conferir ($r.Codigo -eq 0) 'restaurar sai com 0'
    Conferir (TodosOriginais) 'arquivos idênticos byte a byte ao original'
    $r = Rodar 'Restaurar' (J)
    Conferir ($r.Saida -match 'Nada a restaurar') 'segundo restaurar não faz nada'

    Write-Host "`n[5] Atualização simulada do mod (texto novo, texto alterado, linha nova)"
    $r = Rodar 'Traduzir' (J)
    $t = (Texto-Tokens).Replace('"XT_LIGAR" "Engage flux"', '"XT_LIGAR" "Engage flux now"').Replace('"XT_VAZIO" ""', "`"XT_VAZIO`" `"`"`r`n        `"XT_NOVO`" `"Brand new zorblat`"")
    Gravar-Bytes (Cam $TOK) $t $UTF16
    $n = ((Linhas-Nut) -join "`r`n").Replace('	return "Zorblat is empty"', "	return `"Zorblat is empty`"`r`n	return `"Recharging`"")
    Gravar-Bytes (Cam $NUT) $n $UTF8
    Gravar-Bytes (Cam $REG) '{"version":"9.9.2","files":[]}' $UTF8
    $hTok2 = HashDe $TOK; $hNut2 = HashDe $NUT
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 10) "sinaliza pendências (saiu $($r.Codigo))"
    Conferir ($r.Saida -match 'abra uma issue') 'orienta abrir uma issue'
    $pend = LerJson (Join-Path $DADOS 'pendentes.json')
    Conferir (@($pend.itens).Count -eq 3) "3 pendências, inclusive palavra única ($(@($pend.itens).Count))"
    Conferir (@($pend.itens | Where-Object { $_.enHash -cmatch '^[0-9a-f]{64}$' }).Count -eq 3) 'pendência leva o hash para quem for traduzir'
    Conferir ((TextoDe $TOK).Contains('"Brand new zorblat"') -and (TextoDe $TOK).Contains('"Engage flux now"')) 'textos novos ficaram em inglês'
    Conferir ((TextoDe $TOK).Contains('PAINEL ZORBLAT')) 'resto continua traduzido'
    Conferir ((LerJson (Backup 'backup.json')).versaoMod -eq '9.9.2') 'backup passou a ser da versão nova'
    Conferir ((Get-FileHash -LiteralPath (Backup $TOK) -Algorithm SHA256).Hash -eq $hTok2) 'backup igual ao original novo'
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 10 -and $r.Saida -match 'Tudo atualizado' -and $r.Saida -match 'token XT_NOVO') 'rodar de novo continua avisando as pendências'
    Conferir ($r.Saida -notmatch 'Brand new zorblat|Engage flux now|Recharging') 'a saída para colar na issue não tem texto do mod'
    Conferir ($r.Saida -match 'sha256:[0-9a-f]{64}' -and $r.Saida -match 'linha \d+ de teste_dicas\.nut') 'a saída mostra chave, linha e hash'
    $crus = [IO.File]::ReadAllText((Join-Path $DADOS 'pendentes.json')) + [IO.File]::ReadAllText((Join-Path $DADOS 'pendentes-para-issue.txt'))
    Conferir ($crus -notmatch 'Brand new zorblat|Engage flux now|Recharging') 'os arquivos de pendências não têm texto do mod'

    Write-Host "`n[6] Restaurar volta para o original NOVO"
    $r = Rodar 'Restaurar' (J)
    Conferir ((HashDe $TOK) -eq $hTok2 -and (HashDe $NUT) -eq $hNut2) 'restaurou a versão nova do mod'

    Write-Host "`n[7] Dicionário ganha as traduções novas e reaplica a partir do backup"
    $r = Rodar 'Traduzir' (J)
    $d2 = CopiarDic 'd2'
    $o = LerJson (Join-Path $d2 'tokens.json')
    ($o.tokens | Where-Object { $_.chave -eq 'XT_LIGAR' }).enHash = (Sha 'Engage flux now')
    $o.tokens += [pscustomobject]@{ chave = 'XT_NOVO'; enHash = (Sha 'Brand new zorblat'); pt = 'Zorblat novinho' }
    Gravar-Json-Teste (Join-Path $d2 'tokens.json') $o
    $o = LerJson (Join-Path $d2 'dicas.json')
    $o.linhas += [pscustomobject]@{ enHash = (Sha 'return "Recharging"'); textos = @('Recarregando') }
    Gravar-Json-Teste (Join-Path $d2 'dicas.json') $o
    $r = Rodar 'Status' (J) $d2
    Conferir ($r.Saida -match 'traduções novas') 'status avisa que o dicionário tem traduções novas'
    $r = Rodar 'Traduzir' (J) $d2
    Conferir ($r.Codigo -eq 0) "reaplicou sem pendências (saiu $($r.Codigo))"
    Conferir ((TextoDe $TOK).Contains('"Zorblat novinho"') -and (TextoDe $NUT).Contains('"Recarregando"')) 'traduções novas aplicadas'
    Conferir (([regex]::Matches((TextoDe $NUT), $MARCA)).Count -eq 1) 'marcador não duplicou'
    Conferir ((Get-FileHash -LiteralPath (Backup $TOK) -Algorithm SHA256).Hash -eq $hTok2) 'backup continua o original'
    $r = Rodar 'Restaurar' (J) $d2
    Repor; LimparDados

    Write-Host "`n[8] Entradas que mexeriam no código viram pendência"
    $d3 = CopiarDic 'd3'
    $o = LerJson (Join-Path $d3 'tokens.json')
    ($o.tokens | Where-Object { $_.chave -eq 'XT_SEGURE' }).pt = 'Segure perto da escotilha'
    ($o.tokens | Where-Object { $_.chave -eq 'XT_LIGAR' }).pt = "Ati`nvar"
    ($o.tokens | Where-Object { $_.chave -eq 'XT_TITULO' }).pt = 'PAINEL "ZORBLAT'
    Gravar-Json-Teste (Join-Path $d3 'tokens.json') $o
    $h = @{}
    $linhasDic = @(
        # aspas no texto mudariam o código da linha
        [pscustomobject]@{ enHash = (Sha 'return "Zorblat is empty"'); textos = @('Vazio" + TesteMau() + "') }
        # nome interno usado como argumento não pode mudar
        [pscustomobject]@{ enHash = (Sha 'Teste_Comando( "teste_comando_interno" )'); textos = @('kill') }
        # número errado de literais
        [pscustomobject]@{ enHash = (Sha 'return "Tap " + alavanca + " to flip the quark"'); textos = @('Só um') }
        # molde que tenta chamar código novo
        [pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Teste_Gestos()[mao] + " for " + Localize( hint.nome )'); molde = '{0} TesteMau() + {1} + {2}' }
        # quebra de linha dentro do texto
        [pscustomobject]@{ enHash = (Sha 'string alavanca = mao == 0 ? "quark lever" : "muon lever"'); textos = @("ala`nvanca", 'outra') }
    )
    Gravar-Json-Teste (Join-Path $d3 'dicas.json') ([pscustomobject]@{ arquivo = $NUT; nome = 'dicas de teste'; linhas = $linhasDic })
    $r = Rodar 'Traduzir' (J) $d3
    Conferir ($r.Codigo -eq 10) "viram pendência (saiu $($r.Codigo))"
    Conferir ((TextoDe $TOK).Contains('"Keep %use% down near the quark hatch"')) 'token que perdia %use% ficou original'
    Conferir ((TextoDe $TOK).Contains('"XT_LIGAR" "Engage flux"')) 'token com quebra de linha ficou original'
    Conferir ((TextoDe $TOK).Contains('"ZORBLAT PANEL"')) 'token com aspas ficou original'
    Conferir (-not (TextoDe $NUT).Contains('TesteMau')) 'código injetado por texto ou molde não chegou ao mod'
    Conferir ((TextoDe $NUT).Contains('Teste_Comando( "teste_comando_interno" )') -and -not (TextoDe $NUT).Contains('"kill"')) 'nome interno de código não foi trocado'
    Conferir ((TextoDe $NUT).Contains('return "Tap " + alavanca + " to flip the quark"')) 'número errado de literais ficou original'
    Conferir ((TextoDe $NUT).Contains('"quark lever"')) 'quebra de linha na linha ficou original'
    $r = Rodar 'Restaurar' (J) $d3
    Conferir (TodosOriginais) 'restaurar depois disso devolve o original'

    Write-Host "`n[9] Molde sem um trecho do código original é recusado"
    $d4 = CopiarDic 'd4'
    $linhasDic = @([pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Teste_Gestos()[mao] + " for " + Localize( hint.nome )'); molde = '{0} "Sem nome " + {1}' })
    Gravar-Json-Teste (Join-Path $d4 'dicas.json') ([pscustomobject]@{ arquivo = $NUT; nome = 'dicas de teste'; linhas = $linhasDic })
    $r = Rodar 'Traduzir' (J) $d4
    Conferir ((TextoDe $NUT).Contains('"Sweep hand "')) 'linha ficou original'
    $r = Rodar 'Restaurar' (J) $d4

    Write-Host "`n[10] Dicionário defeituoso é recusado sem gravar nada"
    $d5 = CopiarDic 'd5'
    $o = LerJson (Join-Path $d5 'dicas.json'); $o.arquivo = 'Titanfall2.exe'; Gravar-Json-Teste (Join-Path $d5 'dicas.json') $o
    $r = Rodar 'Traduzir' (J) $d5
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'não permitido') 'caminho fora dos textos do mod'
    $d6 = CopiarDic 'd6'
    $o = LerJson (Join-Path $d6 'tokens.json')
    $o.tokens[0] | Add-Member -NotePropertyName en -NotePropertyValue 'Texto do mod'
    Gravar-Json-Teste (Join-Path $d6 'tokens.json') $o
    $r = Rodar 'Traduzir' (J) $d6
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match "campo 'en'") 'entrada com o campo en'
    $d7 = CopiarDic 'd7'
    $o = LerJson (Join-Path $d7 'tokens.json'); $o.tokens[0].enHash = 'abc'; Gravar-Json-Teste (Join-Path $d7 'tokens.json') $o
    $r = Rodar 'Traduzir' (J) $d7
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match "enHash") 'hash inválido'
    $d8 = CopiarDic 'd8'
    $o = LerJson (Join-Path $d8 'tokens.json'); $o.tokens[0].PSObject.Properties.Remove('pt'); Gravar-Json-Teste (Join-Path $d8 'tokens.json') $o
    $r = Rodar 'Traduzir' (J) $d8
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match "sem o campo 'pt'") 'entrada sem pt'
    $d9 = CopiarDic 'd9'
    Copy-Item -LiteralPath (Join-Path $d9 'dicas.json') -Destination (Join-Path $d9 'dicas - Copia.json')
    $r = Rodar 'Traduzir' (J) $d9
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'mesmo script') 'cópia esquecida no dicionário'
    Conferir (TodosOriginais) 'nada foi gravado'

    Write-Host "`n[11] Mudança só de maiúscula no código não casa com o dicionário"
    Gravar-Bytes (Cam $NUT) (((Linhas-Nut) -join "`r`n").Replace('return "Tap " + alavanca', 'return "Tap " + Alavanca')) $UTF8
    $r = Rodar 'Traduzir' (J)
    Conferir ((TextoDe $NUT).Contains('return "Tap " + Alavanca + " to flip the quark"')) 'linha diferente não foi trocada'
    Conferir ($r.Codigo -eq 10) 'e virou pendência'
    $r = Rodar 'Restaurar' (J); Repor

    Write-Host "`n[12] Arquivo já traduzido sem a marca não vira backup"
    $r = Rodar 'Traduzir' (J)
    $semMarca = ((TextoDe $NUT) -split "`r`n" | Where-Object { $_ -notmatch $MARCA }) -join "`r`n"
    $hBackup = (Get-FileHash -LiteralPath (Backup $NUT) -Algorithm SHA256).Hash
    Gravar-Bytes (Cam $NUT) $semMarca $UTF8
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 1) "recusa com erro (saiu $($r.Codigo))"
    Conferir ((Get-FileHash -LiteralPath (Backup $NUT) -Algorithm SHA256).Hash -eq $hBackup) 'backup não foi sobrescrito'
    Repor; LimparDados

    Write-Host "`n[13] Pacote antigo de tradução instalado"
    $copiaAntiga = "$(Cam $NUT).orig-ptbr"
    Gravar-Bytes $copiaAntiga 'x' $UTF8
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'pacote antigo') 'cópia .orig-ptbr: recusa e explica'
    $r = Rodar 'Status' (J)
    Conferir ($r.Saida -match 'pacote antigo') 'status avisa'
    Remove-Item -LiteralPath $copiaAntiga
    $pastaAntiga = Cam 'TF2VR\mods\TF2VR.PTBR'
    New-Item -ItemType Directory -Force -Path $pastaAntiga | Out-Null
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'pacote antigo') 'pasta do mod antigo: recusa e explica'
    Remove-Item -LiteralPath $pastaAntiga -Recurse
    Conferir (TodosOriginais) 'nada foi gravado'

    Write-Host "`n[14] Jogo aberto bloqueia a gravação"
    $r = Rodar 'Traduzir' (J @('-ProcessosJogo', $SHELL_ATUAL))
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'aberto') 'recusa com o jogo aberto'
    Conferir (TodosOriginais) 'nada foi gravado'

    Write-Host "`n[15] Sem permissão de escrita"
    $arq = Get-Item -LiteralPath (Cam $NUT); $arq.IsReadOnly = $true
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 3) "sai com código 3 (saiu $($r.Codigo))"
    $r2 = Rodar 'Traduzir' (J @('-Elevado')) $DIC "`n"
    Conferir ($r2.Codigo -eq 3 -and $r2.Saida -match 'Nem como administrador') 'janela elevada não abre outra'
    $arq.IsReadOnly = $false
    Conferir (TodosOriginais) 'não traduziu pela metade'

    Write-Host "`n[16] Falha no meio da gravação desfaz tudo"
    $trava = [IO.File]::Open((Cam $NUT), 'Open', 'Read', 'ReadWrite')
    try { $r = Rodar 'Traduzir' (J) } finally { $trava.Close() }
    Conferir ($r.Codigo -eq 1) "falha com erro (saiu $($r.Codigo))"
    Conferir (TodosOriginais) 'arquivos gravados antes da falha voltaram ao original'
    Conferir (-not (Get-ChildItem -LiteralPath $JOGO -Recurse -Filter '*.tmp-ptbr')) 'nenhum temporário largado'
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 0) 'depois de destravar, traduz normalmente'
    $r = Rodar 'Restaurar' (J)

    Write-Host "`n[17] Arquivo aberto em outro programa não pede administrador"
    $trava = [IO.File]::Open((Cam $NUT), 'Open', 'Read', 'Read')
    try { $r = Rodar 'Traduzir' (J) } finally { $trava.Close() }
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'aberto em outro programa') 'explica que outro programa está usando'
    Conferir (TodosOriginais) 'nada foi gravado'

    Write-Host "`n[18] Pasta lembrada, menu e troca cancelada"
    $r = Rodar 'Status' (J)
    $r = Rodar 'Status'
    Conferir ($r.Saida.Contains($JOGO)) 'sem -PastaJogo, usa a pasta salva'
    $r = Rodar 'Menu' @() $DIC "9`n0`n"
    Conferir ($r.Codigo -eq 0 -and $r.Saida -match 'Opção inválida') 'opção inválida pede de novo, 0 sai'
    $r = Rodar 'Menu' @() $DIC "3`n`n0`n"
    Conferir ($r.Saida -match 'Troca cancelada|Pasta do jogo') 'cancelar a troca de pasta volta ao menu'
    $r = Rodar 'Status'
    Conferir ($r.Saida.Contains($JOGO)) 'a pasta anterior continua salva'

    Write-Host "`n[19] Restaurar sem backup: recusa sem estragar"
    $r = Rodar 'Traduzir' (J)
    Remove-Item -LiteralPath (Backup $NUT)
    $antes = HashDe $NUT
    $r = Rodar 'Restaurar' (J)
    Conferir ($r.Codigo -eq 1) 'falha com erro claro'
    Conferir ((HashDe $NUT) -eq $antes) 'arquivo não foi alterado'
    Repor; LimparDados

    Write-Host "`n[20] Arquivo-alvo ausente numa versão nova do mod"
    Remove-Item -LiteralPath (Cam $PAINEL)
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 0 -and $r.Saida -match 'foi pulado') 'pula o arquivo ausente e avisa'
    Conferir ((TextoDe $TOK).Contains('PAINEL ZORBLAT')) 'traduz o resto normalmente'
    $r = Rodar 'Restaurar' (J); Repor; LimparDados

    Write-Host "`n[22] Backup adulterado é recusado"
    $r = Rodar 'Traduzir' (J)
    $b = [IO.File]::ReadAllBytes((Backup $NUT)); $b[3] = $b[3] -bxor 1; [IO.File]::WriteAllBytes((Backup $NUT), $b)
    $antes = HashDe $NUT
    $r = Rodar 'Restaurar' (J)
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'não confere') 'restaurar recusa'
    Conferir ((HashDe $NUT) -eq $antes) 'restaurar não gravou nada'
    $d10 = CopiarDic 'd10'
    $o = LerJson (Join-Path $d10 'tokens.json'); ($o.tokens | Where-Object { $_.chave -eq 'XT_TITULO' }).pt = 'PAINEL NOVO'; Gravar-Json-Teste (Join-Path $d10 'tokens.json') $o
    $r = Rodar 'Traduzir' (J) $d10
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'não confere') 'traduzir recusa'
    Conferir ((HashDe $NUT) -eq $antes) 'traduzir não gravou nada'
    Remove-Item -LiteralPath (Join-Path $DADOS 'backup\backup.json')
    $r = Rodar 'Restaurar' (J)
    Conferir ($r.Codigo -eq 1 -and (HashDe $NUT) -eq $antes) 'sem o backup.json também recusa'
    Repor; LimparDados

    Write-Host "`n[23] Temporários de uma janela fechada no meio são limpos"
    $t1 = "$(Cam $NUT).tmp-ptbr"; $t2 = Join-Path (Split-Path (Cam $NUT)) '.ptbr-teste-abc'; $t3 = Join-Path (Split-Path (Cam $NUT)) 'outro.txt'
    foreach ($t in $t1, $t2, $t3) { Gravar-Bytes $t 'x' $UTF8 }
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 0 -and -not (Test-Path -LiteralPath $t1) -and -not (Test-Path -LiteralPath $t2)) 'temporários da ferramenta sumiram'
    Conferir (Test-Path -LiteralPath $t3) 'arquivo de outra origem ficou'
    Remove-Item -LiteralPath $t3
    $r = Rodar 'Restaurar' (J); Repor; LimparDados

    Write-Host "`n[24] Molde sem nome interno em claro"
    $d11 = CopiarDic 'd11'
    $linhasDic = @([pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Teste_Gestos()[mao] + " for " + Localize( hint.nome )'); molde = ('{0} "Mova " + ( {1} == {=' + (Sha 'nome-que-nao-existe') + '} ? "x" : {1} ) + {2}') })
    Gravar-Json-Teste (Join-Path $d11 'dicas.json') ([pscustomobject]@{ arquivo = $NUT; nome = 'dicas de teste'; linhas = $linhasDic })
    $r = Rodar 'Traduzir' (J) $d11
    Conferir ((TextoDe $NUT).Contains('"Sweep hand "') -and $r.Codigo -eq 10) 'nome que não existe no arquivo: linha fica original e vira pendência'
    $r = Rodar 'Restaurar' (J) $d11; Repor; LimparDados

    Write-Host "`n[25] Elevação: o script só pede, e os dados elevados ficam à parte"
    $ADMIN = Join-Path $LAB 'dados admin'
    $arq = Get-Item -LiteralPath (Cam $NUT); $arq.IsReadOnly = $true
    $r = Rodar 'Traduzir' (J) $DIC ''
    Conferir ($r.Codigo -eq 3 -and $r.Saida -match 'Titanfall2VR-PTBR\.exe') 'rodando o script direto: não eleva nada e aponta o exe'
    $r = Rodar 'Traduzir' (J @('-ViaExe')) $DIC ''
    Conferir ($r.Codigo -eq 20) "pelo exe: devolve o pedido (saiu $($r.Codigo))"
    $pedido = [IO.File]::ReadAllText((Join-Path $DADOS 'pedido-elevacao.txt')) -split "`n"
    Conferir ($pedido[0] -ceq 'Traduzir' -and $pedido[1] -ceq $JOGO) 'pedido com a ação e a pasta do jogo'
    $arq.IsReadOnly = $false
    Conferir (TodosOriginais) 'nada foi gravado antes da permissão'
    $DADOS_COMUM = $DADOS; $DADOS = $ADMIN
    $r = Rodar 'Traduzir' (J @('-Elevado')) $DIC ''
    $DADOS = $DADOS_COMUM
    Conferir ($r.Codigo -eq 0 -and (Traduzido $NUT)) 'etapa elevada traduz com os dados dela'
    Conferir (Test-Path -LiteralPath (Join-Path $ADMIN 'backup\backup.json')) 'backup na pasta dos administradores'
    Conferir (-not (Test-Path -LiteralPath (Join-Path $DADOS 'backup'))) 'nada de backup na pasta do usuário'
    $r = Rodar 'Status' (J @('-PastaDadosAdmin', $ADMIN))
    Conferir ($r.Saida -match 'em português' -and $r.Saida.Contains($ADMIN)) 'etapa comum lê o estado elevado'
    $r = Rodar 'Traduzir' (J @('-PastaDadosAdmin', $ADMIN))
    Conferir ($r.Saida -match 'Tudo atualizado') 'nada a fazer: não pede permissão'
    $r = Rodar 'Restaurar' (J @('-PastaDadosAdmin', $ADMIN, '-ViaExe')) $DIC ''
    Conferir ($r.Codigo -eq 20) 'restaurar exige a etapa elevada, mesmo com a pasta gravável'
    $DADOS = $ADMIN
    $r = Rodar 'Restaurar' (J @('-Elevado')) $DIC ''
    $DADOS = $DADOS_COMUM
    Conferir ($r.Codigo -eq 0 -and (TodosOriginais)) 'etapa elevada restaura byte a byte'
    [IO.File]::WriteAllText((Join-Path $ADMIN 'jogo.txt'), 'outra pasta')
    $r = Rodar 'Status' (J @('-PastaDadosAdmin', $ADMIN))
    Conferir (-not $r.Saida.Contains($ADMIN)) 'dados elevados de outro jogo são ignorados'
    LimparDados

    Write-Host "`n[26] Backup de uma pasta do jogo não serve a outra"
    $JOGO2 = Join-Path $LAB 'outro jogo'
    Montar-Mod $JOGO2
    $alvo2 = Join-Path $JOGO2 $NUT
    $r = Rodar 'Traduzir' (J)
    $info = [IO.File]::ReadAllText((Join-Path $DADOS 'backup\backup.json'))
    Conferir ($info.Contains('jogo')) 'backup.json registra a pasta do jogo'
    $bkAntes = (Get-FileHash -LiteralPath (Backup $NUT)).Hash; $h2 = (Get-FileHash -LiteralPath $alvo2).Hash
    $r = Rodar 'Traduzir' @('-PastaJogo', $JOGO2)
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'outra pasta') 'traduzir outra pasta: recusa'
    $r = Rodar 'Restaurar' @('-PastaJogo', ($JOGO2 + '/'))
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'outra pasta') 'restaurar outra pasta: recusa'
    Conferir ((Get-FileHash -LiteralPath $alvo2).Hash -eq $h2) 'a outra pasta ficou como estava'
    Conferir ((Get-FileHash -LiteralPath (Backup $NUT)).Hash -eq $bkAntes) 'o backup continua o mesmo'
    $r = Rodar 'Status' (J @()) ; $r = Rodar 'Restaurar' @('-PastaJogo', ($JOGO + '/'))
    Conferir ($r.Codigo -eq 0 -and (TodosOriginais)) 'mesma pasta, escrita com barra no fim: restaura'
    $r = Rodar 'Traduzir' @('-PastaJogo', $JOGO2)
    Conferir ($r.Codigo -eq 0 -and [IO.File]::ReadAllText($alvo2).Contains($MARCA)) 'depois de restaurar, a outra pasta pode ser traduzida'
    Remove-Item -LiteralPath (Join-Path $JOGO2 'Titanfall2.exe')
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 0) 'instalação registrada que sumiu não prende o backup'
    $r = Rodar 'Restaurar' (J); Repor; LimparDados
    Remove-Item -LiteralPath $JOGO2 -Recurse -Force

    Write-Host "`n[27] Alvo com junction no caminho é recusado"
    $pastaAlvo = Split-Path (Cam $NUT)
    $fora = Join-Path $LAB 'fora do jogo'
    Copy-Item -LiteralPath $pastaAlvo -Destination $fora -Recurse
    Rename-Item -LiteralPath $pastaAlvo -NewName 'pasta real'
    $pastaReal = Join-Path (Split-Path $pastaAlvo) 'pasta real'
    New-Item -ItemType Junction -Path $pastaAlvo -Target $fora | Out-Null
    $hFora = (Get-FileHash -LiteralPath (Join-Path $fora (Split-Path $NUT -Leaf))).Hash
    $r = Rodar 'Traduzir' (J)
    Conferir ($r.Codigo -eq 1 -and $r.Saida -match 'junction') 'recusa, com erro claro'
    Conferir ((Get-FileHash -LiteralPath (Join-Path $fora (Split-Path $NUT -Leaf))).Hash -eq $hFora) 'nada foi gravado no destino do link'
    [IO.Directory]::Delete($pastaAlvo, $false)
    Rename-Item -LiteralPath $pastaReal -NewName (Split-Path $pastaAlvo -Leaf)
    Remove-Item -LiteralPath $fora -Recurse -Force
    Repor; LimparDados

    Write-Host "`n[21] Sem chamada a ferramentas externas de tradução"
    $codigo = [IO.File]::ReadAllText($SCRIPT)
    $a = Rodar 'Status' (J @(('-Sem' + 'Cla' + 'ude')))
    Conferir ($a.Codigo -ne 0 -or $a.Saida -match 'parameter|parâmetro') 'parâmetro antigo não existe mais'
    Conferir (-not ($codigo -match 'Start-Job|Invoke-WebRequest|Invoke-RestMethod|DownloadString|Net\.WebClient')) 'script não baixa nada nem abre tarefa em segundo plano'
} finally {
    Set-Location -LiteralPath $RAIZ
    Get-ChildItem -LiteralPath $LAB -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.IsReadOnly } | ForEach-Object { $_.IsReadOnly = $false }
    Remove-Item -LiteralPath $LAB -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:falhas -eq 0) { Write-Host "TODOS OS $($script:total) TESTES PASSARAM em $SHELL_ATUAL" -ForegroundColor Green }
else { Write-Host "$($script:falhas) FALHA(S) de $($script:total) em $SHELL_ATUAL" -ForegroundColor Red }
exit $script:falhas
