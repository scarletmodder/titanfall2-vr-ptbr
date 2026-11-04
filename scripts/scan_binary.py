"""Scans the bytes of an exe or zip for personal data, machine paths and PDB references.

Reads the file as ASCII and UTF-8 and extracts UTF-16LE text sequences at any byte position. In a zip,
it also scans every name and every decompressed file, checks that the date of all entries is the fixed
date and that there is no extra file. The personal terms come from private/guard-terms.txt, which only
exists on the maintainer's machine; without it, only the generic rules run, and the output says so. The
mod snippets come from private/guard-mod-texts.txt, in the same way.

Usage: scan_binary.py [--terms FILE] [--mod-texts FILE] <file> [<file> ...]
Exits 0 if clean and 1 if it finds anything. The output never repeats the data found.
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
from guard import RULES, SNIPPET_MIN, _term_pattern, check_mod_texts  # noqa: E402

PRIVACY_RULES = ("private-ip", "mac", "user-path", "data-folder", "email", "secret")
EXTRAS = {"pdb": re.compile(r"\.pdb\b", re.IGNORECASE)}
FIXED_ZIP_DATE = (2026, 1, 1, 0, 0, 0)
ALLOWED_IN_ZIP = {"Titanfall2VR-PTBR.exe", "LICENSE.txt"}
# Like `strings -el`: separates the text from the length byte before it, so the whole word matches.
UTF16_SEQUENCE = re.compile(rb"(?:[\x20-\x7e\xa0-\xff]\x00){3,}")


def read_terms(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    return [t.strip() for t in lines if t.strip() and not t.lstrip().startswith("#")]


def readings(raw: bytes) -> dict[str, str]:
    return {
        "ASCII": raw.decode("latin-1"),
        "UTF-8": raw.decode("utf-8", errors="replace"),
        "UTF-16LE": "\n".join(m.group(0).decode("utf-16-le") for m in UTF16_SEQUENCE.finditer(raw)),
    }


def scan_bytes(name: str, raw: bytes, terms: list[str], snippets: Sequence[str] = ()) -> list[str]:
    patterns = [(r, RULES[r]) for r in PRIVACY_RULES] + list(EXTRAS.items())
    patterns += [(f"term {i + 1}", _term_pattern(t)) for i, t in enumerate(terms)]
    found = []
    for reading, text in readings(raw).items():
        for rule, pattern in patterns:
            n = sum(1 for _ in pattern.finditer(text))
            if n:
                found.append(f"{name}: {reading}: {rule}: {n} occurrence(s)")
        found += [f"{name}: {reading}: mod-text: {f.snippet}" for f in check_mod_texts(name, text, snippets)]
    return found


def scan_zip(name: str, raw: bytes, terms: list[str], snippets: Sequence[str] = ()) -> list[str]:
    found = []
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        if z.comment:
            found.append(f"{name}: the zip has a comment")
        for info in z.infolist():
            inside = f"{name}!{info.filename}"
            found += scan_bytes(f"{inside} (name)", info.filename.encode("utf-8"), terms)
            if info.filename not in ALLOWED_IN_ZIP:
                found.append(f"{inside}: extra file in the package")
            if info.date_time != FIXED_ZIP_DATE:
                found.append(f"{inside}: date differs from the fixed one")
            if info.comment or info.extra:
                found.append(f"{inside}: entry with a comment or extra field")
            found += scan_bytes(inside, z.read(info), terms, snippets)
    return found


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument("--terms", type=Path, default=root / "private" / "guard-terms.txt")
    ap.add_argument("--mod-texts", type=Path, default=root / "private" / "guard-mod-texts.txt")
    ap.add_argument("files", nargs="+", type=Path)
    a = ap.parse_args(argv)
    terms: list[str] = []
    if a.terms.is_file():
        terms = read_terms(a.terms)
    else:
        print("warning: no terms file, only the generic rules ran")
    snippets: list[str] = []
    if a.mod_texts.is_file():
        lines = a.mod_texts.read_text(encoding="utf-8-sig").splitlines()
        snippets = [t.strip().lower() for t in lines if len(t.strip()) >= SNIPPET_MIN]
    else:
        print("warning: no mod texts file, the mod text rule did not run")
    total = 0
    for target in a.files:
        raw = target.read_bytes()
        found = scan_bytes(target.name, raw, terms, snippets)
        if zipfile.is_zipfile(io.BytesIO(raw)) and target.suffix.lower() == ".zip":
            found += scan_zip(target.name, raw, terms, snippets)
        for x in found:
            print(x)
        total += len(found)
        if not found:
            print(f"{target.name}: clean ({len(raw)} bytes, {len(terms)} terms, {len(snippets)} mod snippets)")
    return 1 if total else 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
