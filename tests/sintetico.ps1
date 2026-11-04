# Mod e dicionário sintéticos para os testes. Todo texto aqui foi inventado para o teste: nenhuma frase
# do mod real entra neste repositório. Os nomes de arquivo são os que a ferramenta aceita como alvo.

$script:UTF8 = New-Object Text.UTF8Encoding($false)
$script:UTF16 = New-Object Text.UnicodeEncoding($false, $true)
$script:VS = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\scripts\vscripts'
$script:TOK = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\resource\tf2vr_english.txt'
$script:NUT = "$($script:VS)\teste_dicas.nut"
$script:PAINEL = "$($script:VS)\ui\teste_painel.nut"
$script:REG = '.circuitlord-vr-mods\Titanfall2VR.json'
$script:TODOS = @($script:TOK, $script:NUT, $script:PAINEL)

function Sha([string]$t) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($script:UTF8.GetBytes($t)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Gravar-Bytes($caminho, $texto, $cod) {
    New-Item -ItemType Directory -Force -Path (Split-Path $caminho) | Out-Null
    [IO.File]::WriteAllText($caminho, $texto, $cod)
}

function Texto-Tokens { return @'
"lang"
{
    "Language" "English"
    "Tokens"
    {
        "XT_TITULO" "ZORBLAT PANEL"
        "XT_LIGAR" "Engage flux"
        "XT_SEGURE" "Keep %use% down near the quark hatch"
        "XT_DUPLO" "Keep %use% for red quarks||Keep %use% for blue quarks"
        "XT_ICONE" "%$vgui/icone_de_teste%"
        "XT_VAZIO" ""
        "XT_ESPACO" " "
    }
}
'@ -replace "`r?`n", "`r`n" }

function Linhas-Nut { return @(
    'global function Teste_Texto'
    ''
    '// comentario com "Words here" que nao e texto'
    'array<string> function Teste_Gestos()'
    '{'
    '	return [ "norte", "sul" ]'
    '}'
    ''
    'string function Teste_Texto( int mao, bool toque )'
    '{'
    '	string alavanca = mao == 0 ? "quark lever" : "muon lever"'
    '	Teste_Rotulo( Teste_Filho( painel, "RotuloPrincipal" ), "NORTHWARD" )'
    '	Teste_Comando( "teste_comando_interno" )'
    '	if ( Teste_Gestos()[mao] == "norte" )'
    '		return "Tap " + alavanca + " to flip the quark"'
    '	return "Sweep hand " + Teste_Gestos()[mao] + " for " + Localize( hint.nome )'
    '	return "Zorblat is empty"'
    '	return hint'
    '}'
) }

function Linhas-Painel { return @(
    'void function Teste_Painel()'
    '{'
    '	botoes.append( { name = "OPEN ZORBLAT VAULT", ativar = Teste_Abrir } )'
    '	Teste_Outro( "Other words that are never scanned" )'
    '}'
) }

function Montar-Mod($pasta, [string]$versao = '9.9.1') {
    Gravar-Bytes (Join-Path $pasta 'Titanfall2.exe') '' $script:UTF8
    Gravar-Bytes (Join-Path $pasta $script:REG) ("{`"version`":`"$versao`",`"files`":[]}") $script:UTF8
    Gravar-Bytes (Join-Path $pasta $script:TOK) (Texto-Tokens) $script:UTF16
    Gravar-Bytes (Join-Path $pasta $script:NUT) ((Linhas-Nut) -join "`r`n") $script:UTF8
    Gravar-Bytes (Join-Path $pasta $script:PAINEL) ((Linhas-Painel) -join "`n") $script:UTF8
}

function Gravar-Json-Teste($caminho, $objeto) {
    Gravar-Bytes $caminho ($objeto | ConvertTo-Json -Depth 8) $script:UTF8
}

# Dicionário para o mod acima, com hash calculado a partir das linhas inventadas.
function Montar-Dicionario($pasta) {
    $tokens = @(
        @{ chave = 'XT_TITULO'; enHash = (Sha 'ZORBLAT PANEL'); pt = 'PAINEL ZORBLAT' }
        @{ chave = 'XT_LIGAR'; enHash = (Sha 'Engage flux'); pt = 'Ativar fluxo' }
        @{ chave = 'XT_SEGURE'; enHash = (Sha 'Keep %use% down near the quark hatch'); pt = 'Segure %use% perto da escotilha de quark' }
        @{ chave = 'XT_DUPLO'; enHash = (Sha 'Keep %use% for red quarks||Keep %use% for blue quarks'); pt = 'Segure %use% para quarks vermelhos||Segure %use% para quarks azuis' }
    )
    Gravar-Json-Teste (Join-Path $pasta 'tokens.json') ([pscustomobject]@{ arquivo = $script:TOK; nome = 'menus de teste'; tokens = $tokens })
    $linhas = @(
        [pscustomobject]@{ enHash = (Sha 'string alavanca = mao == 0 ? "quark lever" : "muon lever"'); textos = @('alavanca de quark', 'alavanca de múon') }
        [pscustomobject]@{ enHash = (Sha 'Teste_Rotulo( Teste_Filho( painel, "RotuloPrincipal" ), "NORTHWARD" )'); textos = @($null, 'NORTE') }
        [pscustomobject]@{ enHash = (Sha 'return "Tap " + alavanca + " to flip the quark"'); textos = @('Aperte a ', ' para virar o quark') }
        [pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Teste_Gestos()[mao] + " for " + Localize( hint.nome )'); molde = ('{0} "Mova a mão " + ( {1} == {=' + (Sha 'norte') + '} ? "para o norte" : ( {1} == {=' + (Sha 'sul') + '} ? "para o sul" : {1} ) ) + ": " + {2}') }
        [pscustomobject]@{ enHash = (Sha 'return "Zorblat is empty"'); textos = @('O Zorblat está vazio') }
    )
    Gravar-Json-Teste (Join-Path $pasta 'dicas.json') ([pscustomobject]@{ arquivo = $script:NUT; nome = 'dicas de teste'; linhas = $linhas })
    $painel = @([pscustomobject]@{ enHash = (Sha 'botoes.append( { name = "OPEN ZORBLAT VAULT", ativar = Teste_Abrir } )'); textos = @('ABRIR COFRE ZORBLAT') })
    Gravar-Json-Teste (Join-Path $pasta 'painel.json') ([pscustomobject]@{ arquivo = $script:PAINEL; nome = 'painel de teste'; varrer = $false; linhas = $painel })
}
