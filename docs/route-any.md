# Any% route

There is one Any% route and it is not expected to change. Kept in the plain
ordered form `RockmanX2Practice` uses for its route notes, because a runner has
to be able to check it, then the derived state blocks below it.

## The route

```
Initial Stage          (played before the overworld exists)
- Get 2 HP drops
- Get Earth Crest

Town
- Get 2 HP drops

Tower
- Get Claw            (allows sticking to walls)

Forest
- Get Tornado

Castle
- Beat the final boss
```

## Derived state blocks

Progress at the moment each stage is **entered**, i.e. the cumulative sum of
everything collected before it. Generated with `tools/state.py`; max HP is
derived from the HP-up count rather than supplied.

| Stage entered | Destination (`$1326`) | Area (`$8D`/2) | `$1E50`-`$1E58` | Max HP | Items |
|---|---|---|---|---|---|
| Initial Stage | — (before the overworld) | 1 | `04 00 00 00 00 00 00 00 00` | 4 | none |
| Town | 1 | 4 (S2 Town) | `06 10 00 00 03 00 00 00 00` | 6 | Earth Crest, 2 HP-ups |
| Tower | 3 *(inferred)* | 18 (S4_1) | `08 10 00 00 0F 00 00 00 00` | 8 | Earth Crest, 4 HP-ups |
| Forest | 2 | 10 (S3_1) | `08 14 00 00 0F 00 00 00 00` | 8 | + Claw |
| Castle | 6 | 37 (S7_1) | `08 16 00 00 0F 00 00 00 00` | 8 | + Tornado |

Reproduce any row with, for example:

```sh
python3 tools/state.py encode EarthCrest Claw Tornado HPUp1 HPUp2 HPUp3 HPUp4
```

Which HP-up bits are used does not matter to the game, only how many: max HP is
`4 + popcount($1E54, $1E55)`. `HPUp1` upward is chosen for readability.

## How the destinations were identified

The 13-entry destination table at `$81:E0F1` maps `$1326` to an area x 2; see
`docs/recon.md`. Each row above was checked by warping and looking at the frame.

- **Town — confirmed.** Destination 1 renders the town, EXIT sign included, and
  matches the `town` WRAM dump's `$8D = $08`.
- **Forest — confirmed.** The `forest`, `forest-2` and `forest-3-no-canopy`
  dumps read `$8D` as areas 10, 12 and 50, all Stage 3, so the stage entry is
  destination 2 (area 10).
- **Castle — confirmed.** Destination 6 is area 37, and `docs/areas.md` names
  38-41 as S7_2 to S7_5, making 37 the S7_1 entry. The frame shows a castle
  interior: stained glass, ornate torches, red brick.
- **Tower — inferred, not confirmed.** Destination 3 is area 18 (S4_1) and the
  frame shows stone columns, a gargoyle statue and arches opening onto sky at
  height, which reads as a tower. But it is a guess from one screenshot, and
  "tower" and "castle interior" are easy to confuse. **Confirm before building
  the stage-select table against it.**

Note the route order is not destination order: Town, Tower, Forest is
destinations 1, 3, 2. The route visits Stage 4 before Stage 3.

## Not yet decided

- **The Initial Stage is played before the overworld**, so it has no
  destination-table entry to warp to and its state block is all zeros anyway.
  Practising it means starting a new game. Whether the practice ROM should
  offer it at all is open.
- **First visit versus revisit.** The plan is that holding Select at stage
  selection picks a variant, which the game chooses itself from the progress
  block via `$85:9B39`. Blocked on decoding the mask tables `$85:8D61` and
  `$85:8D6B`, so no route state above sets `$1E58` yet.
- **Mid-stage checkpoints.** Deferred. Only the 13 stage entries are reachable
  through the destination table; anything mid-stage needs the untested ROM hook
  at `$85:B0BC`.
