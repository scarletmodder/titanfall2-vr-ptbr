# Changelog

## 1.0.1

- Tradução de 196 textos da versão 1.0.25 do mod: menu de configurações de VR, inclusive as opções de vídeo, avisos de interação, dicas do tutorial, menu de pausa, escolhas de diálogo e menu principal. Jogada no headset, sem problema no conteúdo em PT-BR.
- Instalador com telas, sem pedir administrador para instalar: `Instalador-Traducao-PTBR-Mod-Titanfall2VR-v<versão>.exe`.
- O nome na lista de aplicativos e no menu Iniciar é "Tradução PT-BR do mod Titanfall 2 VR", para deixar claro que é a tradução, sem o jogo nem o mod.
- Desinstalação pela lista de aplicativos do Windows: devolve os textos originais, apaga os dados da ferramenta e a própria entrada. As caixas explicam o que fazer quando o programa ou o jogo não estão mais lá.
- Dicionário sem texto do mod: só o SHA-256 do inglês e a tradução, aplicada sobre a linha real do mod instalado.
- Texto novo fica em inglês e vira uma lista de pendências, só com chave e hash, pronta para colar numa issue.
- Backup do original, restauração idêntica byte a byte e desfazer em caso de falha no meio da gravação.
- Quando precisa de permissão, o programa se reabre elevado e roda de uma pasta nova, só de administradores, com os arquivos conferidos por hash. Recusar o aviso não apaga a mensagem da tela.
- O programa recusa rodar quando aberto de dentro de outro aplicativo que redireciona os arquivos para uma área separada, porque a desinstalação não os encontraria.
