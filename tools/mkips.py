#!/usr/bin/env python3
"""Emit an IPS patch from an original ROM to a modified ROM."""

import sys
from pathlib import Path

MAX_RECORD = 0xFFFF
EOF_MARKER = 0x454F46  # An offset equal to "EOF" would terminate the patch early.


def records(src, dst):
    i = 0
    while i < len(dst):
        orig = src[i] if i < len(src) else None
        if dst[i] == orig:
            i += 1
            continue
        start = i
        while i < len(dst) and i - start < MAX_RECORD:
            orig = src[i] if i < len(src) else None
            if dst[i] == orig:
                # Tolerate short matching gaps rather than splitting into tiny records.
                lookahead = dst[i:i + 6]
                base = src[i:i + 6]
                if len(base) == len(lookahead) and lookahead == base:
                    break
            i += 1
        yield start, dst[start:i]


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: mkips.py <original.sfc> <modified.sfc> <out.ips>")
    src = Path(sys.argv[1]).read_bytes()
    dst = Path(sys.argv[2]).read_bytes()

    out = bytearray(b"PATCH")
    count = 0
    for offset, chunk in records(src, dst):
        if offset == EOF_MARKER:
            offset -= 1
            chunk = dst[offset:offset + len(chunk) + 1]
        if offset > 0xFFFFFF:
            sys.exit("error: offset exceeds the 16MB IPS limit; use BPS instead")
        out += offset.to_bytes(3, "big") + len(chunk).to_bytes(2, "big") + chunk
        count += 1
    out += b"EOF"

    if len(dst) < len(src):
        out += len(dst).to_bytes(3, "big")

    Path(sys.argv[3]).write_bytes(out)
    changed = sum(len(c) for _, c in records(src, dst))
    print(f"wrote {sys.argv[3]}: {count} record(s), {changed:,} bytes changed, patch {len(out):,} bytes")

    if len(dst) > len(src):
        print(f"\nWARNING: the ROM grew by {len(dst) - len(src):,} bytes. IPS cannot express a size\n"
              f"         change compactly, so the whole appended region is embedded above.\n"
              f"         Use BPS (flips) for distribution if the ROM is expanded.", file=sys.stderr)


if __name__ == "__main__":
    main()
