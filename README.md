# Demon's Crest

Practice ROM and research tooling for Demon's Crest / Demon's Blazon (SNES).

Targets the **Japanese** release. The RAM map in `memory-map/README.md` is
JP-only; the English ROM has different mappings.

## Getting it

There is no downloadable ROM and there never will be. Distribution is an **IPS
patch** applied to your own dump of the Japanese release, wrapped in a single
self-contained HTML file:

```sh
make dist      # -> build/dist/DemonsCrestPractice.html  (~15 KB, one file)
```

That one file is the whole distribution. Open it in any browser — including
straight off the filesystem, offline — drop in a ROM, and it verifies the source
against the pinned SHA-1, strips a copier header if there is one, applies the
patch, checks the result against the hash of the build it came from, and offers
the patched ROM as a download. Nothing is uploaded and no toolchain, container
or Python is involved.

The patch, both hashes and the controls documentation are baked in at build
time, the last of these lifted from the section below, so the file cannot drift
from the ROM it was built against. SHA-1 is implemented in JavaScript rather
than via `crypto.subtle`, because a page opened from `file://` is not a secure
context in Chrome and `crypto.subtle` is undefined there.

`tools/apply.py` does the same job from a command line if you would rather
script it, and any ordinary IPS patcher works too — but neither is needed.

## Using the practice ROM

### Controls

All three hotkeys work during gameplay in a stage, and all use **Select** as the
modifier so nothing collides with normal play.

| Buttons | Effect |
|---------|--------|
| **Select + Start** | Leave the current stage for the overworld. No death, no animation, no HP loss. The crest/vellum screen does not open — the Start press is consumed. |
| **Select + R** | Save state |
| **Select + L** | Load the saved state |

### Starting a new game

A new game goes **straight to the overworld map with the Initial Stage already
beaten** — Somulo, Hippogriff and Arma are done, so you start with the Earth
Crest and two HP upgrades. No intro stage to sit through.

You start with the route's **final** progress — Earth Crest, Claw, Tornado and
four HP upgrades — so that **every stage on the route is available on the map**,
the castle included. The castle is otherwise hidden until Flier is dead.

You never actually play with that state. When you enter a stage, the ROM
overwrites your progress with what a runner would have **at that point in the
route**, and when you leave, it restores the full set so the map is complete
again.

### Per-stage progress

Pick a stage by flying to it on the overworld as normal — there is no
stage-select menu. Whatever you enter, you arrive with the correct route state:

| Stage entered | You have | Max HP |
|---------------|----------|--------|
| Stage 1 (revisit) | the Somulo HP upgrade | 5 |
| Town | Earth Crest, 2 HP upgrades | 6 |
| Forest | Earth Crest, 4 HP upgrades | 8 |
| Tower | + Tornado | 8 |
| Castle | + Claw | 8 |

The Any% route is Initial Stage → Town → Forest → Tower → Castle; see
`docs/route-any.md`. Entering the castle with route progress also gets you the
**Any% castle room**, not the late-game castle section that Any% never reaches.

Stages the route does not visit are left alone — you keep whatever progress you
had, which may not make sense for that stage. That is deliberate.

### Save states

Saves all of WRAM, all of VRAM and CGRAM, so the picture comes back as well as
the game state. Verified to restore byte-for-byte after scrolling away.

**Scope: the same section only.** Save and load in one place, for retrying a
jump or a boss. Saving in one area and loading in another is not supported and
has not been tested.

### Things to expect

- **The screen blanks for about a third of a second** on each save and load.
  That is the copy running with the screen off; it is not a crash.
- **Exiting drops you at the map origin**, not above the stage you left, so you
  have to fly back. Known, see `docs/route-any.md`.
- **Progress picked up inside a stage is discarded when you leave.** Every
  attempt starts from the canonical route state, which is the point — but it
  means this ROM is not suitable for an actual playthrough.
- **Practising the Somulo fight is not possible** through the stage select. It
  only exists on a fresh start that has not had the intro skipped, and the ROM
  always skips it.

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
make dist     # the single-file HTML patcher
make test     # regression tests (use `make docker-test` on the host)
```

### Regression tests

`tools/regress.py` guards the faults that have actually happened here, so a
future change fails with a name instead of a mystery. Seven static checks on
the built ROM, then five scenarios driven through the headless core.

It is validated against the broken builds rather than only the good one: v0.6
fails the copier-flag checks, v0.7 fails the `$7F:FFFE` checks, and the current
build passes all 21. A suite that only ever passes proves nothing.

One gap is recorded in the code rather than papered over: `$0EEB`, the flag
that gates the crest menu, is asserted but **not exercised** - measured against
a re-armed build, nothing in these scenarios reaches the check at `$80:8746`.
The exact static byte check is the real guard for that site.

`make verify` pins the source ROM's SHA-1 to `rom.lock` so later builds fail
loudly if the dump changes. Override the path with `make ROM=path/to/rom.sfc`.

### Without installing a toolchain

The build also runs in a container, producing byte-identical output. The ROM is
mounted read-only and never enters the image.

```sh
make docker-image   # one-time
make docker-rom
make docker-dist    # patch + single-file HTML patcher
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
