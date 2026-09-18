; Probe: does declaring SRAM in the ROM header make an emulator provide it?
;
; Demon's Crest has no SRAM. RockmanX2Practice's save state works by changing
; the header's SRAM size and copying WRAM, VRAM and CGRAM into it, so the same
; feature here needs the same change. This probe only flips the header byte and
; asks the core whether save RAM appeared.
;
; RESULT: the core honours the header value exactly up to $07 and clamps above
; it. Measured: $03 -> 8192, $05 -> 32768, $07 -> 131072, $08 and $09 -> 131072.
; So 128 KB is the ceiling in this emulator, which is exactly the size of WRAM
; and leaves no room for VRAM alongside it. X2's approach - WRAM plus VRAM plus
; CGRAM in a 512 KB window - does not fit here.
;
; Set to $07 as the largest usable value.
;
; Build  make rom ASM=src/asm/experiments/sram_probe.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

assert read1($00FFD8) == $00, "header already declares SRAM"

org $00FFD8
    db $07
