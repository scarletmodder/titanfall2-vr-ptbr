<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/banner-dark.svg">
  <img alt="Tradução PT-BR do mod Titanfall 2 VR" src="docs/images/banner-light.svg" width="720">
</picture>

# 🎮 Tradução PT-BR do mod Titanfall 2 VR

**Os textos do mod Titanfall 2 VR em português do Brasil. Não inclui o jogo nem o mod: você baixa o instalador, clica em Avançar e a tradução entra sozinha.**

[![CI](https://img.shields.io/github/actions/workflow/status/scarletmodder/titanfall2-vr-ptbr/ci.yml?branch=main&label=CI&logo=githubactions&logoColor=white&style=flat)](https://github.com/scarletmodder/titanfall2-vr-ptbr/actions)
[![Versão](https://img.shields.io/github/v/release/scarletmodder/titanfall2-vr-ptbr?label=vers%C3%A3o&logo=github&style=flat)](https://github.com/scarletmodder/titanfall2-vr-ptbr/releases)
[![Licença](https://img.shields.io/badge/licen%C3%A7a-MIT-blue?logo=opensourceinitiative&logoColor=white&style=flat)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20e%207-5391FE?logo=powershell&logoColor=white&style=flat)](tool/titanfall-ptbr.ps1)
[![C#](https://img.shields.io/badge/C%23-.NET%20Framework-512BD4?logo=dotnet&logoColor=white&style=flat)](src/Launcher.cs)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white&style=flat)](scripts/guard.py)
[![Plataforma](https://img.shields.io/badge/plataforma-Windows-lightgrey?style=flat)](docs/installation.md)
[![Idioma](https://img.shields.io/badge/idioma-pt--BR-informational?style=flat)](tool/translations/RULES.md)
[![Mod](https://img.shields.io/badge/mod%20VR-1.0.25%20conferido-informational?style=flat)](https://github.com/CircuitLord/CircuitLordVRModInstaller)

[Como instalar](#-como-instalar) · [Guia completo](docs/installation.md) · [Baixar](https://github.com/scarletmodder/titanfall2-vr-ptbr/releases/latest) · [Changelog](CHANGELOG.md)

<img alt="Tela de boas-vindas do instalador da tradução" src="docs/images/installer-1-welcome.png" width="560">

</div>

**Neste documento:** [Como instalar](#-como-instalar) · [Por que existe](#-por-que-existe) · [O que muda](#-o-que-muda) · [Uso](#-uso) · [Segurança](#-segurança-e-privacidade) · [Como funciona](#%EF%B8%8F-como-funciona) · [Problemas comuns](#-problemas-comuns) · [Estado](#%EF%B8%8F-estado-atual)

## 🚀 Como instalar

Você precisa do Titanfall 2 com o [mod VR do CircuitLord](https://github.com/CircuitLord/CircuitLordVRModInstaller) já instalado. Este instalador coloca só a tradução. Depois:

1. **Baixe** o `Instalador-Traducao-PTBR-Mod-Titanfall2VR-v<versão>.exe` na [página de downloads](https://github.com/scarletmodder/titanfall2-vr-ptbr/releases/latest).
2. **Feche o jogo** e abra o arquivo baixado com dois cliques.
3. **Clique em Avançar**, confira a pasta do jogo e clique em **Instalar**. Na última tela, a mensagem é "A tradução foi aplicada. Pode abrir o jogo."

| 1. Boas-vindas | 2. Pasta do jogo |
|---|---|
| <img alt="Tela de boas-vindas do instalador" src="docs/images/installer-1-welcome.png" width="400"> | <img alt="Tela Pasta do jogo, com um caminho de exemplo" src="docs/images/installer-2-game-folder.png" width="400"> |
| **3. Pronto para instalar** | **4. Concluído** |
| <img alt="Tela Pronto pra Instalar, com um caminho de exemplo" src="docs/images/installer-3-ready.png" width="400"> | <img alt="Tela final: a tradução foi aplicada" src="docs/images/installer-4-finished.png" width="400"> |

A pasta que aparece nas capturas é um exemplo. Na sua máquina, o instalador procura o jogo sozinho e você pode trocar a pasta.

Para voltar ao inglês, desinstale "Tradução PT-BR do mod Titanfall 2 VR" pela lista de aplicativos do Windows.

> [!TIP]
> O passo a passo com cada mensagem, a desinstalação e a lista de problemas estão no [guia de instalação](docs/installation.md).

## 🎯 Por que existe

Em VR, o que o mod escreve na tela é o que ensina qual botão apertar e onde: o menu de configurações, os avisos de interação, as dicas do tutorial, o botão de equipamento do Titã e as escolhas de diálogo. Tudo isso vem em inglês. Fiz esta tradução porque acredito que podemos jogar em português sem redistribuir nada do mod nem do jogo.

Ela faz parte do ecossistema do [mod Titanfall 2 VR do CircuitLord](https://github.com/CircuitLord/CircuitLordVRModInstaller), que precisa estar instalado antes. Este é um projeto de fã, sem vínculo com o autor do mod, com a EA ou com a Respawn.

Para você, o ganho é direto: um instalador pequeno acha o mod e troca só os textos em inglês. Ao desinstalar, os originais voltam idênticos byte a byte.

Para a versão 1.0.25 do mod são **196 textos traduzidos e nenhum pendente**, conferidos no mod instalado. Cada arquivo publicado tem o hash (a impressão digital do arquivo) no `SHA256SUMS.txt` da release.

## ✨ O que muda

A ferramenta nunca toca no jogo base. Só os textos do mod mudam.

**Antes:** o menu de configurações de VR, os avisos de interação, as dicas do tutorial, o botão de equipamento do Titã e as escolhas de diálogo aparecem em inglês.

**Depois:** os mesmos textos aparecem em português, dizendo qual botão apertar e onde. Um exemplo escrito no projeto: "Segure o grip no quadril esquerdo para sacar a segunda arma".

**Traduzir**<br/>
Troca os textos em inglês dos arquivos do mod pela tradução, depois de guardar uma cópia do original. ✅ pronto

**Voltar ao inglês**<br/>
Devolve os arquivos exatamente como estavam antes da tradução. ✅ pronto

**Atualizar com o mod**<br/>
O instalador do mod desfaz a tradução a cada atualização. Abra "Tradução PT-BR do mod Titanfall 2 VR" no menu Iniciar e escolha a opção `[1]`: se nada mudou, a ferramenta avisa e não grava nada. ✅ pronto

**Desinstalar pela lista de aplicativos**<br/>
O instalador cria a entrada "Tradução PT-BR do mod Titanfall 2 VR" na lista do Windows. Desinstalar por lá devolve os originais e apaga os dados da ferramenta. ✅ pronto (a desinstalação foi conferida abrindo o desinstalador direto; o clique pela página de aplicativos do Windows ainda não)

**Dicionário sem texto do mod**<br/>
Ele guarda só o hash do texto em inglês e a tradução. A linha real vem do mod instalado no seu computador. ✅ pronto

## 🧭 Uso

| Eu quero | O que faço | O que acontece |
|---|---|---|
| Traduzir | Rodo o instalador até o fim | O mod fica em português e o original vai para um backup |
| Voltar ao inglês | Abro o programa no menu Iniciar e escolho `[2] Voltar aos textos originais (inglês)` | Os arquivos voltam byte a byte ao que eram |
| Trocar a pasta do jogo | No programa, escolho `[3] Trocar a pasta do jogo` | O programa procura de novo ou pede a pasta com o `Titanfall2.exe` |
| Atualizar depois do mod | No programa, escolho `[1]` de novo | Se nada mudou, aparece "Tudo atualizado" e nada é gravado |
| Remover tudo | Configurações do Windows, Aplicativos, Aplicativos instalados | Os originais voltam e os dados da ferramenta são apagados |

Se o mod atualizar e trouxer texto novo, esse texto fica em inglês e o resto continua traduzido. O programa mostra uma lista pronta para colar numa [issue](https://github.com/scarletmodder/titanfall2-vr-ptbr/issues) (um aviso aberto no GitHub), só com chave e hash, sem texto do mod.

## 🔒 Segurança e privacidade

- **Sem internet.** O programa não baixa nem envia nada.
- **Só os textos do mod.** Ele grava em cinco arquivos de texto do próprio mod, nunca no jogo base, e antes guarda uma cópia do original.
- **Backup conferido.** Antes de usar o backup, o programa compara o hash dele com o registrado na criação. Se não bater, não grava.
- **Nunca grava com o jogo aberto.** Se a gravação falhar, os arquivos voltam ao estado de antes daquela execução.
- **Sem pedir administrador para instalar.** O instalador grava só na sua pasta de usuário. Se o Windows pedir essa permissão para gravar na pasta do jogo, a escolha é sua, e recusar não altera nada.
- **Instalador sem assinatura digital.** O Windows pode avisar que o arquivo é desconhecido. Você pode conferir o hash do arquivo ou compilar pelo código com `scripts\build.ps1`. Veja [como conferir](docs/installation.md#2-conferir-o-arquivo-opcional).
- **Antivírus.** Alguns antivírus podem alertar por ser um executável sem assinatura digital, de projeto aberto. É um falso positivo. Veja [o que fazer nesse caso](docs/installation.md#%EF%B8%8F-alerta-do-antivírus).

## 🏗️ Como funciona

O instalador coloca um programa pequeno na sua pasta de usuário e o roda para aplicar a tradução. Esse programa carrega dentro de si a ferramenta em PowerShell e o dicionário, roda no seu computador, não fala com servidor nenhum e só mexe nos arquivos de texto do mod.

**Contexto: com quem o programa conversa no seu computador.**

```mermaid
flowchart TB
    classDef person    fill:#08427b,stroke:#052e56,color:#ffffff
    classDef system    fill:#1168bd,stroke:#0b4884,color:#ffffff
    classDef container fill:#438dd5,stroke:#2e6295,color:#ffffff
    classDef store     fill:#00838f,stroke:#005f66,color:#ffffff
    classDef external  fill:#8a8a8a,stroke:#6b6b6b,color:#ffffff
    classDef optional  fill:#8a8a8a,stroke:#6b6b6b,color:#ffffff,stroke-dasharray:5 5

    pessoa["Quem joga<br/>escolhe no menu"]:::person
    instalador["CircuitLord VR Mod Installer<br/>instala e atualiza o mod"]:::external
    issues["Issues no GitHub<br/>a pessoa cola as pendências"]:::optional

    subgraph pc["Computador de quem joga"]
        setup["Instalador<br/>Inno Setup"]:::system
        exe["Titanfall2VR-PTBR.exe<br/>C#, .NET Framework"]:::system
        script["Ferramenta e dicionário<br/>PowerShell, extraídos do exe"]:::container
        uac["Aviso de administrador<br/>Windows"]:::external
        fontes["Fontes de detecção<br/>registro e libraryfolders.vdf"]:::external
        dados["Dados comuns<br/>%LOCALAPPDATA%\ScarletModder"]:::store
        admin["Dados de administrador<br/>%ProgramData%\ScarletModder"]:::store
        mod["Cinco arquivos de texto do mod<br/>pasta do jogo"]:::external
    end

    pessoa -->|"instala e desinstala"| setup
    setup -->|"coloca e roda"| exe
    pessoa -->|"abre pelo menu Iniciar"| exe
    exe -->|"extrai e roda"| script
    exe -->|"só se o script pedir"| uac
    uac -->|"aceite reabre o exe elevado"| exe
    exe -->|"cópia conferida em run-guid"| admin
    script -->|"lê"| fontes
    script -->|"config, estado, backup"| dados
    script -->|"caso elevado"| admin
    script -->|"traduz ou restaura"| mod
    instalador -.->|"troca os arquivos (inferida)"| mod
    pessoa -.->|"manual, só chave e hash"| issues
```

As linhas tracejadas marcam o que o código não controla: a ação manual de abrir uma issue e o que o instalador do mod faz, que se infere porque ele tem código fechado.

<details>
<summary>Sequência da opção Traduzir e estados de um arquivo do mod</summary>

**Sequência: o que acontece, em ordem, quando a tradução é aplicada, pelo instalador ou pela opção 1 do programa.**

```mermaid
sequenceDiagram
    autonumber
    actor P as Quem joga
    participant E as Exe comum
    participant S as Ferramenta<br/>PowerShell
    participant D as Dados comuns<br/>%LOCALAPPDATA%
    participant M as Arquivos do mod
    participant U as Aviso do Windows
    participant X as Exe elevado
    participant A as Dados de admin<br/>%ProgramData%

    rect rgba(67,141,213,0.12)
        P->>E: Abre o exe
        E->>D: Extrai script e dicionário, conferindo SHA-256
        E->>S: Roda no Windows PowerShell
        S->>D: Lê a pasta salva ou procura o jogo
        S-->>P: Painel e menu
        P->>S: Opção 1, Traduzir para português
    end

    rect rgba(106,61,154,0.12)
        S->>M: Mod presente, sem pacote antigo, backup desta pasta
        S->>M: Etapa 1, compara marca e hash de cada alvo
        alt Nada mudou
            S-->>P: Tudo atualizado, nada foi gravado
        else Há arquivo para traduzir
            S->>M: Etapa 2, jogo fechado, sem link, teste de gravação
            alt Gravação liberada
                S->>S: Etapa 3, traduz e valida em memória
                S->>D: Etapa 4, guarda o original e confere o hash
                S->>M: Etapa 5, grava em lote, desfaz se falhar
                S->>D: Grava estado e pendências
                S-->>P: Tradução aplicada
            else Windows nega ou dados são de admin
                S->>D: Grava o pedido de permissão
                S-->>E: Sai com o código 20
                E->>U: Reabre o exe como administrador
                alt Pessoa recusa
                    U-->>E: Cancelado
                    E-->>P: Permissão recusada, nada foi alterado
                else Pessoa aceita
                    U->>X: Inicia o exe elevado
                    X->>A: Extrai em run-guid e confere cada hash
                    X->>A: Roda a cópia conferida, etapas 1 a 5
                    X->>M: Grava a tradução em lote
                    X->>A: Apaga run-guid
                    X-->>P: Tradução aplicada, Enter para seguir
                end
            end
        end
    end

    rect rgba(46,125,50,0.12)
        E-->>P: Volta ao menu ou encerra com o código do resultado
    end
```

**Estados: por onde cada um dos cinco arquivos de texto do mod passa.**

```mermaid
stateDiagram-v2
    direction TB

    classDef external  fill:#8a8a8a,stroke:#6b6b6b,color:#ffffff
    classDef optional  fill:#8a8a8a,stroke:#6b6b6b,color:#ffffff,stroke-dasharray:5 5
    classDef component fill:#85bbf0,stroke:#5d82a8,color:#000000
    classDef ok        fill:#2e7d32,stroke:#1b5e20,color:#ffffff
    classDef warn      fill:#f9a825,stroke:#c17900,color:#000000
    classDef bad       fill:#c0392b,stroke:#922b21,color:#ffffff

    state "Ausente<br/>não existe nesta versão do mod" as Ausente
    state "Original<br/>em inglês, sem marca" as Original
    state "Original com backup guardado<br/>etapa 4 concluída" as ComBackup
    state "Traduzido com backup conferido<br/>marca e hash batem" as Traduzido
    state "Traduzido, dicionário novo<br/>exe de outra versão" as DicNovo
    state "Traduzido, mexido fora<br/>marca presente, hash diferente" as MexidoFora
    state "Restaurado<br/>bytes do backup, backup continua" as Restaurado
    state "Bloqueado<br/>backup sumiu ou não confere" as Bloqueado

    [*] --> Original: mod instalado
    [*] --> Ausente: mod sem esse arquivo
    Ausente --> Original: mod passa a ter o arquivo
    Original --> ComBackup: opção 1, etapa 4
    ComBackup --> Traduzido: etapa 5, lote gravado
    ComBackup --> Original: lote falha e é desfeito
    Traduzido --> DicNovo: dicionário muda
    Traduzido --> MexidoFora: arquivo muda fora da ferramenta
    DicNovo --> Traduzido: opção 1, retraduz do backup
    MexidoFora --> Traduzido: opção 1, retraduz do backup
    Traduzido --> Restaurado: opção 2
    DicNovo --> Restaurado: opção 2
    MexidoFora --> Restaurado: opção 2
    Restaurado --> ComBackup: opção 1, etapa 4
    Traduzido --> Original: instalador troca o arquivo (inferida)
    Traduzido --> Bloqueado: backup apagado ou alterado
    Bloqueado --> Original: reinstalar o mod (inferida)

    class Ausente optional
    class Original external
    class ComBackup component
    class Traduzido ok
    class Restaurado ok
    class DicNovo warn
    class MexidoFora warn
    class Bloqueado bad
```

As duas transições marcadas "(inferida)" dependem do instalador do mod, que tem código fechado.

</details>

Para quem contribui: as regras do dicionário estão em [tool/translations/RULES.md](tool/translations/RULES.md) e o processo, em [CONTRIBUTING.md](CONTRIBUTING.md).

## 🩺 Problemas comuns

| Sintoma na tela | Causa provável | O que fazer |
|---|---|---|
| `O Titanfall 2 está aberto.` | O jogo está rodando | Feche o jogo e tente de novo |
| `O mod Titanfall 2 VR não está instalado nesta pasta.` | A pasta escolhida não tem o mod | Escolha `[3]` e indique a pasta certa, ou instale o mod antes |
| `Este jogo tem um pacote antigo de tradução instalado ("Titanfall 2 VR em Português").` | O pacote antigo altera os mesmos arquivos | Desinstale em Configurações do Windows, Aplicativos, e rode de novo |
| `O arquivo ... está aberto em outro programa.` | O EA app, a Steam ou o instalador do mod estão verificando o jogo | Espere terminarem e tente de novo |
| `Nem como administrador o Windows deixou gravar em ...` | O arquivo está marcado como somente leitura | Botão direito no arquivo, Propriedades, desmarque "Somente leitura" |
| `N texto(s) do mod ainda não têm tradução e aparecem em inglês no jogo.` | O mod atualizou e trouxe texto novo | Pode jogar. Para ajudar, cole a lista numa issue |

> [!WARNING]
> Apagar a pasta de dados da ferramenta com o jogo ainda traduzido perde a cópia do original. Use a desinstalação pela lista de aplicativos do Windows, que devolve os originais antes de apagar.

Mais casos, como a recusa de abrir de dentro de outro aplicativo, estão no [guia de instalação](docs/installation.md#-problemas-comuns).

## 🗺️ Estado atual

| Área | Estado | Como foi conferido |
|---|---|---|
| Tradução dos textos do mod 1.0.25 | ✅ pronto | 196 textos traduzidos e nenhum pendente, no mod instalado, e jogo testado no headset |
| Voltar ao inglês | ✅ pronto | O backup de cada arquivo tem hash igual ao do original, e os testes automáticos provam a restauração |
| Instalador com telas | ✅ pronto | Testes automáticos e uma instalação pelas telas num computador real, sem pedido de permissão e com os 5 arquivos traduzidos conferidos |
| Antivírus no instalador | ⚠️ medido em uma máquina | Microsoft Defender sem nenhum alerta 54 minutos depois de instalar |
| Desinstalar | ✅ pronto | Testes automáticos e uma desinstalação real, com o desinstalador aberto direto: os 5 arquivos voltaram idênticos aos originais, e programa, dados, atalho e entrada saíram |
| Tela inicial de calibração dos braços | ⚠️ continua em inglês | As frases dessa tela são uma imagem do mod, não um arquivo de texto |
| Aparência dentro do headset | ✅ pronto | Jogo testado no headset, sem problema no conteúdo em PT-BR |
| Aviso de administrador do Windows | ⚠️ só simulado | Os testes automáticos simulam o aviso |

Se algo sair errado na tela do jogo, abra uma [issue](https://github.com/scarletmodder/titanfall2-vr-ptbr/issues) dizendo em qual tela apareceu.

## 📚 Documentação

| Documento | O que tem |
|---|---|
| [Guia de instalação](docs/installation.md) | Passo a passo, desinstalação, onde ficam os dados e problemas comuns |
| [Regras do dicionário](tool/translations/RULES.md) | Como a tradução é escrita e conferida |
| [Como contribuir](CONTRIBUTING.md) | Testes, padrões e o que nunca entra |
| [Changelog](CHANGELOG.md) | O que mudou em cada versão |

## 🤝 Contribuição

Correção de tradução e aviso de texto novo são as contribuições mais úteis. Abra uma issue pelo modelo certo ([problema](.github/ISSUE_TEMPLATE/problem.md) ou [texto novo](.github/ISSUE_TEMPLATE/new-text.md)) e leia o [CONTRIBUTING.md](CONTRIBUTING.md) antes de abrir um PR. Nenhum texto do mod entra em issue, commit ou PR.

## 📄 Licença

Tradução e ferramenta por Scarlet Modder, sob a licença [MIT](LICENSE), que cobre só o código e o texto deste repositório. Titanfall é marca de seus respectivos donos. O mod Titanfall 2 VR é do CircuitLord, tem código fechado e não é redistribuído aqui.
