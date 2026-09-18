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

## SRAM is not writable in this harness at all

Worse than the size limit, and found only after writing the save-state code:
**the CPU cannot reach SRAM in the pinned snes9x core.** Measured with
`src/asm/experiments/sram_where.asm`, which writes a distinct four-byte marker
to each candidate window from a hook whose execution is confirmed (`$7E:0086`
reads `$FF`):

| Write target | Appears in SAVE_RAM |
|--------------|---------------------|
| `$70:0000` | no |
| `$70:8000` | no |
| `$71:0000` | no |
| `$F0:0000` | no |
| `$30:6000` | no |
| `$B0:6000` | no |

Meanwhile `retro_get_memory_size(SAVE_RAM)` reports 131,072 bytes, and that
buffer is uniformly `$60` and never changes. So snes9x allocates an SRAM buffer
but does not map it into the CPU address space for this cartridge.

Setting the header's **chipset byte** to `$02` (ROM + RAM + battery) alongside
the size byte did not help either; `$00FFD6` was still `$00`, which was a
plausible cause and is now ruled out.

**Consequence: the save state cannot be developed or verified here at all**,
at any size. That is a harder blocker than the 128KB ceiling.

**Next step, bounded:** the harness prints `Map_LoROMMap` when it loads a ROM,
so the relevant snes9x function is known. Reading its SRAM-window conditions
would say what the header needs, or whether a 2MB LoROM maps banks `$70`-`$7D`
as ROM mirror and leaves no room for SRAM at all.

**Process note.** The savestate code was written before checking that a single
byte could be written to SRAM and read back. That check costs one probe and
would have come first; the order here was wrong.

## What this means for the save state

The save state has to fit in **snes9x's 128KB** to stay verifiable, which is
the project's whole method. That rules out X2's WRAM + VRAM + CGRAM approach,
but a selective state does fit — see `docs/patches.md`.

## Not investigated

- Whether a newer or differently-built Mesen libretro core implements the
  memory API. The nightly `mesen2` one does not.
- BizHawk, which has Lua and a CLI, but is Windows-centric and would be a
  second harness rather than a swap.
- Driving MesenCE's GUI through its Lua console manually. Workable for one-off
  questions, not for a regression loop.
