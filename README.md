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
| `tools/` | ROM identification and patch generation |
| `docs/` | recon plan and design notes |

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
make docker-shell   # interactive
```

## Status

Phase 0 (build pipeline) works end to end, on the host and in a container.
Phase 1 recon is not started — see `docs/recon.md`. No practice features are
implemented yet.

Two constraints established from the ROM itself: there is **no SRAM**, so
config persistence needs a header change, and the ROM has **no contiguous free
space over 891 bytes**, so it must be expanded to 4MB for practice code.
