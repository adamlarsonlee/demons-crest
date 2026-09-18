; Probe: does declaring SRAM in the ROM header make an emulator provide it?
;
; Demon's Crest has no SRAM. RockmanX2Practice's save state works by changing
; the header's SRAM size and copying WRAM, VRAM and CGRAM into it, so the same
; feature here needs the same change. This probe only flips the header byte and
; asks the core whether save RAM appeared.
;
; RESULT: the core honours the header value exactly up to $07 and clamps above
; it. Measured: $03 -> 8192, $05 -> 32768, $07 -> 131072, $08 and $09 -> 131072.
;
; That 128 KB ceiling is snes9x's, NOT the hardware's or the format's:
; snes9xgit/snes9x#714 records the cap and notes 256 KB works elsewhere, and
; RockmanX2Practice declares 512 KB while running on real hardware. So a larger
; window is possible - it just cannot be verified with this harness.
;
; Set to $07 as the largest value this emulator honours. 128 KB is exactly the
; size of WRAM, which is enough for the agreed same-section scope.
;
; Build  make rom ASM=src/asm/experiments/sram_probe.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

assert read1($00FFD8) == $00, "header already declares SRAM"

org $00FFD8
    db $08
