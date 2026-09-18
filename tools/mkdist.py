#!/usr/bin/env python3
"""Assemble the folder that gets handed to players.

Everything in here is derived from files already in the repo, so the player
documentation cannot drift from the developer documentation: the controls
section is lifted out of README.md rather than kept in a second copy.

The patched ROM is deliberately NOT included. The IPS patch plus the player's
own dump is the only distributable form.
"""

import argparse
import hashlib
import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# The player folder ships no docs/ tree, so references into it would be dead
# links. Rewrite the ones we know about and refuse to ship an unknown one.
DOC_REWRITES = {
    "see `docs/route-any.md`": "see the project repository",
    "`docs/route-any.md`": "the project repository",
}


def delink_docs(text, where):
    for old, new in DOC_REWRITES.items():
        text = text.replace(old, new)
    stragglers = sorted(set(re.findall(r"`?docs/[\w./-]+`?", text)))
    if stragglers:
        sys.exit(f"error: {where} references documentation the player folder does not\n"
                 f"contain: {', '.join(stragglers)}\n"
                 f"Add a rewrite to DOC_REWRITES in tools/mkdist.py, or ship the file.")
    return text


def player_section(readme):
    """Lift '## Using the practice ROM' out of README.md, up to the next H2."""
    lines = readme.splitlines()
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("## Using the practice ROM"))
    except StopIteration:
        sys.exit("error: README.md no longer has a '## Using the practice ROM' section")
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].startswith("## ")), len(lines))
    return "\n".join(lines[start:end]).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ips", type=Path, required=True)
    ap.add_argument("--rom", type=Path, required=True, help="the patched ROM, for its hash only")
    ap.add_argument("--out", type=Path, required=True, help="directory to assemble into")
    ap.add_argument("--zip", type=Path, help="also write this zip")
    args = ap.parse_args()

    for path in (args.ips, args.rom):
        if not path.is_file():
            sys.exit(f"error: missing {path}; run `make patch` first")

    version = (ROOT / "VERSION").read_text().strip()
    out = args.out
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    shutil.copy2(args.ips, out / "DemonsBlazon_Practice.ips")
    shutil.copy2(ROOT / "tools/apply.py", out / "apply.py")
    shutil.copy2(ROOT / "dist-template/PATCHING.md", out / "PATCHING.md")

    rom_sha1 = hashlib.sha1(args.rom.read_bytes()).hexdigest()
    (out / "DemonsBlazon_Practice.ips.sha1").write_text(
        f"{rom_sha1}  DemonsBlazon_Practice.sfc\n")

    readme = delink_docs(player_section((ROOT / "README.md").read_text()), "README.md")
    delink_docs((ROOT / "dist-template/PATCHING.md").read_text(), "PATCHING.md")
    (out / "README.md").write_text(
        f"# Demon's Crest practice ROM v{version}\n"
        f"\nAn Any% practice hack of the Japanese release, *Demon's Blazon:\n"
        f"Makai-mura Monshou-hen*, for real hardware and emulators.\n"
        f"\n**Start with `PATCHING.md`** — you need to apply the patch to your own\n"
        f"ROM before any of the following applies.\n\n"
        + readme)

    names = sorted(p.name for p in out.iterdir())
    print(f"assembled {out}  (v{version})")
    for name in names:
        print(f"  {name:36} {(out / name).stat().st_size:>8,} bytes")
    print(f"patched ROM sha1  {rom_sha1}")

    if args.zip:
        args.zip.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(args.zip, "w", zipfile.ZIP_DEFLATED) as z:
            for name in names:
                z.write(out / name, f"DemonsCrestPractice-v{version}/{name}")
        print(f"wrote {args.zip}  ({args.zip.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
