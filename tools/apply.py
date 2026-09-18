#!/usr/bin/env python3
"""Apply an IPS patch to a Demon's Blazon ROM, with verification either side.

Written for people who are not going to build from source: no dependencies
beyond a stock Python 3, no toolchain, no container. It exists mainly to catch
the two mistakes that produce a ROM that boots to a black screen and gives no
hint why - patching the USA release, and patching a dump that still has its
512-byte copier header, where every patch offset lands 512 bytes early.
"""

import argparse
import hashlib
import sys
from pathlib import Path

SOURCE_SHA1 = "a6dc126a1da593d900b33eb74cf33403075e9525"
SOURCE_NAME = "Demon's Blazon: Makai-mura Monshou-hen (Japan)"


def strip_copier_header(data):
    """Copier dumps prepend 512 bytes; a real cart dump is a whole number of KB."""
    if len(data) % 1024 == 512:
        return data[512:], True
    return data, False


def apply_ips(rom, patch):
    if patch[:5] != b"PATCH":
        raise ValueError("not an IPS patch (missing the 'PATCH' magic)")
    out = bytearray(rom)
    i = 5
    records = 0
    while True:
        if i + 3 > len(patch):
            raise ValueError("patch ended without an EOF marker")
        if patch[i:i + 3] == b"EOF":
            i += 3
            break
        offset = int.from_bytes(patch[i:i + 3], "big")
        i += 3
        size = int.from_bytes(patch[i:i + 2], "big")
        i += 2
        if size == 0:
            run = int.from_bytes(patch[i:i + 2], "big")
            i += 2
            value = patch[i]
            i += 1
            chunk = bytes([value]) * run
        else:
            chunk = patch[i:i + size]
            i += size
            if len(chunk) != size:
                raise ValueError("patch record runs past the end of the file")
        if offset + len(chunk) > len(out):
            out.extend(b"\x00" * (offset + len(chunk) - len(out)))
        out[offset:offset + len(chunk)] = chunk
        records += 1
    # An optional 3-byte trailer truncates the output.
    if i + 3 <= len(patch):
        del out[int.from_bytes(patch[i:i + 3], "big"):]
    return bytes(out), records


def die(*lines):
    sys.stdout.flush()
    print("", file=sys.stderr)
    for line in lines:
        print(line, file=sys.stderr)
    sys.exit(1)


def main():
    ap = argparse.ArgumentParser(
        description="Apply the Demon's Crest practice patch to your own ROM.")
    ap.add_argument("rom", type=Path, help="your unmodified Japanese ROM")
    ap.add_argument("-p", "--patch", type=Path, help="the .ips file (default: found next to this script)")
    ap.add_argument("-o", "--out", type=Path, help="where to write the patched ROM")
    ap.add_argument("--force", action="store_true", help="patch even if the source ROM is not recognised")
    args = ap.parse_args()

    if not args.rom.is_file():
        die(f"error: no such file: {args.rom}",
            "Check the name, and that you are running this from the folder the ROM is in.")

    patch_path = args.patch
    if patch_path is None:
        here = Path(__file__).resolve().parent
        for where in (here, Path.cwd(), here.parent / "build", Path.cwd() / "build"):
            candidates = sorted(where.glob("*.ips"))
            if len(candidates) == 1:
                patch_path = candidates[0]
                break
            if candidates:
                canonical = [c for c in candidates if c.name == "DemonsBlazon_Practice.ips"]
                if len(canonical) == 1:
                    patch_path = canonical[0]
                    break
                die("error: more than one .ips file found in " + str(where),
                    "Pass the one you want:  apply.py YourRom.sfc -p ThePatch.ips")
        else:
            die("error: could not find a .ips patch to apply.",
                "Pass it explicitly:  apply.py YourRom.sfc -p ThePatch.ips")

    if not patch_path.is_file():
        die(f"error: no such file: {patch_path}")

    raw = args.rom.read_bytes()
    rom, had_copier = strip_copier_header(raw)
    sha1 = hashlib.sha1(rom).hexdigest()

    print(f"ROM      {args.rom}")
    print(f"         {len(raw):,} bytes"
          + ("  (512-byte copier header found; it will be removed)" if had_copier else ""))
    print(f"         sha1 {sha1}")
    print(f"patch    {patch_path}")

    forced = False
    if sha1 != SOURCE_SHA1:
        forced = True
        lines = ["error: this is not the ROM the patch was built against.",
                 f"  expected  {SOURCE_SHA1}   {SOURCE_NAME}",
                 f"  got       {sha1}",
                 "",
                 "Most likely you have the USA release, Demon's Crest. It is a different",
                 "build with a different code layout, so this patch would corrupt it.",
                 "The patch needs the Japanese release, 2,097,152 bytes with no header.",
                 "",
                 "Pass --force to patch anyway. Expect it not to boot."]
        if not args.force:
            die(*lines)
        for line in lines[:-2]:
            print(line, file=sys.stderr)
        print("\ncontinuing because --force was given\n", file=sys.stderr)

    try:
        patched, records = apply_ips(rom, patch_path.read_bytes())
    except ValueError as exc:
        die(f"error: {exc}",
            "The patch file looks damaged. Download it again.")

    out = args.out or args.rom.with_name(args.rom.stem + "_Practice.sfc")
    out.write_bytes(patched)
    result = hashlib.sha1(patched).hexdigest()

    print(f"\napplied  {records} record(s)")
    print(f"wrote    {out}")
    print(f"         sha1 {result}")

    expected_path = patch_path.with_suffix(patch_path.suffix + ".sha1")
    if forced:
        print("\n         not verified: patched with --force from an unrecognised ROM")
    elif expected_path.is_file():
        expected = expected_path.read_text().split()[0]
        if expected == result:
            print(f"         matches {expected_path.name} - verified")
        else:
            die("error: the patched ROM does not match the expected hash.",
                f"  expected  {expected}",
                f"  got       {result}",
                "",
                "The patch applied but produced the wrong bytes, which should not happen.",
                f"Delete {out.name} and report this.")

    print("\nDone. Copy the patched ROM to your flash cart or load it in an emulator.")


if __name__ == "__main__":
    main()
