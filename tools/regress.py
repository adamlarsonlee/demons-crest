#!/usr/bin/env python3
"""Regression tests for the practice ROM.

Every check here exists because something actually broke. The comment on each
says what, so a future change that reintroduces it fails with a name rather
than a mystery.

Run with `make test` (in the container) or, inside it:

    python3 tools/regress.py build/DemonsBlazon_Practice.sfc

Static checks run first and cost nothing. The emulated scenarios each boot the
game from states/title.state and drive it with scripted input, which takes a
couple of minutes in total.
"""

import argparse
import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from headless import BUTTONS, MEM_SAVE_RAM, MEM_SYSTEM_RAM, MEM_VIDEO_RAM, Core

SOURCE_SHA1 = "a6dc126a1da593d900b33eb74cf33403075e9525"

results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"   {detail}" if detail else ""))
    return bool(ok)


# ---------------------------------------------------------------------------
# Input scripts. Frame numbers are counted from the title-screen state.
# ---------------------------------------------------------------------------
def boot_to_stage():
    """Start a new game, skip the intro, fly nowhere, enter the nearest stage."""
    p = {}
    def press(frame, *btns):
        p.setdefault(frame, []).extend(BUTTONS[b] for b in btns)
    for f in range(30, 42):
        press(f, "start")
    for base in range(1400, 3100, 90):
        for i in range(4):
            press(base + i, "start")
    for i in range(4):
        press(3300 + i, "y")
    return p


def combo(p, frame, *btns, hold=6):
    for i in range(hold):
        p.setdefault(frame + i, []).extend(BUTTONS[b] for b in btns)
    return p


def run(rom, schedule, frames, want=()):
    """Run the ROM and capture requested artefacts. want: [(frame, kind)]."""
    core = Core("/usr/local/lib/snes9x_libretro.so")
    core.load(rom)
    core.unserialize(Path("states/title.state").read_bytes())
    out = {}
    wanted = {}
    for frame, kind in want:
        wanted.setdefault(frame, []).append(kind)
    for f in range(1, frames + 1):
        core.pressed = set(schedule.get(f, []))
        core.run()
        for kind in wanted.get(f, ()):
            if kind == "px":
                buf, w, h, pitch = core.frame
                from headless import to_rgb_rows
                rows = to_rgb_rows(buf, w, h, pitch, core.pixel_fmt)
                tot = sum(sum(r) for r in rows)
                out[(f, kind)] = tot / (w * h * 3)
            elif kind == "wram":
                out[(f, kind)] = core.memory(MEM_SYSTEM_RAM)
            elif kind == "vram":
                out[(f, kind)] = core.memory(MEM_VIDEO_RAM)
            elif kind == "sram":
                out[(f, kind)] = core.memory(MEM_SAVE_RAM)
    return out


def diff(a, b):
    return sum(1 for x, y in zip(a, b) if x != y)


# ---------------------------------------------------------------------------
def static_checks(rom_path, source_path):
    print("\nstatic checks")
    rom = Path(rom_path).read_bytes()

    if source_path and Path(source_path).is_file():
        # The whole project assumes this exact dump; a different one silently
        # shifts every hook site.
        check("source ROM is the pinned JP dump",
              hashlib.sha1(Path(source_path).read_bytes()).hexdigest() == SOURCE_SHA1)

    # The cartridge must declare RAM *and* a size. A size alone is not enough:
    # with the chipset byte left at $00 the emulator never maps SRAM and the
    # save state silently writes nowhere.
    check("header declares ROM+RAM+battery ($00FFD6 = $02)", rom[0x7FD6] == 0x02,
          f"got ${rom[0x7FD6]:02X}")
    check("header declares SRAM ($00FFD8 = $09)", rom[0x7FD8] == 0x09,
          f"got ${rom[0x7FD8]:02X}")

    # Declaring SRAM makes $70:1FFF writable, which the game reads as "this is a
    # copier". Both checks must stay neutered or the crest menu stops opening
    # and enemies stop taking damage after Firebrand is hit.
    check("copier check 1 neutered ($80:8753 = BRA)", rom[0x000753] == 0x80,
          f"got ${rom[0x000753]:02X}")
    check("copier check 2 neutered ($80:E550 = BRA)", rom[0x006550] == 0x80,
          f"got ${rom[0x006550]:02X}")

    # A third $70:1FFF check appearing would re-arm the protection.
    sig = bytes([0xAF, 0xFF, 0x1F, 0x70, 0x1A, 0x8F, 0xFF, 0x1F, 0x70,
                 0xCF, 0xFF, 0x1F, 0x70])
    sites = []
    s = 0
    while True:
        j = rom.find(sig, s)
        if j < 0:
            break
        sites.append(j)
        s = j + 1
    check("exactly two $70:1FFF protection sites", len(sites) == 2, f"found {len(sites)}")

    # The load must not copy the last two bytes of WRAM: $7F:FFFE-$FFFF is the
    # game's own stack pointer, and restoring it wedges the next mode change.
    # MVN with A=$7FFD moves $7FFE bytes, leaving that word alone.
    have = rom.find(bytes([0xA9, 0xFD, 0x7F]))
    check("load leaves $7F:FFFE-$FFFF alone (LDA #$7FFD before an MVN)", have > 0)

    # A bisect variant with one transfer commented out once shipped as a
    # release, because nothing here noticed the missing call. The load path ends
    # in exactly three JSRs: sram_to_vram, sram_to_cgram, ss_epilogue. Count the
    # JSR opcodes in the window after the last MVN setup.
    if have > 0:
        window = rom[have:have + 64]
        jsrs = sum(1 for i in range(len(window) - 2)
                   if window[i] == 0x20 and window[i + 2] in (0xA5, 0xA6, 0xA7))
        check("load calls all three of VRAM, CGRAM and epilogue", jsrs == 3,
              f"found {jsrs} JSR(s) after the load's MVNs")

    # Both transfer directions must exist for CGRAM: BBAD $3B reads it, $22
    # writes it. A missing one means the palette is not part of the state.
    for bbad, what in ((0x3B, "CGRAM read ($213B)"), (0x22, "CGRAM write ($2122)"),
                       (0x39, "VRAM read ($2139)"), (0x18, "VRAM write ($2118)")):
        pat = bytes([0xA9, bbad, 0x8F, 0x11, 0x43])
        check(f"transfer set up for {what}", rom.find(pat) > 0)


# ---------------------------------------------------------------------------
def scenario_boot_and_menu(rom):
    print("\nboot, stage entry and the crest menu")
    p = boot_to_stage()
    combo(p, 4400, "start")                      # plain Start opens the menu
    o = run(rom, p, 4600, want=[(3200, "px"), (4300, "px"), (4520, "px")])
    check("reaches the overworld from a new game", o[(3200, "px")] > 5,
          f"brightness {o[(3200,'px')]:.1f}")
    check("enters a stage", o[(4300, "px")] > 5, f"brightness {o[(4300,'px')]:.1f}")
    # This is the copier-protection regression: with $0EEB set, Start does
    # nothing at all and the screen stays on the level.
    check("plain Start opens the crest menu", o[(4520, "px")] > 60,
          f"brightness {o[(4520,'px')]:.1f}, menu is much brighter than the level")


def scenario_damage_flags(rom):
    print("\ncopier flags stay clear through a damage event")
    p = boot_to_stage()
    for f in range(4400, 4800):
        p.setdefault(f, []).append(BUTTONS["right"])   # walk into an enemy
    # Press Start *after* the damage: check 2 lives inside the damage handler,
    # so its flag is only set once Firebrand has been hit. Testing the menu
    # before any damage would pass even with the protection re-armed.
    combo(p, 5000, "start")
    o = run(rom, p, 5400, want=[(4990, "wram"), (5350, "wram"), (5150, "px")])
    w = o[(4990, "wram")]
    check("HP dropped, so damage really happened", w[0x1062] < w[0x1E50],
          f"HP ${w[0x1062]:02X} of max ${w[0x1E50]:02X}")
    # $0EEC gates the instruction that subtracts damage from an enemy, $0EEB
    # gates the crest menu. Both are set by the $70:1FFF checks.
    late = o[(5350, "wram")]
    # Asserted but NOT exercised: measured against a build with the protection
    # re-armed, $0EEB stays clear through this scenario, so check 1 at
    # $80:8746 is never reached here. The static byte check is the real guard
    # for that site; this only catches it if some other path sets the flag.
    check("$0EEB clear after damage (menu gate, not exercised here)",
          late[0x0EEB] == 0, f"got ${late[0x0EEB]:02X}")
    check("$0EEC clear after damage (enemy damage gate)", late[0x0EEC] == 0,
          f"got ${late[0x0EEC]:02X}")
    check("crest menu still opens after taking damage", o[(5150, "px")] > 60,
          f"brightness {o[(5150,'px')]:.1f}")


def scenario_exit_and_reenter(rom):
    print("\nexit to the overworld and re-enter")
    p = boot_to_stage()
    combo(p, 4400, "select", "start")            # exit
    combo(p, 5000, "y")                          # re-enter
    combo(p, 6100, "start")                      # menu again
    o = run(rom, p, 6400, want=[(4700, "px"), (6000, "px"), (6250, "px")])
    check("Select+Start exits to the overworld", o[(4700, "px")] > 5,
          f"brightness {o[(4700,'px')]:.1f}")
    check("re-entering a stage works", o[(6000, "px")] > 5,
          f"brightness {o[(6000,'px')]:.1f}")
    check("menu still opens after an exit cycle", o[(6250, "px")] > 60,
          f"brightness {o[(6250,'px')]:.1f}")


def scenario_save_load_roundtrip(rom):
    print("\nsave and load round trip")
    p = boot_to_stage()
    combo(p, 4400, "select", "r")                # save
    for f in range(4500, 4900):
        p.setdefault(f, []).append(BUTTONS["right"])   # move, so the load matters
    combo(p, 5000, "select", "l")                # load
    o = run(rom, p, 5100,
            want=[(4399, "wram"), (4399, "vram"), (4390, "sram"),
                  (4500, "sram"), (5060, "wram"), (5060, "vram")])
    check("save writes SRAM", sum(1 for b in o[(4500, "sram")] if b not in (0, 0xFF, 0x60)) > 10000,
          f"{sum(1 for b in o[(4500,'sram')] if b not in (0,0xFF,0x60)):,} meaningful bytes")
    vd = diff(o[(4399, "vram")], o[(5060, "vram")])
    wd = diff(o[(4399, "wram")], o[(5060, "wram")])
    # Not zero: the frame counter, pad state and a per-scanline ramp table all
    # advance in the frames between the copy finishing and the dump.
    check("VRAM restored", vd < 400, f"{vd:,} bytes differ")
    check("WRAM restored", wd < 400, f"{wd:,} bytes differ")


def scenario_exit_after_load(rom):
    print("\nexit after a load  (the $7F:FFFE regression)")
    p = boot_to_stage()
    combo(p, 4400, "select", "r")
    for f in range(4500, 4900):
        p.setdefault(f, []).append(BUTTONS["right"])
    combo(p, 5000, "select", "l")
    combo(p, 5300, "select", "start")
    o = run(rom, p, 7200, want=[(5500, "px"), (7199, "px")])
    # Restoring $7F:FFFE-$FFFF, the game's own stack pointer, leaves the
    # overworld entered but never faded in: black for good, music still going.
    check("overworld appears after exiting post-load", o[(5500, "px")] > 5,
          f"brightness {o[(5500,'px')]:.1f}")
    check("and stays visible", o[(7199, "px")] > 5, f"brightness {o[(7199,'px')]:.1f}")


SCENARIOS = {
    "boot": scenario_boot_and_menu,
    "damage": scenario_damage_flags,
    "exit": scenario_exit_and_reenter,
    "roundtrip": scenario_save_load_roundtrip,
    "exitload": scenario_exit_after_load,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom")
    ap.add_argument("--source", default="rom/DemonsBlazon.sfc")
    ap.add_argument("--only", help="comma-separated scenario names: " + ", ".join(SCENARIOS))
    ap.add_argument("--static-only", action="store_true")
    args = ap.parse_args()

    print(f"regression tests against {args.rom}")
    static_checks(args.rom, args.source)

    if not args.static_only:
        names = args.only.split(",") if args.only else list(SCENARIOS)
        for n in names:
            if n not in SCENARIOS:
                sys.exit(f"error: no scenario named {n!r}")
            SCENARIOS[n](args.rom)

    failed = [n for n, ok, _ in results if not ok]
    print(f"\n{len(results) - len(failed)}/{len(results)} passed")
    if failed:
        print("failed:")
        for n in failed:
            print(f"  - {n}")
        sys.exit(1)
    print("all good")


if __name__ == "__main__":
    main()
