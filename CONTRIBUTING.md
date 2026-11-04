# Como contribuir

Correção de tradução e aviso de texto novo são as contribuições mais úteis. Abra uma issue pelo modelo certo.

## O que nunca entra

- Nenhum texto do mod: nem frase em inglês, nem linha de script, nem arquivo copiado, em commit, issue ou PR. O mod tem código fechado e o autor não permite redistribuir.
- Nenhum dado pessoal: nome, e-mail, caminho da sua máquina ou captura de tela com esses dados.

## Corrigir ou acrescentar tradução

As regras e o formato estão em [`ferramenta/traducao/REGRAS.md`](ferramenta/traducao/REGRAS.md). A lista de pendências da ferramenta (`pendentes-para-issue.txt`, na pasta de dados) traz a chave ou a linha e o hash de cada texto novo, sem o texto do mod.

## Antes de abrir um PR

```powershell
powershell -File tests\testar.ps1
pwsh -File tests\testar.ps1
python tests\testar_guardas.py
python scripts\verificar_dicionario.py
python scripts\guard.py --raiz . --historico
python -m ruff check scripts tests
python -m mypy
```

Os testes são scripts próprios, não pytest, porque o que importa exercitar está em PowerShell e no exe.

Os testes usam um mod sintético (`tests\sintetico.ps1`), com frases inventadas. Quem tem o mod instalado pode conferir também numa cópia, nunca na instalação real, com `tests\testar-copia-mod.ps1`.

## Padrões

- Texto, comentários e commits em português do Brasil, tratando quem lê por "você". Sem travessão nem meia-risca.
- Conventional Commits, com tipo e escopo em inglês: `fix(dictionary): corrige o termo de embarque`.
- Branch `<tipo>/<descricao-em-ingles>`.
- UTF-8 e LF em tudo. Os `.ps1` também levam BOM, que o Windows PowerShell 5.1 exige para ler acentos.
- Critérios de aceite em `docs/historias/`.
