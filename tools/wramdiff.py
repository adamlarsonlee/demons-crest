#!/usr/bin/env python3
"""Diff WRAM dumps and name the differences from memory-map/README.md.

Built for the question "what changed between these two moments", which is how
this project localises a variable it cannot find by disassembly. The naming is
the point: a bare address list means re-deriving what each one is, and the map
already knows for 50-odd of them.

Dumps are the 128 KB of WRAM, $7E:0000-$7F:FFFF, as both tools/headless.py and
Mesen's Debug -> Memory Tools -> Work RAM -> export produce.

Addresses that change every frame regardless of what is being investigated are
suppressed by default, because they drown the signal. --all keeps them.
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WRAM_SIZE = 0x20000

# Known per-frame churn. Suppressed unless --all. Each entry is (start, end,
# why), end exclusive.
NOISE = [
    (0x0073, 0x0074, "frame counter"),
    (0x0086, 0x0087, "level-loop flag, written every frame"),
    (0x0090, 0x009C, "controller state"),
    (0x0100, 0x0200, "stack page"),
    (0x0300, 0x0500, "CGRAM shadow"),
]


def load_map():
    """Parse the address table. Returns [(addr, length, name)] sorted."""
    rows = []
    for line in (ROOT / "memory-map/README.md").read_text().splitlines():
        m = re.match(r"\|\s*([0-9A-Fa-f]{6})\s*\|([^|]*)\|([^|]*)\|([^|]*)", line)
        if not m:
            continue
        addr = int(m.group(1), 16)
        raw = m.group(2).strip()
        length = int(raw) if raw.isdigit() else 1
        rows.append((addr, length, m.group(4).strip()))
    return sorted(rows)


def name_for(addr, mapping):
    """The map entry covering addr, else the nearest one below it."""
    best = None
    for a, length, label in mapping:
        if a <= addr:
            best = (a, length, label)
        else:
            break
    if not best:
        return ""
    a, length, label = best
    if addr < a + length:
        return label if addr == a else f"{label} (+{addr - a})"
    if addr - a <= 0x20:
        return f"~{label} +{addr - a}?"
    return ""


def snes_addr(off):
    """The dump is $7E:0000-$7F:FFFF, so the second 64 KB is bank $7F."""
    return f"$7E:{off:04X}" if off < 0x10000 else f"$7F:{off - 0x10000:04X}"


def noise_reason(addr):
    for lo, hi, why in NOISE:
        if lo <= addr < hi:
            return why
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before", type=Path)
    ap.add_argument("after", type=Path)
    ap.add_argument("--all", action="store_true", help="do not suppress per-frame churn")
    ap.add_argument("--range", help="restrict to LO-HI, e.g. 1000-1100 or 1E50-1E58")
    ap.add_argument("--max", type=int, default=120, help="stop after this many runs")
    ap.add_argument("--control", type=Path,
                    help="a third dump taken in the same situation as BEFORE, with the "
                         "thing under investigation NOT done. Any address that also "
                         "differs between BEFORE and the control is ordinary churn and "
                         "is dropped, which is the only way to tell a cause from a "
                         "counter across two samples")
    args = ap.parse_args()

    a = args.before.read_bytes()
    b = args.after.read_bytes()
    for p, d in ((args.before, a), (args.after, b)):
        if len(d) != WRAM_SIZE:
            print(f"warning: {p} is {len(d):,} bytes, expected {WRAM_SIZE:,} "
                  f"(is it a WRAM dump?)", file=sys.stderr)
    n = min(len(a), len(b))

    lo, hi = 0, n
    if args.range:
        parts = args.range.split("-")
        lo, hi = int(parts[0], 16), int(parts[1], 16) + 1

    mapping = load_map()

    control = None
    if args.control:
        control = args.control.read_bytes()
        n = min(n, len(control))

    def changed(i):
        """Differs between before and after, and not merely churning."""
        if a[i] == b[i]:
            return False
        if control is not None and a[i] != control[i]:
            return False
        return True

    runs, start = [], None
    for i in range(lo, min(hi, n)):
        if changed(i):
            if start is None:
                start = i
        elif start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, min(hi, n)))

    shown = suppressed = 0
    print(f"{args.before.name}  ->  {args.after.name}")
    if control is not None:
        churn = sum(1 for i in range(lo, min(hi, n)) if a[i] != b[i] and a[i] != control[i])
        print(f"control {args.control.name}: {churn:,} byte(s) dropped as churn")
    print(f"{sum(e - s for s, e in runs):,} differing bytes in {len(runs)} run(s)\n")
    print(f"{'address':>12} {'len':>4}  {'before':<14} {'after':<14} what")
    print("-" * 82)
    for s, e in runs:
        if not args.all and all(noise_reason(x) for x in range(s, e)):
            suppressed += e - s
            continue
        if shown >= args.max:
            print(f"... {len(runs) - shown} more run(s); raise --max")
            break
        bef = " ".join(f"{x:02X}" for x in a[s:e][:4]) + ("…" if e - s > 4 else "")
        aft = " ".join(f"{x:02X}" for x in b[s:e][:4]) + ("…" if e - s > 4 else "")
        label = name_for(s, mapping) or ""
        why = noise_reason(s)
        if why and args.all:
            label = f"[{why}] {label}".strip()
        print(f"  {snes_addr(s):>9} {e-s:4}  {bef:<14} {aft:<14} {label}")
        shown += 1

    if suppressed and not args.all:
        print(f"\n{suppressed:,} bytes suppressed as per-frame churn; --all to see them")


if __name__ == "__main__":
    main()
