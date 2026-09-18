# Headless emulator survey

Prompted by the question of whether a >128KB SRAM save state could be verified
headlessly. **Conclusion: no tool available here can do it.** snes9x is the only
core that both exposes memory through the libretro API and honours a header SRAM
declaration, and it caps at 128KB.

Recorded so this is not re-investigated from scratch.

## Core compatibility, measured

All aarch64 libretro cores from the nightly buildbot, loaded with
`tools/headless.py` against a ROM whose header declares `$08` (256KB nominal):

| Core | SAVE_RAM | SYSTEM_RAM | VIDEO_RAM | Verdict |
|------|---------|-----------|----------|---------|
| `snes9x` (pinned) | 131,072 | 131,072 | 65,536 | **the only usable one**; clamps 256KB to 128KB |
| `bsnes2014_accuracy` | 0 | 131,072 | 65,536 | WRAM/VRAM fine, ignores the header's SRAM |
| `bsnes_mercury_accuracy` | 0 | 131,072 | 65,536 | same |
| `bsnes` | 0 | 0 | 0 | no memory API |
| `mesen2` | 0 | 0 | 0 | loads the ROM, exposes no memory |
| `mesen-s` | — | — | — | crashes during init/load |

**Why bsnes reports no SRAM.** bsnes and higan derive cartridge layout from
their own board database rather than the SNES header, so patching the header's
SRAM size does not reach them. Worth remembering generally: a header SRAM
declaration is not universally honoured.

## MesenCE: no headless mode

`--testrunner` **does not exist.** It appears nowhere in the source of
`SourMesen/Mesen`, `SourMesen/Mesen2` or `nesdev-org/MesenCE`. The apparent
documentation for it was `SourMesen/Mesen` issue #526, which is a **feature
request** — its body begins "### Feature Request" — that was mistaken for a
description of an existing feature.

The MesenCE 2.2.1 Linux ARM64 release does run inside the build container after
adding `libfontconfig1`, `libsdl2-2.0-0`, `xvfb` and `xauth`
(`docker/Dockerfile.mesen`), but only as a GUI application: it initialises
Avalonia even for `--help`, and passing an unknown `--testrunner` option is
silently ignored, so it just launches the GUI and never exits. A trivial Lua
script that logs and calls `emu.stop(0)` produced no output and had to be killed
after 60 seconds.

Mesen's Lua API is real and rich, but reaching it requires the GUI, which is not
automation.

## SRAM *is* reachable — the earlier finding here was wrong

This document previously said "the CPU cannot reach SRAM in the pinned snes9x
core", measured with `sram_where.asm`, and concluded the save state "cannot be
developed or verified here at all". **That was wrong, and it cost three rounds
of blind guessing at a save-state bug that could have been measured.**

The tell was in the old text itself: it noted that setting the chipset byte to
`$02` "did not help either; `$00FFD6` was still `$00`". That is not a result, it
is a failed write - the byte the test depended on was never actually in the ROM.

With `$00FFD6 = $02` and `$00FFD8 = $09` genuinely present, CPU writes reach
SRAM and `retro_get_memory_data(SAVE_RAM)` reflects them. Measured with v0.9:
SAVE_RAM held 0 meaningful bytes before the save hotkey and **67,913** after it.
The WRAM half of the transfer is correct too - bank `$71`'s window matches WRAM
`$7E:0000-$7FFF` in 32,728 of 32,768 bytes, the difference being the frames
between the reference dump and the save.

Use `tools/headless.py --dump-sram FRAME[,FRAME]`.

### Window size differs per emulator, and that bounds what can be verified

The header declares `$09` (512 KB). Nobody honours that literally. The LoROM
offset is `(((Address & $ff0000) >> 1) | (Address & $7fff)) & SRAMMask`, so the
mask decides how many 32 KB bank windows are distinct:

| Emulator | SAVE_RAM | Distinct windows | Effect on a 7-bank, 224 KB state |
|---|---|---|---|
| snes9x (pinned) | 131,072 | 4 (`$1FFFF` mask) | `$75`-`$77` **alias onto** `$71`-`$73`, so VRAM and CGRAM overwrite the WRAM copy |
| MesenCE | — | 8, measured | `$71`-`$77` all distinct; `$78` wraps to `$70` |

MesenCE's eight windows were measured from a reporter's 16 MB bus dump by
comparing the first 4 KB of each bank: `$70` and `$78` are identical and the
rest differ.

So this harness can now **exercise** the save path, dump the result and check
any single region's transfer, but it **cannot validate a full round trip**,
because four windows cannot hold seven banks. A full round trip needs an
emulator with at least 224 KB mapped. Reducing the state to four banks would
make it fully verifiable here, at the cost of dropping VRAM or CGRAM.

## Not investigated

- Whether a newer or differently-built Mesen libretro core implements the
  memory API. The nightly `mesen2` one does not.
- BizHawk, which has Lua and a CLI, but is Windows-centric and would be a
  second harness rather than a swap.
- Driving MesenCE's GUI through its Lua console manually. Workable for one-off
  questions, not for a regression loop.
