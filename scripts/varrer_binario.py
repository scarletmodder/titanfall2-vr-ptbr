"""Varre os bytes de um exe ou zip atrás de dado pessoal, caminho de máquina e PDB.

Lê o arquivo em ASCII e UTF-8 e extrai as sequências de texto UTF-16LE em qualquer posição de byte. Num zip, varre também cada
nome e cada arquivo descompactado, confere que a data de todas as entradas é a data fixa e que
não há arquivo extra. Os termos pessoais vêm de private/guarda-termos.txt, que só existe na
máquina de quem mantém; sem ele, só as regras genéricas rodam, e a saída avisa isso. Os trechos do
mod vêm de private/guarda-textos-mod.txt, do mesmo jeito.

Uso: varrer_binario.py [--termos ARQUIVO] [--textos-mod ARQUIVO] <arquivo> [<arquivo> ...]
Sai com 0 se limpo e 1 se achar algo. A saída nunca repete o dado achado.
"""

from __future__ import annotations

import argparse
import io
import re
import sys
import zipfile
from collections.abc import Sequence
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from guard import REGRAS, TRECHO_MINIMO, _padrao_termo, conferir_textos_do_mod  # noqa: E402

REGRAS_DE_PRIVACIDADE = ("ip-privado", "mac", "caminho-usuario", "pasta-de-dados", "email", "segredo")
EXTRAS = {"pdb": re.compile(r"\.pdb\b", re.IGNORECASE)}
DATA_FIXA_ZIP = (2026, 1, 1, 0, 0, 0)
PERMITIDOS_NO_ZIP = {"Titanfall2VR-PTBR.exe", "LICENSE.txt"}
# Como `strings -el`: separa o texto do byte de tamanho que o antecede, para a palavra inteira casar.
SEQUENCIA_UTF16 = re.compile(rb"(?:[\x20-\x7e\xa0-\xff]\x00){3,}")


def ler_termos(caminho: Path) -> list[str]:
    linhas = caminho.read_text(encoding="utf-8-sig").splitlines()
    return [t.strip() for t in linhas if t.strip() and not t.lstrip().startswith("#")]


def leituras(bruto: bytes) -> dict[str, str]:
    return {
        "ASCII": bruto.decode("latin-1"),
        "UTF-8": bruto.decode("utf-8", errors="replace"),
        "UTF-16LE": "\n".join(m.group(0).decode("utf-16-le") for m in SEQUENCIA_UTF16.finditer(bruto)),
    }


def varrer_bytes(nome: str, bruto: bytes, termos: list[str], trechos: Sequence[str] = ()) -> list[str]:
    padroes = [(r, REGRAS[r]) for r in REGRAS_DE_PRIVACIDADE] + list(EXTRAS.items())
    padroes += [(f"termo {i + 1}", _padrao_termo(t)) for i, t in enumerate(termos)]
    achados = []
    for leitura, texto in leituras(bruto).items():
        for regra, padrao in padroes:
            n = sum(1 for _ in padrao.finditer(texto))
            if n:
                achados.append(f"{nome}: {leitura}: {regra}: {n} ocorrência(s)")
        achados += [f"{nome}: {leitura}: texto-do-mod: {a.trecho}" for a in conferir_textos_do_mod(nome, texto, trechos)]
    return achados


def varrer_zip(nome: str, bruto: bytes, termos: list[str], trechos: Sequence[str] = ()) -> list[str]:
    achados = []
    with zipfile.ZipFile(io.BytesIO(bruto)) as z:
        if z.comment:
            achados.append(f"{nome}: o zip tem comentário")
        for info in z.infolist():
            dentro = f"{nome}!{info.filename}"
            achados += varrer_bytes(f"{dentro} (nome)", info.filename.encode("utf-8"), termos)
            if info.filename not in PERMITIDOS_NO_ZIP:
                achados.append(f"{dentro}: arquivo extra no pacote")
            if info.date_time != DATA_FIXA_ZIP:
                achados.append(f"{dentro}: data diferente da fixa")
            if info.comment or info.extra:
                achados.append(f"{dentro}: entrada com comentário ou campo extra")
            achados += varrer_bytes(dentro, z.read(info), termos, trechos)
    return achados


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--termos", type=Path, default=Path(__file__).resolve().parent.parent / "private" / "guarda-termos.txt")
    ap.add_argument("--textos-mod", type=Path, default=Path(__file__).resolve().parent.parent / "private" / "guarda-textos-mod.txt")
    ap.add_argument("arquivos", nargs="+", type=Path)
    a = ap.parse_args(argv)
    termos: list[str] = []
    if a.termos.is_file():
        termos = ler_termos(a.termos)
    else:
        print("aviso: sem arquivo de termos, só as regras genéricas rodaram")
    trechos: list[str] = []
    if a.textos_mod.is_file():
        linhas = a.textos_mod.read_text(encoding="utf-8-sig").splitlines()
        trechos = [t.strip().lower() for t in linhas if len(t.strip()) >= TRECHO_MINIMO]
    else:
        print("aviso: sem arquivo de textos do mod, a regra de texto do mod não rodou")
    total = 0
    for alvo in a.arquivos:
        bruto = alvo.read_bytes()
        achados = varrer_bytes(alvo.name, bruto, termos, trechos)
        if zipfile.is_zipfile(io.BytesIO(bruto)) and alvo.suffix.lower() == ".zip":
            achados += varrer_zip(alvo.name, bruto, termos, trechos)
        for x in achados:
            print(x)
        total += len(achados)
        if not achados:
            print(f"{alvo.name}: limpo ({len(bruto)} bytes, {len(termos)} termos, {len(trechos)} trechos do mod)")
    return 1 if total else 0


if __name__ == "__main__":
    for fluxo in (sys.stdout, sys.stderr):
        if hasattr(fluxo, "reconfigure"):
            fluxo.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
