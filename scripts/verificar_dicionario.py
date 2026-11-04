"""Confere o dicionário público e a codificação dos scripts sem precisar do mod.

- cada entrada só tem os campos do formato público, sem nenhum `en`;
- hash em hexadecimal minúsculo de 64 dígitos, sem hash repetido no mesmo arquivo;
- tradução igual ao inglês (hash do `pt` igual ao `enHash`) só em nome técnico da lista abaixo;
- molde sem nome interno em claro: comparação com literal entre aspas é recusada;
- JSON em UTF-8 sem BOM e com LF;
- todo .ps1 em UTF-8 com BOM (exigência do Windows PowerShell 5.1) e LF.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
HASH = re.compile(r"^[0-9a-f]{64}$")
TOPO_TOKENS = {"arquivo", "nome", "tokens"}
TOPO_LINHAS = {"arquivo", "nome", "varrer", "linhas"}
# Nome técnico genérico, igual em qualquer idioma: pode ficar como está no mod.
PT_IGUAL_AO_EN = {"TF2VR_SMAA"}
COMPARA_LITERAL = re.compile(r'(?:==|!=)\s*"')


def conferir_json(caminho: Path) -> list[str]:
    erros: list[str] = []
    bruto = caminho.read_bytes()
    if bruto.startswith(b"\xef\xbb\xbf"):
        erros.append(f"{caminho.name}: tem BOM")
    if b"\r" in bruto:
        erros.append(f"{caminho.name}: tem CR")
    dados = json.loads(bruto.decode("utf-8"))
    e_tokens = caminho.name == "tokens.json"
    topo = TOPO_TOKENS if e_tokens else TOPO_LINHAS
    if set(dados) - topo:
        erros.append(f"{caminho.name}: campos de topo inesperados: {sorted(set(dados) - topo)}")
    vistos: set[str] = set()
    for n, e in enumerate(dados["tokens" if e_tokens else "linhas"], 1):
        rotulo = f"{caminho.name}, entrada {n}"
        campos = set(e)
        if e_tokens:
            if campos != {"chave", "enHash", "pt"}:
                erros.append(f"{rotulo}: campos {sorted(campos)}")
        elif campos not in ({"enHash", "textos"}, {"enHash", "molde"}):
            erros.append(f"{rotulo}: campos {sorted(campos)}")
        if e_tokens and e.get("chave") not in PT_IGUAL_AO_EN and hashlib.sha256(str(e.get("pt")).encode("utf-8")).hexdigest() == e.get("enHash"):
            erros.append(f"{rotulo}: a tradução é igual ao texto do mod")
        if "molde" in e and COMPARA_LITERAL.search(e["molde"]):
            erros.append(f"{rotulo}: molde com nome interno em claro")
        if not HASH.match(str(e.get("enHash"))):
            erros.append(f"{rotulo}: enHash inválido")
        chave = e.get("chave", e.get("enHash"))
        if chave in vistos:
            erros.append(f"{rotulo}: repetida")
        vistos.add(chave)
    return erros


def main() -> int:
    erros: list[str] = []
    arquivos = sorted((RAIZ / "ferramenta" / "traducao").glob("*.json"))
    if not arquivos:
        erros.append("nenhum dicionário encontrado")
    for caminho in arquivos:
        erros.extend(conferir_json(caminho))
    scripts = [*RAIZ.glob("ferramenta/*.ps1"), *RAIZ.glob("scripts/*.ps1"), *RAIZ.glob("tests/*.ps1")]
    for caminho in scripts:
        bruto = caminho.read_bytes()
        if not bruto.startswith(b"\xef\xbb\xbf"):
            erros.append(f"{caminho.name}: sem BOM UTF-8")
        if b"\r" in bruto:
            erros.append(f"{caminho.name}: tem CR")
    for e in erros:
        print(e)
    print(f"{len(erros)} problema(s)" if erros else f"dicionário ok: {len(arquivos)} arquivos, {len(scripts)} scripts")
    return 1 if erros else 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
