# Synthetic mod and dictionary for the tests. All text here was invented for the test: no phrase
# from the real mod enters this repository. The file names are the ones the tool accepts as targets.

$script:UTF8 = New-Object Text.UTF8Encoding($false)
$script:UTF16 = New-Object Text.UnicodeEncoding($false, $true)
$script:VS = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\scripts\vscripts'
$script:TOK = 'TF2VR\mods\Titanfall2VR.Cockpit\mod\resource\tf2vr_english.txt'
$script:NUT = "$($script:VS)\test_hints.nut"
$script:PANEL = "$($script:VS)\ui\test_panel.nut"
$script:REG = '.circuitlord-vr-mods\Titanfall2VR.json'
$script:ALL_FILES = @($script:TOK, $script:NUT, $script:PANEL)

function Sha([string]$t) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($script:UTF8.GetBytes($t)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Write-TestFile($path, $text, $encoding) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, $text, $encoding)
}

function Get-TokensText { return @'
"lang"
{
    "Language" "English"
    "Tokens"
    {
        "XT_TITLE" "ZORBLAT PANEL"
        "XT_ENGAGE" "Engage flux"
        "XT_HOLD" "Keep %use% down near the quark hatch"
        "XT_DOUBLE" "Keep %use% for red quarks||Keep %use% for blue quarks"
        "XT_ICON" "%$vgui/test_icon%"
        "XT_EMPTY" ""
        "XT_SPACE" " "
    }
}
'@ -replace "`r?`n", "`r`n" }

function Get-NutLines { return @(
    'global function Test_Text'
    ''
    '// comment with "Words here" that is not text'
    'array<string> function Test_Gestures()'
    '{'
    '	return [ "north", "south" ]'
    '}'
    ''
    'string function Test_Text( int hand, bool touch )'
    '{'
    '	string lever = hand == 0 ? "quark lever" : "muon lever"'
    '	Test_Label( Test_Child( panel, "MainLabel" ), "NORTHWARD" )'
    '	Test_Command( "test_internal_command" )'
    '	if ( Test_Gestures()[hand] == "north" )'
    '		return "Tap " + lever + " to flip the quark"'
    '	return "Sweep hand " + Test_Gestures()[hand] + " for " + Localize( hint.name )'
    '	return "Zorblat is empty"'
    '	return hint'
    '}'
) }

function Get-PanelLines { return @(
    'void function Test_Panel()'
    '{'
    '	buttons.append( { name = "OPEN ZORBLAT VAULT", activate = Test_Open } )'
    '	Test_Other( "Other words that are never scanned" )'
    '}'
) }

function Build-Mod($dir, [string]$version = '9.9.1') {
    Write-TestFile (Join-Path $dir 'Titanfall2.exe') '' $script:UTF8
    Write-TestFile (Join-Path $dir $script:REG) ("{`"version`":`"$version`",`"files`":[]}") $script:UTF8
    Write-TestFile (Join-Path $dir $script:TOK) (Get-TokensText) $script:UTF16
    Write-TestFile (Join-Path $dir $script:NUT) ((Get-NutLines) -join "`r`n") $script:UTF8
    Write-TestFile (Join-Path $dir $script:PANEL) ((Get-PanelLines) -join "`n") $script:UTF8
}

function Write-TestJson($path, $object) {
    Write-TestFile $path ($object | ConvertTo-Json -Depth 8) $script:UTF8
}

# Dictionary for the mod above, with hashes computed from the invented lines.
function Build-Dictionary($dir) {
    $tokens = @(
        @{ key = 'XT_TITLE'; enHash = (Sha 'ZORBLAT PANEL'); pt = 'PAINEL ZORBLAT' }
        @{ key = 'XT_ENGAGE'; enHash = (Sha 'Engage flux'); pt = 'Ativar fluxo' }
        @{ key = 'XT_HOLD'; enHash = (Sha 'Keep %use% down near the quark hatch'); pt = 'Segure %use% perto da escotilha de quark' }
        @{ key = 'XT_DOUBLE'; enHash = (Sha 'Keep %use% for red quarks||Keep %use% for blue quarks'); pt = 'Segure %use% para quarks vermelhos||Segure %use% para quarks azuis' }
    )
    Write-TestJson (Join-Path $dir 'tokens.json') ([pscustomobject]@{ file = $script:TOK; name = 'menus de teste'; tokens = $tokens })
    $lines = @(
        [pscustomobject]@{ enHash = (Sha 'string lever = hand == 0 ? "quark lever" : "muon lever"'); texts = @('alavanca de quark', 'alavanca de múon') }
        [pscustomobject]@{ enHash = (Sha 'Test_Label( Test_Child( panel, "MainLabel" ), "NORTHWARD" )'); texts = @($null, 'NORTE') }
        [pscustomobject]@{ enHash = (Sha 'return "Tap " + lever + " to flip the quark"'); texts = @('Aperte a ', ' para virar o quark') }
        [pscustomobject]@{ enHash = (Sha 'return "Sweep hand " + Test_Gestures()[hand] + " for " + Localize( hint.name )'); template = ('{0} "Mova a mão " + ( {1} == {=' + (Sha 'north') + '} ? "para o norte" : ( {1} == {=' + (Sha 'south') + '} ? "para o sul" : {1} ) ) + ": " + {2}') }
        [pscustomobject]@{ enHash = (Sha 'return "Zorblat is empty"'); texts = @('O Zorblat está vazio') }
    )
    Write-TestJson (Join-Path $dir 'hints.json') ([pscustomobject]@{ file = $script:NUT; name = 'dicas de teste'; lines = $lines })
    $panel = @([pscustomobject]@{ enHash = (Sha 'buttons.append( { name = "OPEN ZORBLAT VAULT", activate = Test_Open } )'); texts = @('ABRIR COFRE ZORBLAT') })
    Write-TestJson (Join-Path $dir 'panel.json') ([pscustomobject]@{ file = $script:PANEL; name = 'painel de teste'; scan = $false; lines = $panel })
}
