#!/usr/bin/env python3
"""Encode and decode Demon's Crest progress state blocks.

The practice ROM sets progress by writing a hardcoded block rather than by
replaying a password, so route checkpoints need to be expressed as bytes. Doing
that by hand is error-prone: the block is nine bytes of packed bit flags.

The bit mapping is the one documented in memory-map/README.md, derived from
Item::completion_data() in FredYeye/Demon-s-Crest-Rando and verified against
password-loaded WRAM dumps on the JP ROM.

  decode   9 bytes -> readable item list
  encode   item names -> 9 bytes

Encoding writes SOURCE flags only. $1E52 bits 1-10 are a derived mirror the
game recomputes at $82:E11F, and $1E44 is likewise recomputed, so a written
block deliberately leaves them clear. A block encoded from a decoded dump will
therefore not always be byte-identical to that dump - the difference is the
mirror, and the game fills it in.

Usage:
    python3 tools/state.py decode 14 FF FF FF FF FF FF 03 00
    python3 tools/state.py decode --wram states/wram/town.wram
    python3 tools/state.py encode --hp 6 Buster "Earth Crest" Vellum1
    python3 tools/state.py known            # decode the documented passwords
"""

import argparse
import sys

# (byte offset from $1E50, bit, name). Source flags only.
FLAGS = [
    (1, 0, "Buster"),      (1, 1, "Tornado"),     (1, 2, "Claw"),
    (1, 3, "DemonFire"),
    (1, 4, "EarthCrest"),  (1, 5, "AirCrest"),    (1, 6, "WaterCrest"),
    (1, 7, "TimeCrest"),
    (2, 0, "UltimateCrest"),
    (3, 3, "Crown"),       (3, 4, "Skull"),       (3, 5, "Armor"),
    (3, 6, "Fang"),        (3, 7, "Hand"),
]
FLAGS += [(4, b, "HPUp%d" % (b + 1)) for b in range(8)]
FLAGS += [(5, b, "HPUp%d" % (b + 9)) for b in range(8)]
FLAGS += [(6, b, "Vellum%d" % (b + 1)) for b in range(5)]
FLAGS += [(6, 5 + b, "Potion%d" % (b + 1)) for b in range(3)]
FLAGS += [(7, b, "Potion%d" % (b + 4)) for b in range(2)]

BY_NAME = {n.lower(): (o, b) for o, b, n in FLAGS}

# Bits the game recomputes rather than reads. Writing them is harmless but
# pointless, and leaving them clear makes a hand-written block easier to read.
DERIVED = "$1E52 bits 1-10 (vellum/potion mirror, rebuilt at $82:E11F)"

KNOWN = {
    "boss rush": [0x04, 0, 0, 0, 0, 0, 0, 0],
    "level 2":   [0x06, 0x10, 0x42, 0x00, 0x03, 0x00, 0x81, 0x00],
    "level 3":   [0x07, 0x10, 0x02, 0x00, 0x07, 0x00, 0x01, 0x00],
    "level 5":   [0x0D, 0x77, 0xDE, 0x19, 0x5F, 0x23, 0xAF, 0x01],
    "all items": [0x14, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x03],
}


def decode(block):
    """Return (max_hp, [item names], [notes]) for a block of 8 or 9 bytes."""
    items = [n for o, b, n in FLAGS if o < len(block) and block[o] >> b & 1]
    notes = []
    mirror = (block[2] | (block[3] << 8)) & 0x07FE if len(block) > 3 else 0
    if mirror:
        notes.append("derived mirror present: %s" % DERIVED)
    if len(block) > 8 and block[8] & 1:
        notes.append("$1E58 bit 0 set - read by the area-variant selector $85:9B39")
    return block[0], items, notes


BASE_HP = 4        # max HP with no upgrades; see hp_invariant()


def hp_from_upgrades(block):
    """Max HP is BASE_HP plus one per HP-up flag. Exact on every known block."""
    n = bin(block[4]).count("1") + bin(block[5]).count("1")
    return BASE_HP + n


def hp_invariant():
    """Check $1E50 == 4 + HP-up count across the documented passwords."""
    bad = []
    for label, block in KNOWN.items():
        want = hp_from_upgrades(block)
        if block[0] != want:
            bad.append((label, block[0], want))
    return bad


def encode(max_hp, names):
    block = [0] * 9
    block[0] = max_hp
    unknown = []
    for n in names:
        key = n.lower().replace(" ", "").replace("_", "")
        if key not in BY_NAME:
            unknown.append(n)
            continue
        o, b = BY_NAME[key]
        block[o] |= 1 << b
    if unknown:
        raise SystemExit("unknown item name(s): %s\nvalid: %s"
                         % (", ".join(unknown),
                            ", ".join(n for _, _, n in FLAGS)))
    return block


def fmt(block):
    return " ".join("%02X" % b for b in block)


def show(label, block):
    hp, items, notes = decode(block)
    print("%s" % label)
    print("  $1E50-$1E58  %s" % fmt(block))
    print("  max HP       %d" % hp)
    print("  items (%d)   %s" % (len(items), ", ".join(items) if items else "none"))
    for n in notes:
        print("  note         %s" % n)
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("decode", help="decode a block to an item list")
    d.add_argument("bytes", nargs="*", help="hex bytes, 8 or 9 of them")
    d.add_argument("--wram", help="read $1E50-$1E58 from a 128KB WRAM dump instead")

    e = sub.add_parser("encode", help="encode an item list to a block")
    e.add_argument("--hp", type=int,
                   help="max HP for $1E50; derived from the HP-up flags if omitted")
    e.add_argument("items", nargs="*")

    sub.add_parser("check", help="verify the max-HP invariant against known blocks")

    sub.add_parser("known", help="decode the passwords in docs/passwords.md")

    args = ap.parse_args()

    if args.cmd == "check":
        bad = hp_invariant()
        for label, got, want in bad:
            print("FAIL %-10s $1E50=%d but 4 + HP-ups = %d" % (label, got, want))
        if bad:
            raise SystemExit("%d of %d known blocks violate the invariant"
                             % (len(bad), len(KNOWN)))
        print("OK  $1E50 == 4 + HP-up count for all %d known blocks" % len(KNOWN))
        return

    if args.cmd == "known":
        for label, block in KNOWN.items():
            show(label, block)
        return

    if args.cmd == "decode":
        if args.wram:
            data = open(args.wram, "rb").read()
            if len(data) < 0x1E59:
                raise SystemExit("%s is too small to hold $1E58" % args.wram)
            block = list(data[0x1E50:0x1E59])
            show(args.wram, block)
        else:
            if len(args.bytes) not in (8, 9):
                raise SystemExit("expected 8 or 9 hex bytes, got %d" % len(args.bytes))
            show("block", [int(x, 16) for x in args.bytes])
        return

    block = encode(args.hp or 0, args.items)
    if args.hp is None:
        block[0] = hp_from_upgrades(block)
    print(fmt(block))
    print("; max HP %d%s, %d item flag(s)"
          % (block[0], "" if args.hp else " (derived)", len(args.items)),
          file=sys.stderr)


if __name__ == "__main__":
    main()
