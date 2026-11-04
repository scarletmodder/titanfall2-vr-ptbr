# E02 Entrega pública

## H-E02-01 Executável único

- Estado: parcial
- Origem: 2026-11-03
- Tema: entrega

Como quem joga, quero baixar um arquivo só e abrir, para não precisar instalar nada nem mexer em linha de comando.

### Notas

O caminho elevado foi testado com uma compilação que simula o aviso. A troca de dono da pasta e o aviso real só rodam como administrador de verdade.

### Critérios de aceite

- [x] CA-E02-01-1 O exe embute script e dicionário, extrai na pasta de dados do usuário e roda o PowerShell do Windows.
- [x] CA-E02-01-2 O manifesto é `asInvoker`, e o código de saída do script chega a quem chamou.
- [x] CA-E02-01-3 Compilado com o csc do .NET Framework, sem dependência nova, sem PDB e com autor "Scarlet Modder" no arquivo.
- [x] CA-E02-01-4 Testado de ponta a ponta em pasta temporária com espaço no caminho, sem criar nada na pasta padrão.
- [x] CA-E02-01-5 Quando o jogo exige administrador, o exe se reabre elevado, extrai numa pasta nova só de administradores, confere o hash de cada arquivo, roda dali e apaga ao final, com backup e estado numa pasta em que só administradores gravam. Depois de criar as pastas, revalida dono e permissões delas e dos filhos diretos e recusa sem rodar se não forem confiáveis; pastas de execução antigas são varridas sem seguir junction.
- [ ] CA-E02-01-6 O aviso real do Windows foi aceito e recusado numa instalação de verdade.

## H-E02-02 Nada pessoal e nada do mod publicado

- Estado: feito
- Origem: 2026-11-03
- Tema: entrega

Como dona do projeto, quero garantir que nada identifique a pessoa e nada do mod saia, para publicar sob o pseudônimo sem risco.

### Critérios de aceite

- [x] CA-E02-02-1 A guarda confere árvore, todas as versões do histórico, nomes de arquivo, mensagens, autores, committers e tags anotadas.
- [x] CA-E02-02-2 A varredura confere os bytes do exe e do zip, em ASCII, UTF-8 e UTF-16LE, e o conteúdo descompactado.
- [x] CA-E02-02-3 Os termos pessoais só existem em arquivo ignorado pelo git, e testes com valores inventados provam que as guardas acham cada tipo de dado.
- [x] CA-E02-02-4 O zip tem data fixa nas entradas e só leva o executável e a licença.
- [x] CA-E02-02-5 Os testes usam um mod sintético, e nenhuma frase do mod está no repositório.
- [x] CA-E02-02-6 Regra local procura trechos do mod na árvore, no histórico e nos bytes do pacote, a partir de lista que nunca é versionada.
- [x] CA-E02-02-7 No conteúdo de arquivos, só o noreply do projeto passa na regra de e-mail; em autor, committer, mensagem e tag, o noreply de qualquer conta do GitHub passa, e e-mail comum é achado.

## H-E02-03 Publicação automatizada

- Estado: parcial
- Origem: 2026-11-03
- Tema: entrega

Como dona do projeto, quero que uma tag gere a release sozinha, para publicar sem segredo pessoal e sempre pelo mesmo caminho.

### Critérios de aceite

- [x] CA-E02-03-1 O CI roda em `windows-latest` em PR e push: ruff, mypy, guardas, testes nos dois PowerShell e compilação.
- [x] CA-E02-03-2 Tag `v*` confere se o commit está na `main`, repete as verificações do CI, inclusive ruff e mypy, compila, gera `SHA256SUMS.txt`, confere o conteúdo exato do pacote e publica com `GITHUB_TOKEN` só no job de publicação, com o corpo vindo de `docs/releases/`.
- [x] CA-E02-03-3 As actions estão fixadas por hash, e nenhum passo depende de segredo pessoal.
- [ ] CA-E02-03-4 Os dois fluxos rodaram no GitHub.

### Notas

O repositório ainda não foi criado no GitHub, então os fluxos só foram escritos, não executados.
