# Areas

`FredYeye/Demon-s-Crest-Rando` (Rust, targets the USA ROM) contains the
authoritative flat area table, which confirms that location is a single
level-section index rather than a level plus a separate section value. There are
**116 area slots**; the named ones are:

|Index|Area||Index|Area||Index|Area|
|----|----|-|----|----|-|----|----|
|0|Somulo arena||17|Somulo exit||29|S6_1|
|1|S1_1||18|S4_1||30|S6_2a (bottom path)|
|2|S1_2||19|S4_2||31|S6_2b (upper path)|
|3|S1_3||20|S4_3||32|S6 HP room|
|4|**S2 Town**||21|S4_4||33|S6_3b|
|5|S2_1||22|S4 Crown||34|S6_4b|
|6|S2_2b||23|S4_5||35|S6_5b|
|7|S2_3b||24|S5_1||36|S6_6b|
|8|S2 Ovnunu||25|S5_2b||38|S7_2|
|9|S2_2a (right path)||26|S5_3b (water path)||39|S7_3|
|10|S3_1||27|S5_2a (right path)||40|S7_4|
|11|S3_2b||28|S5 Crawler alcove||41|S7_5|
|12|S3_2a||50|S3_3a3||51|S3_3a2|
|13|S3_3b (cave, to Scula)||53|Trio the Pago 3||59|S5_2a2|
|14|S3_3a (right path)|||||||
|15|S3 HP cave|||||||
|16|S3 Skull cave|||||||

So the two areas measured here are **index 2 = S1_2** and **index 7 = S2_3b**.

## Area 0 versus area 1

Area 0 (`Somulo arena`) is reachable **only on the pre-overworld first visit**,
when `$1E54` bit 0 is clear. Entering through destination 0 from the overworld
gives **area 1** (`S1_1`) instead, which is a visibly different place — a swamp
with dead trees rather than area 0's purple stone hall. Measured; see
`docs/route-any.md`. The separate `17 Somulo exit` entry is consistent with the
Initial Stage being the Somulo fight plus an exit, distinct from the S1_1-S1_3
sections revisited later.

## Additions from the destination table

`$81:E0F1` (JP) is the 13-entry overworld destination table; see `docs/recon.md`.
It names one previously unnamed slot:

- **55 — the shop.** Reached as destination 9; identified from a screenshot of
  the warp (candles, shelves of items, a shopkeeper).

Destinations 6, 7, 8, 10 and 12 point at areas 37, 44, 49, 52 and 54, which are
also unnamed here and are each reachable in one command now.

## What this settles

- **WRAM addresses are shared between USA and JP.** The randomizer's ASM uses
  `lda $1E51,X` for item flags, which is the same address this project found
  independently on the JP ROM. Its WRAM knowledge therefore transfers directly,
  even though its ROM addresses do not.
- **abyssonym's notes are for the USA ROM.** His "AE11: Pointer to some kind of
  graphical info for objects in the level" is the randomizer's `sprite_base` of
  `$81:AE11`. This was previously inferred from his index-5 example failing to
  validate on the JP ROM; it is now confirmed from a second source.
- Its `snes_to_effective` is the same LoROM conversion used here.

## Per-area graphics tables

USA addresses, with the format taken from `Gfx::write_tile_list`:

|Table|USA address|
|-----|-----------|
|tile set|`$BD:9953`|
|sprite set|`$81:AE11`|
|mid stage|`$BD:9CFD`|

Each is **116 little-endian 16-bit pointers** — one per area — followed by the
deduplicated lists they point into. The first pointer therefore equals
`base + 232`.

On the JP ROM, `$81:ADDA` matches that signature exactly: its first pointer is
`$AEC2`, and `$ADDA + 232 = $AEC2`. It also sits `$37` from the USA
`$81:AE11`. That makes it very likely the JP sprite-set table, but it is **not
confirmed as area-indexed** — one observed read landed at `base+2` with `Y=2`
in area 2, and the second area produced no read in the sampled window.

`$81:C0EE`, found earlier by watchpoint, *is* confirmed area-indexed (read with
`X = area x 2`, entry 2 for S1_2 and entry 7 for S2_3b), and is a separate
table the randomizer does not touch.

## Progress bits

`Item::completion_data()` yields the full progress-block bit mapping, with
offsets relative to `$1E51`. Because WRAM is shared between regions this applies
directly to the JP ROM, and it has been checked against password-loaded saves
here. The table lives in `memory-map/README.md`, along with three resulting
corrections to `src/lua/items/items.lua`.

## Other useful details

- The randomizer identifies its expected USA ROM by CRC32 `0xC47D3B82`.
- It claims free space at `$BF:D500` onward for injected code, which is a hint
  about where spare room exists in the USA ROM.
- Known code addresses (USA): `$82:EAC8` exit stage, `$80:BB58` exit area,
  `$80:9A5A` update item total, `$85:A1EE` stage reveal requirements.
