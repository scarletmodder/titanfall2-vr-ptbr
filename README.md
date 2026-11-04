# Titanfall 2 VR em português do Brasil

Tradução para PT-BR dos textos do mod Titanfall 2 VR, sem redistribuir nada do mod nem do jogo. Você baixa um executável pequeno, ele encontra o mod já instalado no seu computador e troca só os textos em inglês. Uma opção do mesmo programa devolve os arquivos originais, idênticos byte a byte.

## O que muda

O mod coloca o jogo em realidade virtual e acrescenta textos próprios, todos em inglês. O jogo base continua com a dublagem e as legendas oficiais: a ferramenta não toca nele.

**Antes:** o menu de configurações de VR, os avisos de interação, as dicas do tutorial, o botão de equipamento do Titã, o aviso de melhores momentos e as escolhas de diálogo do mod aparecem em inglês.

**Depois:** os mesmos textos aparecem em português, dizendo qual botão apertar e onde. Por exemplo: "Segure o grip no quadril esquerdo para sacar a segunda arma".

Para a versão 1.0.25 do mod são 196 textos traduzidos e nenhum pendente.

## Requisitos

- Windows 10 ou 11.
- Titanfall 2 instalado (Steam, EA app, Origin ou Xbox).
- O mod instalado pelo [instalador oficial do CircuitLord](https://github.com/CircuitLord/CircuitLordVRModInstaller). A tradução foi conferida contra o mod 1.0.25.

Este repositório e a release não contêm arquivos do jogo nem do mod. Sem o mod instalado, a ferramenta não tem o que traduzir.

## Instalar

1. Baixe `Titanfall2VR-PTBR.exe` (ou o zip, que traz o mesmo executável e a licença) na página [Releases](https://github.com/scarletmodder/titanfall2-vr-ptbr/releases).
2. Feche o jogo.
3. Dê dois cliques no executável e escolha `[1] Traduzir para português`.

Na primeira vez, a ferramenta procura o jogo sozinha. Se não achar, ela pede para você colar o caminho da pasta que tem o `Titanfall2.exe`. A escolha fica salva.

**Se você usou o pacote antigo "Titanfall 2 VR em Português":** desinstale esse pacote antes. Ele altera os mesmos arquivos e guarda as próprias cópias, e a ferramenta recusa traduzir enquanto ele estiver lá, para não salvar um arquivo já traduzido como se fosse o original.

## Atualizar

O instalador do mod troca os arquivos a cada atualização, e a tradução some. Rode a opção `[1]` de novo. Se nada mudou, a ferramenta avisa que está tudo atualizado e não mexe em nada.

Se a atualização trouxer texto novo, ele fica em inglês, o resto continua traduzido e a ferramenta mostra um texto pronto para colar, só com chave e hash de cada pendência. Nesse caso, [abra uma issue](https://github.com/scarletmodder/titanfall2-vr-ptbr/issues) com esse texto, para a tradução entrar na próxima versão.

## Voltar para o inglês

Abra o executável e escolha `[2] Voltar aos textos originais`. Os arquivos voltam a ser exatamente os que estavam antes da tradução.

## Segurança

- **O Windows pode avisar que o arquivo é desconhecido.** O executável não tem assinatura digital, que é paga. Em "Mais informações", você pode escolher "Executar assim mesmo", ou preferir compilar pelo código, com o `scripts\build.ps1`.
- **Confira o arquivo.** Cada release traz o `SHA256SUMS.txt`, e o hash também está nas notas da release. No PowerShell: `Get-FileHash .\Titanfall2VR-PTBR.exe -Algorithm SHA256`.
- **Sem internet.** A ferramenta não baixa nada nem envia nada.
- **Só os textos do mod.** Ela grava em uma lista curta de arquivos de texto do próprio mod, nunca no jogo base. Antes, guarda uma cópia do original.
- **Sem pedir administrador à toa.** O programa abre como usuário comum. Só se o Windows negar a gravação na pasta do jogo é que o aviso aparece, e você pode recusar. Ele mostra o nome `Titanfall2VR-PTBR.exe`, com editor desconhecido, porque o programa não tem assinatura digital.
- **O que roda como administrador.** Se você aceitar, o próprio executável se reabre elevado, extrai o script e o dicionário numa pasta nova em `%ProgramData%\ScarletModder`, em que só administradores gravam, confere o hash de cada arquivo com o que está embutido no exe, roda dali e apaga a pasta ao final. Nada da sua pasta de usuário é executado como administrador. O backup e o estado desse caso ficam em `%ProgramData%\ScarletModder\Titanfall2VR-PTBR`. Vale conferir o hash do exe antes de aceitar, porque ele fica numa pasta que qualquer programa seu consegue alterar.
- **Backup conferido.** Antes de usar o backup, a ferramenta compara o hash dele com o registrado na criação. Se não bater, ela não grava nada.
- **Nunca grava com o jogo aberto.** Se a gravação falhar por erro, os arquivos voltam ao estado de antes daquela execução. Se a janela for fechada no meio, rode a opção `[1]` ou `[2]` de novo: a ferramenta reconhece o que ficou pela metade, limpa os temporários e termina o trabalho ou devolve o original.

O programa extrai o script e o dicionário em `%LOCALAPPDATA%\ScarletModder\Titanfall2VR-PTBR` e guarda ali a pasta do jogo escolhida e o backup. Para começar do zero, use antes a opção `[2]` e só depois apague essa pasta. Apagar com o jogo traduzido perde a cópia do original, e aí só reinstalando o mod.

## Limitações conhecidas

- **Acentos em texto de interface do jogo não foram confirmados dentro do jogo.** Os testes conferem os arquivos, não o que aparece no headset. Se um acento sair errado, abra uma issue.
- **A tradução ainda não foi testada dentro do jogo nesta versão.** Texto cortado ou fora de lugar só aparece lá.
- Alguns nomes de habilidade e o rótulo "Reiniciar Desafio" não foram comparados com a tradução oficial do jogo.
- A ferramenta só encontra texto novo nos scripts que já conhece. Um script novo do mod, fora dessa lista, continua em inglês sem aparecer nas pendências. O script do menu principal é quase todo código do jogo base: ali só as linhas conhecidas são aplicadas, sem procurar texto novo.
- O aviso real de administrador do Windows não é coberto pelos testes automáticos, que simulam esse passo.
- Backup e estado têm um espaço só. Com duas instalações do jogo, restaure os originais numa antes de traduzir a outra; a ferramenta recusa o contrário. Também recusa alvo com junction ou link simbólico no caminho dentro da pasta do jogo.
- O hash do executável muda a cada compilação, porque o compilador grava um identificador aleatório. Compare com o `SHA256SUMS.txt` da mesma release.

## Problemas comuns

- **"O Windows não deixou gravar":** aceite o pedido de administrador que aparece em seguida. Se nem assim der, veja se o arquivo está marcado como "Somente leitura".
- **"O arquivo está aberto em outro programa":** espere o EA app, a Steam ou o instalador do mod terminarem de verificar ou atualizar o jogo.
- **"O mod não está instalado nesta pasta":** use a opção `[3]` e escolha a pasta certa, ou instale o mod antes.
- **Texto cortado ou estranho no jogo:** use a opção `[2]` e abra uma issue contando em qual tela apareceu.

## Como funciona

O dicionário não contém o texto do mod. Ele guarda o SHA-256 de cada texto em inglês, as chaves dos textos e a tradução escrita aqui. A única palavra igual à do mod é `SMAA`, nome técnico que não se traduz. Os nomes internos do código, quando a tradução precisa deles, são lidos do arquivo do mod em tempo de execução. No seu computador, a ferramenta lê a linha real do mod, confere o hash e troca só os textos entre aspas, mantendo o código da linha. Se o hash não bater, a linha fica em inglês. As regras de tradução estão em [`ferramenta/traducao/REGRAS.md`](ferramenta/traducao/REGRAS.md) e o processo para contribuir, em [`CONTRIBUTING.md`](CONTRIBUTING.md).

Para rodar os testes, que usam um mod sintético inventado para isso:

```powershell
powershell -File tests\testar.ps1
pwsh -File tests\testar.ps1
```

## Créditos e aviso

Tradução e ferramenta por Scarlet Modder, sob a licença [MIT](LICENSE), que cobre só o código e o texto deste repositório.

Este é um projeto de fã, sem nenhum vínculo com a Electronic Arts, a Respawn Entertainment ou o CircuitLord, e sem o apoio deles. Titanfall é marca de seus respectivos donos. O mod Titanfall 2 VR é do CircuitLord, tem código fechado e não é redistribuído aqui: instale pelo [instalador oficial](https://github.com/CircuitLord/CircuitLordVRModInstaller).
