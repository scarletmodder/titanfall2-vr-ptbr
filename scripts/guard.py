"""Guarda de publicação: nada pessoal, nada de segredo, nada fora do estilo entra no git.

Roda sobre os arquivos que o git versionaria (rastreados e novos não ignorados). Com `--historico`,
confere também todas as versões de todos os arquivos, nomes de arquivo, mensagens, autores e
committers de todos os commits, inclusive o que já foi apagado da árvore.

Regras genéricas (valem no CI):
- `ip-privado`: IPv4 de rede local (as três faixas privadas). Exemplos com letras no lugar
  dos números passam. Um ponto final de frase logo depois do IP não o esconde.
- `mac`: endereço MAC.
- `caminho-usuario`: `C:\\Users\\<nome>`, `/c/Users/<nome>`, `/home/<nome>`, `/Users/<nome>`.
  Placeholders entre `<>`, `%VAR%`, `$env` e `~` passam, e `/home/` só conta no início de um
  caminho (`docs/home/x` e URLs com `/home/` passam).
- `pasta-de-dados`: a pasta de dados do Windows escrita por extenso. A variável
  `$env:LOCALAPPDATA` passa, porque é descoberta em tempo de execução.
- `email`: e-mail que não seja de exemplo, noreply genérico, de remoto git (`git@host`) ou o
  noreply público do projeto; o noreply de outra conta do GitHub é achado no conteúdo de arquivos.
  Em autor, committer, mensagem de commit e tag, o noreply de qualquer conta do GitHub passa, para
  não barrar quem colabora, e os termos pessoais continuam valendo nele. O domínio
  precisa terminar em TLD só de letras (`pkg@1.0rc` não é e-mail).
- `segredo`: formatos conhecidos de token (GitHub, Anthropic, OpenAI `sk-`, AWS, Google, Slack
  `xox`) e cabeçalho de chave privada PEM. Ficam de fora: `Authorization: Bearer ...` e tokens
  sem prefixo reconhecível, que não têm padrão confiável.
- `travessao`: travessão ou meia-risca (regra de estilo do projeto).
- `atribuicao-ia`: trailer de coautoria ou rodapé de geração por IA.

Regra pessoal (só local): termos listados, um por linha, em `private/guarda-termos.txt` (nome
civil, pseudônimo, serial, SSID), procurados como palavra inteira. Escrito entre asteriscos
(`*termo*`, miolo com pelo menos 4 caracteres), o termo casa em qualquer posição, para pegar um
nome colado dentro de login ou URL. O arquivo vive em `private/`, que o git ignora; no CI ele não
existe e a regra não roda, e a saída avisa isso para não dar falsa segurança. Arquivos grandes
demais ou binários não são lidos; a saída conta e lista esses casos. UTF-16 com BOM é lido.

Regra do texto do mod (só local): trechos do mod, um por linha, em `private/guarda-textos-mod.txt`,
procurados em qualquer posição, sem diferenciar maiúsculas. Com menos de 14 caracteres o trecho é
ignorado. O arquivo é gerado na máquina de quem mantém e, como os termos, nunca é versionado. A saída
mostra só um hash curto do trecho.

A saída nunca repete o dado por inteiro: só o início aparece, o resto vira asteriscos.

Uma linha com o marcador `guarda: ignorar` é pulada (use com parcimônia e justifique ao lado).
"""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

MIOLO_MINIMO = 4  # `*ab*` casaria em quase toda linha; abaixo disso vale palavra inteira
MARCADOR_IGNORAR = "guarda: ignorar"
TERMOS_PESSOAIS = Path("private/guarda-termos.txt")
TEXTOS_DO_MOD = Path("private/guarda-textos-mod.txt")
TRECHO_MINIMO = 14
TAMANHO_MAXIMO = 2 * 1024 * 1024
BOMS_UTF16 = (b"\xff\xfe", b"\xfe\xff")

_OCTETO = r"(?:25[0-5]|2[0-4]\d|1?\d?\d)"
REGRAS: dict[str, re.Pattern[str]] = {
    "ip-privado": re.compile(
        rf"(?<![\d.])(?:10\.{_OCTETO}|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.{_OCTETO}\.{_OCTETO}(?!\d|\.\d)"
    ),
    "mac": re.compile(r"(?<![0-9A-Fa-f:-])(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:-])"),
    "caminho-usuario": re.compile(
        r"(?:[A-Za-z]:[\\/]+Users[\\/]+|/[cC]/Users/|(?<![\w.:/-])/home/|(?<![\w.])/Users/)"
        r"(?!<|%|\$|\{|Public\b|Default\b|runner\b|\.\.\.)[A-Za-z0-9._-]+",
        re.IGNORECASE,
    ),
    "pasta-de-dados": re.compile(r"(?<![A-Za-z])AppData(?![A-Za-z])", re.IGNORECASE),  # guarda: ignorar
    "email": re.compile(
        r"(?<![\w.+-])(?!noreply@|no-reply@|git@|[\w.+-]*@(?:example|exemplo)\.|341213439\+scarletmodder@users\.noreply\.github\.com)"
        r"[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,}(?![\w-])"
    ),
    "segredo": re.compile(
        r"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-ant-[A-Za-z0-9_-]{20,}"
        r"|(?<![A-Za-z0-9_-])sk-(?!ant-)[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}"
        r"|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----"
    ),
    "travessao": re.compile("[\u2014\u2013]"),
    "atribuicao-ia": re.compile(
        r"Co-Authored-By:\s*Claude|Generated with \[Claude Code\]|\U0001F916 Generated with", re.IGNORECASE  # guarda: ignorar
    ),
}
# Regras cujo trecho não é dado sensível: aparece inteiro na saída.
REGRAS_SEM_MASCARA = frozenset({"travessao", "atribuicao-ia"})


@dataclass(frozen=True)
class Achado:
    arquivo: str
    linha: int
    regra: str
    trecho: str

    def __str__(self) -> str:
        return f"{self.arquivo}:{self.linha}: {self.regra}: {self.trecho}"


@dataclass
class Relatorio:
    """Resultado de uma conferência: achados, o que não foi lido e se a regra pessoal rodou."""

    achados: list[Achado] = field(default_factory=list)
    puladas: list[str] = field(default_factory=list)  # "arquivo (motivo)"
    termos_ativos: bool = True
    textos_ativos: bool = True


def termos_pessoais(raiz: Path) -> list[str]:
    caminho = raiz / TERMOS_PESSOAIS
    if not caminho.is_file():
        return []
    # utf-8-sig: o Windows PowerShell 5 grava BOM, que grudaria no primeiro termo.
    linhas = caminho.read_text(encoding="utf-8-sig").splitlines()
    return [t.strip() for t in linhas if t.strip() and not t.lstrip().startswith("#")]


NOREPLY_GITHUB = re.compile(r"[\w.+-]+@users\.noreply\.github\.com", re.IGNORECASE)


def conferir_metadados(nome: str, texto: str, termos: Sequence[str] = ()) -> list[Achado]:
    achados = [a for a in conferir_texto(nome, texto, termos) if a.regra != "email"]
    return achados + [a for a in conferir_texto(nome, NOREPLY_GITHUB.sub("", texto)) if a.regra == "email"]


def textos_do_mod(raiz: Path) -> list[str]:
    caminho = raiz / TEXTOS_DO_MOD
    if not caminho.is_file():
        return []
    linhas = caminho.read_text(encoding="utf-8-sig").splitlines()
    return [t.strip().lower() for t in linhas if len(t.strip()) >= TRECHO_MINIMO]


def conferir_textos_do_mod(nome: str, texto: str, trechos: Sequence[str]) -> list[Achado]:
    minusculo = texto.lower()
    return [
        Achado(nome, 0, "texto-do-mod", hashlib.sha256(t.encode("utf-8")).hexdigest()[:10]) for t in trechos if t in minusculo
    ]


def _padrao_termo(termo: str) -> re.Pattern[str]:
    # Palavra inteira por padrão: um termo não deve casar dentro de outra palavra. Entre
    # asteriscos (`*termo*`), casa em qualquer posição, para nomes que aparecem colados
    # dentro de logins e URLs.
    miolo = termo[1:-1]
    if termo.startswith("*") and termo.endswith("*") and len(miolo) >= MIOLO_MINIMO:
        return re.compile(re.escape(miolo), re.IGNORECASE)
    return re.compile(rf"(?<!\w){re.escape(termo)}(?!\w)", re.IGNORECASE)


def conferir_texto(nome: str, texto: str, termos: Sequence[str] = ()) -> list[Achado]:
    achados: list[Achado] = []
    padroes = [(t, _padrao_termo(t)) for t in termos]
    for n, linha in enumerate(texto.splitlines(), 1):
        if MARCADOR_IGNORAR in linha:
            continue
        for regra, padrao in REGRAS.items():
            m = padrao.search(linha)
            if m:
                achados.append(Achado(nome, n, regra, _mascarar(regra, m.group(0))))
        for termo, padrao_termo in padroes:
            if padrao_termo.search(linha):
                achados.append(Achado(nome, n, "termo-pessoal", _mascarar("termo-pessoal", termo)))
    return achados


def _mascarar(regra: str, trecho: str) -> str:
    # Nunca repetir o dado por inteiro na saída (ela vai para log de CI): só o início aparece, e
    # trechos curtos (como um termo de 3 letras) ficam totalmente escondidos.
    if regra in REGRAS_SEM_MASCARA:
        return trecho
    visivel = min(2, (len(trecho) - 1) // 3)
    return trecho[:visivel] + "*" * (len(trecho) - visivel)


def arquivos_versionaveis(raiz: Path) -> list[Path]:
    r = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=raiz,
        capture_output=True,
        check=True,
    )
    nomes = [n for n in r.stdout.decode("utf-8").split("\0") if n]
    return [raiz / n for n in nomes if (raiz / n).is_file()]


def _decodificar(bruto: bytes) -> str | None:
    """Texto do arquivo, ou None se for binário (byte nulo fora de UTF-16 com BOM)."""
    if bruto[:2] in BOMS_UTF16:
        return bruto.decode("utf-16", errors="replace")
    if b"\0" in bruto[:8192]:
        return None
    return bruto.decode("utf-8", errors="replace")


def conferir_arquivos(
    raiz: Path,
    arquivos: Iterable[Path],
    termos: Sequence[str] = (),
    *,
    termos_ativos: bool = True,
    trechos: Sequence[str] = (),
) -> Relatorio:
    relatorio = Relatorio(termos_ativos=termos_ativos, textos_ativos=bool(trechos))
    for caminho in arquivos:
        try:
            nome = caminho.resolve().relative_to(raiz.resolve()).as_posix()
        except ValueError:
            nome = caminho.as_posix()
        try:
            if caminho.stat().st_size > TAMANHO_MAXIMO:
                relatorio.puladas.append(f"{nome} (maior que {TAMANHO_MAXIMO // 2**20} MiB)")
                continue
            bruto = caminho.read_bytes()
        except OSError:
            relatorio.puladas.append(f"{nome} (ilegível)")
            continue
        relatorio.achados.extend(conferir_texto(f"{nome} (nome do arquivo)", nome, termos))
        texto = _decodificar(bruto)
        if texto is None:
            relatorio.puladas.append(f"{nome} (binário)")
            continue
        relatorio.achados.extend(conferir_texto(nome, texto, termos))
        relatorio.achados.extend(conferir_textos_do_mod(nome, texto, trechos))
    return relatorio


def conferir_commits(raiz: Path, intervalo: str, termos: Sequence[str] = ()) -> list[Achado]:
    """Confere as mensagens dos commits de `intervalo` (ex.: `origin/main..HEAD`)."""
    r = subprocess.run(
        ["git", "log", "--format=%H%x00%B%x01", "--end-of-options", intervalo],
        cwd=raiz,
        capture_output=True,
        check=True,
    )
    achados: list[Achado] = []
    for bloco in r.stdout.decode("utf-8", errors="replace").split("\x01"):
        sha, _, corpo = bloco.strip("\n").partition("\0")
        if sha:
            achados.extend(conferir_metadados(f"commit {sha[:10]}", corpo, termos))
    return achados


def conferir_historico(raiz: Path, termos: Sequence[str] = (), trechos: Sequence[str] = ()) -> Relatorio:
    """Confere tudo o que `git push --all --tags` publicaria: versões, nomes, mensagens e autores."""
    relatorio = Relatorio(termos_ativos=bool(termos))
    objetos = subprocess.run(
        ["git", "rev-list", "--objects", "--all"], cwd=raiz, capture_output=True, check=True
    ).stdout.decode("utf-8", errors="replace")
    for linha in objetos.splitlines():
        sha, _, nome = linha.partition(" ")
        if nome:
            relatorio.achados.extend(conferir_texto(f"historico {nome} (nome do arquivo)", nome, termos))
        tipo = subprocess.run(["git", "cat-file", "-t", sha], cwd=raiz, capture_output=True, check=True).stdout.strip()
        if tipo == b"tag":
            # Tag anotada guarda quem criou e a mensagem, à parte dos commits.
            corpo_tag = subprocess.run(["git", "cat-file", "tag", sha], cwd=raiz, capture_output=True, check=True).stdout
            texto_tag = corpo_tag.decode("utf-8", errors="replace")
            relatorio.achados.extend(conferir_metadados(f"historico tag {sha[:10]}", texto_tag, termos))
            relatorio.achados.extend(conferir_textos_do_mod(f"historico tag {sha[:10]}", texto_tag, trechos))
            continue
        if tipo != b"blob":
            continue
        bruto = subprocess.run(["git", "cat-file", "blob", sha], cwd=raiz, capture_output=True, check=True).stdout
        texto = _decodificar(bruto)
        if texto is None:
            relatorio.puladas.append(f"{nome or sha} (binário no histórico)")
            continue
        relatorio.achados.extend(conferir_texto(f"historico {sha[:10]} {nome}", texto, termos))
        relatorio.achados.extend(conferir_textos_do_mod(f"historico {sha[:10]} {nome}", texto, trechos))
    commits = subprocess.run(
        ["git", "log", "--all", "--format=%H%x00%an <%ae>%n%cn <%ce>%n%B%x01"], cwd=raiz, capture_output=True, check=True
    ).stdout.decode("utf-8", errors="replace")
    for bloco in commits.split("\x01"):
        sha, _, corpo = bloco.strip("\n").partition("\0")
        if sha:
            relatorio.achados.extend(conferir_metadados(f"commit {sha[:10]}", corpo, termos))
            relatorio.achados.extend(conferir_textos_do_mod(f"commit {sha[:10]}", corpo, trechos))
    refs = subprocess.run(["git", "for-each-ref", "--format=%(refname)"], cwd=raiz, capture_output=True, check=True)
    relatorio.achados.extend(conferir_texto("referências", refs.stdout.decode("utf-8", errors="replace"), termos))
    return relatorio


def conferir_repositorio(raiz: Path) -> Relatorio:
    termos = termos_pessoais(raiz)
    return conferir_arquivos(raiz, arquivos_versionaveis(raiz), termos, termos_ativos=bool(termos), trechos=textos_do_mod(raiz))


def main(argv: list[str] | None = None) -> int:
    import argparse

    ap = argparse.ArgumentParser(description="Procura dado pessoal, segredo e fora do estilo.")
    ap.add_argument("--raiz", default=".")
    ap.add_argument("--commits", help="intervalo de commits, ex.: origin/main..HEAD")
    ap.add_argument("--historico", action="store_true", help="confere o histórico inteiro, não só a árvore")
    a = ap.parse_args(argv)
    raiz = Path(a.raiz)
    try:
        relatorio = conferir_repositorio(raiz)
        achados = relatorio.achados
        if a.commits:
            achados += conferir_commits(raiz, a.commits, termos_pessoais(raiz))
        if a.historico:
            historico = conferir_historico(raiz, termos_pessoais(raiz), textos_do_mod(raiz))
            achados += historico.achados
            relatorio.puladas += historico.puladas
    except (subprocess.CalledProcessError, FileNotFoundError) as erro:
        detalhe = erro.stderr.decode("utf-8", "replace").strip() if hasattr(erro, "stderr") else str(erro)
        print(f"guarda: git falhou ({raiz} não é repositório git ou o intervalo não existe): {detalhe}")
        return 2
    for x in achados:
        print(x)
    if not relatorio.termos_ativos:
        termos = TERMOS_PESSOAIS.as_posix()
        print(f"aviso: regra de termos pessoais não rodou ({termos} ausente ou vazio)")
    if not relatorio.textos_ativos:
        print(f"aviso: regra de texto do mod não rodou ({TEXTOS_DO_MOD.as_posix()} ausente ou vazio)")
    if relatorio.puladas:
        puladas = ", ".join(relatorio.puladas[:10])
        print(f"aviso: {len(relatorio.puladas)} arquivo(s) não conferido(s): {puladas}")
    print(f"{len(achados)} achado(s)" if achados else "guarda: nada pessoal, segredo ou fora do estilo.")
    return 1 if achados else 0


if __name__ == "__main__":
    for fluxo in (sys.stdout, sys.stderr):
        if hasattr(fluxo, "reconfigure"):
            fluxo.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
