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
|001E44 |1|Unsigned|Probably a progress checksum|Differs between saves whose $1E50-$1E57 are identical, so it depends on later bytes. Purpose unverified
|001054 |Unsure|Binary?|Selected form|0 is Firebrand and the first bit is crazy (I dare you to set it to 1), but not I'm not sure exactly how this works yet and there are more addresses required to load in graphics


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
