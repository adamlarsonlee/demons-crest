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
| 1 | Progress-state region | **found** | Contiguous 8 bytes at `$7E:1E50`-`$1E57`; see memory-map/README.md |
| 2 | `current_level` | open | Warp destination |
| 3 | Level-load entry | open | Triggers the warp |
| 4 | `controller_1_new` | open | Hotkey edge detection |
| 5 | Frame hook | **found + proven** | NMI vector `$FFA4` jumps to `$80:8329`; chaining through injected code verified |
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

## Code injection is proven

`src/asm/experiments/nmi_probe.asm` chains the NMI vector through injected code
that counts frames into WRAM, then jumps on to the original handler:

```
org $80FFA4
    JML nmi_hook      ; was JML $80:8329
nmi_hook:
    PHP : REP #$20 : PHA
    LDA.l $7FC700 : INC A : STA.l $7FC700
    PLA : PLP
    JML $808329
```

Results:

| Check | Result |
|-------|--------|
| Counter at frame 1000 / 3400 | 385 / 2785 — delta 2400 over 2400 frames, exactly one per NMI |
| Title screen, hooked vs not | pixel-identical |
| WRAM, hooked vs not (no input) | differs only in our counter and page `$01` (stack residue) |
| ROM gap `$90:8000` | genuinely free: code present but unexecuted gives a pixel-identical frame |

The counter lags the frame number by ~615 because the RESET stub disables NMI
and the game enables it later.

Scratch WRAM is `$7F:C700`, inside `$7F:C668`-`$7F:C802`, which reads as zero
across six sampled states (title, cinematic, early and later gameplay). Zero is
evidence of being free, not proof — `$7E:1E51` also reads zero early on and is
the documented item-flag region. The counter test is self-validating: an exact
count means nothing contended the address during the window.

## NMI cycle budget is the real constraint

Measured against a scripted-input gameplay run:

| Hook cost | Effect |
|-----------|--------|
| ~30 cycles | Game state identical, shifted by exactly **one frame** (hooked frame 2549 is pixel-identical to unpatched 2550) |
| ~4000 cycles | Gross divergence, no clean frame offset |

So work at the top of NMI competes with the game's vblank-critical DMA. A
practice menu polling hotkeys must either stay very cheap or hook after the
game's vblank work rather than before it. Finding a late-NMI or main-loop hook
site should come before any substantial feature code.

The harness is deterministic run to run (same ROM twice gives zero differing
subpixels), so pixel comparison is a valid regression test. When comparing a
hooked build against stock, sweep a few frames either side: a constant offset
means a timing shift, whereas no matching offset means real corruption.

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

## The password screen

Demon's Crest has no SRAM because it saves via passwords, which means a
password encodes the whole progress state. Entering a known one and diffing
WRAM against a fresh boot should reveal the progress-flag region directly.

Route from a cold boot: the title logo appears around frame 3400; Start (or Y)
opens a **START / CONTINUE / OPTIONS** menu; CONTINUE opens password entry.
Nothing else on the logo screen does anything.

The entry screen is a 4x4 grid of 16 characters, each defaulting to `B`:

- d-pad moves the cursor; Down from the bottom row reaches `END`, then `EXIT`
- **B** cycles the character under the cursor, wrapping through 21 entries:
  `B Z Y X W V T S R Q P N M L K J H G F D C`
- sorted, that alphabet is `BCDFGHJKLMNPQRSTVWXYZ` — every letter except the
  vowels `A E I O U`
- **A**, **Y** or **Start** on `END` submits; a bad password prints
  `PASS WORD ERROR!`

So a valid password is 16 characters, consonants only. Anything containing a
vowel belongs to a different game or region.

`tools/mkpassword.py` converts a password into a `--press` schedule, verified
by entering `BCDFGHJKLMNPQRST` and reading the grid back off the screen.

## Probing memory directly

`headless.py --poke frame:$7FC750=0xA5` writes into WRAM through the core's
memory pointer. This gives a second, password-free route to the progress
flags: set a candidate address and observe whether the in-game menus or
overworld change. It confirms addresses rather than discovering them, so it
complements the password diff rather than replacing it.

## The central hypothesis

`memory-map/README.md` places items, powers, crests, urns, talismans and HP
upgrades in a contiguous run at `$1E30`-`$1E55` (~38 bytes). RockmanXPractice
works because the equivalent state in Rockman X is one 48-byte block that can
be treated as a hardcoded save.

**Hypothesis:** boss-defeated and overworld-stage-open flags also live in or
adjacent to `$1E30`-`$1E55`, making Demon's Crest amenable to the same design.

**CONFIRMED.** Rather than beating a boss, six passwords representing different
progression points were loaded and WRAM diffed in a matched context — all of
them land on the overworld, so location state cancels out. Progress resolves to
a contiguous 8-byte block at `$7E:1E50`-`$1E57`: max HP plus 56 flag bits, of
which `$1E56` and `$1E57` were previously unmapped. Max HP rises monotonically
across the six states.

State blocks are therefore viable exactly as in RockmanXPractice, and this has
been demonstrated rather than assumed: poking the eight bytes from an all-items
save into a level-2 save yields an in-level item menu **pixel-identical** to the
genuine all-items save, with max HP updated to match.

`$1E44` turned out not to be a blocker. It was suspected to be a checksum over
the block, which would have had to be computed for any written state. In fact it
is stable during play but **recomputed by the game on level load** — after the
poke it moved from `47` to `7C` on its own, and the resulting state was correct.
So a state block does not need to supply it. It is not a per-frame value either
(stable across 60 frames on the overworld), and it still depends on something
beyond `$1E50`-`$1E57`, since two saves with identical blocks hold different
values. Its exact meaning remains unidentified, but nothing depends on that now.

### Screen observables

Useful for verifying state changes headlessly:

| Context | Input | Result |
|---------|-------|--------|
| Overworld | Start | World map with numbered stages |
| Overworld | Y | Enter the stage |
| In a level | Start | Item menu — the definitive view of the progress block |

The world map is a poor observable for progress, because Firebrand's position
on it differs between saves and dominates a pixel diff. The in-level item menu
is the reliable one.

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
