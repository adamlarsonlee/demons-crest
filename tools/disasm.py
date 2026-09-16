#!/usr/bin/env python3
"""65816 disassembler for LoROM SNES images.

Instruction width depends on the M and X status flags, so the initial widths
can be given and REP/SEP are tracked as they are encountered. Where the widths
are wrong the output desynchronises, so they are reported in the header.
"""

import argparse
import re
from pathlib import Path

# opcode -> (mnemonic, mode). Modes:
#  imp implied          acc accumulator      imm8/imm16 fixed immediate
#  immM immediate sized by M flag            immX immediate sized by X flag
#  dp  $nn              dpx $nn,X            dpy $nn,Y
#  idp ($nn)            idx ($nn,X)          idy ($nn),Y
#  idl [$nn]            idly [$nn],Y
#  sr  $nn,S            isry ($nn,S),Y
#  abs $nnnn            abx $nnnn,X          aby $nnnn,Y
#  abl $nnnnnn          alx $nnnnnn,X
#  ind ($nnnn)          iax ($nnnn,X)        ial [$nnnn]
#  rel signed 8         rell signed 16       bm  block move
TABLE = {}
_T = """
00 BRK imm8   01 ORA idx    02 COP imm8   03 ORA sr     04 TSB dp     05 ORA dp     06 ASL dp     07 ORA idl
08 PHP imp    09 ORA immM   0A ASL acc    0B PHD imp    0C TSB abs    0D ORA abs    0E ASL abs    0F ORA abl
10 BPL rel    11 ORA idy    12 ORA idp    13 ORA isry   14 TRB dp     15 ORA dpx    16 ASL dpx    17 ORA idly
18 CLC imp    19 ORA aby    1A INC acc    1B TCS imp    1C TRB abs    1D ORA abx    1E ASL abx    1F ORA alx
20 JSR abs    21 AND idx    22 JSL abl    23 AND sr     24 BIT dp     25 AND dp     26 ROL dp     27 AND idl
28 PLP imp    29 AND immM   2A ROL acc    2B PLD imp    2C BIT abs    2D AND abs    2E ROL abs    2F AND abl
30 BMI rel    31 AND idy    32 AND idp    33 AND isry   34 BIT dpx    35 AND dpx    36 ROL dpx    37 AND idly
38 SEC imp    39 AND aby    3A DEC acc    3B TSC imp    3C BIT abx    3D AND abx    3E ROL abx    3F AND alx
40 RTI imp    41 EOR idx    42 WDM imm8   43 EOR sr     44 MVP bm     45 EOR dp     46 LSR dp     47 EOR idl
48 PHA imp    49 EOR immM   4A LSR acc    4B PHK imp    4C JMP abs    4D EOR abs    4E LSR abs    4F EOR abl
50 BVC rel    51 EOR idy    52 EOR idp    53 EOR isry   54 MVN bm     55 EOR dpx    56 LSR dpx    57 EOR idly
58 CLI imp    59 EOR aby    5A PHY imp    5B TCD imp    5C JML abl    5D EOR abx    5E LSR abx    5F EOR alx
60 RTS imp    61 ADC idx    62 PER rell   63 ADC sr     64 STZ dp     65 ADC dp     66 ROR dp     67 ADC idl
68 PLA imp    69 ADC immM   6A ROR acc    6B RTL imp    6C JMP ind    6D ADC abs    6E ROR abs    6F ADC abl
70 BVS rel    71 ADC idy    72 ADC idp    73 ADC isry   74 STZ dpx    75 ADC dpx    76 ROR dpx    77 ADC idly
78 SEI imp    79 ADC aby    7A PLY imp    7B TDC imp    7C JMP iax    7D ADC abx    7E ROR abx    7F ADC alx
80 BRA rel    81 STA idx    82 BRL rell   83 STA sr     84 STY dp     85 STA dp     86 STX dp     87 STA idl
88 DEY imp    89 BIT immM   8A TXA imp    8B PHB imp    8C STY abs    8D STA abs    8E STX abs    8F STA abl
90 BCC rel    91 STA idy    92 STA idp    93 STA isry   94 STY dpx    95 STA dpx    96 STX dpy    97 STA idly
98 TYA imp    99 STA aby    9A TXS imp    9B TXY imp    9C STZ abs    9D STA abx    9E STZ abx    9F STA alx
A0 LDY immX   A1 LDA idx    A2 LDX immX   A3 LDA sr     A4 LDY dp     A5 LDA dp     A6 LDX dp     A7 LDA idl
A8 TAY imp    A9 LDA immM   AA TAX imp    AB PLB imp    AC LDY abs    AD LDA abs    AE LDX abs    AF LDA abl
B0 BCS rel    B1 LDA idy    B2 LDA idp    B3 LDA isry   B4 LDY dpx    B5 LDA dpx    B6 LDX dpy    B7 LDA idly
B8 CLV imp    B9 LDA aby    BA TSX imp    BB TYX imp    BC LDY abx    BD LDA abx    BE LDX aby    BF LDA alx
C0 CPY immX   C1 CMP idx    C2 REP imm8   C3 CMP sr     C4 CPY dp     C5 CMP dp     C6 DEC dp     C7 CMP idl
C8 INY imp    C9 CMP immM   CA DEX imp    CB WAI imp    CC CPY abs    CD CMP abs    CE DEC abs    CF CMP abl
D0 BNE rel    D1 CMP idy    D2 CMP idp    D3 CMP isry   D4 PEI dp     D5 CMP dpx    D6 DEC dpx    D7 CMP idly
D8 CLD imp    D9 CMP aby    DA PHX imp    DB STP imp    DC JML ial    DD CMP abx    DE DEC abx    DF CMP alx
E0 CPX immX   E1 SBC idx    E2 SEP imm8   E3 SBC sr     E4 CPX dp     E5 SBC dp     E6 INC dp     E7 SBC idl
E8 INX imp    E9 SBC immM   EA NOP imp    EB XBA imp    EC CPX abs    ED SBC abs    EE INC abs    EF SBC abl
F0 BEQ rel    F1 SBC idy    F2 SBC idp    F3 SBC isry   F4 PEA abs    F5 SBC dpx    F6 INC dpx    F7 SBC idly
F8 SED imp    F9 SBC aby    FA PLX imp    FB XCE imp    FC JSR iax    FD SBC abx    FE INC abx    FF SBC alx
"""
for _tok in _T.split():
    pass
_parts = _T.split()
for i in range(0, len(_parts), 3):
    TABLE[int(_parts[i], 16)] = (_parts[i + 1], _parts[i + 2])
assert len(TABLE) == 256, f"opcode table has {len(TABLE)} entries, expected 256"

FIXED = {"imp": 0, "acc": 0, "imm8": 1, "dp": 1, "dpx": 1, "dpy": 1, "idp": 1,
         "idx": 1, "idy": 1, "idl": 1, "idly": 1, "sr": 1, "isry": 1, "rel": 1,
         "imm16": 2, "abs": 2, "abx": 2, "aby": 2, "ind": 2, "iax": 2,
         "ial": 2, "rell": 2, "bm": 2, "abl": 3, "alx": 3}


def operand_size(mode, m_width, x_width):
    if mode == "immM":
        return 2 if m_width == 16 else 1
    if mode == "immX":
        return 2 if x_width == 16 else 1
    return FIXED[mode]


def snes_to_file(bank, addr):
    """LoROM: banks $80-$FF expose 32KB at $8000-$FFFF."""
    return ((bank & 0x7F) * 0x8000) + (addr - 0x8000)


def parse_addr(text):
    t = text.replace("$", "").replace(":", "").strip()
    v = int(t, 16)
    return (v >> 16) & 0xFF, v & 0xFFFF


def load_labels(path):
    """Parse a Mesen .msl label file into {('WORK'|'PRG', addr): name}."""
    labels = {}
    if not path or not Path(path).is_file():
        return labels
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        m = re.match(r"^(WORK|PRG|REG):([0-9A-Fa-f]+)(?:-[0-9A-Fa-f]+)?:([^:]+)", line.strip())
        if m:
            labels[(m.group(1), int(m.group(2), 16))] = m.group(3)
    return labels


def annotate(mode, value, labels):
    """Name a known RAM address or hardware register where one applies."""
    if mode in ("dp", "dpx", "dpy", "idp", "idx", "idy", "idl", "idly"):
        key = value
    elif mode in ("abs", "abx", "aby", "ind", "iax", "ial"):
        key = value
    elif mode in ("abl", "alx"):
        bank = (value >> 16) & 0xFF
        if bank in (0x7E,) or bank <= 0x3F:
            key = value & 0xFFFF
        else:
            return ""
    else:
        return ""
    for domain in ("WORK", "REG"):
        if (domain, key) in labels:
            return f"  ; {labels[(domain, key)]}"
    return ""


def format_operand(mode, raw, pc_bank, next_addr):
    if mode in ("imp",):
        return ""
    if mode == "acc":
        return "A"
    if mode in ("imm8",):
        return f"#${raw:02X}"
    if mode in ("immM", "immX"):
        return f"#${raw:02X}" if raw <= 0xFF else f"#${raw:04X}"
    if mode == "imm16":
        return f"#${raw:04X}"
    if mode == "dp":
        return f"${raw:02X}"
    if mode == "dpx":
        return f"${raw:02X},X"
    if mode == "dpy":
        return f"${raw:02X},Y"
    if mode == "idp":
        return f"(${raw:02X})"
    if mode == "idx":
        return f"(${raw:02X},X)"
    if mode == "idy":
        return f"(${raw:02X}),Y"
    if mode == "idl":
        return f"[${raw:02X}]"
    if mode == "idly":
        return f"[${raw:02X}],Y"
    if mode == "sr":
        return f"${raw:02X},S"
    if mode == "isry":
        return f"(${raw:02X},S),Y"
    if mode == "abs":
        return f"${raw:04X}"
    if mode == "abx":
        return f"${raw:04X},X"
    if mode == "aby":
        return f"${raw:04X},Y"
    if mode == "ind":
        return f"(${raw:04X})"
    if mode == "iax":
        return f"(${raw:04X},X)"
    if mode == "ial":
        return f"[${raw:04X}]"
    if mode == "abl":
        return f"${raw:06X}"
    if mode == "alx":
        return f"${raw:06X},X"
    if mode == "rel":
        off = raw - 256 if raw > 127 else raw
        return f"${pc_bank:02X}:{(next_addr + off) & 0xFFFF:04X}"
    if mode == "rell":
        off = raw - 65536 if raw > 32767 else raw
        return f"${pc_bank:02X}:{(next_addr + off) & 0xFFFF:04X}"
    if mode == "bm":
        return f"${raw & 0xFF:02X},${(raw >> 8) & 0xFF:02X}"
    return f"${raw:X}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("--start", required=True, help="SNES address, e.g. $80C5C0")
    group = ap.add_mutually_exclusive_group()
    group.add_argument("--end", help="SNES address to stop at")
    group.add_argument("--count", type=int, default=32, help="instruction count")
    ap.add_argument("--m", type=int, choices=(8, 16), default=8,
                    help="initial accumulator width")
    ap.add_argument("--x", type=int, choices=(8, 16), default=8,
                    help="initial index width")
    ap.add_argument("--labels", default="mesen-s/labels.msl")
    args = ap.parse_args()

    rom = Path(args.rom).read_bytes()
    if len(rom) % 1024 == 512:
        rom = rom[512:]
    labels = load_labels(args.labels)

    bank, addr = parse_addr(args.start)
    end_addr = parse_addr(args.end)[1] if args.end else None
    m_width, x_width = args.m, args.x

    print(f"; {args.rom}  start ${bank:02X}:{addr:04X}  "
          f"initial M={m_width} X={x_width}  {len(labels)} labels")

    issued = 0
    while True:
        if end_addr is not None and addr >= end_addr:
            break
        if end_addr is None and issued >= args.count:
            break

        off = snes_to_file(bank, addr)
        if not 0 <= off < len(rom):
            print("; address outside ROM")
            break
        op = rom[off]
        mnem, mode = TABLE[op]
        n = operand_size(mode, m_width, x_width)
        raw_bytes = rom[off:off + 1 + n]
        raw = int.from_bytes(raw_bytes[1:], "little") if n else 0

        next_addr = (addr + 1 + n) & 0xFFFF
        text = format_operand(mode, raw, bank, next_addr)
        note = annotate(mode, raw, labels)

        # Track register widths so later instruction lengths stay correct.
        if mnem == "REP":
            if raw & 0x20: m_width = 16
            if raw & 0x10: x_width = 16
            note = note or f"  ; A={m_width} X={x_width}"
        elif mnem == "SEP":
            if raw & 0x20: m_width = 8
            if raw & 0x10: x_width = 8
            note = note or f"  ; A={m_width} X={x_width}"

        hexpart = " ".join(f"{b:02X}" for b in raw_bytes)
        print(f"${bank:02X}:{addr:04X}  {hexpart:<12}  {mnem} {text}".rstrip() + note)

        addr = next_addr
        issued += 1
        if mnem in ("RTS", "RTL", "RTI") and end_addr is None:
            print("; returned")
            break


if __name__ == "__main__":
    main()
