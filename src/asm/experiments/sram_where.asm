; Probe: can the CPU write SRAM and read it back?
;
; This separates two things an earlier probe conflated: whether SRAM works
; inside the emulator, and whether the harness's SAVE_RAM view shows it. The
; ROM writes a marker, reads it straight back, and parks the result in WRAM at
; $7E:0087-$008A where a normal WRAM dump can see it.
;
; Build  make rom ASM=src/asm/experiments/sram_where.asm

incsrc "../../../build/rom_config.inc"
warnings disable Wfreespace_leaked

assert read1($00FFD6) == $00, "header already declares a chipset"
assert read1($00FFD8) == $00, "header already declares SRAM"
assert read1($80B8F5) == $A9, "hook site changed"

org $00FFD6
    db $02                      ; ROM + RAM + battery
org $00FFD8
    db $07                      ; 128 KB

org $80B8F5
    JSL where_hook
    NOP

freecode
where_hook:
    LDA #$FF
    STA.l $7E0086               ; displaced instruction

    ; $70:0000 - by the source this is SRAM offset 0
    LDA #$A5
    STA.l $700000
    LDA.l $700000
    STA.l $7E0087               ; expect $A5 if SRAM round-trips

    ; $71:0000 - should be SRAM offset $8000
    LDA #$5A
    STA.l $710000
    LDA.l $710000
    STA.l $7E0088               ; expect $5A

    ; $F0:0000 - the mirror map_LoROMSRAM also installs
    LDA #$3C
    STA.l $F00000
    LDA.l $F00000
    STA.l $7E0089               ; expect $3C

    ; control: the same round trip through known-good WRAM
    LDA #$C3
    STA.l $7FFF00
    LDA.l $7FFF00
    STA.l $7E008A               ; expect $C3
    RTL
