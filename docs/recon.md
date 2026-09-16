# Phase 1 Recon

Every feature in the practice ROM writes to RAM or hooks a routine. On a
physical SNES a wrong address crashes rather than misbehaves, so each address
below must be observed in a debugger against the JP ROM before any code is
written against it.

The existing Lua HUD is the instrument: it already reads and draws arbitrary
WRAM across BizHawk, Mesen-S and snes9x-rr, so candidate addresses can be
watched live and written to before being committed to assembly.

## Targets

| # | Target | Status | Notes |
|---|--------|--------|-------|
| 1 | Progress-state region | open | Items/powers at `$1E30`-`$1E55`; boss-defeated and stage-open flags not yet located |
| 2 | `current_level` | open | Warp destination |
| 3 | Level-load entry | open | Triggers the warp |
| 4 | `controller_1_new` | open | Hotkey edge detection |
| 5 | Frame hook | **found** | NMI vector `$FFA4` jumps to `$80:8329` (file `0x000329`) |
| 6 | `rng_value` | open | Display and reseeding |
| 7 | Free ROM space | **mapped** | See "ROM space"; expansion required |

## Boot path

Decoded statically from the vector table at the end of bank `$80`:

```
RESET $FF8F   STZ $4200 / STZ $420B / STZ $420C   disable NMI, DMA, HDMA
              LDA #$8F / STA $2100                forced blank
              SEI / CLC / XCE                     enter native mode
              JML $80:8000                        main init
NMI   $FFA4   JML $80:8329
IRQ   $FFA8   JML $80:8669
```

## Headless verification

`tools/headless.py` drives a libretro core (baked into the container image) with
no GUI, no display server and nothing installed on the host. It dumps frames as
PNG and exposes memory, which makes most of the remaining recon tractable
without a debugging emulator:

- video frames -> PNG (256x224)
- `RETRO_MEMORY_SYSTEM_RAM` -> 128 KB WRAM
- `RETRO_MEMORY_VIDEO_RAM` -> 64 KB VRAM
- scripted controller input via `--press frame:button`

`tools/vramsheet.py` renders a VRAM or ROM region as a tile sheet so graphics
can be identified by eye.

Useful frames, from a cold boot with no input:

| Frame | Screen |
|-------|--------|
| 420 | Capcom logo |
| ~1100-1900 | Opening cinematic |
| 3400 | Title screen |

Pressing Start during the cinematic skips into gameplay by roughly frame 1400,
which is how to reach in-game state for WRAM diffing.

## Locating uncompressed graphics

Dump VRAM at a frame of interest, then search the ROM for each 32-byte tile
verbatim. Sequential runs (VRAM and ROM both advancing by `$20`) indicate an
uncompressed block that can be edited directly, with no code injection.

Found this way:

| VRAM | ROM | LoROM | Tiles | Contents |
|------|-----|-------|-------|----------|
| `$2000` | `0x0F4000` | `$9E:C000` | 36 (12x3) | Capcom logo |
| `$A000` | `0x0F44A0` | `$9E:C4A0` | 4+ | Loaded at the title screen but **not displayed** |

Palette indices in the logo block: `0` is transparent, and the letters use a
vertical gradient of `14` (top row) through `13`/`12` (middle) to `11` (bottom).

`tools/mkglyphs.py` generates a patch that overwrites the logo block with text,
which is how the "PRACTICE" demo on the opening screen is produced. It is a
data-only change, so it carries no crash risk.

## The central hypothesis

`memory-map/README.md` places items, powers, crests, urns, talismans and HP
upgrades in a contiguous run at `$1E30`-`$1E55` (~38 bytes). RockmanXPractice
works because the equivalent state in Rockman X is one 48-byte block that can
be treated as a hardcoded save.

**Hypothesis:** boss-defeated and overworld-stage-open flags also live in or
adjacent to `$1E30`-`$1E55`, making Demon's Crest amenable to the same design.

**Falsifying check:** beat a boss and watch the whole of WRAM for changes, not
just that region. If flags turn out to be scattered across distant addresses,
the hypothesis is dead and state blocks become a sparse address/value list
rather than a contiguous `memcpy` — materially more code and more risk.

Run this check before anything else; it determines the shape of the feature work.

## ROM identity

Confirmed against the JP dump (`sha1 a6dc126a1da593d900b33eb74cf33403075e9525`,
headerless):

| Field | Value |
|-------|-------|
| Title | `demon's blazon` |
| Mapping | LoROM + FastROM (`$30`) |
| Size | 2048 KB |
| Chipset | ROM only (`$00`) |
| SRAM | **none** |
| Region | Japan |
| Checksum | valid |

## No SRAM: config cannot persist as-is

RockmanXPractice stores its config in battery SRAM tagged `"CATS"`. Demon's
Crest has no SRAM at all — it shipped with a password system instead — so that
approach does not port directly. Options:

1. Declare SRAM in the header (chipset `$02`, non-zero SRAM size byte). FXPak Pro
   honours the header and allocates SRAM, saving it to SD. This would **not**
   work on an original cartridge, which has no battery hardware.
2. Accept no persistence; practice config resets on each power cycle.
3. Encode practice state into the existing password system.

Option 1 is viable given FXPak Pro is the target, but it is a deliberate
divergence from stock hardware behaviour and should be decided explicitly.

## ROM space: expansion is required

The original ROM is densely packed. Filler runs (`$00`/`$FF`) measured across
the whole 2MB:

| Minimum run | Runs | Total |
|-------------|------|-------|
| >=64 B | 409 | 54,751 B |
| >=256 B | 38 | 11,105 B |
| >=512 B | 1 | 891 B |
| >=1024 B | 0 | 0 B |

The largest contiguous gap is 891 bytes at `$98:A4B5`. There is no region big
enough for a practice menu plus route state tables, so the ROM must be expanded
from 2MB to 4MB and new code placed in the upper banks. LoROM addresses banks
`$80`-`$FF` (4MB), so this stays within standard mapping, and FXPak Pro handles
4MB without issue.

Consequence: once expanded, IPS is the wrong distribution format, because it
cannot express a size change compactly. Use BPS (flips) instead.

A no-op `freedata` against the real ROM did **not** expand it — asar found a
128-byte zero run at `$080000` and tagged it. An earlier contrary observation
came from an all-`$FF` synthetic test fixture and did not reflect the real ROM.

## Hardware constraints

Emulators tolerate things a console does not. Code must:

- Never read uninitialized RAM or rely on open-bus values.
- Keep any NMI-time work inside the vblank budget.
- Avoid writes to PPU registers outside vblank.
- Use only documented 65816 opcodes.
