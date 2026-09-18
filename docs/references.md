# Reference practice ROMs

Practice hacks whose design this project borrows from. Each entry records what
it contributes and where its approach does *not* transfer, since both games
differ from Demon's Crest in ways that matter.

## `Myriachan/RockmanXPractice` — Rockman X1

The original architectural model for this project: a true ASM hack for real
hardware, with progress supplied as hardcoded RAM blocks rather than emulator
save states. Built with bass v10, whose macro syntax v18 rejects, which is why
this project uses asar instead.

## `Myriachan/RockmanX2Practice` — Rockman X2

The closer mirror of what this project wants, and worth reading in full before
designing features. `hack.asm`, `readme.txt` and `rmx2 ramstate.txt`.

### Feature set

| Feature | How |
|---------|-----|
| Route selection | The title screen asks which of three supported routes you are playing |
| Per-stage item presets | "When you choose a stage, you will have the weapons and items appropriate to where you would be in the route you selected" |
| Save / load state | Select+R saves, Select+L loads |
| Quick death | Select+Start |
| Exit anytime | The Exit option on the pause screen always works, on every level |
| Infinite lives | |
| Boss practice loop | In the Teleporter stage, killing a boss does not disable its teleporter |
| Final-stage access | Hold Select while choosing one of the top five stage icons |

### What transfers

**Per-stage state blocks behind a pointer table.** The route data is a set of
labelled blocks — `state_data_anypercent_stag3rd.intro`, `.sponge`, `.moth` and
so on — with a `dw` table indexed by stage ID selecting one, copied into the
game's live state at `$7E:1FA0` with `MVN`. One table per supported route. This
is exactly the shape the Demon's Crest route states need, with `$1E50`-`$1E58`
as the destination instead.

**A caution, from the version history.** "1.20 Added Total's saved state code"
followed by "1.21 Rewrote the saved state code to be much more stable". The save
state needed a stability rewrite in a hack that was otherwise mature, and it is
credited to different contributors than the rest. Treat a save state that works
once as unproven.

**Quick death by writing a state variable, not by jumping.** It checks
`current_play_state` (`$7E:00D2`) is the normal value, then writes the death
value to it and to `countdown_play_state` (`$7E:00D6`). A data write, so the
game's own state machine runs the death. This project's `death_probe.asm`
instead jumped into the middle of the death routine at `$80:E602` and blanked
the screen — the X2 approach is the right shape, and the Demon's Crest
equivalent is to find the play-state variable rather than a code entry point.

**Reusing the game's own exit.** Rather than adding an exit hotkey, X2 makes the
*existing* pause-screen Exit option always available. The same instinct as this
project's "make the game do the work" rule.

**Hold-Select as a modifier at stage selection.** X2 uses it for final-stage
access; the same idea is planned here for first-visit versus revisit.

**The route as plain text.** `rmx2 ramstate.txt` records the speedrun route as
an ordered stage list with the pickups in each, and the state for stage N is the
cumulative sum of everything collected before it. Worth copying as the source
format, because it is reviewable by a runner rather than by a programmer.

**Controller layout confirmation.** X2's controller bits — `$0010` R, `$0020`
L, `$0040` X, `$0080` A, `$0100`-`$0800` the d-pad, `$1000` Start, `$2000`
Select, `$4000` Y, `$8000` B — match what this project measured at
`$7E:0090`/`$0092`/`$0094`, in the same current/previous/new three-word shape.
Independent corroboration from a different game.

### What does not transfer

**The save state needs SRAM the cartridge does not have.** X2 copies all of
WRAM plus VRAM and CGRAM into a 512KB SRAM window (`$70:0000` onward), and
`hack.asm` changes the header's SRAM size to do it. Demon's Crest has **no
SRAM**, so the same feature here needs the same header change. That is a real
option — FXPak Pro honours the header — but it is a decision, not a detail, and
it interacts with the deferred 4MB expansion.

It also means the claim that hardware rules out save-state practice is **wrong
as stated**: X2 does exactly that on real hardware. What is true is that it
costs an SRAM header change and a large copy.

**X2's NMI and IRQ handlers live in RAM** (`$7E:1FEF` jumps to `$7E:2000`),
because of the Cx4 chip. Demon's Crest has no coprocessor and its NMI vector
points into ROM at `$80:8329`, so none of X2's vector handling applies.

**Addresses are per-game.** X2's `$7E:00D2`, `$7E:1FA0`, `$7E:1FAD` and so on
are X2's. Only the *patterns* carry over — unlike the WRAM sharing between the
USA and JP builds of Demon's Crest itself, where addresses do transfer.

## `FredYeye/Demon-s-Crest-Rando`

Same game, USA ROM. Authoritative area table, the progress bit mapping behind
`tools/state.py`, and USA code landmarks. Its author's separate
`various-game-disassembly` repo declares `!area = $8D`, which closed the
area-index target here.

## `abyssonym/demons_crest_hacking`

Same game, level data *structure*. Its addresses are USA file offsets; treat it
as a guide to format, not to addresses.
