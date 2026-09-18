# ROM changes

Every modification the practice ROM makes to the original, in plain language:
where it goes, what the original bytes were, what replaces them, and why that
site. This is the document to read before changing a hook, and to check a patch
against when something misbehaves on hardware.

Conventions used throughout:

- **Hooks are made at a slot of complete instructions**, never mid-instruction,
  and the displaced instructions are reproduced inside the injected routine.
- **`asar` places injected code with `freecode`**, so its address is not fixed.
  It has landed in bank `$90` so far. Nothing depends on where it lands.
- **Every hook asserts its site's first bytes at build time.** A shifted hook
  would corrupt a loop rather than fail, so the build refuses instead.
- **Injected code enters the game's own routines at the start of a sequence**,
  not partway down it. See "Why entry points matter" at the end.

## Status

| Change | File | State |
|--------|------|-------|
| Boot to the overworld with route progress | `patch.asm` | **works** |
| Exit a stage to the overworld on a hotkey | `patch.asm` | **works**, validated on hardware |
| Per-stage route presets on entry | `patch.asm` | **works** |
| Save / load state within a section | `savestate_probe.asm` | **works**, not yet in `patch.asm` |
| Kill Firebrand on a hotkey | `death_probe.asm` | **fails**, kept as a negative result |
| Exit from the intro stage | `boot_exit_combo.asm` | **fails**, kept as a negative result |

All three working changes are in `src/asm/patch.asm`, so plain `make rom`
builds the practice ROM. The two failures stay in `src/asm/experiments/` as
recorded negative results.

Verified on the combined build: a new game reaches the overworld with
`06 10 00 00 03 00 00 00 00`; entering destination 2 gives area 10 with the
Forest block; entering destination 6 gives **area 42** with the Castle block,
from an all-items save, which is the ordering constraint working; and
Select+Start in area 1 reaches the overworld. The diff against the original is
200 bytes across four hook sites plus injected code and the checksum.

---

## 1. Boot to the overworld — `patch.asm`

**What the player sees.** Starting a new game goes straight to the overworld
map with the Initial Stage already beaten: max HP 6, the Earth Crest, two HP
upgrades, and stage markers I to IV available. No Somulo fight.

**Where.** `$84:8906`, inside the new-game progress init routine `$84:88DE`.

**Original five bytes.**

```
$84:8906  A9 04         LDA #$04
$84:8908  8D 50 1E      STA $1E50     ; max HP 4
```

**Replaced with** a `JSL` to injected code plus a `NOP`.

**What the injected code does.** Copies a nine-byte progress block over
`$1E50`-`$1E58`, then jumps to `$84:C18F`.

**The block is the route's FINAL state, not its opening one** —
`08 16 00 00 07 01 00 00 00`, taken from the `overworld-castle` route dump. The
overworld only offers a stage once the progress to reach it exists, and the
castle specifically stays hidden until Flier is dead. Booting with the final
block makes every route stage selectable. The player never actually plays with
that generous state, because the preset hook (change 3) writes the correct
per-stage progress when a stage is entered.

Measured: switching the boot block from the Town state to the final state
changes the overworld map in 356 of 172,256 pixel bytes, confined to rows
94-105 — one new marker appearing rather than a redraw.

**Why.** The original two instructions set a fresh game's max HP to 4; the
block we write includes `$1E50`, so it subsumes them. The seven `STZ`
instructions just above the slot have already cleared `$1E51`-`$1E57`, which is
harmless because the block overwrites all nine bytes.

`$84:C18F` is the **password path's setup phase**. The game already knows how to
put a player on the overworld with arbitrary progress — that is what entering a
password does — so instead of inventing a transition, the hook supplies the
block and lets that path run. The password path's tail tests `$1E54` bit 0 at
`$84:C1EF` and dispatches to the overworld when it is set; bit 0 is the Somulo
HP upgrade, so it means "the Initial Stage is finished".

Only the password *decoder* above `$84:C18F` is skipped: it would write `$1E50`
from the decoded password and `$1E58` from `$15`, both of which we supply. HP is
re-derived from the block at `$84:C1BB`, and `$1061`/`$1062` are cleared by the
`$1000`-`$107F` loop at `$84:C1B3`, so nothing needed is missed.

**Stack.** The hook jumps out of a routine reached by `JSR` from a `JSL` stub,
stranding return addresses. Harmless: the path ends in `JML $80:829B`, which
resets the stack pointer from `$0034,Y`.

---

## 2. Exit a stage to the overworld — `patch.asm`

**What the player sees.** Holding Select and pressing Start during gameplay
leaves the current stage for the overworld, with no death, no animation, no HP
loss and no menu. The crest/vellum screen does not also open.

**Where.** `$80:B8F5`, inside the level gameplay loop `$80:B843`-`$80:B905`.

**Original five bytes.**

```
$80:B8F5  A9 FF         LDA #$FF
$80:B8F7  8D 86 00      STA $0086
```

**Replaced with** a `JSL` to injected code plus a `NOP`.

**What the injected code does.**

1. Reproduces `LDA #$FF` / `STA $0086` unconditionally, so the loop is
   unaffected when the hotkey is not pressed.
2. Tests Start newly pressed (`$0095` bit 4) and Select held (`$0091` bit 5).
   Both are high bytes of the game's own 16-bit pad words, so the tests are
   8-bit and the loop's register widths are left alone. The game computes edge
   detection itself at `$0094`, so the hook does not.
3. Clears Start from `$0094` so the pause handler does not also see it.
4. Restores the route's final progress block over `$1E50`-`$1E58`.
5. Discards its own `JSL` return address and jumps to `$80:BB07`, passing
   `$0EA6` in `A`.

**Why step 4 matters.** Without it the player arrives on the overworld carrying
whatever the preset hook wrote for the stage they just left, and the map only
offers the stages reachable at that progress — so one visit to Town would make
the castle, Forest and Tower disappear. Restoring the final block closes the
loop: boot offers everything, entering a stage presets that stage, exiting
offers everything again. Progress earned inside a stage is discarded, which is
what a practice ROM wants.

Verified: in Town the block is `06 10 00 00 03 00 00 00 00` at max HP 6; after
Select+Start it is `08 16 00 00 07 01 00 00 00` at max HP 8, on the overworld.

**Why this site.** The hotkey needs a per-frame site in *task* context. The NMI
hook cannot serve: the exit never returns, while NMI must end in `RTI`, so
jumping out of an interrupt would abandon the NMI frame. `$80:B8F5` was found
by watching writes to the frame counter `$0073` and tallying the program
counter — 320 writes came from `$80:B8FA` in this loop.

**Why `$80:BB07` and not `$80:BB30`.** `$80:BB07` is the exit routine's real
entry. It takes a 0-15 overworld return location in `A`, stores it to `$0EA6`,
and then makes three calls that entering at `$80:BB30` would skip. Passing back
the value already in `$0EA6` is idempotent.

**Known limitation.** The exit leaves the player at the map origin rather than
above the stage they left, because the overworld setup clears the 30-byte
position block at `$1DFA`-`$1E17` and nothing restores it. Investigated and
parked; see `route-any.md`.

---

## 3. Per-stage route presets — `patch.asm`

**What the player sees.** Entering any stage from the overworld gives the
progress a runner would have at that point in the route. No stage-select menu:
the player picks a stage by flying to it.

**Where.** `$85:B097`, the first instruction of the level-load entry. Six bytes
of `LDA $1E50 / STA $1062` replaced by a `JSL` plus two `NOP`s.

**What the injected code does.** Reads the destination from `$1326`, and if it
is 0-6 and has a route entry, copies that stage's nine-byte block over
`$1E50`-`$1E58`. Then reproduces the displaced `LDA $1E50 / STA $1062`, which
now picks up whatever block is in place. Destinations without a route entry
(4 and 5) are left untouched, so stages the route never visits keep the
player's own progress.

One implementation note: the copy needs two independent indices, one into the
table and one into the block, and the 65816 has no `STA long,Y`. So it sets
`DB` to `$7E` and uses `absolute,Y` for the stores, restoring `DB` afterwards.

**Why that exact instruction.** The order downstream matters:

```
$85:B097  LDA $1E50      <- hook here
$85:B09A  STA $1062      ; max HP taken from the block
$85:B09D  JSL $859B39    ; progress tier computed from the block
$85:B0A1  CPY #$02       ; tier 2 + destination 6 redirects the castle
$85:B0A5  LDY $26        ; destination
$85:B0BC  LDA $E0F1,Y    ; area
```

Writing the block any later means `$85:B09D` computes the tier from stale
progress, and the castle resolves to area 37 — a section Any% never reaches —
instead of area 42.

---

## 4. Save / load state — `savestate_probe.asm`

**What the player sees.** Select+R saves, Select+L loads, matching
`RockmanX2Practice`. Roughly a quarter-second freeze on each, which is the copy.

**Scope.** Same section only, agreed up front. The state is not meant to survive
a move to a different area.

**Header change.** `$00:FFD8`, the SRAM size byte, `$00` to `$07`. Demon's Crest
shipped with no SRAM. `$07` is 128 KB and is the largest the emulator honours —
`$08` and `$09` both clamp to 128 KB, measured in `sram_probe.asm`.

**Where.** `$80:B8F5`, the same level-loop slot the exit hook uses.

**What the injected code does.** On Select+R or Select+L, copies WRAM to or
from SRAM in four 32 KB `MVN` blocks, since LoROM maps SRAM as 32 KB windows at
banks `$70`-`$7D`:

```
$7E:0000-$7FFF  <->  $70:0000-$7FFF
$7E:8000-$FFFF  <->  $71:0000-$7FFF
$7F:0000-$7FFF  <->  $72:0000-$7FFF
$7F:8000-$FFFF  <->  $73:0000-$7FFF
```

**Why WRAM only, no VRAM.** 128 KB is exactly WRAM's size, so there is no room
for VRAM beside it. That is affordable only because of the agreed scope:
restoring within the same section means VRAM already holds the right graphics.

X2 does save VRAM and CGRAM as well, in a 512 KB window. **Why it does is not
documented** — its readme says only "Press Select+R to save your current state.
Press Select+L to load it", with no stated limitation. It may need them for
restores that cross areas, or it may simply save everything as the safe option.
Do not treat "X2 needed VRAM" as established.

**Why the stack survives.** Restoring WRAM overwrites the stack in use. That is
safe only because save and load happen at the *same hook site* — `SP` and our
own return address are identical both times, so the bytes written over the
stack are the bytes already there.

X2 instead keeps a separate `sram_saved_sp`, which is solid evidence that its
load can happen at a different point in the program than its save. That
difference is real, unlike the VRAM question above: a saved `SP` has no purpose
unless the site can differ.

**Why NMI is masked.** `MVN` is interruptible between iterations, and an NMI
firing while the stack is half-restored would push onto corrupt memory. `$4200`
is set to `$00` for the copy and restored to `$B1`, the value the game itself
writes at `$80:B7BA`. It cannot be read back and restored, because `$4200` is
write-only and there is nowhere in WRAM to stash it — WRAM is what is being
overwritten.

**WRAM-only is not safe if the player scrolls.** Measured: VRAM changes
*within* a section, monotonically as the camera moves — 930 bytes different
after 110 frames of moving right, 2,405 after 410, 2,665 after 550, out of
65,536. That is tile streaming. So saving WRAM and restoring after scrolling
leaves the restored state against the wrong tiles. The probe below is only
sound if the player does not move between save and load, which is a fragile
thing to rely on.

**A selective save state looks feasible but its region set is not
established.** Only about 1.5% of WRAM goes dirty during play, in a few 8KB
regions, and `$7E:4000`-`$FFFF` — the level buffers loaded at section entry —
appears static:

| Region | Dirty after scrolling | Dirty after varied play |
|--------|----------------------|-------------------------|
| `$7E:0000`-`$1FFF` | 689 | 985 |
| `$7E:2000`-`$3FFF` | — | 36 |
| `$7F:A000`-`$BFFF` | 756 | 739 |
| `$7F:E000`-`$FFFF` | 232 | 230 |

The problem is the second column: `$7E:2000`-`$3FFF` only appeared once the
test pressed more buttons. **Each test so far has found another region**, so
the set cannot be trusted yet, and a missed region means silent corruption
rather than a visible failure. Saving ~32KB of WRAM plus all 64KB of VRAM
would be 96KB and fit inside snes9x's 128KB, but only on the assumption that
the region list is complete.

**Measured.** Save in area 1, move right for 170 frames, load. Zero page is
byte-identical to the save immediately afterwards; whole-WRAM divergence bottoms
at 178 bytes of 131,072 (0.14%) at a matched sampling offset, the residual being
the game continuing to run. The frame afterwards is ordinary gameplay with
Firebrand back at his saved position.

**Not in `patch.asm` yet** — it shares the `$80:B8F5` slot with the exit hook,
so the two need merging into one handler.

**Caution from X2's history.** Its version log reads "1.20 Added Total's saved
state code" then "1.21 Rewrote the saved state code to be much more stable".
The save state was the feature that gave a more experienced hack trouble, and
it was credited to different people than the rest of the hack. Ours passes its
first test, which is not the same as being stable.

---

## 5. Recorded failures

Both are kept in `src/asm/experiments/` rather than deleted, because the reason
each failed is worth not rediscovering.

### `death_probe.asm` — jumping to the death entry

Hooked `$80:B8F5`, set `D = $1000` and jumped to `$80:E602`, the game's death
entry. The jump itself worked — a watchpoint caught `$80:E606` running with
`D=1000` and zeroing HP — but the screen blanked within 20 frames.

`$80:E602` sits *past* the player-state setup the damage handler performs
between `$80:E578` and `$80:E5C6`, which touches `$0B`, `$0A`, `$4B`, `$4A`,
`$78`, `$49`, `$3C` and `$6B`. Entering there skips all of it. `RockmanX2Practice`
kills its player by writing a play-state variable instead, which is the right
shape; the Demon's Crest equivalent has not been found.

### `boot_exit_combo.asm` — exiting from the intro stage

Tried to let a new game start in area 0 and have the player exit. The boot half
worked; the exit never fired at any of three sites. `$80:B8F5` does not run in
area 0 at all. `$80:A8EE` never executed either, proven with a marker. `$80:A90B`
does execute but the hotkey branch was never taken, with an edge test or a held
test. Area 0's loop is not understood; superseded by change 1, which avoids the
intro entirely.

---

## Why entry points matter

Three of the changes above turn on the same lesson, learned by getting it wrong
twice:

**Enter the game's own sequence at its start, not at the furthest point down
it.** `$80:BB30` looked like the stage exit and is 0x29 bytes into the routine;
`$80:E602` looked like the death routine and is past its setup. Entering
`$80:BB07` works and entering `$80:E602` does not, for the same reason. The
smallest hook is usually the wrong one.

The corollary for recon: when a routine looks like the right target, find what
*calls* it before hooking it.
