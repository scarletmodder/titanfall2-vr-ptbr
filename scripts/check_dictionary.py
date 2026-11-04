"""Checks the public dictionary and the script encoding without needing the mod.

- each entry only has the fields of the public format, never an `en`;
- lowercase hexadecimal hash of 64 digits, no repeated hash in the same file;
- translation equal to the English (hash of `pt` equal to `enHash`) only for a technical name in the list below;
- template without an internal name in clear: comparison with a quoted literal is refused;
- JSON in UTF-8 without BOM and with LF;
- every .ps1 in UTF-8 with BOM (required by Windows PowerShell 5.1) and LF.
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HASH = re.compile(r"^[0-9a-f]{64}$")
TOP_TOKENS = {"file", "name", "tokens"}
TOP_LINES = {"file", "name", "scan", "lines"}
# Generic technical name, the same in any language: it may stay as it is in the mod.
PT_EQUAL_TO_EN = {"TF2VR_SMAA"}
LITERAL_COMPARISON = re.compile(r'(?:==|!=)\s*"')


def check_json(path: Path) -> list[str]:
    errors: list[str] = []
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        errors.append(f"{path.name}: has a BOM")
    if b"\r" in raw:
        errors.append(f"{path.name}: has a CR")
    data = json.loads(raw.decode("utf-8"))
    is_tokens = path.name == "tokens.json"
    top = TOP_TOKENS if is_tokens else TOP_LINES
    if set(data) - top:
        errors.append(f"{path.name}: unexpected top-level fields: {sorted(set(data) - top)}")
    seen: set[str] = set()
    for n, e in enumerate(data["tokens" if is_tokens else "lines"], 1):
        label = f"{path.name}, entry {n}"
        fields = set(e)
        if is_tokens:
            if fields != {"key", "enHash", "pt"}:
                errors.append(f"{label}: fields {sorted(fields)}")
        elif fields not in ({"enHash", "texts"}, {"enHash", "template"}):
            errors.append(f"{label}: fields {sorted(fields)}")
        if is_tokens and e.get("key") not in PT_EQUAL_TO_EN and hashlib.sha256(str(e.get("pt")).encode("utf-8")).hexdigest() == e.get("enHash"):
            errors.append(f"{label}: the translation is equal to the mod text")
        if "template" in e and LITERAL_COMPARISON.search(e["template"]):
            errors.append(f"{label}: template with an internal name in clear")
        if not HASH.match(str(e.get("enHash"))):
            errors.append(f"{label}: invalid enHash")
        key = e.get("key", e.get("enHash"))
        if key in seen:
            errors.append(f"{label}: repeated")
        seen.add(key)
    return errors


def main() -> int:
    errors: list[str] = []
    files = sorted((ROOT / "tool" / "translations").glob("*.json"))
    if not files:
        errors.append("no dictionary found")
    for path in files:
        errors.extend(check_json(path))
    scripts = [*ROOT.glob("tool/*.ps1"), *ROOT.glob("scripts/*.ps1"), *ROOT.glob("tests/*.ps1")]
    for path in scripts:
        raw = path.read_bytes()
        if not raw.startswith(b"\xef\xbb\xbf"):
            errors.append(f"{path.name}: no UTF-8 BOM")
        if b"\r" in raw:
            errors.append(f"{path.name}: has a CR")
    for e in errors:
        print(e)
    print(f"{len(errors)} problem(s)" if errors else f"dictionary ok: {len(files)} files, {len(scripts)} scripts")
    return 1 if errors else 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
