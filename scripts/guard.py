"""Publication guard: nothing personal, no secret and nothing off-style enters git.

Runs over the files git would version (tracked and new, not ignored). With `--history`, it also
checks every version of every file, file names, messages, authors and committers of all
commits, including what was already removed from the tree.

Generic rules (they apply in CI):
- `private-ip`: LAN IPv4 (the three private ranges). Examples with letters in place of the
  numbers pass. A sentence-ending period right after the IP does not hide it.
- `mac`: MAC address.
- `user-path`: `C:\\Users\\<name>`, `/c/Users/<name>`, `/home/<name>`, `/Users/<name>`.
  Placeholders between `<>`, `%VAR%`, `$env` and `~` pass, and `/home/` only counts at the start
  of a path (`docs/home/x` and URLs with `/home/` pass).
- `data-folder`: the Windows data folder written out in full. The variable
  `$env:LOCALAPPDATA` passes, because it is discovered at run time.
- `email`: an e-mail that is not an example, a generic noreply, a git remote (`git@host`) or the
  project's public noreply; the noreply of another GitHub account is found in file contents.
  In author, committer, commit message and tag, the noreply of any GitHub account passes, so
  collaborators are not blocked, and the personal terms still apply to it. The domain
  must end in a letters-only TLD (`pkg@1.0rc` is not an e-mail).
- `secret`: known token formats (GitHub, Anthropic, OpenAI `sk-`, AWS, Google, Slack
  `xox`) and the PEM private key header. Left out: `Authorization: Bearer ...` and tokens
  without a recognisable prefix, which have no reliable pattern.
- `dash`: em dash or en dash (project style rule).

Personal rule (local only): terms listed one per line in `private/guard-terms.txt` (legal
name, pseudonym, serial, SSID), searched as whole words. Written between asterisks
(`*term*`, core with at least 4 characters), the term matches at any position, to catch a
name glued inside a login or URL. The file lives in `private/`, which git ignores; in CI it
does not exist and the rule does not run, and the output says so to avoid false confidence. Files that are too
large or binary are not read; the output counts and lists those cases. UTF-16 with BOM is read.

Mod text rule (local only): mod snippets, one per line, in `private/guard-mod-texts.txt`,
searched at any position, case-insensitively. A snippet shorter than 14 characters is
ignored. The file is generated on the maintainer's machine and, like the terms, is never versioned. The output
shows only a short hash of the snippet.

The output never repeats the whole datum: only the start appears, the rest becomes asterisks.

A line with the marker `guard: ignore` (or the legacy Portuguese one) is skipped (use sparingly and justify next to it).
"""

from __future__ import annotations

import hashlib
import re
import subprocess
import sys
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

CORE_MIN = 4  # `*ab*` would match almost every line; below that, whole-word matching applies
IGNORE_MARKER = "guard: ignore"
# Older spelling of the marker, still honoured.
LEGACY_IGNORE_MARKER = "guarda: ignorar"  # guard: ignore
PERSONAL_TERMS = Path("private/guard-terms.txt")
MOD_TEXTS = Path("private/guard-mod-texts.txt")
SNIPPET_MIN = 14
MAX_SIZE = 2 * 1024 * 1024
UTF16_BOMS = (b"\xff\xfe", b"\xfe\xff")

_OCTET = r"(?:25[0-5]|2[0-4]\d|1?\d?\d)"
RULES: dict[str, re.Pattern[str]] = {
    "private-ip": re.compile(
        rf"(?<![\d.])(?:10\.{_OCTET}|172\.(?:1[6-9]|2\d|3[01])|192\.168)\.{_OCTET}\.{_OCTET}(?!\d|\.\d)"
    ),
    "mac": re.compile(r"(?<![0-9A-Fa-f:-])(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}(?![0-9A-Fa-f:-])"),
    "user-path": re.compile(
        r"(?:[A-Za-z]:[\\/]+Users[\\/]+|/[cC]/Users/|(?<![\w.:/-])/home/|(?<![\w.])/Users/)"
        r"(?!<|%|\$|\{|Public\b|Default\b|runner\b|\.\.\.)[A-Za-z0-9._-]+",
        re.IGNORECASE,
    ),
    "data-folder": re.compile(r"(?<![A-Za-z])AppData(?![A-Za-z])", re.IGNORECASE),  # guard: ignore
    "email": re.compile(
        r"(?<![\w.+-])(?!noreply@|no-reply@|git@|[\w.+-]*@(?:example|exemplo)\.|341213439\+scarletmodder@users\.noreply\.github\.com)"
        r"[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,}(?![\w-])"
    ),
    "secret": re.compile(
        r"gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-ant-[A-Za-z0-9_-]{20,}"
        r"|(?<![A-Za-z0-9_-])sk-(?!ant-)[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}"
        r"|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----"
    ),
    "dash": re.compile("[\u2014\u2013]"),
}
# Rules whose snippet is not sensitive data: it appears in full in the output.
UNMASKED_RULES = frozenset({"dash"})


@dataclass(frozen=True)
class Finding:
    file: str
    line: int
    rule: str
    snippet: str

    def __str__(self) -> str:
        return f"{self.file}:{self.line}: {self.rule}: {self.snippet}"


@dataclass
class Report:
    """Result of a check: findings, what was not read and whether the personal rule ran."""

    findings: list[Finding] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)  # "file (reason)"
    terms_active: bool = True
    texts_active: bool = True


def personal_terms(root: Path) -> list[str]:
    path = root / PERSONAL_TERMS
    if not path.is_file():
        return []
    # utf-8-sig: Windows PowerShell 5 writes a BOM, which would stick to the first term.
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    return [t.strip() for t in lines if t.strip() and not t.lstrip().startswith("#")]


GITHUB_NOREPLY = re.compile(r"[\w.+-]+@users\.noreply\.github\.com", re.IGNORECASE)


def check_metadata(name: str, text: str, terms: Sequence[str] = ()) -> list[Finding]:
    findings = [f for f in check_text(name, text, terms) if f.rule != "email"]
    return findings + [f for f in check_text(name, GITHUB_NOREPLY.sub("", text)) if f.rule == "email"]


def mod_texts(root: Path) -> list[str]:
    path = root / MOD_TEXTS
    if not path.is_file():
        return []
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    return [t.strip().lower() for t in lines if len(t.strip()) >= SNIPPET_MIN]


def check_mod_texts(name: str, text: str, snippets: Sequence[str]) -> list[Finding]:
    lowered = text.lower()
    return [
        Finding(name, 0, "mod-text", hashlib.sha256(s.encode("utf-8")).hexdigest()[:10]) for s in snippets if s in lowered
    ]


def _term_pattern(term: str) -> re.Pattern[str]:
    # Whole word by default: a term must not match inside another word. Between
    # asterisks (`*term*`), it matches at any position, for names that appear glued
    # inside logins and URLs.
    core = term[1:-1]
    if term.startswith("*") and term.endswith("*") and len(core) >= CORE_MIN:
        return re.compile(re.escape(core), re.IGNORECASE)
    return re.compile(rf"(?<!\w){re.escape(term)}(?!\w)", re.IGNORECASE)


def check_text(name: str, text: str, terms: Sequence[str] = ()) -> list[Finding]:
    findings: list[Finding] = []
    patterns = [(t, _term_pattern(t)) for t in terms]
    for n, line in enumerate(text.splitlines(), 1):
        if IGNORE_MARKER in line or LEGACY_IGNORE_MARKER in line:
            continue
        for rule, pattern in RULES.items():
            m = pattern.search(line)
            if m:
                findings.append(Finding(name, n, rule, _mask(rule, m.group(0))))
        for term, term_pattern in patterns:
            if term_pattern.search(line):
                findings.append(Finding(name, n, "personal-term", _mask("personal-term", term)))
    return findings


def _mask(rule: str, snippet: str) -> str:
    # Never repeat the whole datum in the output (it goes to the CI log): only the start appears, and
    # short snippets (such as a 3-letter term) are fully hidden.
    if rule in UNMASKED_RULES:
        return snippet
    visible = min(2, (len(snippet) - 1) // 3)
    return snippet[:visible] + "*" * (len(snippet) - visible)


def versionable_files(root: Path) -> list[Path]:
    r = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
        capture_output=True,
        check=True,
    )
    names = [n for n in r.stdout.decode("utf-8").split("\0") if n]
    return [root / n for n in names if (root / n).is_file()]


def _decode(raw: bytes) -> str | None:
    """File text, or None if it is binary (a null byte outside UTF-16 with BOM)."""
    if raw[:2] in UTF16_BOMS:
        return raw.decode("utf-16", errors="replace")
    if b"\0" in raw[:8192]:
        return None
    return raw.decode("utf-8", errors="replace")


def check_files(
    root: Path,
    files: Iterable[Path],
    terms: Sequence[str] = (),
    *,
    terms_active: bool = True,
    snippets: Sequence[str] = (),
) -> Report:
    report = Report(terms_active=terms_active, texts_active=bool(snippets))
    for path in files:
        try:
            name = path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            name = path.as_posix()
        try:
            if path.stat().st_size > MAX_SIZE:
                report.skipped.append(f"{name} (larger than {MAX_SIZE // 2**20} MiB)")
                continue
            raw = path.read_bytes()
        except OSError:
            report.skipped.append(f"{name} (unreadable)")
            continue
        report.findings.extend(check_text(f"{name} (file name)", name, terms))
        text = _decode(raw)
        if text is None:
            report.skipped.append(f"{name} (binary)")
            continue
        report.findings.extend(check_text(name, text, terms))
        report.findings.extend(check_mod_texts(name, text, snippets))
    return report


def check_commits(root: Path, revision_range: str, terms: Sequence[str] = ()) -> list[Finding]:
    """Checks the commit messages of `revision_range` (e.g. `origin/main..HEAD`)."""
    r = subprocess.run(
        ["git", "log", "--format=%H%x00%B%x01", "--end-of-options", revision_range],
        cwd=root,
        capture_output=True,
        check=True,
    )
    findings: list[Finding] = []
    for block in r.stdout.decode("utf-8", errors="replace").split("\x01"):
        sha, _, body = block.strip("\n").partition("\0")
        if sha:
            findings.extend(check_metadata(f"commit {sha[:10]}", body, terms))
    return findings


def check_history(root: Path, terms: Sequence[str] = (), snippets: Sequence[str] = ()) -> Report:
    """Checks everything `git push --all --tags` would publish: versions, names, messages and authors."""
    report = Report(terms_active=bool(terms))
    objects = subprocess.run(
        ["git", "rev-list", "--objects", "--all"], cwd=root, capture_output=True, check=True
    ).stdout.decode("utf-8", errors="replace")
    for entry in objects.splitlines():
        sha, _, name = entry.partition(" ")
        if name:
            report.findings.extend(check_text(f"history {name} (file name)", name, terms))
        kind = subprocess.run(["git", "cat-file", "-t", sha], cwd=root, capture_output=True, check=True).stdout.strip()
        if kind == b"tag":
            # An annotated tag stores who created it and the message, apart from the commits.
            tag_body = subprocess.run(["git", "cat-file", "tag", sha], cwd=root, capture_output=True, check=True).stdout
            tag_text = tag_body.decode("utf-8", errors="replace")
            report.findings.extend(check_metadata(f"history tag {sha[:10]}", tag_text, terms))
            report.findings.extend(check_mod_texts(f"history tag {sha[:10]}", tag_text, snippets))
            continue
        if kind != b"blob":
            continue
        raw = subprocess.run(["git", "cat-file", "blob", sha], cwd=root, capture_output=True, check=True).stdout
        text = _decode(raw)
        if text is None:
            report.skipped.append(f"{name or sha} (binary in history)")
            continue
        report.findings.extend(check_text(f"history {sha[:10]} {name}", text, terms))
        report.findings.extend(check_mod_texts(f"history {sha[:10]} {name}", text, snippets))
    commits = subprocess.run(
        ["git", "log", "--all", "--format=%H%x00%an <%ae>%n%cn <%ce>%n%B%x01"], cwd=root, capture_output=True, check=True
    ).stdout.decode("utf-8", errors="replace")
    for block in commits.split("\x01"):
        sha, _, body = block.strip("\n").partition("\0")
        if sha:
            report.findings.extend(check_metadata(f"commit {sha[:10]}", body, terms))
            report.findings.extend(check_mod_texts(f"commit {sha[:10]}", body, snippets))
    refs = subprocess.run(["git", "for-each-ref", "--format=%(refname)"], cwd=root, capture_output=True, check=True)
    report.findings.extend(check_text("refs", refs.stdout.decode("utf-8", errors="replace"), terms))
    return report


def check_repository(root: Path) -> Report:
    terms = personal_terms(root)
    return check_files(root, versionable_files(root), terms, terms_active=bool(terms), snippets=mod_texts(root))


def main(argv: list[str] | None = None) -> int:
    import argparse

    ap = argparse.ArgumentParser(description="Looks for personal data, secrets and off-style content.")
    ap.add_argument("--root", default=".")
    ap.add_argument("--commits", help="commit range, e.g. origin/main..HEAD")
    ap.add_argument("--history", action="store_true", help="checks the whole history, not only the tree")
    a = ap.parse_args(argv)
    root = Path(a.root)
    try:
        report = check_repository(root)
        findings = report.findings
        if a.commits:
            findings += check_commits(root, a.commits, personal_terms(root))
        if a.history:
            history = check_history(root, personal_terms(root), mod_texts(root))
            findings += history.findings
            report.skipped += history.skipped
    except (subprocess.CalledProcessError, FileNotFoundError) as error:
        detail = error.stderr.decode("utf-8", "replace").strip() if hasattr(error, "stderr") else str(error)
        print(f"guard: git failed ({root} is not a git repository or the range does not exist): {detail}")
        return 2
    for f in findings:
        print(f)
    if not report.terms_active:
        print(f"warning: personal terms rule did not run ({PERSONAL_TERMS.as_posix()} missing or empty)")
    if not report.texts_active:
        print(f"warning: mod text rule did not run ({MOD_TEXTS.as_posix()} missing or empty)")
    if report.skipped:
        skipped = ", ".join(report.skipped[:10])
        print(f"warning: {len(report.skipped)} file(s) not checked: {skipped}")
    print(f"{len(findings)} finding(s)" if findings else "guard: nothing personal, secret or off-style.")
    return 1 if findings else 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
