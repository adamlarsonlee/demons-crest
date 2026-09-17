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
| 2 | `current_level` | open | `$7E:1D82` retracted — not area-discriminating across seven dumps; see "Seven named-area WRAM dumps" |
| 3 | Level-load entry | partial | Per-mode setups and loops found; the area-specific load path is not |
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

## current_level: lead and dead ends

`$7E:0088` and `$0089` always hold the same value and take a coherent value per
level across five level entries:

| Entry | `$0088`/`$0089` | Screen |
|-------|-----------------|--------|
| stage I from allitems | `06` | castle interior |
| fly up, then enter | `06` | same as stage I |
| fly left 150 / 400, then enter | `12` | matching pair |
| fly right 150, then enter | `10` | forest/swamp |

Corroborating: the two entries reading `06` produce nearly identical screens,
and forcing `$0088` every frame across the load **hangs** the game on a black
screen, so the address is genuinely used by the load path.

It is **not confirmed** as `current_level`. A single poke at frames 12, 20, 30,
50, 80 or 120 after pressing Y changes nothing at all, so either the game writes
the value after those points (making these bytes a copy rather than the source)
or it reads the real source earlier.

Dead ends, recorded so they are not repeated:

- Poking any of 22 filtered candidates on the overworld *before* entering has no
  effect. The destination is determined by Firebrand's position, and the level
  id is written during the load.
- Searching the ROM for instructions referencing abyssonym's level pointer
  tables finds nothing usable. His addresses are file offsets, not SNES
  addresses (his `7C800` cannot be a SNES address in a 2MB LoROM), so they map
  to bank `$81`; even searching there, the only matches are coincidental byte
  patterns. The tables are presumably reached through runtime-computed indices
  or pointer indirection.
- The world map is unusable as a progress observable because Firebrand's
  position on it dominates any pixel diff.

## Watchpoints in the instrumented core

`docker/snes9x-watchpoints.patch` adds watchpoints to the libretro core, giving
the headless setup the one thing it previously lacked: the ability to see *which
code* touches an address. The snes9x commit is pinned in the Dockerfile because
the patch is applied against it. Output goes to stderr.

```sh
# what writes this WRAM address?
docker run --rm -v "$PWD":/work -e S9X_WATCH_WRITE=0088 -e S9X_WATCH_LIMIT=60 \
    demons-crest-build python3 tools/headless.py build/nmi.sfc \
    --load-state states/allitems.state --frames 700 --press '10:y,11:y'

# what reads this ROM range, and with what index?
docker run --rm -v "$PWD":/work -e S9X_WATCH_READ='81A291-81A400' \
    demons-crest-build python3 tools/headless.py ...
```

- `S9X_WATCH_WRITE` — WRAM addresses, bare offsets (`0088`) or bank-qualified
  (`7E0088`). Matching resolves the WRAM mirror, so a write via `$00:0088` is
  caught as well as one via `$7E:0088`; games normally use the low-RAM mirror,
  so matching on the raw address alone would miss nearly everything.
- `S9X_WATCH_READ` — ranges of full addresses, e.g. `81A291-81A400`.
- `S9X_WATCH_LIMIT` — cap on logged hits (default 200).

Each hit logs the PC plus A, X, Y, D and DB, which is what makes an indexed
table read interpretable. Both `S9xSetByte`/`S9xSetWord` and
`S9xGetByte`/`S9xGetWord` are hooked, because the word paths have a fast case
that bypasses the byte ones. Verified to cause no behavioural change: a frame
captured with the patched core is byte-identical to one from the unpatched core.

## $7E:0088 is not the level index

The watchpoint disproved the lead immediately. `$0088` is written repeatedly
from `$80:BCC8` with values stepping `00 02 04 06 08 0A 0C`, which is a loop or
table counter. That also explains the earlier symptoms: a single poke did
nothing lasting, and forcing the value every frame hung the game by corrupting
a loop counter.

## Level-load code and data, so far

From read-watching during a level entry:

| Address | Role |
|---------|------|
| `$80:BBA4`, `$80:BCC8` | write the `$0088` loop counter during load |
| `$80:C5D2` | reads a 2-byte table entry — the first level-data lookup seen |
| `$80:C5FE`, `$80:C61E`, `$80:C62C` | read level data sequentially, indexed by Y |
| `$81:A342`-`$81:A3xx` | level data being read |

At `$80:C5D2` the read lands on `$81:A355` with `Y=2`, implying a base around
`$81:A353`. Immediately after, A holds `$A342` while reading `$81:A342`, i.e. a
pointer was fetched and then followed.

**abyssonym's ROM map is for the US release** (confirmed via the randomizer —
see `docs/areas.md`). His index-5 example
says the pointer at `a29b` holds `$A3E0`; on the JP ROM that word is `$A53C`,
and no instruction references his table addresses. The JP level tables are in
the same neighbourhood but at different offsets, so his notes are a guide to
*structure*, not to addresses.

`tools/disasm.py` is a stdlib-only 65816 disassembler for LoROM images. Register
widths change instruction length, so `--m`/`--x` set the initial widths and
REP/SEP are tracked from there; wrong widths desynchronise the output. It
annotates operands from `mesen-s/labels.msl`. Validated against the reset stub,
which it decodes identically to a hand decode.

```sh
python3 tools/disasm.py rom/DemonsBlazon.sfc --start '$80C5B2' --end '$80C60A' --m 16 --x 16
```

## The level-load path

```
$80:A864  LDY $8D          ; area index
$80:A866  JSR $C5B2        ; also called from $80:AF96 and $80:B7C1

$80:C5B2  REP #$20
$80:C5C6  LDA $A25A,Y      ; base pointer table, indexed by the area
$80:C5C9  STA $10
$80:C5CB  LDA $A6A1,Y      ; second table, same index
$80:C5CE  STA $14
$80:C5D0  LDA ($10)        ; fetch a per-area value
$80:C5D2  AND #$FF
$80:C5D7  ASL A
$80:C5D9  ADC $00          ; x3
$80:C5DC  ADC #$A342       ; 3-byte entries based at $81:A342
$80:C5DF  STA $10
$80:C5E2  JSR $C5F8        ; follow the pointer and read the data
```

### Retraction: `$8D` is a mode, not the area

`$7E:008D` was briefly recorded as the area index. It is not. Sampling it
*during* a load rather than after shows it is `$BC` on the overworld and `02`
in a level — **the same for two visibly different destinations**. It selects a
screen or mode type. Forcing it to `00`/`04`/`06` loads a different kind of
screen, which is why it looked like a level selector.

`$80:C5B2` is likewise not the area-specific load path. Watching its table
reads across two matched loads, one into the castle and one into the forest,
produces **byte-identical access patterns** (`$81:A355` then `$81:A342`-`$A344`,
`Y=2` in both). It is a shared data-load helper called during screen setup.

The area index is still unfound. A diff of every bank-`$81` read across the two
matched loads showed only two differing program counters, `$85:98EE` and
`$85:98F3`, and those turn out to be a sine table: they read the same table at
`$81:C371` with `X` and with `Y = $5A - X`, which is the classic 90-degree
sin/cos pair. `X` there is a transition-effect angle, not an area.

So area selection is either driven by data outside bank `$81` or reached
through a pointer computed in RAM.

### The area graphics path

Found by working backwards from the data rather than by diffing variables,
which is the only method here that has produced correct answers.

Two areas that differ reliably: `states/allitems.state` + Y enters a
tree-and-torches area, `states/bossrush.state` + Y enters the castle. The other
password states all enter the same area as `allitems`. **Overworld navigation
is not a reliable way to reach a second area** — flying right for 250, 350, 450
or 550 frames and then pressing Y all enter the same place.

Matching VRAM against the ROM shows each area loads VRAM `$C000` from a
different source:

| Area | VRAM `$C000` source |
|------|---------------------|
| tree | `0x0D0000` = `$9A:8000` |
| castle | `0x0D4C80` = `$9A:CC80` |

Tracing that backwards:

```
$7E:0500+            DMA queue, 8-byte entries:
                       +1 VRAM address   +3 size
                       +5 source address +7 source bank
                     end pointer in $81
$80:85B4             drains the queue, one DMA per entry
$84:9DAC             fills it, walking a 3-byte-entry graphics list
                       tree list at $C144, castle list at $C18E
$81:C0EE             per-area table of those list pointers, indexed by area x2
                       entry 2 = $C144 (tree), entry 7 = $C18E (castle)
$84:9C60             takes the area index in A:
                       AND #$00FF / STA $0000 / ASL A / TAY
                       LDA $C0EE,Y / TAY
                       LDA $0000 / STA $1D82,X
$7E:1D82             the stored area index: 02 for tree, 07 for castle
```

`$7E:1D82` is stable across frames and matches the table entry exactly in both
areas, so the index and the table agree independently. Per the randomizer's area
table (`docs/areas.md`), index 2 is **S1_2** and index 7 is **S2_3b**.

**Scope, honestly:** forcing A to 7 at `$84:9C60` does store `$1D82 = 07` and
changes some graphics, but the level still loads as the tree area — only 1927
subpixels differ. So this is the **graphics** half of the area load. Whatever
selects the layout is a separate consumer of the index and is still unfound.
Poking `$7E:1D82` directly has no effect at all, because the game writes it
during the load from `$84:9C71`.

### Closed leads

Each of these looked like the area index and is not. Recorded so they are not
retried:

| Address / site | What it actually is |
|----------------|---------------------|
| `$7E:008D` | screen/mode type: `$BC` overworld, `02` in level |
| `$7E:0088`, `$7E:0089` | sound command queue indices (`AND #$3E`, 32 entries) |
| `$7E:0920`-`$095F` | the sound command ring buffer itself; `$092C` is slot 6 |
| `$7E:0073` | frame counter, incremented in the overworld loop |
| `$7E:008F` | allocation counter, `+= $0B` per call at `$84:9CD7` |
| `$7E:0100`-`$01FF` | the stack |
| `$80:C5B2` | shared data loader; byte-identical across two destinations |
| `$81:C371` | sine table, read with `X` and `$5A - X` |

Two process notes. Diffing WRAM between two loads surfaces counters and buffers
by the hundred, because a level load touches everything; it produced no correct
answer here. And an earlier comparison was invalid because both "destinations"
were the same area — worth verifying that two states actually differ, visually,
before drawing conclusions from a diff between them.

### Per-mode loops, and the shared frame-sync routine

The three callers of `$80:C5B2` are three mode setups, each followed by its own
loop. The overworld one is:

```
$80:AFDC  JSR $B0A3
$80:AFDF  JSL $828600
$80:AFE3  JSR $AFFF
$80:AFE6  STZ $008A
$80:AFE9  JSL $85AE26
$80:AFED  JSR $F66B
$80:AFF0  INC $0073      ; $7E:0073 is a frame counter
$80:AFF3  JSL $849C04
$80:AFF7  LDA $E7
$80:AFF9  JSL $80821E    ; shared frame sync
$80:AFFD  BRA $80:AFDC
```

Hooking `$80:AFF0` proves the mechanism works but only counts 79 frames and
then stops, because this loop belongs to the overworld alone.

`$80:821E` is called once per iteration by *every* mode, so it is the portable
per-frame site. It must be hooked **after** its register-save prologue — at
`$80:822D`, displacing `LDY $0072` and `LDA #$01` — because moving
`PHB`/`PHD`/`PHP` into a subroutine would leave those pushes stacked on top of
the `JSL` return address and break the `RTL`. Hooking there counts continuously
across the overworld, the transition and gameplay.

Caveat: it fires roughly **twice per frame** during gameplay (+400 counts over
200 frames), so anything needing exactly one call per frame has to guard for
that.

### Moving out of NMI does not fix the frame shift

The reason for wanting a non-NMI hook was the one-frame shift the NMI hook
causes at load transitions. Measured against stock in a *moving* scene, with
frames swept either side to distinguish a shift from corruption:

| Hook | Frames matching stock 650 exactly | Offset |
|------|-----------------------------------|--------|
| NMI | 649, 650 | none in this scenario |
| Frame sync at `$80:822D` | 648, 649 | **-1** |

The frame-sync hook shifts timing *more* than the NMI hook, not less, probably
because it runs twice per frame inside the loop. A static scene cannot measure
this at all — several consecutive frames are identical, so everything appears
to match.

So "hook outside NMI to avoid the shift" is **not supported**. Both sites
perturb pacing, and choosing between them needs a purpose-built repeatable
measurement rather than the ad-hoc scenarios used so far.

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

## Seven named-area WRAM dumps (2026-09-17)

Seven full CPU-bus dumps were captured on a GUI emulator at named locations and
sliced to WRAM in `states/wram/` (see `MANIFEST.md` there for the file list,
hashes and capture caveats). This is the "raw WRAM dump per named area" that
`CLAUDE.md` asked for. Validation before use:

- The ROM region of every dump matches `rom/DemonsBlazon.sfc` byte for byte, so
  all seven are against the correct unmodified JP ROM.
- All 21 pairs are genuinely distinct — the closest pair (`forest`/`ice`)
  differs in 9.1% of page 0, every other pair in 15-40%. The lesson-3 trap of
  diffing two states that are really the same area does not apply here.
- `$7E:008D` reads `$BC` in the `overworld` dump, matching the closed-lead note
  for that address. Independent confirmation that the WRAM slice is aligned.
- The progress block `$1E50`-`$1E57` is `14 FF FF FF FF FF FF 03` in all seven,
  identically, as expected from one password-loaded save.

### `$7E:1D82` does not identify the area

Contents of `$1D82`-`$1D8A` per dump:

| Dump | `$1D82`-`$1D8A` |
|------|-----------------|
| `forest` | 01 00 32 02 04 03 03 00 00 |
| `forest-2` | 01 00 32 02 04 08 01 00 00 |
| `forest-3-no-canopy` | 01 00 32 02 04 0A 00 00 00 |
| `ice` | 01 00 32 02 04 03 03 00 00 |
| `water` | 01 00 32 02 04 08 03 00 00 |
| `town` | 07 00 08 04 03 01 00 00 00 |
| `overworld` | 07 00 08 04 03 01 00 00 00 |

`$1D82`-`$1D86` is byte-identical across five visibly different areas, and
`$1D87`/`$1D88` collide (`forest` and `ice` are both `03 03`). Town and the
overworld share the whole record.

So the earlier reading — "`$7E:1D82` the stored area index: 02 for tree, 07 for
castle" — **holds only for the two areas it was measured in**. Across seven it
is not an area index, not even a graphics index; the two-sample agreement with
the `$81:C0EE` table entry was coincidence of exactly the kind lesson 1 warns
about. What `$1D82,X` actually is remains open: `$84:9C60` writes it with a
varying `X`, so it is an array, and these dumps show its contents are a
per-mode record rather than a per-area one. **Unverified hypothesis:** it is the
queue of graphics lists a mode loads. Falsify with a watchpoint on `$1D82,X`
across one load, logging `X` — if `X` is a slot counter walking a list, the
hypothesis stands; if `X` is constant, it falls.

### Per-area palettes — `$99:AB40 + id x $C0`

WRAM `$0300`-`$04FF` is the CGRAM shadow (512 bytes = 256 colours). It is
loaded verbatim from ROM bank `$99`, and `$7F:A000` holds a second copy of the
same buffer — which is why `$0431` and `$1A131` always carry equal values.

The background palette base per dump is an exact multiple of `$C0` from
`$99:AB40` in all six cases — a consistent stride, measured, not assumed:

| Dump | Palette base | id |
|------|--------------|-----|
| `town` | `$99:AB40` | 0 |
| `forest`, `forest-2` | `$99:ACC0` | 2 |
| `forest-3-no-canopy` | `$99:AF00` | 5 |
| `ice` | `$99:B380` | 11 |
| `water` | `$99:B440` | 12 |
| `overworld` | `$99:B980` | 19 |

`forest` and `forest-2` share a palette, as two sections of one stage should.

The **stride** is solid at 6/6, but the block *size* is not: the verbatim
ROM-to-WRAM run at `$0340` is 192 bytes for `town`, `forest` and `forest-2`,
128 for `forest-3-no-canopy`, `ice` and `water`, and only ~32 for `overworld`.
So part of the CGRAM shadow is overwritten after the copy — by fades or by
sprite palettes — and `$C0` should be read as the table stride, not as a
confirmed block length.

This id is currently the best available area fingerprint, and unlike every
WRAM candidate it is anchored to a ROM address rather than to cross-sample
correlation. The table mapping area -> palette id has **not** been found: no
116-byte run of small values in the ROM carries the required entries, and no
16-bit table of these bases exists.

### Negative results from the dumps

The dumps do **not** contain the area or layout index. Specifically:

- No WRAM byte holds `(1, 2, 3, ., ., 4)` — the indices `docs/areas.md` predicts
  for S1_1, S1_2, S1_3 and S2 Town. Nor does any 16-bit word.
- No WRAM byte holds three consecutive values across the three forest dumps,
  which a section index walked in order would.
- Neither the palette id nor the 16-bit palette base is retained anywhere in
  WRAM, in any dump.

Taken together with `$84:9C60` writing `$1D82,X` from `$0000` — and poking
`$1D82` after the load having no effect — the picture is that **the area index
is consumed during the load and not kept in WRAM afterwards.** That is the
reason targets 2 and 3 have resisted, and it means no quantity of area dumps
will settle them on their own. A write-watchpoint during the load is required.

### Closed leads from this batch

| Address / site | What it actually is |
|----------------|---------------------|
| `$7E:0079`, `$7E:00D9`, `$7E:0E31` | three copies of one small per-area value (`05 06 08 08/16 07 04`); not an area index — `ice` collides with `forest-3`, and `town` and `overworld` share it |
| `$7E:1D82`-`$1D86` | a per-mode record, identical across five distinct areas |
| `$7E:2200`-`$31FF` | object/sprite arrays; dense even-address entries whose small values track enemy type per area. Every "6 distinct small values" hit in this range is one of these |
| `$7F:A000`-`$A1FF` | second copy of the `$0300` CGRAM shadow |

### Next capture

The highest-value remaining dump is **forest section 3 with the canopy
triggered**. Diffed against `forest-3-no-canopy` it isolates the layout selector
directly: same area, same palette, same tileset, one differing layout. That is a
far tighter experiment than comparing different areas, where a load touches
hundreds of variables.
