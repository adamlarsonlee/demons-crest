# Memory Map

The goal of thie project is to map as many memory locations as we can.

THIS MEMORY MAP IS FOR THE JAPANESE VERSION - THE ENGLISH ROM HAS DIFFERENT MAPPINGS

|Address|Bytes|Display|Maps|Notes|
|-------|-----|-------|----|-----|
|0000C0 |1|Unsigned|Viewport Something ?
|001062 |1|Unsigned|Current HP
|001031 |2|Unsigned|Horizontal Position (Coarse)
|001034 |2|Unsigned|Vertical Position (Coarse)
|001063 |2|Unsigned|Zam
|001E30 |1|Unsigned|Scroll 1 Contents|
|001E31 |1|Unsigned|Scroll 2 Contents|
|001E32 |1|Unsigned|Scroll 3 Contents|
|001E33 |1|Unsigned|Scroll 4 Contents|
|001E34 |1|Unsigned|Scroll 5 Contents|
|001E35 |1|Unsigned|Phial 1 Contents|
|001E36 |1|Unsigned|Phial 2 Contents|
|001E37 |1|Unsigned|Phial 3 Contents|
|001E38 |1|Unsigned|Phial 4 Contents|
|001E39 |1|Unsigned|Phial 5 Contents|
|001E50 |1|Unsigned|Max HP
|001E51	|1|Binary|Fire/Blazon Power (Not Ultimate)|Each bit is mapped to the next power sequence (0000 0001 is Buster, 1000 0000 is Legenday, etc.)
|001E52	|1|Binary|Ultimate - Jar 2|Again, bits are mapped to menu selections (0000 0001 is Ultimate, 1000 0000 is jar 2)
|001E53	|1|Binary|Jar 3 - Talismans|Same story
|001E54	|2|Binary|Max HP+|Each bit is mapped to a specific max health increase pickup, not sure yet which bits map to which drop but 0000 0000 0000 0001 is Somulo, obviously
|001E56	|1|Binary|Progress flags (boss/stage)|Not previously mapped. Found by diffing password-loaded saves; goes 81 -> FF as the game is completed
|001E57	|1|Binary|Progress flags, continued|Only the low two bits are used
|001E44 |1|Unsigned|Derived from progress; do not write|Stable during play but recomputed by the game on level load. Differs between saves whose $1E50-$1E57 are identical, so it depends on more than that block. A state block does not need to supply it. Exact meaning still unidentified
|001054 |Unsure|Binary?|Selected form|0 is Firebrand and the first bit is crazy (I dare you to set it to 1), but not I'm not sure exactly how this works yet and there are more addresses required to load in graphics


# Progress Block Bit Mapping

Complete mapping, cross-checked two ways: taken from `Item::completion_data()`
in `FredYeye/Demon-s-Crest-Rando` (whose offsets are relative to `$1E51`, per
`mod.rs` writing `completion_data().0 + 0x51`), and verified against WRAM dumps
from password-loaded saves on this JP ROM.

|Address|Bit|Contents|
|-------|---|--------|
|`$1E51`|0-3|Buster, Tornado, Claw, Demon Fire|
|`$1E51`|4-7|Earth Crest, Air Crest, Water Crest, Time Crest|
|`$1E52`|0|Ultimate / Infinity crest (the randomizer tests it as `$1E51` bit 8)|
|`$1E53`|3-7|Talismans: Crown, Skull, Armor, Fang, Hand|
|`$1E54`|0-7|HP upgrades 1-8|
|`$1E55`|0-7|HP upgrades 9-16|
|`$1E56`|0-4|**Vellums 1-5**|
|`$1E56`|5-7|Potions 1-3|
|`$1E57`|0-1|Potions 4-5|

The all-items password gives `$1E56 = FF` and `$1E57 = 03`, which is exactly the
set of bits this mapping defines — nothing above `$1E57` bit 1 is used. That is
why `$1E57` only ever showed its low two bits set.

`$85:A1EE` (USA) is the stage-reveal requirement function; it gates Phalanx on
`lda $1E56 : and #$001F : cmp #$001F`, i.e. all five vellums.

## Two representations, and what items.lua actually reads

There are two places this data lives, which resolves an apparent contradiction.

**Source flags**, set when an item is collected:

- `$1E56` bits 0-4 vellums, bits 5-7 potions 1-3
- `$1E57` bits 0-1 potions 4-5

**A derived mirror**, recomputed by `$82:E11F`-`$82:E148` on the JP ROM:

```
LDA $1E56 : AND #$001F          ; vellum bits
JSR $E17A                       ; spread 5 flags, mask starting at $0002 = bit 1
LDA #$0040 : STA $0002          ; potion mask starts at bit 6
LDA $1E56 : AND #$03E0          ; potion bits ($1E56 5-7 + $1E57 0-1)
LSR A x5 : JSR $E17A
LDA #$07FE : TRB $1E52          ; clear bits 1-10
LDA $0000  : TSB $1E52          ; write the spread result
```

So the mirror occupies the 16-bit field at `$1E52`:

|Address|Bit|Contents (derived)|
|-------|---|------------------|
|`$1E52`|1-5|Vellums 1-5|
|`$1E52`|6-7|Potions 1-2|
|`$1E53`|0-2|Potions 3-5|

`src/lua/items/items.lua` reads this mirror, which is legitimate — the game
maintains it. Its vellum and urn entries are **correct**.

The one genuine error is the talismans: `items.lua` places Crown and Skull at
`$1E52` bits 3-4, where they collide with derived Vellum 3 and Vellum 4. Per
`Item::completion_data()` they belong at `$1E53` bits 3-4. Armor, Fang and Hand
(`$1E53` bits 5-7) are already right.

# Progress Block

`$7E:1E50`-`$7E:1E57` is a contiguous 8-byte block holding max HP plus 56
progress bits. Confirmed by loading six different passwords and diffing WRAM
in a matched context (all loaded to the overworld, so location state cancels):

|State|$1E50|$1E51|$1E52|$1E53|$1E54|$1E55|$1E56|$1E57|set bits in $1E51-$1E57|
|-----|-----|-----|-----|-----|-----|-----|-----|-----|----|
|boss rush|04|00|00|00|00|00|00|00|0|
|level 2|06|10|42|00|03|00|81|00|7|
|level 3|07|10|02|00|07|00|01|00|6|
|level 5|0D|77|DE|19|5F|23|AF|01|31|
|all items|14|FF|FF|FF|FF|FF|FF|03|50|
|super|14|FF|FF|FF|FF|FF|FF|03|50|

Max HP rises monotonically with progression. The "level N" passwords are not a
strict superset chain, so their bit counts are not strictly ordered.

This block being contiguous is what makes hardcoded state blocks viable for the
practice ROM, in the same way RockmanXPractice uses one 48-byte region.

Data from `$1E58` to roughly `$1E70` also varies between saves but has not been
identified, and may be incidental rather than progress.

Writing this block is sufficient on its own. Poking the eight bytes from an
all-items save into a level-2 save produces an in-level item menu that is
**pixel-identical** to the genuine all-items save, and the game recomputes
`$1E44` by itself. Nothing rejected or corrupted the written state.

# Scroll and Phial Contents

Scroll and Phials use the same value set to determine what they do. That means you can store a potion on a Scroll and a spell on a Phial. Once you store a value beyond the valid range of contents available in stores, weird behaviour happens. It seems like the game only responds to even numbers.


|Value|Contents|Effect|
|-----|--------|------|
|0|Unknown|Unknown|
|2|Hold|Casts Hold|
|4|Death|Casts Death|
|6|Shock|Casts Shock|
|8|Imp|Casts Imp|
|10|Shadow|Casts Shadow|
|12|Herb|Consumes Herb|
|14|Elixir|Consumes Elixir|
|16|Mercury|Consumes Mercury|
|18|Sulfur|Consumes Sulfur|
|20|Ginsing|Consumes Ginsing|
|22|Skull|Deals four points of damage|
|24|Next Talisman|Unknown|
|26|Next Talisman|Spawns moving Firebrand platform|
|28|Next Talisman|Unknown|
|30|Next Talisman|Unknown|


At some point it seems like it just gives standard health drops (254 and down to an unkown value). Some values (64) don't seem to do anything but break the game if you pause and unpause. Others will show scambled sprites after unpausing. Some values show test in the identity box even though they're outside the valid range.

40 is absurd - shows MUTEK 1 MODE OFF! TEST MODE.

44 is where identity text starts getting weird.
