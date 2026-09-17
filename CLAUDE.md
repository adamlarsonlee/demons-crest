# Demon's Crest practice ROM

## The goal

An **Any% practice ROM** for Demon's Crest that runs on **real SNES hardware**
via FXPak Pro, modelled on `Myriachan/RockmanXPractice`. Practice features are
baked into the ROM as 65816 assembly, not provided by an emulator.

Everything else in this repo — the Lua HUD, the headless harness, the
disassembler — is **research tooling in service of that goal**, not the
deliverable. Don't propose emulator-side Lua features as the product.

## Settled decisions

| Decision | Why |
|----------|-----|
| **Japanese ROM** (Demon's Blazon) | `memory-map/README.md` is JP-only and warns the English ROM differs. The repo's prior research is all JP. |
| **True ASM hack, not a Lua harness** | Must run on a physical SNES. This rules out savestate-based practice. |
| **asar**, not bass | RockmanXPractice pins bass v10, whose macro syntax the v18 that builds on macOS rejects (verified). asar is native, maintained, one brew command — and is in the container. |
| **State blocks**, per RockmanXPractice | Hardware can't do savestates, so progress is hardcoded RAM blocks written on warp. Validated: writing `$1E50`-`$1E57` into another save gives a pixel-identical item menu. |
| **Container for everything** | The host is a company-managed Mac. asar and a patched libretro core both live in the image; nothing needs installing. |
| **Any% first** | Route scope agreed up front. Boss Rush and 100% later. |

## Open decisions

- **4MB expansion.** The ROM has no contiguous free region over 891 bytes, so
  practice code needs the ROM expanded 2MB -> 4MB. Deferred pending a
  conversation about playability across FXPak Pro, other flashcarts and
  emulators. **Do not expand the ROM without settling this.** It also forces
  BPS over IPS for distribution.
- **Where the per-frame hook lives.** Both candidates perturb frame pacing;
  see "Hooks" below. Needs a purpose-built repeatable measurement.

## Status

Phase 0 (build pipeline) is done. Phase 1 recon is partly done.

| # | Target | Status |
|---|--------|--------|
| 1 | Progress-state region | **done** — `$7E:1E50`-`$1E57`, mapped bit-for-bit |
| 2 | Area / level index | **done** — `$7E:008D` is the area ID **x 2**; confirmed three ways |
| 3 | Level-load entry | **partial** — `$85:B0BA`: `$7E:1326` -> `$81:E0F1` -> `$8D`. Clean warp verified, but only riding the game's own overworld trigger; warping from arbitrary state is untested |
| 4 | Controller RAM | **done** — `$7E:0094` newly-pressed, `$7E:0090` held; Select is `$2000` |
| 5 | Per-frame hook | **done** — NMI `$FFA4` -> `$80:8329`; code injection proven transparent |
| 6 | RNG | open |
| 7 | Free ROM space | **mapped** — fragmented; needs expansion |

Also established: the password system is fully mapped and scriptable, and the
area/section index space is known by name (`docs/areas.md`).

Nothing of the practice ROM itself is written yet. `src/asm/experiments/` holds
probes, not features.

## How to work here

```sh
make verify      # identify the ROM, pin its SHA-1, emit the asar mapping
make rom         # build build/DemonsBlazon_Practice.sfc
make docker-rom  # same, in the container (byte-identical output)
make docker-shot # capture frames to build/frames as PNG
```

Supply your own ROM at `rom/DemonsBlazon.sfc`; ROMs and save states are
gitignored and never distributed.

**The verification loop is headless and visual.** `tools/headless.py` drives a
patched libretro core: PNG frames, WRAM and VRAM dumps, save states, WRAM
pokes, scripted input. Emulation is deterministic run to run, so pixel
comparison is a valid regression test.

**Watchpoints** are the sharpest tool. `S9X_WATCH_WRITE`, `S9X_WATCH_WRANGE`,
`S9X_WATCH_READ`, `S9X_WATCH_REG` log the PC plus A/X/Y/D/DB. See
`docs/recon.md`.

`tools/disasm.py` is a 65816 disassembler. Register widths change instruction
length, so pass `--m`/`--x`; wrong widths silently desynchronise the output.

## Lessons — read before asserting what an address means

These are all mistakes already made here. Each cost real time.

1. **Correlation across two samples is not causation.** A value that differs
   between two areas is usually a counter, a buffer index or stack residue. A
   level load touches hundreds of variables. Four separate "found it" claims
   had to be retracted this way.
2. **Disassemble the routine before naming an address.** Every false lead died
   the moment its writer was read: `$0088` was a sound-queue index, `$008F` an
   allocation counter, `$092C` a sound ring-buffer slot, `$0073` a frame
   counter, `$8D` a screen-mode type.
3. **Verify that two states actually differ before diffing them.** An entire
   experiment run was invalid because both "destinations" entered the same area.
   Compare the screenshots first.
4. **Zero does not mean unused.** `$1E51` reads zero early in the game and is
   the item-flag region.
5. **Measure timing in a moving scene.** In a static scene several consecutive
   frames are identical, so any frame shift looks like a match.
6. **WRAM is shared between USA and JP; ROM is not.** So USA sources' WRAM
   knowledge transfers directly. Better still, instructions referencing WRAM
   have identical bytes in both, so searching the JP ROM for e.g. `AD 56 1E`
   (`LDA $1E56`) locates the JP equivalent of a known USA routine. This works
   far better than statistical diffing.
7. **Search name variants for prior art.** `FredYeye/Demon-s-Crest-Rando` never
   matched a query for "demons crest" and turned out to hold the authoritative
   area table. Better still: **ask the author.** One message from FredYeye
   closed target 2 after this repo had spent four retractions on it.
8. **A closed lead can be wrong too.** `$8D` was listed under closed leads as a
   "screen/mode type" on two samples. It is the area ID. A later search for
   `index x 2` hit `$8D` and the hit was discarded *because* the closed-leads
   table said so. Closures deserve the same scrutiny as findings — record what
   evidence closed a lead, and re-open it when a hit contradicts it.
9. **Test more than one encoding before concluding "absent".** "The area index
   is not in WRAM" was concluded from searching for the raw value. It was there
   all along, doubled. An absence claim is only as wide as the encodings tested,
   so state which ones those were.

## Hooks

Two per-frame sites are known, neither clearly better:

- **NMI**, `$80:FFA4` -> `$80:8329`. Injected code verified transparent to game
  state (only our counter and stack residue differ). Shifts the game by one
  frame at load transitions in some scenarios.
- **`$80:821E`**, a frame-sync routine every mode calls. Hook at `$80:822D`,
  *after* its register-save prologue — displacing `PHB`/`PHD`/`PHP` into a
  subroutine strands them on top of the `JSL` return address and breaks the
  `RTL`. Fires roughly twice per frame in gameplay, and measured a larger frame
  shift than the NMI hook.

NMI cycle cost is the binding constraint: ~30 cycles shifts one frame, ~4000
diverges grossly.

## What a GUI emulator would unlock

The headless harness can observe state and force values, but it cannot single
step. The blocker on targets 2, 3, 4 and 6 is not tooling so much as **reliable,
known destinations**: only two areas are reachable dependably here
(`states/allitems.state` + Y enters S1_1, `states/bossrush.state` + Y enters the
castle), and overworld navigation does not work as a way to reach a third —
flying right for 250/350/450/550 frames and pressing Y all enter the same place.

Seven named-area dumps now exist in `states/wram/`, and they did their job:
combined with Fred's disassembly they closed target 2. **Any dump now
self-identifies its area** — read `$8D` and halve it — so future dumps no
longer need careful labelling, only variety. Drop them in `states/`
(gitignored); `states/wram/MANIFEST.md` records what is there.

Dumps, not save states. A dump is just bytes, so it works from any emulator; in
Mesen it is Debug -> Memory Tools -> Work RAM -> export. Save states are
core- and version-specific: this harness pins the snes9x libretro core at commit
`890b5d4`, so a Mesen state will not load and even another snes9x build probably
will not. A mismatch fails loudly with `retro_unserialize failed` rather than
producing garbage. VRAM dumps are worth taking too — matching VRAM against the
ROM is what located the area-specific tilesets.

Either must be made against the unmodified JP ROM,
`sha1 a6dc126a1da593d900b33eb74cf33403075e9525` (headerless).

Target 2 is closed, so the write-breakpoint that would have finished it is no
longer needed. What remains open and needs a debugger is targets 3, 4 and 6 —
and for 3, the cheapest next step is static: read the data behind
`$BD:9FF6`'s pointers and settle whether that table is the layout selector.

## Documentation

Keep these current — they are the project's memory:

- `docs/recon.md` — recon targets, findings, **closed leads**, methods
- `docs/areas.md` — the 116-slot area table and randomizer-derived facts
- `docs/passwords.md` — working passwords and how to enter them headlessly
- `memory-map/README.md` — the canonical RAM map

Record negative results. Knowing what an address *isn't* is worth as much as
knowing what it is, and half of `docs/recon.md`'s value is the closed-leads list.

**An address is not found until it is in `memory-map/README.md`.** `docs/recon.md`
holds the evidence and the routine that established it; the RAM map is where it
gets looked up months later. Propagate it in the same commit that establishes
it, with the address of the code that proves it, so the next session can
re-verify instead of re-deriving. Addresses have sat in `recon.md` while the map
went stale, and the load-bearing ones — the task-switcher block, the CGRAM
shadow, the overworld destination index — are exactly the ones that get lost.

**Read the map before hunting.** It already held the scroll and phial content
values, Sulfur among them, while they were being re-derived from the ROM. Check
what is documented before disassembling; this repo has more written down than it
feels like.

## External sources

- `Myriachan/RockmanXPractice` — the architectural model (bass, USA Rockman X)
- `FredYeye/Demon-s-Crest-Rando` — authoritative area table, progress bit
  mapping, USA code landmarks. Targets the **USA** ROM.
- `FredYeye/various-game-disassembly`, `SNES/demons_crest.asm` — the same
  author's partial disassembly, and the best source in the project. It declares
  `!area = $8D`, which closed target 2, and labels the area-indexed tables
  (`_BDA04A` layout, `_BD9953` tilesets, `_BD9C7D` area config). USA addresses;
  cross to JP with the lesson-6 byte trick. Its comments are working notes, not
  proven claims — verify before relying on a label.
- `abyssonym/demons_crest_hacking` — level data *structure*. Its addresses are
  **USA file offsets**, confirmed; treat as a guide to format, not to addresses.

## Conventions

- No AI attribution in commits or PRs.
- Commit messages state what was established and what remains uncertain.
  Retractions are committed promptly and explicitly.
