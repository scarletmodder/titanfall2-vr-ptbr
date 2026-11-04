# Como contribuir

Correção de tradução e aviso de texto novo são as contribuições mais úteis. Abra uma issue pelo modelo certo.

## 🔒 O que nunca entra

- Nenhum texto do mod: nem frase em inglês, nem linha de script, nem arquivo copiado, em commit, issue ou PR. O mod tem código fechado e o autor não permite redistribuir.
- Nenhum dado pessoal: nome, e-mail, caminho da sua máquina ou captura de tela com esses dados.

## 🧭 Corrigir ou acrescentar tradução

As regras e o formato estão em [`tool/translations/RULES.md`](tool/translations/RULES.md). A lista de pendências da ferramenta (`pendentes-para-issue.txt`, na pasta de dados) traz a chave ou a linha e o hash de cada texto novo, sem o texto do mod.

## ✅ Antes de abrir um PR

```powershell
powershell -File tests\test.ps1
pwsh -File tests\test.ps1
python tests\test_guards.py
python scripts\check_dictionary.py
python scripts\guard.py --root . --history
python -m ruff check scripts tests
python -m mypy
```

Se você mexeu no exe, na janela ou no instalador, compile e rode também os testes deles. O teste da janela abre o programa e clica nos botões, e por isso precisa de uma sessão do Windows com a área de trabalho aberta:

```powershell
powershell -File scripts\build.ps1
powershell -File tests\test-exe.ps1
powershell -File tests\test-window.ps1
powershell -File tests\test-installer.ps1
```

São dois programas: `Titanfall2VR-PTBR.exe` é a ferramenta sem janela (`src\Launcher.cs`), usada pelo instalador, e `Titanfall2VR-PTBR-Window.exe` é a janela do menu Iniciar (`src\Window.cs`), que só chama a ferramenta.

Os testes são scripts próprios, não pytest, porque o que importa exercitar está em PowerShell e no exe.

Os testes usam um mod sintético (`tests\synthetic.ps1`), com frases inventadas. Quem tem o mod instalado pode conferir também numa cópia, nunca na instalação real, com `tests\test-mod-copy.ps1`.

## 📚 Padrões

- Documentação, título e descrição de commit em português do Brasil, tratando quem lê por "você". Código, comentários, nomes de arquivo e de pasta em inglês. Sem travessão nem meia-risca.
- Conventional Commits, com tipo e escopo em inglês: `fix(dictionary): corrige o termo de embarque`.
- Branch `<tipo>/<descricao-em-ingles>`.
- UTF-8 e LF em tudo. Os `.ps1` também levam BOM, que o Windows PowerShell 5.1 exige para ler acentos.
