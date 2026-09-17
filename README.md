# Demon's Crest

Practice ROM and research tooling for Demon's Crest / Demon's Blazon (SNES).

Targets the **Japanese** release. The RAM map in `memory-map/README.md` is
JP-only; the English ROM has different mappings.

## Layout

| Path | Contents |
|------|----------|
| `src/asm/` | asar sources for the practice ROM |
| `src/lua/` | cross-emulator Lua HUD, used as the reverse-engineering instrument |
| `memory-map/` | documented RAM addresses |
| `mesen-s/` | Mesen-S label file |
| `watch/` | RAM watch files, per boss |
| `tools/` | ROM identification, patch generation, headless capture, disassembly |
| `states/` | Save states (gitignored, regenerate with `headless.py --save-state`) |
| `docs/` | recon plan, design notes, passwords, area table |

## Building

Requires `asar` (`brew install asar`) and Python 3. Supply your own ROM dump at
`rom/DemonsBlazon.sfc`; ROMs are gitignored and never distributed.

```sh
make verify   # identify the ROM, pin its hash, emit the asar mapping include
make rom      # build build/DemonsBlazon_Practice.sfc
make patch    # emit a distributable IPS patch
```

`make verify` pins the source ROM's SHA-1 to `rom.lock` so later builds fail
loudly if the dump changes. Override the path with `make ROM=path/to/rom.sfc`.

### Without installing a toolchain

The build also runs in a container, producing byte-identical output. The ROM is
mounted read-only and never enters the image.

```sh
make docker-image   # one-time
make docker-rom
make docker-shot    # capture frames to build/frames as PNG
make docker-shell   # interactive
```

The image also carries a headless libretro core, patched with watchpoints, so a
ROM change can be verified visually, WRAM/VRAM inspected, and the code touching
an address identified — all without a GUI emulator. See `docs/recon.md` for the
`S9X_WATCH_*` variables.

```sh
make docker-shot FRAMES=3410 DUMP=3400        # title screen
make docker-shell   # then: python3 tools/headless.py --help
```

## Capturing reference dumps

Some recon needs a GUI emulator with a debugger, which this repo's headless
harness cannot replace. Dumps go in `states/wram/` (gitignored) with a
`MANIFEST.md` recording which area each file is. Seven area dumps are already
recorded there; `docs/recon.md` has what they established.

Export from Mesen with Debug -> Memory Tools -> CPU Memory -> export. That
gives a 16MB image of the whole bus, which is preferred over a 128KB Work RAM
export because it embeds the ROM and so proves which cartridge the dump came
from. WRAM is the 128KB window at offset `0x7E0000`.

Three rules that make a batch comparable:

1. **One password save for the whole batch.** The progress block `$1E50`-`$1E57`
   must read identically in every file, otherwise item state becomes a
   confound. The existing seven are all `14 FF FF FF FF FF FF 03`.
2. **Note the variant** — `forest-3-canopy` vs `forest-3-no-canopy`. The area
   itself no longer needs labelling: `$7E:008D` holds the area ID x 2, so every
   dump self-identifies. Variants of one area still need a note, since they
   share an ID.
3. **Standardize the moment.** Same landmark, standing still, ideally with no
   active enemies. Animation frames, enemy spawn slots and scroll position
   differ between any two captures and account for most of the churn between
   files.

**Emulator pause is not the in-game pause.** Emulation -> Pause freezes the CPU
without changing game state. The in-game Start pause switches mode to the
crest/vellum screen, which is a different thing and a separate experiment.
Where a capture below says "paused", it means the emulator. Pausing before
export also makes the snapshot atomic, but the effect is small — tearing was
34-60 bytes out of 131,072, confined to zero page and the stack.

### Priority order

| # | Capture | Files | What it buys |
|---|---------|-------|--------------|
| 1 | **Noise floor** — one area, entered twice, dumped at the same landmark both times | 2, ideally 4 (two re-entries) | The set of addresses that differ between two dumps of an *identical* area. Subtracting it from a cross-area diff is what makes the diff usable at all; without it a level load touches hundreds of variables and the candidate list is meaningless |
| 2 | **Layout variant** — forest section 3 with the canopy triggered | 1 | Pairs against the existing `forest-3-no-canopy`. Same area, same palette, same tileset, one differing layout, so it isolates the layout selector and localizes the layout buffer |
| 3 | **Paused equipment screen** — one area, dumped unpaused and again on the crest/vellum screen | 2 | The pause screen switches mode without unloading the level, so whatever the handler needs to restore the level is live in the paused dump |
| 4 | **Overworld positions** — two or three distinct map locations | 3 | `$8D` holds a mode marker (`$BC`) rather than an area on the overworld, so what selects the destination when Y is pressed is still unknown. Needed for a warp feature |
| 5 | **Consecutive sections** of one more stage, in order | 3 | More points for the palette-id to area-index mapping, and tests whether sections of a stage share a palette as forest 1 and 2 do |
| 6 | **Boss rooms** — Somulo's arena and one other | 2 | Unambiguous single area slots, so they anchor the index mapping |

Stopping after #2 still unblocks the work that is currently stuck.

### What dumps cannot settle

The area index is no longer among them: `$7E:008D` carries it, and target 2 is
closed. Read `docs/recon.md` before planning a session — the cheapest remaining
work on the level-load path is **static**, reading the data behind the
`$BD:9FF6` pointer table, and needs no emulator at all.

What still wants a debugger is the RNG (target 6) and confirming what consumes
the layout pointers. For those the artifact to bring back is a **trace log
across one level entry**: Debug -> Trace Logger, start it on the overworld just
before entering, run it through the load until the level is playable, save to
file. Size is not a concern; it is analysed offline.

Before doing any of that, though, check
`FredYeye/various-game-disassembly` (`SNES/demons_crest.asm`) for the routine in
question. It is a partial USA disassembly by the randomizer's author, it already
labels most of the area-indexed tables, and cross-referencing it against the JP
ROM with the lesson-6 byte trick has been faster than every measurement this
project has run.

## Status

Phase 0 (build pipeline) works end to end, on the host and in a container.
Phase 1 recon is under way — see `docs/recon.md`. Code injection is proven and
the progress-state block is identified at `$7E:1E50`-`$1E57`. No practice
features are implemented yet.

Two constraints established from the ROM itself: there is **no SRAM**, so
config persistence needs a header change, and the ROM has **no contiguous free
space over 891 bytes**, so it must be expanded to 4MB for practice code.

Two experiments under `src/asm/experiments/`:

- `title_practice.asm` — data-only, replaces the Capcom logo on the opening
  screen with the word PRACTICE.
- `nmi_probe.asm` — chains the NMI vector through injected code, proving code
  execution. Verified transparent to game state; see the NMI cycle budget note
  in `docs/recon.md` before writing anything substantial into that hook.
