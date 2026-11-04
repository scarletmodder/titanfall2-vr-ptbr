# Regras do dicionário PT-BR (Titanfall 2 VR)

Fonte única das regras de tradução. Os exemplos abaixo foram inventados: nenhuma frase do mod entra neste repositório.

## O que nunca entra

O mod tem código fechado. O dicionário não guarda o texto em inglês nem a linha de script: só o SHA-256 dela, as chaves dos textos e o que foi escrito para a tradução. A ferramenta recusa qualquer entrada com o campo `en`, e `scripts\verificar_dicionario.py` recusa tradução igual ao inglês, fora de nome técnico da lista dele (hoje, `SMAA`).

Texto novo do mod não é traduzido sozinho. Ele fica em inglês, entra na lista de pendências e alguém escreve a entrada seguindo estas regras.

## Formato

Em `tokens.json`, cada token:

```json
{ "chave": "XT_LIGAR", "enHash": "<SHA-256 do texto em inglês>", "pt": "Ativar fluxo" }
```

Nos outros `.json`, um por script `.nut` do mod, cada linha:

```json
{ "enHash": "<SHA-256 da linha inteira, sem recuo>", "textos": ["Aperte a ", " para virar o quark"] }
```

- `enHash` é o SHA-256, em hexadecimal minúsculo, do texto em UTF-8. Na linha de script, vale a linha sem o recuo do início e sem espaço no fim.
- `textos` traz os literais entre aspas da linha, na ordem em que aparecem. A ferramenta lê a linha real, confere o hash e troca só o que está entre aspas, mantendo o código.
- Nem tudo entre aspas é texto. Nome interno passado para função, comparado ou usado como índice é código: use `null` na posição dele, e o literal real fica como está. Assim o nome interno também não precisa ser copiado para cá. A ferramenta recusa a linha se um nome desses mudar.
- Quantidade errada de literais, aspas dentro do texto ou quebra de linha real fazem a entrada virar pendência. Quando o original tem `\n` escrito, mantenha `\n` escrito (no JSON aparece como `\\n`).
- Os campos de topo `arquivo`, `nome` e `varrer` são de quem mantém a ferramenta. `varrer: false` faz a ferramenta só aplicar as linhas conhecidas daquele script, sem procurar textos novos.

### Linha que muda a estrutura (`molde`)

Quando a tradução precisa de mais do que trocar literais, como um ternário que converte o nome interno de um gesto em palavra, a entrada usa `molde` em vez de `textos`:

```json
{ "enHash": "<SHA-256 da linha>", "molde": "{0} \"Mova a mão \" + ( {1} == {=<SHA-256 de norte>} ? \"para o norte\" : {1} ) + {2}" }
```

`{0}`, `{1}` e assim por diante são os trechos de código entre os literais da linha real, sem espaços nas pontas e sem o `+` das bordas. `{=hash}` é um nome interno do mod, achado no próprio arquivo pelo SHA-256 e escrito com as aspas. O molde guarda só o que foi escrito para a tradução, e a ferramenta remonta a linha com o código lido do mod. Se o nome não existir no arquivo, a linha fica em inglês e vira pendência. Fora das aspas, só podem aparecer esses trechos e os operadores `+ ( ) ? : =`, e todo trecho não vazio precisa ser usado. Comparação com nome interno em claro é recusada. Qualquer outra coisa é recusada, para o dicionário não conseguir chamar código novo.

### Quando o mod muda

- Token com texto alterado: atualize o `enHash` e o `pt` da entrada com a mesma chave.
- Linha com texto alterado: acrescente uma entrada com o hash novo e deixe a antiga, que só deixa de ser usada.

A lista `pendentes.json`, na pasta de dados da ferramenta, traz a chave ou o número da linha e o `enHash` de cada pendência, sem o texto.

## Texto

- Idênticos e na mesma quantidade: variáveis como `%use%`, `%s1` e `%$rui/...%`, o separador `||`, `\n` escrito e referências `#TOKEN`. A ferramenta recusa a tradução que perder algum.
- "Aperte" para apertar e soltar. "Segure" para manter apertado, inclusive o grip para sacar arma.
- Dizer sempre qual botão e onde: "Segure o grip no quadril esquerdo para sacar a segunda arma".
- Tratar quem joga por "você".
- Tamanho: até cerca de 1,4 vez o inglês nos textos com mais de 40 caracteres. Texto flutuante no VR quebra ou é cortado. Botões de menu: o mais curto possível.
- Português do Brasil natural, frase curta, sem travessão nem meia-risca.

## Termos

| Inglês | PT-BR | Nota |
|---|---|---|
| Titan | Titã | oficial |
| Pilot | Piloto | oficial |
| Gauntlet | Desafio | oficial |
| Ark | Arca | oficial |
| loadout | equipamento | oficial |
| cloak | camuflar | oficial |
| Arc Tool | Chave Voltaica | certeza média |
| Rodeo | Rodeio (nome); "montar no Titã" na ação | "fazer Rodeio" confundiu no teste cego |
| Fastball | Fastball (nome); "ser arremessado" na ação | |
| embark / disembark | embarcar / desembarcar | |
| highlights | melhores momentos | |
| grip | grip | termo usado por quem joga VR no Brasil |
| Stalker, Prowler, Spectre | em inglês | nomes |

## Já deram problema no teste cego

"pegue no quadril" (duplo sentido), "em saltos" (salto alto), "vinheta" (jingle de TV), "pulso" (pulso de energia), "ângulo do salto" (parece pulo), "clique o analógico" (é "aperte").
