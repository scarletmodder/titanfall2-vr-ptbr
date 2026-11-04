"""Proves the guards find personal data in the tree, in the history and in the bytes of exe and zip.

All values are invented and assembled at run time, so this file passes its own guard. Runs in
temporary repositories. Usage: python tests/test_guards.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUARD = ROOT / "scripts" / "guard.py"
SCAN = ROOT / "scripts" / "scan_binary.py"

TERM = "Zorbleton" + "Chimera"
SAMPLES = {
    "personal-term": f"name: {TERM}",
    "user-path": "folder: C:" + "\\Users\\" + "janedoe\\games",
    "home-path": "folder: /ho" + "me/" + "janedoe/games",
    "data-folder": "folder: x\\App" + "Data\\Local\\y",
    "email": "contact: janedoe" + "@" + "provider.com",
    "private-ip": "ip: 192" + ".168.7.9",
    "mac": "mac: 0A:1B:2C:" + "3D:4E:5F",
}
failures = 0


def check(cond: bool, msg: str) -> None:
    global failures
    print(("  OK    " if cond else "  FAIL  ") + msg)
    failures += 0 if cond else 1


def run(*args: object, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(a) for a in args], check=False, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
        errors="replace", env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )


def git(*args: str, cwd: Path) -> None:
    identity = ["-c", "user.name=Test", "-c", "user.email=noreply@example.com", "-c", "commit.gpgsign=false"]
    subprocess.run(["git", *identity, *args], cwd=cwd, check=True, capture_output=True)


def new_repo(base: Path, name: str) -> Path:
    r = base / name
    r.mkdir()
    git("init", "-q", "-b", "main", cwd=r)
    (r / ".gitignore").write_text("private/\n", encoding="utf-8")
    (r / "private").mkdir()
    (r / "private" / "guard-terms.txt").write_text(TERM + "\n", encoding="utf-8")
    return r


def main() -> int:
    with tempfile.TemporaryDirectory() as t:
        base = Path(t)

        print("[1] Tree")
        r = new_repo(base, "tree")
        (r / "clean.txt").write_text("nothing here\n", encoding="utf-8")
        check(run(sys.executable, GUARD, "--root", ".", cwd=r).returncode == 0, "clean tree passes")
        for name, text in SAMPLES.items():
            (r / "dirty.txt").write_text(text + "\n", encoding="utf-8")
            out = run(sys.executable, GUARD, "--root", ".", cwd=r)
            check(out.returncode == 1, f"finds {name}")
            value = text.split(": ", 1)[1]
            check(value not in out.stdout, f"output does not repeat the value of {name}")
        (r / "dirty.txt").unlink()
        (r / f"{TERM}.txt").write_text("x\n", encoding="utf-8")
        check(run(sys.executable, GUARD, "--root", ".", cwd=r).returncode == 1, "finds a term in the file name")
        (r / f"{TERM}.txt").unlink()
        (r / "ok.txt").write_text("uses $env:LOCALAPPDATA and author 341213439+scarletmodder@users.noreply.github.com\n", encoding="utf-8")
        check(run(sys.executable, GUARD, "--root", ".", cwd=r).returncode == 0, "environment variable and noreply pass")

        (r / "ok.txt").unlink()
        (r / "dirty.txt").write_text("author 12345+otheraccount@users." + "noreply.github.com\n", encoding="utf-8")
        check(run(sys.executable, GUARD, "--root", ".", cwd=r).returncode == 1, "finds the noreply of another account")
        (r / "dirty.txt").unlink()
        mod_snippet = "Invented mod phrase for the test"
        (r / "private" / "guard-mod-texts.txt").write_text(mod_snippet + "\nshort\n", encoding="utf-8")
        (r / "dirty.txt").write_text(f"pt: {mod_snippet.upper()}\n", encoding="utf-8")
        out = run(sys.executable, GUARD, "--root", ".", cwd=r)
        check(out.returncode == 1 and "mod-text" in out.stdout, "finds mod text, ignoring case")
        check(mod_snippet.upper() not in out.stdout, "output does not repeat the mod text")
        (r / "dirty.txt").write_text("short\n", encoding="utf-8")
        check(run(sys.executable, GUARD, "--root", ".", cwd=r).returncode == 0, "a snippet that is too short is ignored")
        (r / "dirty.txt").unlink()

        print("[2] Whole history")
        r = new_repo(base, "history")
        (r / "a.txt").write_text("clean\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: start", cwd=r)
        check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 0, "clean history passes")
        for name, text in SAMPLES.items():
            (r / "a.txt").write_text(text + "\n", encoding="utf-8")
            git("add", "a.txt", cwd=r)
            git("commit", "-qm", "chore: dirty", cwd=r)
            (r / "a.txt").write_text("clean\n", encoding="utf-8")
            git("add", "a.txt", cwd=r)
            git("commit", "-qm", "chore: clean", cwd=r)
            check(run(sys.executable, GUARD, "--root", ".", cwd=r).returncode == 0, f"{name}: current tree is clean")
            check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 1, f"{name}: finds it in an old version")
            git("reset", "-q", "--hard", "HEAD~2", cwd=r)
            git("reflog", "expire", "--expire=now", "--all", cwd=r)
            git("gc", "-q", "--prune=now", cwd=r)
        r = new_repo(base, "message")
        (r / "a.txt").write_text("clean\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", f"chore: request from {TERM}", cwd=r)
        check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 1, "finds a term in a commit message")
        r = new_repo(base, "author")
        (r / "a.txt").write_text("clean\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        subprocess.run(["git", "-c", "user.name=" + TERM, "-c", "user.email=noreply@example.com", "commit", "-qm", "chore: x"], cwd=r, check=True, capture_output=True)
        check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 1, "finds a term in the author name")

        r = new_repo(base, "tag")
        (r / "a.txt").write_text("clean\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: x", cwd=r)
        check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 0, "tag: clean repository passes before the tag")
        email = "janedoe" + "@" + "provider.com"
        subprocess.run(
            ["git", "-c", "user.name=Test", "-c", f"user.email={email}", "tag", "-a", "v9", "-m", "release"], cwd=r, check=True, capture_output=True
        )
        out = run(sys.executable, GUARD, "--root", ".", "--history", cwd=r)
        check(out.returncode == 1 and "history tag" in out.stdout, "finds the e-mail of whoever created the annotated tag")
        git("tag", "-d", "v9", cwd=r)
        git("tag", "-a", "v9", "-m", f"request from {TERM}", cwd=r)
        out = run(sys.executable, GUARD, "--root", ".", "--history", cwd=r)
        check(out.returncode == 1 and "history tag" in out.stdout, "finds a term in the annotated tag message")
        r = new_repo(base, "history-noreply")
        (r / "a.txt").write_text("author 1+x@users." + "noreply.github.com\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: x", cwd=r)
        (r / "a.txt").write_text("clean\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: y", cwd=r)
        check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 1, "a foreign noreply in an old version is found")
        r = new_repo(base, "author-noreply")
        (r / "a.txt").write_text("clean\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)

        def commit_as(email: str, msg: str, repo: Path) -> None:
            (repo / "a.txt").write_text(msg + "\n", encoding="utf-8")
            git("add", "a.txt", cwd=repo)
            subprocess.run(["git", "-c", "user.name=Test", "-c", f"user.email={email}", "commit", "-qm", msg], cwd=repo, check=True, capture_output=True)

        commit_as("12345+collaborator@users." + "noreply.github.com", "chore: a", r)
        check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 0, "an author with the noreply of another account passes")
        r = new_repo(base, "author-plain")
        commit_as("janedoe" + "@" + "provider.com", "chore: a", r)
        check(run(sys.executable, GUARD, "--root", ".", "--history", cwd=r).returncode == 1, "an author with a plain e-mail is found")
        r = new_repo(base, "author-term")
        commit_as(f"12345+{TERM}@users." + "noreply.github.com", "chore: a", r)
        out = run(sys.executable, GUARD, "--root", ".", "--history", cwd=r)
        check(out.returncode == 1 and "personal-term" in out.stdout, "a noreply with a personal term is found")
        r = new_repo(base, "mixed-message")
        commit_as("1+x@users." + "noreply.github.com", "chore: a from 1+x@users." + "noreply.github.com and janedoe" + "@" + "provider.com", r)
        out = run(sys.executable, GUARD, "--root", ".", "--commits", "HEAD", cwd=r)
        check(any(x.startswith("commit ") and ": email:" in x for x in out.stdout.splitlines()), "a plain e-mail next to a noreply in the message is found")
        r = new_repo(base, "history-mod")
        (r / "private" / "guard-mod-texts.txt").write_text(mod_snippet + "\n", encoding="utf-8")
        (r / "a.txt").write_text(mod_snippet + "\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: x", cwd=r)
        (r / "a.txt").write_text("clean\n", encoding="utf-8")
        git("add", "a.txt", cwd=r)
        git("commit", "-qm", "chore: y", cwd=r)
        out = run(sys.executable, GUARD, "--root", ".", "--history", cwd=r)
        check(out.returncode == 1 and "mod-text" in out.stdout, "finds mod text in an old version")

        print("[3] Bytes of exe and zip")
        terms = base / "terms.txt"
        terms.write_text(TERM + "\n", encoding="utf-8")
        clean = base / "clean.exe"
        clean.write_bytes(b"MZ" + b"\0" * 64 + "any text".encode("utf-16-le"))
        check(run(sys.executable, SCAN, "--terms", terms, clean, cwd=base).returncode == 0, "clean binary passes")
        for name, text in SAMPLES.items():
            value = text.split(": ", 1)[1]
            for enc in ("ascii", "utf-16-le"):
                for offset in (b"", b"\0"):
                    target = base / "dirty.exe"
                    target.write_bytes(b"\x01\x02\x03" + offset + value.encode(enc) + b"\x01\x02")
                    check(run(sys.executable, SCAN, "--terms", terms, target, cwd=base).returncode == 1, f"finds {name} in {enc}, offset {len(offset)}")
        pdb = base / "pdb.exe"
        pdb.write_bytes(b"MZ\0x\\Launcher." + b"pdb\0")
        check(run(sys.executable, SCAN, "--terms", terms, pdb, cwd=base).returncode == 1, "finds a PDB reference")

        mod_texts = base / "texts.txt"
        mod_texts.write_text(mod_snippet + "\n", encoding="utf-8")
        for enc in ("ascii", "utf-16-le"):
            target = base / "mod.exe"
            target.write_bytes(b"\x01\x02\x03" + mod_snippet.encode(enc) + b"\x01\x02")
            out = run(sys.executable, SCAN, "--terms", terms, "--mod-texts", mod_texts, target, cwd=base)
            check(out.returncode == 1 and "mod-text" in out.stdout, f"finds mod text in the binary, {enc}")

        def make_zip(name: str, entries: dict[str, bytes], date: tuple[int, int, int, int, int, int] = (2026, 1, 1, 0, 0, 0)) -> Path:
            path = base / name
            with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
                for n, b in entries.items():
                    z.writestr(zipfile.ZipInfo(n, date_time=date), b, zipfile.ZIP_DEFLATED)
            return path

        def scan_zip(target: Path) -> int:
            return run(sys.executable, SCAN, "--terms", terms, target, cwd=base).returncode

        check(scan_zip(make_zip("ok.zip", {"Titanfall2VR-PTBR.exe": b"MZ", "LICENSE.txt": b"MIT"})) == 0, "clean zip passes")
        check(scan_zip(make_zip("date.zip", {"LICENSE.txt": b"MIT"}, (2026, 3, 4, 5, 6, 8))) == 1, "finds a build date in the zip")
        check(scan_zip(make_zip("extra.zip", {"LICENSE.txt": b"MIT", "notes.txt": b"x"})) == 1, "finds an extra file in the zip")
        check(scan_zip(make_zip("inside.zip", {"LICENSE.txt": (" " + TERM + " ").encode("utf-16-le")})) == 1, "finds a compressed term inside the zip")
    print()
    print("GUARDS OK" if failures == 0 else f"{failures} FAILURE(S) in the guards")
    return 1 if failures else 0


if __name__ == "__main__":
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
