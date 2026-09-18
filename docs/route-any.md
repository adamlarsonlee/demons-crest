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
| Initial Stage | — (before the overworld) | 0 (Somulo arena) | `04 00 00 00 00 00 00 00 00` | 4 | none |
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

## Booting straight to the overworld

The practice ROM should start on the overworld with the Initial Stage already
beaten, since it is the least useful thing to practise. **This needs no custom
transition code.** The game already decides it, at the tail of the routine that
applies a loaded password:

```
$84:C1EF  AD 54 1E      LDA $1E54
$84:C1F2  29 01         AND #$01      ; bit 0 = the Somulo HP-up
$84:C1F4  D0 04         BNE $84:C1FA
$84:C1F6  A9 04         LDA #$04      ; -> level state: the Initial Stage
$84:C1F8  80 02         BRA $84:C1FC
$84:C1FA  A9 10         LDA #$10      ; -> overworld state
$84:C1FC  5C 9B 82 80   JML $80829B
```

Somulo is the Initial Stage's boss, so `$1E54` bit 0 *is* "Initial Stage
beaten". Confirmed both ways:

| `$1E54` bit 0 | Lands in |
|---|---|
| clear (boss rush password, `$1E54 = 00`) | area 0, the Somulo arena, state `$04` |
| set (every other documented password) | the overworld, state `$10` |

`docs/passwords.md` corroborates it independently: boss rush is the only
password recorded as merely "accepted", while all the others say "accepted,
loads overworld".

So every route block from Town onward already sets the bit — Town's `$1E54` is
`$03` — and boots to the overworld for free. A starting block for "Initial
Stage beaten" is exactly the Town row.

### Area 0 is the Somulo fight only, and is not re-enterable

Measured, because it changes what "practise the Initial Stage" can mean.

| How entered | `$8D` | Area | What is on screen |
|---|---|---|---|
| `$1E54` bit 0 clear, pre-overworld | `$00` | 0, Somulo arena | purple stone hall, fire-breathing gargoyle face, columns |
| destination 0 from the overworld, Somulo already beaten | `$02` | 1, S1_1 | swamp with dead trees, torches, ghost enemies |

So **area 0 is reachable only on the first visit.** Re-entering through the
destination table gives area 1, an entirely different place. `docs/areas.md`
listing both `0 Somulo arena` and `17 Somulo exit` fits the Initial Stage being
the Somulo fight plus an exit section, separate from the S1_1-S1_3 sections you
return to.

**Resetting progress does not bring area 0 back.** Tested, because it was worth
hoping for: with `$1E50`-`$1E58` written back to `04 00 00 00 00 00 00 00 00` on
the overworld, entering destination 0 still loads area 1, not area 0. The
progress override at the load entry is narrow — `$85:B0A1` requires tier 2 *and*
destination 6 — so nothing redirects destination 0.

The consequence for the practice ROM: offering "Initial Stage" as a stage-select
entry would **not** give the Somulo fight. Practising that specific fight needs
a new game with `$1E54` bit 0 clear, which is the one case where booting to the
overworld is the wrong behaviour. Usefully, that is also the *default* — so the
practice ROM's Somulo option is simply "do not write a route block", and every
other option writes one.

### Writing the progress block before entry works

The core of the route-state feature is validated. Poking `$1E50`-`$1E58` on the
overworld and then entering a stage produces a clean load that reflects the new
state: with the block reset to `$04 00 ...`, area 1 loaded normally and the HP
bar showed **4 pips instead of 20**, i.e. `$1E50` reached `$1062` through
`$85:B097` as expected, with no corruption of graphics or state.

So the mechanism the stage-select presets depend on — write the block, then let
the game load the stage — needs no hook beyond the write itself.

**Not established:** stage 1's section layout. Holding Right for 700 frames in
area 1 never changed `$8D`, though Firebrand did move — the section is either
long or he was blocked or fighting — so no transition to areas 2, 3 or 17 was
observed.

**Still to find:** where a *new game* initialises `$1E50`-`$1E58`, so the
practice ROM can write a route block there instead of zeros. The password path
writes the block just before `$84:C182`; a new game presumably has its own
init, and that is the hook site.

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
