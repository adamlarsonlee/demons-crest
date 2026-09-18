; Probe: where does the emulator map SRAM into the CPU address space?
;
; savestate_vram.asm wrote to $70:0000 on the assumption of a standard LoROM
; SRAM window and nothing reached the SAVE_RAM the harness exposes. This writes
; a distinct marker to each candidate location so the landing spot can be found
; by searching SAVE_RAM.
;
; Build  make rom ASM=src/asm/experiments/sram_where.asm

incsrc "../../../build/rom_config.inc"
warnings disable Wfreespace_leaked

assert read1($00FFD6) == $00, "header already declares a chipset"
assert read1($00FFD8) == $00, "header already declares SRAM"
assert read1($80B8F5) == $A9, "hook site changed"

; The chipset byte must also say the cartridge has RAM. $00 is "ROM only", and
; an emulator that trusts it will not map an SRAM window however large the size
; byte claims. $02 is ROM + RAM + battery.
org $00FFD6
    db $02

org $00FFD8
    db $07

org $80B8F5
    JSL where_hook
    NOP

freecode
where_hook:
    LDA #$FF
    STA.l $7E0086               ; displaced instruction

    ; Markers, each 4 bytes so a search cannot match by chance.
    LDA #$A5 : STA.l $700000 : STA.l $700001 : STA.l $700002 : STA.l $700003
    LDA #$B5 : STA.l $708000 : STA.l $708001 : STA.l $708002 : STA.l $708003
    LDA #$C5 : STA.l $F00000 : STA.l $F00001 : STA.l $F00002 : STA.l $F00003
    LDA #$D5 : STA.l $306000 : STA.l $306001 : STA.l $306002 : STA.l $306003
    LDA #$E5 : STA.l $B06000 : STA.l $B06001 : STA.l $B06002 : STA.l $B06003
    LDA #$F5 : STA.l $710000 : STA.l $710001 : STA.l $710002 : STA.l $710003
    RTL
