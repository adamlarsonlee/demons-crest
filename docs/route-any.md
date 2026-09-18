# Any% route

There is one Any% route and it is not expected to change. Kept in the plain
ordered form `RockmanX2Practice` uses for its route notes, because a runner has
to be able to check it, then the derived state blocks below it.

## The route

As described verbally, then as measured from a full set of route dumps. **The
two disagree on one point — see "Order" below.**

```
Initial Stage          (played before the overworld exists)
- Beat Somulo          -> 1st HP drop
- Beat Hippogriff      -> 2nd HP drop
- Beat Arma            -> Earth Crest

Town
- Beat Belth           -> 2 HP drops

Forest
- Beat Flame Lord      -> Tornado

Tower
- Beat Flier           -> Claw

Castle
- Beat the final boss
```

### Order — settled

**Town, Forest, Tower.** Confirmed by the runner after the dumps showed it: the
forest-section dumps carry no Tornado or Claw, `flame-lord-dead` adds Tornado,
the tower sections follow, and `flier-dead` then adds Claw. An earlier verbal
description had Tower before Forest and was a miscommunication.

## Measured state blocks

Read directly from the route dumps rather than derived, so these are what the
game itself produces. Progress is as of *leaving* each milestone, which is the
state to preset when entering the stage after it.

| Milestone | Area | `$1E50`-`$1E58` | HP | Items |
|---|---|---|---|---|
| Somulo dead | 1 | `05 00 00 00 01 00 00 00 00` | 5 | 1 HP-up |
| Hippogriff dead | 2 | `06 00 00 00 03 00 00 00 00` | 6 | 2 HP-ups |
| Arma dead (Initial Stage done) | overworld | `06 10 00 00 03 00 00 00 00` | 6 | + Earth Crest |
| Belth dead (Town done) | overworld | `08 10 00 00 07 01 00 00 00` | 8 | + 2 HP-ups |
| Flame Lord dead (Forest done) | overworld | `08 12 00 00 07 01 00 00 00` | 8 | + Tornado |
| Flier dead (Tower done) | overworld | `08 16 00 00 07 01 00 00 00` | 8 | + Claw |

So the block to preset for each stage entry is the previous milestone's:

| Stage entered | Destination (`$1326`) | Area | Block to write |
|---|---|---|---|
| Stage 1, first visit | — (mid Initial Stage) | 1 | `05 00 00 00 01 00 00 00 00` |
| Town | 1 | 4 | `06 10 00 00 03 00 00 00 00` |
| Forest | 2 | 10 | `08 10 00 00 07 01 00 00 00` |
| Tower | 3 | 18 | `08 12 00 00 07 01 00 00 00` |
| Castle | 6 | **42**, not 37 — see below | `08 16 00 00 07 01 00 00 00` |

These supersede the blocks previously derived by hand. The hand-derived ones had
the right items but chose HP-up bits `$0F` where the game actually sets `$07` in
`$1E54` plus `$01` in `$1E55` — the same *count*, so functionally identical
under the `4 + popcount` rule, but no reason not to use the authentic values.

## Section areas, measured

| Stage | Sections (`$8D`/2) |
|-------|--------------------|
| Initial Stage | 1, 2 (and 0 for the Somulo arena, first visit only) |
| Town | 4, 5, 9 |
| Forest | 10, 12, 14 |
| Tower | 18, 19 |

Consistent with `docs/areas.md`: town is 4/5/9 = `S2 Town`, `S2_1`, `S2_2a`;
forest 10/12/14 = `S3_1`, `S3_2a`, `S3_3a`; tower 18/19 = `S4_1`, `S4_2`.
**Tower being area 18 confirms destination 3**, which was previously only
inferred from a screenshot.

## The castle is progress-gated, and the variant selector works

Entering destination 6 with the authentic Any% block produces **area 42**, not
the area 37 the destination table holds. The override at the load entry fired:

```
$85:B09D  JSL $859B39      ; progress -> tier in Y
$85:B0A1  CPY #$02
$85:B0A3  BNE $85:B0BA     ; normal table path -> area 37
$85:B0A5  LDY $26
$85:B0A7  CPY #$06         ; destination 6 only
$85:B0A9  BNE $85:B0BA
$85:B0B0  LDA #$54         ; area 42
```

| Progress | destination 6 gives |
|---|---|
| all items | area 37 — stained glass, ornate torches, castle interior |
| Any% route block | **area 42** — a lava cavern, loads cleanly, HP bar shows 8 |

**This is the first-visit-versus-revisit mechanism working, observed rather than
inferred.** `$85:9B39` returns tier 2 for route-level progress, and the game
picks a different area for the same destination. So for the castle the practice
ROM gets the right variant **for free** by writing the right progress block —
no hold-Select modifier and no mask-table decode needed. Whether that
generalises to other stages is untested; the override only checks destination 6.

**Settled: area 42 is the Any% castle.** Confirmed by the runner — the Any%
castle is a single dark room, which matches area 42's lava-cavern frame. Area 37,
the stained-glass interior, is a **later castle section that Any% never
reaches**; both are the castle, at different points in the game. So the route's
castle preset must produce area 42, which it does automatically: writing the
Any% block makes `$85:9B39` return tier 2 and the override redirects
destination 6.

Note the consequence for testing — entering destination 6 with an all-items
save, as every earlier warp test did, lands in a section the route never
visits. Route states have to be written before a destination is entered, or the
area itself comes out wrong.

## Two things the dumps did not settle

**`$7E:0EA6` is not a simple per-stage location.** Across the route it reads 0
for the Initial Stage and Town, 1 for the forest, 2 for the tower and 3 at the
castle — which looks like a boss or route counter. But the older all-items dumps
give 5 for the forest, 0 for town, 4 for ice and 1 for water, and the old and
new forest dumps are the *same areas* (10 and 12) with different values. So it
is neither area-determined nor a pure counter. It is written by `$80:BB09` from
whatever the exit routine is passed in `A`, so it is "the overworld location to
return to" — but what sets that value is unknown.

**`$1E58` stays `$00` for the entire route**, through all four bosses. Yet the
boss-rush password sets it to `$01`. So its bit 0 — the one the area-variant
selector `$85:9B39` reads — is not set by normal Any% progression at all, and
whatever it distinguishes does not occur on this route.

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

## Implementation plan

Two hooks, no stage-select menu. The player picks a stage by flying the
overworld as normal, and the practice ROM supplies the route state for whatever
they enter.

### 1. Boot: start on the overworld

Write a starting block with `$1E54` bit 0 set. The game's own gate at
`$84:C1EF` then sends a new game to the overworld instead of the Initial Stage.
Setting that single bit is the whole feature.

**Hook site found, and the block write works — but the bit alone is not
enough.** `src/asm/experiments/boot_overworld.asm` hooks it and is verified to
produce the intended state; a new game still starts in area 0.

The new-game progress init is `$84:88DE`, reached from a `JSL` stub at
`$84:8550`:

```
$84:88E2  STZ $008D      ; area 0, hardcoded
$84:88E8  STZ $1E51      ; ... through $1E57
$84:8906  LDA #$04       <- 5-byte hook slot
$84:8908  STA $1E50      ; max HP 4
$84:890F  (second init part, called separately from $84:856B)
$84:8919  RTS
```

Hooking `$84:8906` and writing the Town block gives exactly
`06 10 00 00 03 00 00 00 00`, max HP 6 with the Earth Crest — measured. But
`$8D` is still `$00`, so the game starts in the Somulo arena regardless.

**Why: a new game never reaches the `$84:C1EF` gate.** That gate is on the
*password* path only. Two different tests for "has the intro been finished"
exist:

| Path | Test | Effect |
|------|------|--------|
| password apply, `$84:C1EF` | `$1E54` bit 0 (Somulo HP-up) | overworld, else area 0 |
| `$84:8557` | `$1E51` bit 4 (**Earth Crest**) plus an area check | keeps you in the intro when absent |

and separately `$84:88E2` writes `$8D = 0` unconditionally. So skipping the
intro on a fresh start needs the dispatch changed too, not just progress.

**Options, none implemented:**

1. Find what dispatches a new game into area 0 and change the state it passes
   to `$80:829B` from `$04` to `$10`. Cleanest, but the site is not yet
   located — `$84:8570` looked like it and is gated on the Earth Crest, which
   the written block already satisfies, so it is not the one that ran.
2. Reuse the proven exit. Let the new game start in area 0 and have the level
   hook jump to `$80:BB07` once, bouncing straight out to the overworld.
   Uses only mechanisms already verified, at the cost of a frame or two in
   area 0.

### `$0EA6` is a table lookup

Answering the earlier open question: the second init part derives it from the
area.

```
$84:892C  LDA $008D      ; area x 2
$84:892F  LSR A
$84:8930  TAX
$84:8931  LDA $9B80,X    ; area -> overworld location
$84:8934  STA $0EA6
```

So `$0EA6` is `table[area]`, which is why it looked neither area-independent nor
like a counter — it is per-area, but only updated when this init runs.

### 2. Level entry: write the route block for the destination

Hook `$85:B097`, the first instruction of the load entry, and before the
original `LDA $1E50` runs: read the destination from `$26` (direct page,
`D = $1300`), look it up in a route table, and write that stage's nine bytes to
`$1E50`-`$1E58`.

Everything downstream then uses it, in the right order:

```
$85:B097  LDA $1E50      <- hook here, block already written
$85:B09A  STA $1062      ; max HP picked up from the new block
$85:B09D  JSL $859B39    ; tier computed from the new block
$85:B0A1  CPY #$02       ; so the castle override fires correctly
$85:B0A5  LDY $26        ; destination
$85:B0BC  LDA $E0F1,Y    ; area
```

This is why the hook must be at `$85:B097` and not later: the tier calculation
that redirects destination 6 to area 42 reads the progress block, so the block
has to be in place before `$85:B09D`.

`$26` is already valid at `$85:B097` — nothing between there and the `LDY $26`
at `$85:B0A5` writes it. That is static reasoning from the disassembly, not
measured, so it is the first thing a probe should confirm.

### Route table

Indexed by destination, not by route position:

| Destination | Stage | Block |
|---|---|---|
| 1 | Town | `06 10 00 00 03 00 00 00 00` |
| 2 | Forest | `08 10 00 00 07 01 00 00 00` |
| 3 | Tower | `08 12 00 00 07 01 00 00 00` |
| 6 | Castle | `08 16 00 00 07 01 00 00 00` |
| 0 | Stage 1 revisit | `05 00 00 00 01 00 00 00 00` |

Destinations the route does not use (4, 5, 7-12) need a policy: leave progress
untouched, or supply the final block so those stages are at least playable.

### Deferred to 100%

The hold-Select first-visit/revisit modifier, and with it the decode of the
mask tables `$85:8D61` and `$85:8D6B`. **Any% never revisits an area**, so
progress alone disambiguates every stage on this route — as the castle already
demonstrates, where writing the Any% block is what produces area 42 rather than
area 37.
