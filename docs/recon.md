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
| 2 | `current_level` | **found** | `$7E:008D` is the area ID **x 2**; see "`$7E:008D` is the area ID" |
| 3 | Level-load entry | **found** | `$85:B0BA`; destination `$7E:1326` -> table `$81:E0F1` -> `$8D`. Warp verified |
| 4 | `controller_1_new` | **found** | `$7E:0094` newly-pressed, `$7E:0090` held; the game computes the edge itself |
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
| ~~`$7E:008D`~~ | **This entry was wrong and is retracted.** `$8D` is the area ID x 2. The `02` seen "in level" was area 1 (S1_1) x 2; `$BC` on the overworld is not an area. See "`$7E:008D` is the area ID" |
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

> **Retracted 2026-09-17.** The headline claim below — that the dumps do not
> contain the area index — is **wrong**. `$7E:008D` carries it in all seven, as
> area x 2. The individual bullets remain accurate as written: the index is not
> present *raw*, which is why searching for the raw value found nothing. The
> error was concluding "not retained" from "not retained in the one encoding I
> tested". See "`$7E:008D` is the area ID".

The dumps do **not** contain the area or layout index. Specifically:

- No WRAM byte holds `(1, 2, 3, ., ., 4)` — the indices `docs/areas.md` predicts
  for S1_1, S1_2, S1_3 and S2 Town. Nor does any 16-bit word.
- No WRAM byte holds three consecutive values across the three forest dumps,
  which a section index walked in order would.
- Neither the palette id nor the 16-bit palette base is retained anywhere in
  WRAM, in any dump.

~~Taken together with `$84:9C60` writing `$1D82,X` from `$0000` — and poking
`$1D82` after the load having no effect — the picture is that the area index is
consumed during the load and not kept in WRAM afterwards.~~ **Retracted:** it is
kept, at `$8D`, doubled.

### Closed leads from this batch

| Address / site | What it actually is |
|----------------|---------------------|
| `$7E:0079`, `$7E:00D9`, `$7E:0E31` | three copies of one small per-area value (`05 06 08 08/16 07 04`); not an area index — `ice` collides with `forest-3`, and `town` and `overworld` share it |
| `$7E:1D82`-`$1D86` | a per-mode record, identical across five distinct areas |
| `$7E:2200`-`$31FF` | object/sprite arrays; dense even-address entries whose small values track enemy type per area. Every "6 distinct small values" hit in this range is one of these |
| `$7F:A000`-`$A1FF` | second copy of the `$0300` CGRAM shadow |

### Derived encodings tested, all negative

The negative result above was initially only tested against the **raw**
`areas.md` index. Two derived encodings were then tested, in case the area is
retained in a transformed form:

- **The graphics-list pointer.** `$81:C0EE` is confirmed area-indexed, and its
  entries validate against recon independently — entry 2 is `$C144`, entry 7 is
  `$C18E`. No WRAM word holds its area's entry: zero addresses carry a C0EE
  table entry in all six level dumps.
- **A table offset (`index x 2`).** ~~Every hit is already-closed noise —
  `$7E:008D`, or the `$2200`-`$31FF` object arrays.~~ **Retracted, and this was
  the whole mistake: `$7E:008D` was the answer.** It was discarded solely
  because the closed-leads table said `$8D` was a mode byte — an entry itself
  written from two samples. A closed lead is only as good as the evidence that
  closed it, and a two-sample closure can be as wrong as a two-sample finding.

So the area is not retained raw, and not as the pointer the index was used to
fetch. It **is** retained as a doubled offset, at `$8D`.

### Hypothesis: what persists is the overworld position — WITHDRAWN

> **Withdrawn 2026-09-17, unnecessary.** It was built to explain negative
> results that turned out to be an artifact of testing one encoding. `$8D`
> holds the area, so nothing needs re-deriving. Kept only to record that the
> reasoning was sound and the premise was not.

The game must be able to re-derive the area — after a death, and to know where
the player is on the overworld. Nothing in WRAM holds the index, so the
**unverified hypothesis** is that the persistent value is the overworld map
position, with the area index computed from it through a table at load time.

That would explain all four negative results at once, and it means the quantity
to hunt is a coordinate pair, not a small integer.

Falsify with two overworld dumps taken at different map positions: they should
differ in a small, stable pair of values which also appear, unchanged, in the
in-level dumps for the areas those positions lead to. If no such pair exists,
or if it does not survive into the in-level dumps, the hypothesis falls.

Note also that the in-game pause (the crest/vellum screen) switches mode
*without* unloading the level, so whatever the pause handler needs in order to
restore it is live in a paused dump. That is a separate and cheaper probe at
the same question.

### `$7E:008D` is the area ID (target 2 closed)

`$7E:008D` holds the area index **multiplied by two** — the pre-doubled offset
the area tables are indexed with. Target 2 is closed.

The lead came from **FredYeye**, author of `Demon-s-Crest-Rando`, who pointed
at his own disassembly (`FredYeye/various-game-disassembly`,
`SNES/demons_crest.asm`) where it is simply declared:

```
!area = $8D
```

Three independent confirmations, none of them cross-sample correlation:

1. **Fred's disassembly declares it.** Authoritative, and it targets USA — but
   WRAM is shared between regions (lesson 6), so it transfers directly.
2. **The seven dumps agree.** All six in-level values are even, and all six
   halve into valid named slots from `docs/areas.md`. `town` halves to 4, which
   is `S2 Town` — the one area whose index was known independently, from the
   capture's own name.
3. **The JP code halves it.** `$80:BE96` is `LDA $8D / LSR A / TAX /
   LDA $9ECF,X`, and `$80:BEAC` is `LDX $8D / REP #$30 / LDY $9FF6,X`. A byte
   table gets the value shifted right; a word table gets it as-is. That is only
   consistent with the stored value being doubled.

| Dump | `$8D` | area | `docs/areas.md` |
|------|-------|------|-----------------|
| `town` | `$08` | 4 | S2 Town |
| `forest` | `$14` | 10 | S3_1 |
| `forest-2` | `$18` | 12 | S3_2a |
| `forest-3-no-canopy` | `$64` | 50 | S3_3a3 |
| `water` | `$30` | 24 | S5_1 |
| `ice` | `$3A` | 29 | S6_1 |
| `overworld` | `$BC` | 94 | not a slot — `$BC` is a mode marker here |

Two corrections to earlier assumptions fall out of this. The "forest" dumps are
**Stage 3**, not Stage 1 — which is why the prediction that three consecutive
sections would hold consecutive indices failed: the route runs S3_1 -> S3_2a ->
S3_3a3, i.e. 10, 12, 50, because the `a`/`b` path variants occupy separate
slots. And `$8D` reading `02` "in level" in the original closed-leads entry was
area 1 (`S1_1`) x 2, not a mode constant.

### JP counterparts of Fred's USA tables

Found by searching the JP ROM for the instruction bytes that reference `$8D`
(`A6 8D` = `LDX $8D`, `A5 8D` = `LDA $8D`) — lesson 6's crossing trick, which
worked first time. `$80:BE9E` is Fred's `_80BEBA` byte-for-byte, 0x1C earlier:

```
$80:BE9E  A9 BD      LDA #$BD
$80:BEA0  48         PHA
$80:BEA1  AB         PLB            ; DB = $BD
$80:BEA2  A2 00      LDX #$00
$80:BEA4  9E 5E 0E   STZ $0E5E,X    ; zero $0E5E-$0E8F, $32 bytes
$80:BEA7  E8         INX
$80:BEA8  E0 32      CPX #$32
$80:BEAA  90 F8      BCC $BEA4
$80:BEAC  A6 8D      LDX $8D        ; area x 2
$80:BEAE  C2 30      REP #$30
$80:BEB0  BC F6 9F   LDY $9FF6,X    ; -> $BD:9FF6
```

| JP | USA (Fred's label) | Read at |
|----|--------------------|---------|
| `$BD:9FF6` | `_BDA04A` — level layout / metatile references | `$80:BEB0`, `X = $8D` |
| `$BD:9ECF` | — | `$80:BE9A`, `X = $8D >> 1` |
| `$BD:98FF` | — | `$80:BEE2`+4, `X = $8D` |
| `$BD:AD66` | — | `$80:BEF3`+, `X = $8D >> 1` |

`$BD:9FF6` is confirmed a **116-entry area-indexed pointer table**: its first
pointer is `$A0DE`, and `$9FF6 + 232 = $A0DE` exactly — the same signature the
other 116-entry tables in this ROM carry (see `docs/areas.md`).

**Not yet established:** whether `$BD:9FF6` is the layout selector proper. It
has only 41 distinct entries across 116 slots, and areas 10 and 12 (`forest`,
`forest-2`) share pointer `$BD:A116` — the same two that share a palette. So it
may be a per-stage or per-tileset record rather than per-section geometry.
Fred's label is a comment in a partial disassembly, not a proven claim. Falsify
by reading the data at `$BD:A116` and `$BD:A0ED` and checking whether it is
section geometry or a descriptor pointing to it.

### Palette id by real area index

With `$8D` decoded, the palette ids from the CGRAM finding map to actual areas:

| Area | Name | Palette id |
|------|------|-----------|
| 4 | S2 Town | 0 |
| 10 | S3_1 | 2 |
| 12 | S3_2a | 2 |
| 50 | S3_3a3 | 5 |
| 24 | S5_1 | 12 |
| 29 | S6_1 | 11 |

Two Stage 3 sections sharing palette 2 is consistent, and `$BD:9FF6` pairs them
too.

### The level-load entry, and a working warp (target 3)

Found by watchpointing `$8D` across a level entry, exactly as FredYeye
suggested. One write per load:

```
[watch] write $81008D (wram $0008D) = 02  PC $85:B0C2  A=FF02 X=0004 Y=0000 D=1300 DB=81
```

The site, with the alternative constant path above it:

```
$85:B0B0  A9 54         LDA #$54
$85:B0B2  8D 8D 00      STA $008D
$85:B0B5  8D 56 0E      STA $0E56
$85:B0B8  80 11         BRA $85:B0CB
$85:B0BA  A4 26         LDY $26         ; D=$1300, so $7E:1326
$85:B0BC  B9 F1 E0      LDA $E0F1,Y     ; DB=$81, so $81:E0F1
$85:B0BF  8D 8D 00      STA $008D       ; area x 2
$85:B0C2  8D 56 0E      STA $0E56       ; second copy
$85:B0C5  B9 82 E1      LDA $E182,Y
$85:B0C8  8D A7 0E      STA $0EA7
```

Two traps worth naming, because both cost time here. `LDY $26` is
**direct page** and `D=$1300`, so the selector is `$7E:1326`, not `$0026`.
And `LDA $E0F1,Y` is **absolute-indexed off DB**, and `DB=$81` while the
program bank is `$85` — the table is `$81:E0F1`, not `$85:E0F1`. The
watchpoint logs `D` and `DB` precisely so this is recoverable.

#### `$81:E0F1` — the destination table

Thirteen bytes, each an area x 2. These are the stage entry points the
overworld can reach:

| Destination (`$1326`) | `$81:E0F1` | Area | Name |
|---|---|---|---|
| 0 | `$02` | 1 | S1_1 |
| 1 | `$08` | 4 | S2 Town |
| 2 | `$14` | 10 | S3_1 |
| 3 | `$24` | 18 | S4_1 |
| 4 | `$30` | 24 | S5_1 |
| 5 | `$3A` | 29 | S6_1 |
| 6 | `$4A` | 37 | unnamed |
| 7 | `$58` | 44 | unnamed |
| 8 | `$62` | 49 | unnamed |
| 9 | `$6E` | 55 | **the shop** (identified from the screenshot) |
| 10 | `$68` | 52 | unnamed |
| 11 | `$6A` | 53 | Trio the Pago 3 |
| 12 | `$6C` | 54 | unnamed |

A parallel table at `$81:E182` (`02 x7` then `04 x6`) feeds `$0EA7`; role
unknown.

#### The warp works

Poking the destination word before the routine reads it produces a **clean**
load — correct layout, tileset and palette, no tearing:

```sh
docker run --rm -v "$PWD":/work -v "$ROM":/work/rom/DemonsBlazon.sfc:ro \
    demons-crest-build python3 tools/headless.py rom/DemonsBlazon.sfc \
    --load-state states/allitems.state --frames 700 --press '10:y,11:y' \
    --poke '76:0x1326=0x01,76:0x1327=0x00' --dump 690
```

Verified for destinations 1, 2, 3, 4, 5 and 9: `$8D` came out as the table
predicts every time, and the frames render as coherent areas. Destination 1 is
Town, 5 is the ice area, 9 is the shop.

Timing, measured: Y is pressed at frame 10, and `$8D` flips from `$BC` to its
area value between frames 79 and 80. Poking `$1326` anywhere in 76-79 works.

#### Poking `$8D` after the write tears the load

Poking `$8D` at frame 80 — one frame *after* it is written — gives Town's
**layout** rendered with the forest's **tile graphics**: recognisable Town
geometry in the wrong tiles. Identical result whether poked once at frame 80 or
held across frames 61-140, so every consumer runs after that write, but the
VRAM upload happens in the same frame as the write, before the frame boundary a
poke can reach.

Consequence for the practice ROM: the 13 destinations are warpable by writing
`$1326` alone, but **warping to an arbitrary one of the 116 areas needs a ROM
hook at `$85:B0BF`** — substitute the value the table read produced, and the
game's own load runs to completion with it. That is the natural shape for the
feature anyway, and it is a two-instruction patch. **Untested**; falsify by
patching `$85:B0BC` to load from a free RAM byte instead of `$81:E0F1,Y` and
warping to a mid-stage area such as 12 (S3_2a).

#### Correction: `allitems.state` enters S1_1

`$8D = $02` on that state's entry, so the destination is area **1**, S1_1. The
earlier "index 2 = S1_2" reading came from `$1D82`, which is retracted. Any
note elsewhere saying `allitems.state` enters S1_2 is wrong.

### Controller RAM (target 4 closed)

The NMI handler reads the pad and computes edge detection itself, so the
practice ROM does not have to. From `$80:835D`, inside the NMI the repo already
hooks (`$FFA4` -> `$80:8329`):

```
$80:8355  AD 12 42      LDA $4212      ; wait for auto-joypad
$80:8358  4A            LSR A
$80:8359  B0 FA         BCS $80:8355
$80:835B  C2 30         REP #$30
$80:835D  A5 90         LDA $90        ; previous <- current
$80:835F  85 92         STA $92
$80:8361  AD 18 42      LDA $4218      ; JOY1L
$80:8364  AA            TAX
$80:8365  29 0F 00      AND #$0F       ; reject non-standard pad
$80:836A  A2 00 00      LDX #$00
$80:836D  86 90         STX $90        ; held
$80:836F  8A            TXA
$80:8370  45 92         EOR $92        ; changed
$80:8372  25 90         AND $90        ; ...and now set
$80:8374  85 94         STA $94        ; newly pressed
```

| Address | Width | Meaning |
|---------|-------|---------|
| `$7E:0090` | 16 | controller 1, **held** |
| `$7E:0092` | 16 | controller 1, previous frame |
| `$7E:0094` | 16 | controller 1, **newly pressed** (one frame) |
| `$7E:0096` / `$0098` / `$009A` | 16 | the same three for controller 2 |

Standard SNES layout, high byte first: `B $8000`, `Y $4000`, **`Select $2000`**,
`Start $1000`, `Up $0800`, `Down $0400`, `Left $0200`, `Right $0100`, `A $0080`,
`X $0040`, `L $0020`, `R $0010`. The low nibble is always zero, which is what
`AND #$000F` tests.

Confirmed headlessly, not just read off the disassembly:

| Frame | Input | `$90` | `$94` |
|---|---|---|---|
| 300 | Y pressed | `4000` | `4000` |
| 301-302 | Y held | `4000` | `0000` |
| 303 | released | `0000` | `0000` |
| 310 | Start | `1000` | `1000` |

The edge at `$94` fires for exactly one frame, which is what a hotkey wants.

### `$85:9B39` — the progress-to-variant selector

Called from the level-load entry at `$85:B09D`, immediately before the
destination table is read, and returns a small tier value in `Y` which the
caller compares with `CPY #$02`. This is the mechanism behind areas having
different forms on a first visit and a revisit.

```
$85:9B39  C2 20         REP #$20
$85:9B3B  AD 58 1E      LDA $1E58
$85:9B3E  89 01 00      BIT #$01
$85:9B41  D0 35         BNE $85:9B78
$85:9B43  A0 03         LDY #$03
$85:9B45  AD 51 1E      LDA $1E51      ; 16-bit: $1E51/$1E52
$85:9B48  89 00 01      BIT #$0100
$85:9B4B  D0 18         BNE $85:9B65   ; return Y = 3
$85:9B4D  A0 00         LDY #$00
$85:9B4F  A2 08         LDX #$08
$85:9B51  AD 51 1E      LDA $1E51
$85:9B54  3C 61 8D      BIT $8D61,X    ; mask table $85:8D61, stride 2
$85:9B57  D0 08         BNE $85:9B61
$85:9B59  AD 54 1E      LDA $1E54      ; 16-bit
$85:9B5C  3C 6B 8D      BIT $8D6B,X    ; mask table $85:8D6B
$85:9B5F  F0 07         BEQ $85:9B68
$85:9B61  CA            DEX
$85:9B62  CA            DEX
$85:9B63  10 EC         BPL $85:9B51
$85:9B65  E2 20         SEP #$20
$85:9B67  6B            RTL
```

**The progress block extends past `$1E57`.** This routine reads `$1E58` bit 0,
which is outside the eight bytes `memory-map/README.md` documents. Any state
block intended to control area variants must cover `$1E58` as well.

Inputs are therefore `$1E58` bit 0, `$1E51`/`$1E52` (bit 8 tested explicitly,
then against `$85:8D61`) and `$1E54`/`$1E55` (against `$85:8D6B`). The two mask
tables are nine entries each, walked `X = 8` down to `0` in steps of 2.

**Not yet established:** what each tier means, and the target of the `$85:9B78`
early-out. Read the two mask tables against the documented progress bit map to
recover the tier definitions — static work, no emulator needed.

### The mode dispatcher is a cooperative task switcher

All of this is **static disassembly, not yet observed running** — treat every
address here as a hypothesis until a watchpoint confirms it.

```
$80:81C8  08            PHP
$80:81C9  8B            PHB
$80:81CA  C2 20         REP #$20
$80:81CC  3B            TSC             ; save the caller's stack pointer
$80:81CD  8D 70 00      STA $0070
$80:81D0  B9 32 00      LDA $0032,Y     ; the target task's saved SP
$80:81D3  1B            TCS             ; switch stacks
$80:81D4  A9 00 00      LDA #$00
$80:81D7  5B            TCD             ; D = 0
$80:81D8  E2 20         SEP #$20
$80:81DA  BE 36 00      LDX $0036,Y     ; that task's state index x 2
$80:81DD  7C C3 82      JMP ($82C3,X)   ; dispatch
```

The yield path back out is `$80:82B7 STA $0032,Y` then `LDA $0070 / TCS / PLB /
PLP`. So per task, indexed by `Y`:

| Address | Meaning |
|---------|---------|
| `$7E:0032,Y` | that task's saved stack pointer |
| `$7E:0036,Y` | that task's **state index x 2** |
| `$7E:0070` | the switcher's scratch for the caller's SP |

`$80:82C3` is a table of 16-bit pointers, each to a four-byte `JML` stub:

| Index | Handler | What it is |
|-------|---------|-----------|
| 0 | `$80:86BE` | |
| 1 | `$80:A7FF` | |
| 2 | `$80:B702` | |
| 3 | `$80:BE9E` | reads `$BD:9FF6` via `$8D`; **not** the state a level entry dispatches to — see the correction below |
| 4 | `$84:F0EA` | |
| 5 | `$84:A0B9` | |
| 6 | `$84:EC3D` | |
| 7 | `$80:86BE` | |
| **8** | **`$80:AF20`** | **the overworld** |
| 9 | `$80:B99D` | |
| 10 | `$80:B9CE` | |

**Why this matters for the practice ROM.** A mode change resets the stack
pointer from `$0032,Y`, so switching state from arbitrary game code does not
require unwinding whatever the level mode had on its stack. That is what makes
an exit-to-overworld hotkey viable on real hardware, and it is why an
exit-and-re-enter design is safer than a direct level-to-level warp.

`$8D` fits this picture too. `$80:AF36` computes it as `#$50 ASL` plus `$0000`,
i.e. `$A0 + index`, which is why the overworld reads `$BC`. Below `$80` it is
area x 2; `$A0` and above encodes overworld state. Named areas stop at 59
(`$76`), so the two ranges do not collide. The original closed-leads note
calling `$8D` a "screen/mode type" was picking up this half of its behaviour.

### Tested: the state-change API, and the exit works

The section above was static disassembly. This part is measured.

A write-range watch on `$0036`-`$0037` across a level entry logs exactly one
write, `$0036 = $04` at `$80:82A9`. The routine doing it, reached by the
`JML $80:829B` that ends the level-entry flow:

```
$80:829E  A9 81         LDA #$81
$80:82A0  48            PHA
$80:82A1  AB            PLB              ; DB = $81
$80:82A2  68            PLA              ; the new state, passed in by the caller
$80:82A3  AC 72 00      LDY $0072        ; the current task
$80:82A6  99 36 00      STA $0036,Y      ; state index x 2
$80:82A9  EB            XBA
$80:82AA  99 37 00      STA $0037,Y
$80:82AD  A9 08         LDA #$08
$80:82AF  99 30 00      STA $0030,Y      ; task status
$80:82B2  C2 30         REP #$30
$80:82B4  B9 34 00      LDA $0034,Y      ; the task's base SP
$80:82B7  99 32 00      STA $0032,Y      ; saved SP := base SP
$80:82BA  AD 70 00      LDA $0070
$80:82BD  1B            TCS
$80:82BE  AB            PLB
$80:82BF  28            PLP
$80:82C0  4C 95 81      JMP $8195        ; back to the scheduler
```

So `$7E:0072` is the current task index, and the stack is **reset** from
`$0034,Y` rather than restored — the property that makes a state change from
arbitrary code safe. That is now observed, not inferred.

**Correction.** The observed level-entry state is `$04`, which selects table
entry `$82C7` -> `$80:B702`, index **2**. The earlier labelling of index 3
(`$80:BE9E`) as "the level load" was wrong: `$80:BE9E` does read `$BD:9FF6`
via `$8D`, so it is part of the load, but it is not what a level entry
dispatches to.

**The exit to the overworld works.** From in-level, poking task 0's state and
status the way `$80:829B` does:

```sh
--poke '400:0x36=0x10,400:0x37=0x00,400:0x30=0x08'
```

`$8D` goes from `$02` to `$BC` within 30 frames and the overworld renders
coherently — Firebrand on the pedestal, world map, correct palette. The pad is
still read afterwards (`$90 = $0100` while Right is held).

**Not established, and the next thing to check:** whether the resulting
overworld is fully *interactive*. Holding Right for 200 frames did not visibly
move Firebrand, and a later `Y` press did not enter a stage. Neither is
conclusive — the `Y` press may simply not have been over an entrance, and the
control run from a legitimate overworld state also leaves him on a platform, so
there is no clean movement baseline. Settling it needs **the overworld position
variable**, which is not yet known: `$1031`/`$1034` are level coordinates and
do not change here. Until that is found, "the exit reaches the overworld" is
proven and "the exit leaves a usable overworld" is not.

`LDX #$10 / LDA #$06 / JSL $80:81E0` at `$80:AF3E` and `$80:A820` remains
undisassembled; it is no longer on the critical path, since `$80:829B` is the
confirmed request API.

### The mode graph, from the state-change call sites

Every state change goes through `JML $80:829B`, and the state is pushed by an
`LDA #$xx` immediately before it. Fifteen sites, so the whole mode graph is
readable statically:

| Site | State pushed | Goes to |
|------|--------------|---------|
| `$80:BB3C` | `$10` | **the overworld — this is the "exit area" routine** |
| `$BE:F565` | `$10` | the overworld, same four-instruction shape |
| `$84:C1FC` | `$04` or `$10` | conditional on `$1E54` bit 0 — a **progress gate**, not the death menu |
| `$85:B0D6` | `$04` | the level (the entry path already traced) |
| `$82:CAF3`, `$84:8570`, `$84:EFEA`, `$85:C485`, `$BE:F4D1` | `$04` | the level |
| `$84:814B`, `$84:C25A`, `$85:9497`, `$85:A512` | `$02` | |
| `$84:88D4` | indexed | a table at `$9B71,X` |
| `$BE:85B5` | `$10` | via `JSL $BE:85C9` |

#### `$80:BB30` — exit to the overworld

**Corrected:** an earlier version of this block was misaligned by two bytes and
began with a non-existent `STA $84`. The real sequence is:

```
$80:BB30  22 1C 85 84   JSL $84851C     ; teardown
$80:BB34  A2 10         LDX #$10
$80:BB36  22 12 82 80   JSL $808212
$80:BB3A  A9 10         LDA #$10        ; state index x 2 = the overworld
$80:BB3C  5C 9B 82 80   JML $80829B
```

`$80:829B` opens `SEP #$30 / PHA`, so the state is passed **in `A`** and the
routine sets its own register widths. The two `JSL`s ahead of it do the
teardown, which is why entering at `$80:BB30` works from arbitrary level code
and jumping to the death entry does not. **Verified working** — see the probes
below.

#### `$84:C1FC` is a progress gate, not the death menu

**Retracted.** This was recorded as the death menu's branch on the strength of
the `AND #$01` shape, without reading the operand. It reads `$1E54`:

```
$84:C1EF  AD 54 1E      LDA $1E54     ; Max-HP+ bits; bit 0 is the Somulo pickup
$84:C1F2  29 01         AND #$01
$84:C1F4  D0 04         BNE $84:C1FA
$84:C1F6  A9 04         LDA #$04      ; -> the level
$84:C1F8  80 02         BRA $84:C1FC
$84:C1FA  A9 10         LDA #$10      ; -> the overworld
$84:C1FC  5C 9B 82 80   JML $80829B
```

`$1E54` bit 0 is documented in `memory-map/README.md` as a progress bit, so this
branches on progress, not on a menu selection. The region is still death- or
respawn-related — `$84:C182` and `$84:C1BE` both write `$1062` — but the label
was wrong. Lesson 2 applies to operands as much as to addresses.

#### Poking `$0036` directly is unreliable

Sweeping task 0's state across every table value from in-level, with status set
to `$08` as `$80:829B` does:

| State poked | Result |
|-------------|--------|
| `$10` | works — clean overworld, `$8D` `$02` -> `$BC` |
| `$0C`, `$14` | black screen |
| `$00`, `$02`, `$06`, `$08`, `$0A`, `$0E`, `$12`, `$16` | no effect; the level keeps running and the poked value simply sits in `$0036` |

So the scheduler does not re-dispatch on a bare state write in general, and the
one value that worked did so for reasons not yet understood. **Use the game's
own exit routine, not a state poke.**

#### The USA-to-JP offset in bank `$80` is `-$1C`

`areas.md` records USA `$80:BB58` as "exit area"; the JP routine is `$80:BB3C`.
FredYeye's USA `_80BEBA` is JP `$80:BE9E`. Both are `$1C` apart, with matching
contents. Useful for crossing the other bank `$80` landmarks, though it holds at
two sites and is **not proven to apply generally** — verify each crossing by
comparing the instructions, not by trusting the constant.

#### Two things that did not work

Poking `$1062` (current HP) to zero does **not** kill Firebrand: HP stayed at 0
for 650 frames with no death, so death is triggered from the damage routine
rather than by polling HP. And the phial slots `$1E35`-`$1E39` are **all zero**
in `states/allitems.state`, so that save has no sulfur potion and cannot test
the potion exit without one being granted first. The item-id table the shop
fills slots from is at `$85:E64F` (`$85:CD36 LDA $E64F,X` / `$85:CD3A STA
$1E35,X`).

Incidental corroboration of the controller finding: the game's own menu code at
`$85:CD4B` does `LDA $0095 / BIT #$80`, i.e. tests B in the newly-pressed word
at `$0094`.

### Death, measured

Death is reachable headlessly: poke `$1062` (current HP) to **1**, not 0, then
walk into an enemy. Poking it to 0 does nothing, because death is driven from
the damage routine rather than an HP poll.

```sh
--poke '200:0x1062=0x01' --press "10:y,11:y,<hold right from 210>"
```

What happens, measured over 1400 frames in area 1:

| Frame | HP | `$8D` | `$0036` |
|-------|-----|-------|---------|
| 300 | 1 | `$02` | `$04` |
| 600 | 0 | `$02` | `$04` |
| 900 | 20 | `$02` | `$04` |
| 1380 | 20 | `$02` | `$04` |

So a single death **respawns in the same area with HP restored** to `$1E50`
(max HP, 20 here), and `$0036` never changes. The death flow does not go
through the state dispatcher at all.

By frame 1380 the three-option menu is on screen, drawn over the level:

- もういちど ちょうせんする — try again
- ステージを えらびなおす — reselect the stage
- ゲームを しゅうりょうする — quit

**The menu is rendered inside the level state `$04`**, which is why no state
write is logged: the dispatch happens only after the player picks. So there is
no mode to jump to in order to raise it.

**Open: how to raise the menu without dying.** Diffing an alive frame against a
menu frame from the same run leaves 1258 differing bytes. The candidates that
went `0` to a small value were `$0016`, `$00E5`, `$0E51` and `$0E5B`, and a
write watch killed the first three:

| Address | What it actually is |
|---------|---------------------|
| `$7E:0016` | general parameter, written constantly from `$80:9536` with varying `X`/`Y` |
| `$7E:0E51` | part of a pointer block; `$82:8B54` stores `$1D50` through it |

`$00E5` and `$0E5B` are untested — the watch budget was consumed by `$0016`'s
churn. Retry with `$0016` excluded, or watch a narrow range only in the frames
around the menu appearing.

**Worth noting for the design:** the retry behaviour may not need the menu at
all. Death already restores HP and respawns in-area without a mode change, and
`$80:BB3C` already exits to the overworld. Two hotkeys invoking those two
behaviours directly would give the same two options with less machinery than
reproducing the menu.

### Killing Firebrand outright: `$80:E602`

Watching writes to `$1062` across a scripted death gives four writes and no
noise:

| PC | Value | What |
|----|-------|------|
| `$85:B09D` | `$14` | level load, `LDA $1E50 / STA $1062` |
| `$80:E57D` | `0000` | 16-bit clear of `$1061`/`$1062` |
| `$80:E606` | `$00` | **the death write** |
| `$84:8524` | `$14` | respawn restores max HP |

The damage check and the death entry, with `D=$1000` during gameplay:

```
$80:E5C4  C2 30      REP #$30
$80:E5C6  A5 61      LDA $61        ; 16-bit read of $1061/$1062
$80:E5C8  F0 38      BEQ $80:E602   ; zero     -> death
$80:E5CA  30 36      BMI $80:E602   ; negative -> death
...
$80:E600  80 29      BRA $80:E62B   ; the survive path jumps over the death code
$80:E602  E2 30      SEP #$30       ; <-- DEATH ENTRY
$80:E604  64 62      STZ $62        ; $1062 = 0
$80:E606  64 61      STZ $61        ; $1061 = 0
$80:E608  A9 08      LDA #$08
$80:E60A  20 76 BD   JSR $BD76
$80:E60D  A9 FF      LDA #$FF
$80:E60F  85 3C      STA $3C
$80:E611  A9 10      LDA #$10
$80:E613  85 05      STA $05
$80:E615  64 06      STZ $06
$80:E617  A9 2D      LDA #$2D
$80:E619  8D E7 00   STA $00E7
$80:E61C  A5 04      LDA $04
$80:E61E  29 04      AND #$04
$80:E620  F0 09      BEQ $80:E62B
$80:E626  A9 24      LDA #$24
$80:E628  4C D3 EF   JMP $EFD3
$80:E62B  A9 12      LDA #$12
$80:E62D  4C D3 EF   JMP $EFD3
```

Only two things reach `$E602`, both from the damage handler, so death is
**never polled** — which is exactly why poking `$1062` to zero did nothing.

**HP is 16-bit at `$1061`.** The check reads `$1061` as a word, so `$1062` holds
HP units and `$1061` a sub-unit below them. `memory-map/README.md` listed only
`$1062` as a single byte; that is the units half.

**To kill outright: `JMP $80:E602`.** Constraints, from the code above:

- It must be entered from **task context**, not from NMI. The original reason
  given here was that `D = $1000` does not hold in NMI; that was wrong, since a
  hook can set `D` itself with `LDA #$1000 / TCD`. The real blocker is that
  `$80:E602` never returns, while NMI must end in `RTI`: jumping into
  non-returning task code from an interrupt abandons the NMI frame on the stack
  and leaves `$4200`/interrupt state wrong. `$80:BB3C` has the same constraint,
  since it tails into `$80:829B`, which hands control back to the scheduler
  through `$0070`. Both hotkey actions therefore need a task-context hook.
- It is **not a subroutine.** It never returns; both exits are `JMP $EFD3`. So
  it must be tail-jumped to, replacing the rest of that frame's update rather
  than being called and returned from. That suits a hook well, and means no
  stack unwinding is needed.
- It is reached only by two relative branches, so nothing else in the ROM jumps
  to it long — a hook in another bank needs `JML $80E602`.

**Untested.** Everything above is disassembly plus the watchpoint that found
`$80:E606`; no code has jumped to `$E602` yet. Falsify with a minimal asar patch
that hooks a player-update site, tests the hotkey and jumps there: if Firebrand
dies and the three-option menu appears, it holds.

This also answers the menu question without needing the menu's own flag. Death
raises the genuine menu, so an outright kill gives both "try again" and
"reselect the stage" with no reconstruction of the UI.

### Death is not triggerable by a data write

**Falsified.** The damage check reads `$1061` as a 16-bit word, so the earlier
test that poked only `$1062` left the word non-zero. Zeroing **both** bytes and
waiting 430 frames still produces no death:

| Frame | `$1061` | `$1062` | word | outcome |
|-------|---------|---------|------|---------|
| 399 | 0 | 20 | 5120 | alive (pre-poke) |
| 450 | 0 | 0 | 0 | alive |
| 880 | 0 | 0 | 0 | alive, HP never restored |

So `$80:E5C4` runs only inside the damage handler and is never polled. `$1061`
is normally zero anyway, so the 16-bit framing is right but the sub-unit is
rarely populated.

The consequence matters for the design: **death cannot be caused by writing
RAM.** It requires a control transfer to `$80:E602`, which in turn requires a
task-context hook — a data write from the NMI hook would have been enough, and
is not.

### Every mode's main loop

Found by searching for `JSL $80821E` (the shared frame sync) followed by a
backward branch. 84 call sites in total, 44 of which form a loop. The ones in
bank `$80`:

```
$80:870E -> $86C7    $80:873B -> $872F    $80:878E -> $8771
$80:87C1 -> $87B3    $80:88D5 -> $88C4    $80:88EE -> $88E0
$80:88FB -> $888C    $80:A801 -> $A7FF    $80:A846 -> $A844
$80:A879 -> $A82D    $80:AF6A -> $AF68    $80:AFF9 -> $AFDC  (the overworld)
$80:B748 -> $B746    $80:B79B -> $B799    $80:B7ED -> $B7EB
$80:B94F -> $B904    $80:B997 -> $B989    $80:B9B1 -> $B9A5
$80:B9C5 -> $B9B7    $80:B9DA -> $B9CE    $80:B9EC -> $B9E0
$80:B9FE -> $B9F2    $80:C500 -> $C4E5    $80:C865 -> $C844
$80:CAD7 -> $CA7D    $80:CD26 -> $CCD2
```

Plus sites in banks `$84` and `$BE`. Short spans of 10-20 bytes are fade and
wait loops; the longer ones are candidates for mode loops.

**FOUND — see "The level gameplay loop" below.** The note that follows is kept
for the method. **Still open: the level's gameplay loop.** The level mode handler is `$80:B702`
(dispatch state `$04`), and its setup runs at least to `$80:B824`, containing
three short wait loops (`$80:B746`, `$80:B799`, `$80:B7EB`) that are fades, not
gameplay. No frame-sync-plus-backward-branch exists between `$80:B7ED` and
`$80:B904`, so the mode hands off rather than looping in place, and the
gameplay loop has not been located.

**Lead for finding it cheaply:** a write watch during level gameplay already
showed `$80:9536` and `$80:953F` writing `$0016` every frame. Those are inside
the per-frame path, so walking their caller chain should reach the loop — no
new measurement needed, just a static trace back from a PC already observed.

### The level gameplay loop, and the hook slot

Found by watching writes to `$0073` across a level entry and tallying the PCs:

| PC | Writes | What |
|----|--------|------|
| `$80:AFF3` | 79 | the overworld loop, frames 0-79 before entry |
| `$80:B824` | 1 | level setup zeroing the counter |
| `$80:B8FD` | 320 | **the level gameplay loop** |

```
$80:B8EB  22 26 AE 85   JSL $85AE26
$80:B8EF  20 6B F6      JSR $F66B
$80:B8F2  20 49 B9      JSR $B949
$80:B8F5  A9 FF         LDA #$FF
$80:B8F7  8D 86 00      STA $0086
$80:B8FA  EE 73 00      INC $0073
$80:B8FD  AD 54 0E      LDA $0E54
$80:B900  0D 55 0E      ORA $0E55
$80:B903  D0 03         BNE $80:B908    ; leave the loop
$80:B905  4C 43 B8      JMP $B843       ; otherwise go round again
```

So the loop body is **`$80:B843` to `$80:B905`**, closed by `JMP $B843`, and it
exits when `$0E54 | $0E55` becomes non-zero. This is a task-context per-frame
site in bank `$80`, which is what both hotkey actions need.

**A 5-byte hook slot** exists at `$80:B8F5`: `LDA #$FF / STA $0086` is five
bytes, so it takes a `JSL` (four) plus a `NOP`, with the displaced two
instructions moved into the hook. Free space is at `$98:A4B5`, a different bank,
so it must be `JSL`/`RTL` rather than `JSR`.

**Complication, measured:** the watch log shows `D = 0000` throughout this loop,
but `$80:E602` addresses HP as `STZ $62` / `STZ $61`, i.e. it expects
`D = $1000`. So a hook here cannot simply `JMP $E602` — it has to set the direct
page first (`REP #$20 / LDA #$1000 / TCD`). Whether `D` is the *only* context
the death code needs is **untested**: it goes on to touch `$3C`, `$05`, `$06`
and `$04` on that direct page and calls `JSR $BD76`, so it may assume more of
the player-update state than the direct-page register alone.

That is the next thing to settle, and it is what the first patch should probe:
hook `$80:B8F5`, set `D`, jump to `$E602`, and see whether Firebrand dies
cleanly and the menu appears, or whether something further is missing.

A safer fallback if that context turns out to be insufficient: find the entry of
the damage routine containing `$80:E5C4` and apply lethal damage through the
normal path, which gets the game to set up its own context.

### The damage application routine

```
$80:E56B  A6 02         LDX $02        ; defence/armour index
$80:E56D  E0 08         CPX #$08
$80:E56F  90 01         BCC $80:E572
$80:E571  4A            LSR A          ; halve the damage when $02 >= 8
$80:E572  8D 00 00      STA $0000      ; stash the damage amount
$80:E575  A5 61         LDA $61        ; HP, 16-bit, D=$1000 -> $1061/$1062
$80:E577  38            SEC
$80:E578  ED 00 00      SBC $0000      ; HP -= damage
$80:E57B  85 61         STA $61
$80:E57D  20 0D EF      JSR $EF0D
... invulnerability, flags and sound set up through $80:E5C4 ...
$80:E5C6  A5 61         LDA $61        ; only now is death checked
$80:E5C8  F0 38         BEQ $80:E602
$80:E5CA  30 36         BMI $80:E602
```

Damage arrives in `A`, is halved when the defence index at `$02` is 8 or more,
and is subtracted from the 16-bit HP at `$1061`. The death check runs well after
the subtraction, which is why it is not a per-frame poll.

`$80:E57B` is the `STA $61` the HP watch caught as "`$80:E57D` wrote `0000` to
`$1061`" — the clamp to zero after lethal damage, one instruction before the
`JSR`.

**Deliberately not added to the RAM map:** `$0000` and `$0002` here. They are
general scratch whose meaning is per-routine — `$0000` is the area index during
the level load at `$84:9C60` and the damage amount here. Mapping either as
"damage amount" would be wrong in most contexts.

**Almost nothing calls into `$80:E4xx`-`$E6xx`** — one internal `JSR $E408`
from `$80:E404` and nothing else. So the damage handler, like the death code, is
a player state-machine target reached through a jump table rather than a
callable subroutine.

**Which is why the death entry stays the better trigger.** Entering the damage
path would mean supplying `A`, `$02` and `D`, and entering a state handler
mid-flow. `$80:E602` sits further down the same path and needs only `D` plus
whatever player-update state it inherits — and everything after it (animation,
HP restore from `$1E50`, the three-option menu, the state dispatch) is work the
game already does. Kept as research and as the fallback if the death entry turns
out to need more context than `D`.

### Two probes: the exit works, the death jump does not

First practice-ROM code that does something. Both live in
`src/asm/experiments/`, both hook `$80:B8F5` in the level gameplay loop, and
both fire on Start newly pressed while Select is held, reading the game's own
`$0094`/`$0090` and clearing the Start bit so the crest screen does not also
open.

#### `death_probe.asm` — FAILED

Sets `D = $1000` and jumps to the death entry `$80:E602`. The jump itself is
fine: the watch confirms `$80:E606` executing with `D=1000` and zeroing HP, so
the hook, the hotkey and the direct-page fixup all work. But the screen goes
black within 20 frames and stays black, with `$0036` still `$04` and HP stuck
at 0.

The direct page was not the missing piece. The damage handler does a large
amount of player-state setup between the HP subtract at `$80:E578` and the
death check at `$80:E5C6` — `$0B`, `$00`, `$0A`, `$4B`, `$4A`, `$78`, `$49`,
`$05`, `$3C`, `$6B` — and jumping straight to `$E602` skips all of it. Kept as
a recorded negative result.

#### `exit_probe.asm` — PASSES

Jumps to `$80:BB30`, the exit-area sequence, with no direct-page fixup (the
loop's `D=0` is what that path expects, since it is normally reached from level
code).

| Frame | `$8D` | `$0036` |
|-------|-------|---------|
| 399 | `$02` (area 1) | `$04` |
| 600 | `$BC` (overworld) | `$10` |
| 880 | `$BC` | `$10` |

The overworld renders correctly with Firebrand placed by the game, and — the
test the `$0036` poke failed — **it is interactive**: holding Right for 320
frames moves him visibly across the map, from the inland pedestal out to the
coastline. So the exit half of the practice loop works on the game's own code
path, in about twelve instructions.

**The round trip closes.** Exit by hotkey at frame 400, hold Right 500-700,
then press `Y`: `$8D` returns to `$02` by frame 900 and the frame at 1180 is
ordinary gameplay in area 1, full HP bar, enemies live.

| Frame | `$8D` | |
|-------|-------|---|
| 710 | `$BC` | overworld, after the hotkey exit |
| 900 | `$02` | back in area 1 |
| 1180 | `$02` | still playing |

So level -> hotkey -> overworld -> fly -> `Y` -> level all works, which is the
practice loop the design asks for.

Two limits on that result. `Y` pressed **on the pedestal itself does nothing**;
Firebrand has to be flown to an entrance first, which matches the design's
"fly around and choose it" rather than contradicting it. And this re-entered
the *same* area, consistent with the older note that flying right for
250/350/450/550 frames and pressing `Y` all enter the same place — choosing a
*different* stage by flying is still not demonstrated in the harness, though
that is an overworld-navigation question and not a defect in the exit.

#### What this says about the design

The contrast between the two probes is the "make the game do the work"
principle paying off and being punished in the same session. `$80:BB30` works
because the game's own teardown runs ahead of the state change; `$80:E602`
fails because it sits *past* the setup it depends on. **The useful rule is to
enter at the start of the game's sequence, not at the furthest point down it** —
which corrects the corollary written into `CLAUDE.md` earlier today.

For a retry feature, the remaining options are to enter the damage path at
`$80:E56B` with lethal damage in `A` (untested), or to drop the in-place retry
and rely on exit-and-re-enter, which now works.

### Why the hotkey exit lands you at the map origin

Reported from real play: the exit works but drops you somewhere other than the
stage you left. Traced, and it is a wipe rather than a misplacement.

The overworld position lives in a **30-byte block at `$7E:1DFA`-`$1E17`**,
mirrored at `$7F:F6E0`. Within it, `$1DFA`-`$1E01` are multi-layer parallax
scroll values in 3:2:1 ratios; Firebrand is fixed centre-bottom on screen and
the map scrolls under him, so scroll *is* position.

Measured across a round trip, entering a stage from `states/ow-250.state` and
leaving by hotkey:

| | `$1DFA`-`$1E01` |
|---|---|
| overworld before entering | `7D C0 5D 80 3E 40 1F 50` |
| in the level | `7D C0 5D 80 3E 40 1F 3C` — **preserved** |
| after the hotkey exit | `00 00 00 00 00 00 00 50` — **wiped** |

So the position survives the whole level visit and is destroyed on the way out.
A write-range watch names the writers:

| PC | What |
|----|------|
| `$85:B5B8` | the per-frame scroll update, 130 writes |
| `$82:8B46` | 16-bit clears on level entry |
| `$85:9976` | **the clear that costs us the position** |
| `$85:94EB` | writes `$1E01 = $0050` |

```
$85:9971  A9 00         LDA #$00
$85:9973  AA            TAX
$85:9974  95 15         STA $15,X        ; D=$1DE5, so from $1DFA
$85:9976  9F E0 F6 7F   STA $7FF6E0,X    ; and the mirror
$85:997A  E8            INX
$85:997B  E0 1E         CPX #$1E         ; 30 bytes
$85:997D  D0 F5         BNE $85:9974
$85:997F  A9 50         LDA #$50
$85:9982  E5 33         SBC $33
$85:9984  8D 00 00      STA $0000
```

**Falsified:** that `SBC $33` looked like it derived the landing position from
`$1E18`, but `$1E18` reads `$00` in every overworld dump and every frame of a
flight, so `$50 - 0 = $50` is simply the constant that ends up in `$1E01`. It
is not a lever.

**How the natural exit places you correctly is still unknown.** Reusing that
would be the better fix by the "make the game do the work" rule, and it has not
been found.

**A workable fix that is fully in our control:** the block is intact at the
moment our hook runs, so save `$1DFA`-`$1E17` into spare RAM before jumping to
`$80:BB30`, then restore it from a second hook placed just after the clear loop
at `$85:997F`. Thirty bytes each way. `$7F:C668`-`$7F:C802` is documented in
`nmi_probe.asm` as reading zero across title, cinematic and gameplay states, so
it can hold the copy. **Untested**, and it would land you where you *entered*
the stage, which is above it.

### Next capture

The highest-value remaining dump is **forest section 3 with the canopy
triggered**. Diffed against `forest-3-no-canopy` it isolates the layout selector
directly: same area, same palette, same tileset, one differing layout. That is a
far tighter experiment than comparing different areas, where a load touches
hundreds of variables.
