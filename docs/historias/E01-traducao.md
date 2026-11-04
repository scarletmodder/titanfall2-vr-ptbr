# E01 Tradução e ferramenta

## H-E01-01 Traduzir os textos do mod sem redistribuir o mod

- Estado: parcial
- Origem: 2026-11-03
- Tema: tradução

Como quem joga em VR, quero ver em português os textos que o mod mostra, para entender menus e dicas, sem que o projeto copie o mod de terceiro.

### Critérios de aceite

- [x] CA-E01-01-1 O dicionário guarda só o SHA-256 do inglês e a tradução, e entrada com o campo `en` é recusada.
- [x] CA-E01-01-2 Na linha de script, a ferramenta lê a linha real, confere o hash e troca só os literais, sem mudar nome interno.
- [x] CA-E01-01-3 A linha com ternário de gesto é aplicada por `molde`, que guarda só o que foi escrito para a tradução, com os nomes internos achados no arquivo pelo hash, e molde com código novo ou nome interno em claro é recusado.
- [x] CA-E01-01-4 Na cópia do mod 1.0.25, todos os textos cobertos ficam traduzidos, sem pendências.
- [ ] CA-E01-01-5 Os acentos e o tamanho dos textos foram conferidos dentro do jogo.

### Notas

O último critério depende de jogar com o headset. Texto de interface renderizado pelo jogo pode não ter todos os acentos.

## H-E01-02 Voltar ao original com segurança

- Estado: feito
- Origem: 2026-11-03
- Tema: tradução

Como quem joga, quero voltar ao inglês quando eu quiser, para não ficar preso à tradução nem perder o mod por causa dela.

### Critérios de aceite

- [x] CA-E01-02-1 Restaurar devolve os arquivos idênticos byte a byte, inclusive na cópia do mod 1.0.25.
- [x] CA-E01-02-2 Erro no meio da gravação desfaz o que já foi gravado, sem deixar temporário. Janela fechada no meio se resolve na execução seguinte, que limpa os temporários.
- [x] CA-E01-02-3 Arquivo já traduzido nunca vira backup, inclusive sem a marca ou com o pacote antigo instalado.
- [x] CA-E01-02-4 Com o jogo aberto, a ferramenta não grava nada.
- [x] CA-E01-02-5 Backup que não bate com o hash registrado é recusado, sem gravar nada.
- [x] CA-E01-02-6 Com backup ativo de outra pasta do jogo, traduzir e restaurar são recusados, e alvo com junction ou link no caminho também.

## H-E01-03 Lidar com a atualização do mod sem chamar nada externo

- Estado: feito
- Origem: 2026-11-03
- Tema: tradução

Como quem joga, quero que uma atualização do mod não quebre nada, para continuar com o que já está traduzido e saber o que falta.

### Critérios de aceite

- [x] CA-E01-03-1 Texto novo ou alterado fica em inglês e o resto continua traduzido.
- [x] CA-E01-03-2 A ferramenta lista as pendências só com chave ou linha e hash, sem texto do mod, e dá o texto pronto para colar na issue.
- [x] CA-E01-03-3 Nenhuma tradução automática é chamada: os parâmetros e a lógica antiga foram removidos.
