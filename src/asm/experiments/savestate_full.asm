; Save state covering all of WRAM, all of VRAM and CGRAM.
;
; Supersedes savestate_vram.asm, which saved only the two WRAM halves measured
; as dynamic. That selective design existed to fit a 128 KB budget that turned
; out not to exist: snes9x's SRAM_SIZE is 0x80000 and it accepts header sizes up
; to $09, so 512 KB is available. The 128 KB figure was the libretro *size
; report*, not the emulator's limit.
;
; Saving everything removes the selective reasoning entirely, and with it the
; possibility that the striping savestate_vram.asm produced after scrolling was
; something excluded from the copy.
;
; SRAM layout. The LoROM SRAM offset is
;   (((Address & 0xff0000) >> 1) | (Address & 0x7fff)) & SRAMMask
; so with SRAMMask = $7FFFF each bank from $70 up owns a distinct 32 KB window:
;
;   WRAM $7E:0000-$7FFF  <->  $70    SRAM offset $00000
;   WRAM $7E:8000-$FFFF  <->  $71                $08000
;   WRAM $7F:0000-$7FFF  <->  $72                $10000
;   WRAM $7F:8000-$FFFF  <->  $73                $18000
;   VRAM $0000-$7FFF     <->  $74                $20000
;   VRAM $8000-$FFFF     <->  $75                $28000
;   CGRAM (512 bytes)    <->  $76                $30000
;                                        = 192.5 KB of 512 KB
;
; Hotkeys: Select+R saves, Select+L loads.
;
; Header. Both bytes are needed: the size byte alone is not enough, because
; $00:FFD6 saying "ROM only" is what stopped an earlier attempt from reaching
; SRAM through the libretro memory view.
;
; Cost. Roughly 2 million cycles, about 0.55s, with the screen blanked for the
; duration. WRAM moves by MVN; VRAM and CGRAM have to go through the PPU a byte
; at a time, which is the slow part.
;
; Note on PHB: it is in the callers, never before an RTS inside a subroutine.
; An earlier version had that bug and froze the game - the same hazard
; CLAUDE.md records for the $80:821E hook.
;
; Build  make rom ASM=src/asm/experiments/savestate_full.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

!pad_held_hi = $7E0091          ; high byte of $0090; Select is bit 5
!pad_new_lo  = $7E0094          ; low byte of $0094; R is bit 4, L is bit 5
!loop_flag   = $7E0086

!inidisp     = $002100
!vmain       = $002115
!vmaddl      = $002116
!vmdatalr    = $002139
!vmdatahr    = $00213A
!vmdatalw    = $002118
!vmdatahw    = $002119
!cgadd       = $002121
!cgdataw     = $002122
!cgdatar     = $00213B
!nmitimen    = $004200

assert read1($00FFD6) == $00, "header already declares a chipset"
assert read1($00FFD8) == $00, "header already declares SRAM"
assert read1($80B8F5) == $A9, "hook site changed: expected LDA #$FF at $80:B8F5"

org $00FFD6
    db $02                      ; ROM + RAM + battery
org $00FFD8
    db $09                      ; 512 KB, the largest snes9x accepts

org $80B8F5
    JSL state_hook
    NOP

freecode
state_hook:
    LDA #$FF
    STA.l !loop_flag            ; displaced instruction

    LDA.l !pad_held_hi
    AND #$20                    ; Select held?
    BEQ .done
    LDA.l !pad_new_lo
    AND #$10                    ; R newly pressed?
    BNE .save
    LDA.l !pad_new_lo
    AND #$20                    ; L newly pressed?
    BNE .load
.done:
    RTL

; ---------------------------------------------------------------------------
.save:
    PHB
    JSR prologue
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $70,$7E
    LDX #$8000 : LDY #$0000 : LDA #$7FFF : MVN $71,$7E
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $72,$7F
    LDX #$8000 : LDY #$0000 : LDA #$7FFF : MVN $73,$7F
    SEP #$30
    JSR vram_to_sram
    JSR cgram_to_sram
    ; Instrumentation: read back the first bytes the VRAM copy wrote, so a
    ; failed VRAM *read* can be told apart from a failed VRAM *write*.
    LDA.l $740000 : STA.l $7E00A0
    LDA.l $740001 : STA.l $7E00A1
    LDA.l $740002 : STA.l $7E00A2
    JSR epilogue
    PLB
    RTL

; ---------------------------------------------------------------------------
.load:
    PHB
    JSR prologue
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $7E,$70
    LDX #$0000 : LDY #$8000 : LDA #$7FFF : MVN $7E,$71
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $7F,$72
    LDX #$0000 : LDY #$8000 : LDA #$7FFF : MVN $7F,$73
    SEP #$30
    JSR sram_to_vram
    JSR sram_to_cgram
    JSR epilogue
    PLB
    RTL

; ---------------------------------------------------------------------------
; NMI off for the whole copy, because MVN is interruptible and an NMI landing
; on a half-restored stack would push onto corrupt memory. Forced blank so VRAM
; and CGRAM are accessible outside vblank. Neither $4200 nor $2100 can be read
; back, so they are restored to $B1 and $0F, the values the game itself writes.
; ---------------------------------------------------------------------------
prologue:
    SEP #$20
    LDA #$00
    STA.l !nmitimen
    LDA #$8F
    STA.l !inidisp
    RTS

epilogue:
    SEP #$30
    LDA #$0F
    STA.l !inidisp
    LDA #$B1
    STA.l !nmitimen
    RTS

; ---------------------------------------------------------------------------
; VRAM and CGRAM, by DMA, following RockmanX2Practice's recipe in hack.asm.
;
; A hand-written PPU loop was tried first and failed in both directions. Three
; mistakes, all visible in X2's table:
;   * VMAIN ($2115) must be $00 - increment after the LOW byte. $80 was used.
;   * VMADD ($2116) takes a WORD address, so the second half is $4000, not
;     $8000.
;   * A dummy read of $2139 after setting VMADD is required, not optional.
;
; DMA channel 1 is used, as X2 does. The game is not running DMA of its own here
; because NMI is off and the screen is in forced blank.
;
; Register packing: a 16-bit store to $4312 sets A1T low and high; to $4314 sets
; the A bank and DAS low; to $4315 sets DAS low and high. DAS $8000 is 32768
; bytes, the size of one SRAM bank window.
; ---------------------------------------------------------------------------
vram_to_sram:
    SEP #$30
    LDA #$00 : STA.l !vmain         ; increment after the low byte, step 1 word
    LDA #$81 : STA.l $004310        ; DMAP: B->A, word, two registers
    LDA #$39 : STA.l $004311        ; BBAD = $2139, VRAM read

    REP #$20 : LDA #$0000 : STA.l !vmaddl : SEP #$20
    LDA.l !vmdatalr                 ; required dummy read
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$74 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B        ; run channel 1

    REP #$20 : LDA #$4000 : STA.l !vmaddl : SEP #$20
    LDA.l !vmdatalr
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$75 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS

sram_to_vram:
    SEP #$30
    LDA #$00 : STA.l !vmain
    LDA #$01 : STA.l $004310        ; DMAP: A->B, word, two registers
    LDA #$18 : STA.l $004311        ; BBAD = $2118, VRAM write

    REP #$20 : LDA #$0000 : STA.l !vmaddl : SEP #$20
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$74 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B

    REP #$20 : LDA #$4000 : STA.l !vmaddl : SEP #$20
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$75 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS

cgram_to_sram:
    SEP #$30
    LDA #$00 : STA.l !cgadd
    LDA #$80 : STA.l $004310        ; DMAP: B->A, byte, one register
    LDA #$3B : STA.l $004311        ; BBAD = $213B, CGRAM read
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$76 : STA.l $004314
    REP #$20 : LDA #$0200 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS

sram_to_cgram:
    SEP #$30
    LDA #$00 : STA.l !cgadd
    LDA #$00 : STA.l $004310        ; DMAP: A->B, byte, one register
    LDA #$22 : STA.l $004311        ; BBAD = $2122, CGRAM write
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$76 : STA.l $004314
    REP #$20 : LDA #$0200 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS
