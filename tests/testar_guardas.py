"""Prova que as guardas acham dado pessoal na árvore, no histórico e nos bytes de exe e zip.

Todos os valores são inventados e montados em tempo de execução, para que este arquivo passe na
própria guarda. Roda em repositório temporário. Uso: python tests/testar_guardas.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
GUARD = RAIZ / "scripts" / "guard.py"
VARRER = RAIZ / "scripts" / "varrer_binario.py"

TERMO = "Fulanoide" + "Quimera"
AMOSTRAS = {
    "termo-pessoal": f"nome: {TERMO}",
    "caminho-usuario": "pasta: C:" + "\\Users\\" + "fulana\\jogos",
    "caminho-home": "pasta: /ho" + "me/" + "fulana/jogos",
    "pasta-de-dados": "pasta: x\\App" + "Data\\Local\\y",
    "email": "contato: fulana" + "@" + "provedor.com",
    "ip-privado": "ip: 192" + ".168.7.9",
    "mac": "mac: 0A:1B:2C:" + "3D:4E:5F",
}
falhas = 0


def conferir(cond: bool, msg: str) -> None:
    global falhas
    print(("  OK    " if cond else "  FALHA ") + msg)
    falhas += 0 if cond else 1


def rodar(*args: object, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(a) for a in args], check=False, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
        errors="replace", env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )


def git(*args: str, cwd: Path) -> None:
    identidade = ["-c", "user.name=Teste", "-c", "user.email=noreply@example.com", "-c", "commit.gpgsign=false"]
    subprocess.run(["git", *identidade, *args], cwd=cwd, check=True, capture_output=True)


def repo_novo(base: Path, nome: str) -> Path:
    r = base / nome
    r.mkdir()
    git("init", "-q", "-b", "main", cwd=r)
    (r / ".gitignore").write_text("private/\n", encoding="utf-8")
    (r / "private").mkdir()
    (r / "private" / "guarda-termos.txt").write_text(TERMO + "\n", encoding="utf-8")
    return r


def main() -> int:
    with tempfile.TemporaryDirectory() as t:
        base = Path(t)

        print("[1] Árvore")
        r = repo_novo(base, "arvore")
        (r / "limpo.txt").write_text("nada aqui\n", encoding="utf-8")
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", cwd=r).returncode == 0, "árvore limpa passa")
        for nome, texto in AMOSTRAS.items():
            (r / "sujo.txt").write_text(texto + "\n", encoding="utf-8")
            saida = rodar(sys.executable, GUARD, "--raiz", ".", cwd=r)
            conferir(saida.returncode == 1, f"acha {nome}")
            valor = texto.split(": ", 1)[1]
            conferir(valor not in saida.stdout, f"saída não repete o valor de {nome}")
        (r / "sujo.txt").unlink()
        (r / f"{TERMO}.txt").write_text("x\n", encoding="utf-8")
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", cwd=r).returncode == 1, "acha termo no nome do arquivo")
        (r / f"{TERMO}.txt").unlink()
        (r / "ok.txt").write_text("usa $env:LOCALAPPDATA e autor 341213439+scarletmodder@users.noreply.github.com\n", encoding="utf-8")
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", cwd=r).returncode == 0, "variável de ambiente e noreply passam")

        (r / "ok.txt").unlink()
        (r / "sujo.txt").write_text("autor 12345+outraconta@users." + "noreply.github.com\n", encoding="utf-8")
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", cwd=r).returncode == 1, "acha noreply de outra conta")
        (r / "sujo.txt").unlink()
        trecho_mod = "Frase inventada do mod para o teste"
        (r / "private" / "guarda-textos-mod.txt").write_text(trecho_mod + "\ncurta\n", encoding="utf-8")
        (r / "sujo.txt").write_text(f"pt: {trecho_mod.upper()}\n", encoding="utf-8")
        saida = rodar(sys.executable, GUARD, "--raiz", ".", cwd=r)
        conferir(saida.returncode == 1 and "texto-do-mod" in saida.stdout, "acha texto do mod, sem diferenciar maiúsculas")
        conferir(trecho_mod.upper() not in saida.stdout, "saída não repete o texto do mod")
        (r / "sujo.txt").write_text("curta\n", encoding="utf-8")
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", cwd=r).returncode == 0, "trecho curto demais é ignorado")
        (r / "sujo.txt").unlink()

        print("[2] Histórico inteiro")
        r = repo_novo(base, "historico")
        (r / "a.txt").write_text("limpo\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: inicio", cwd=r)
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 0, "histórico limpo passa")
        for nome, texto in AMOSTRAS.items():
            (r / "a.txt").write_text(texto + "\n", encoding="utf-8")
            git("add", "a.txt", cwd=r)
            git("commit", "-qm", "chore: suja", cwd=r)
            (r / "a.txt").write_text("limpo\n", encoding="utf-8")
            git("add", "a.txt", cwd=r)
            git("commit", "-qm", "chore: limpa", cwd=r)
            conferir(rodar(sys.executable, GUARD, "--raiz", ".", cwd=r).returncode == 0, f"{nome}: árvore atual está limpa")
            conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 1, f"{nome}: acha em versão antiga")
            git("reset", "-q", "--hard", "HEAD~2", cwd=r)
            git("reflog", "expire", "--expire=now", "--all", cwd=r)
            git("gc", "-q", "--prune=now", cwd=r)
        r = repo_novo(base, "mensagem")
        (r / "a.txt").write_text("limpo\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", f"chore: pedido de {TERMO}", cwd=r)
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 1, "acha termo em mensagem de commit")
        r = repo_novo(base, "autor")
        (r / "a.txt").write_text("limpo\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        subprocess.run(["git", "-c", "user.name=" + TERMO, "-c", "user.email=noreply@example.com", "commit", "-qm", "chore: x"], cwd=r, check=True, capture_output=True)
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 1, "acha termo no nome do autor")

        r = repo_novo(base, "tag")
        (r / "a.txt").write_text("limpo\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: x", cwd=r)
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 0, "tag: repositório limpo passa antes da tag")
        email = "fulana" + "@" + "provedor.com"
        subprocess.run(
            ["git", "-c", "user.name=Teste", "-c", f"user.email={email}", "tag", "-a", "v9", "-m", "versao"], cwd=r, check=True, capture_output=True
        )
        saida = rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r)
        conferir(saida.returncode == 1 and "historico tag" in saida.stdout, "acha e-mail de quem criou a tag anotada")
        git("tag", "-d", "v9", cwd=r)
        git("tag", "-a", "v9", "-m", f"pedido de {TERMO}", cwd=r)
        saida = rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r)
        conferir(saida.returncode == 1 and "historico tag" in saida.stdout, "acha termo na mensagem da tag anotada")
        r = repo_novo(base, "historico-noreply")
        (r / "a.txt").write_text("autor 1+x@users." + "noreply.github.com\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: x", cwd=r)
        (r / "a.txt").write_text("limpo\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: y", cwd=r)
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 1, "noreply alheio em versão antiga é achado")
        r = repo_novo(base, "autor-noreply")
        (r / "a.txt").write_text("limpo\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        def commit_de(email: str, msg: str, repo: Path) -> None:
            (repo / "a.txt").write_text(msg + "\n", encoding="utf-8")
            git("add", "a.txt", cwd=repo)
            subprocess.run(["git", "-c", "user.name=Teste", "-c", f"user.email={email}", "commit", "-qm", msg], cwd=repo, check=True, capture_output=True)
        commit_de("12345+colaboradora@users." + "noreply.github.com", "chore: a", r)
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 0, "autor com noreply de outra conta passa")
        r = repo_novo(base, "autor-comum")
        commit_de("fulana" + "@" + "provedor.com", "chore: a", r)
        conferir(rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r).returncode == 1, "autor com e-mail comum é achado")
        r = repo_novo(base, "autor-termo")
        commit_de(f"12345+{TERMO}@users." + "noreply.github.com", "chore: a", r)
        saida = rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r)
        conferir(saida.returncode == 1 and "termo-pessoal" in saida.stdout, "noreply com termo pessoal é achado")
        r = repo_novo(base, "mensagem-mista")
        commit_de("1+x@users." + "noreply.github.com", "chore: a de 1+x@users." + "noreply.github.com e fulana" + "@" + "provedor.com", r)
        saida = rodar(sys.executable, GUARD, "--raiz", ".", "--commits", "HEAD", cwd=r)
        conferir(any(x.startswith("commit ") and ": email:" in x for x in saida.stdout.splitlines()), "e-mail comum ao lado de noreply na mensagem é achado")
        r = repo_novo(base, "historico-mod")
        (r / "private" / "guarda-textos-mod.txt").write_text(trecho_mod + "\n", encoding="utf-8")
        (r / "a.txt").write_text(trecho_mod + "\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: x", cwd=r)
        (r / "a.txt").write_text("limpo\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: y", cwd=r)
        saida = rodar(sys.executable, GUARD, "--raiz", ".", "--historico", cwd=r)
        conferir(saida.returncode == 1 and "texto-do-mod" in saida.stdout, "acha texto do mod em versão antiga")

        print("[3] Bytes de exe e zip")
        termos = base / "termos.txt"
        termos.write_text(TERMO + "\n", encoding="utf-8")
        limpo = base / "limpo.exe"
        limpo.write_bytes(b"MZ" + b"\0" * 64 + "texto qualquer".encode("utf-16-le"))
        conferir(rodar(sys.executable, VARRER, "--termos", termos, limpo, cwd=base).returncode == 0, "binário limpo passa")
        for nome, texto in AMOSTRAS.items():
            valor = texto.split(": ", 1)[1]
            for cod in ("ascii", "utf-16-le"):
                for desvio in (b"", b"\0"):
                    alvo = base / "sujo.exe"
                    alvo.write_bytes(b"\x01\x02\x03" + desvio + valor.encode(cod) + b"\x01\x02")
                    conferir(rodar(sys.executable, VARRER, "--termos", termos, alvo, cwd=base).returncode == 1, f"acha {nome} em {cod}, desvio {len(desvio)}")
        pdb = base / "pdb.exe"
        pdb.write_bytes(b"MZ\0x\\Launcher." + b"pdb\0")
        conferir(rodar(sys.executable, VARRER, "--termos", termos, pdb, cwd=base).returncode == 1, "acha referência a PDB")

        textos_mod = base / "textos.txt"
        textos_mod.write_text(trecho_mod + "\n", encoding="utf-8")
        for cod in ("ascii", "utf-16-le"):
            alvo = base / "mod.exe"
            alvo.write_bytes(b"\x01\x02\x03" + trecho_mod.encode(cod) + b"\x01\x02")
            saida = rodar(sys.executable, VARRER, "--termos", termos, "--textos-mod", textos_mod, alvo, cwd=base)
            conferir(saida.returncode == 1 and "texto-do-mod" in saida.stdout, f"acha texto do mod no binário, {cod}")

        def fazer_zip(nome: str, entradas: dict[str, bytes], data: tuple[int, int, int, int, int, int] = (2026, 1, 1, 0, 0, 0)) -> Path:
            caminho = base / nome
            with zipfile.ZipFile(caminho, "w", zipfile.ZIP_DEFLATED) as z:
                for n, b in entradas.items():
                    z.writestr(zipfile.ZipInfo(n, date_time=data), b, zipfile.ZIP_DEFLATED)
            return caminho

        def varrer_zip(alvo: Path) -> int:
            return rodar(sys.executable, VARRER, "--termos", termos, alvo, cwd=base).returncode

        conferir(varrer_zip(fazer_zip("ok.zip", {"Titanfall2VR-PTBR.exe": b"MZ", "LICENSE.txt": b"MIT"})) == 0, "zip limpo passa")
        conferir(varrer_zip(fazer_zip("data.zip", {"LICENSE.txt": b"MIT"}, (2026, 3, 4, 5, 6, 8))) == 1, "acha data de compilação no zip")
        conferir(varrer_zip(fazer_zip("extra.zip", {"LICENSE.txt": b"MIT", "notas.txt": b"x"})) == 1, "acha arquivo extra no zip")
        conferir(varrer_zip(fazer_zip("dentro.zip", {"LICENSE.txt": (" " + TERMO + " ").encode("utf-16-le")})) == 1, "acha termo comprimido dentro do zip")
    print()
    print("GUARDAS OK" if falhas == 0 else f"{falhas} FALHA(S) nas guardas")
    return 1 if falhas else 0


if __name__ == "__main__":
    for fluxo in (sys.stdout, sys.stderr):
        if hasattr(fluxo, "reconfigure"):
            fluxo.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
