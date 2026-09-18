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
; VRAM, 32768 words, split across two SRAM banks because the window is 32 KB.
; VMAIN $80 increments after the high byte, so the access order is low then
; high and no dummy read is needed.
; ---------------------------------------------------------------------------
vram_to_sram:
    SEP #$20
    LDA #$80
    STA.l !vmain
    ; Prime the read prefetch. A read of $2139/$213A returns the prefetch
    ; register, which is only loaded when VMADD is written or incremented, so
    ; reading straight after setting VMADD=0 yields stale data - measured: the
    ; first bytes came back $07 $09 where VRAM held $00 $00. Setting VMADD to
    ; $FFFF and discarding one word wraps the address to 0 with VRAM[0]
    ; prefetched, so the loop starts correctly aligned.
    REP #$30
    LDA #$FFFF
    STA.l !vmaddl
    SEP #$20
    LDA.l !vmdatalr             ; discard
    LDA.l !vmdatahr             ; discard; wraps VMADD to $0000
    REP #$10

    LDX #$0000
.first:
    LDA.l !vmdatalr : STA.l $740000,X
    LDA.l !vmdatahr : STA.l $740001,X
    INX : INX
    CPX #$8000
    BNE .first

    LDX #$0000
.second:
    LDA.l !vmdatalr : STA.l $750000,X
    LDA.l !vmdatahr : STA.l $750001,X
    INX : INX
    CPX #$8000
    BNE .second
    RTS

sram_to_vram:
    SEP #$20
    LDA #$80
    STA.l !vmain
    REP #$30
    LDA #$0000
    STA.l !vmaddl
    SEP #$20
    REP #$10

    LDX #$0000
.first:
    LDA.l $740000,X : STA.l !vmdatalw
    LDA.l $740001,X : STA.l !vmdatahw
    INX : INX
    CPX #$8000
    BNE .first

    LDX #$0000
.second:
    LDA.l $750000,X : STA.l !vmdatalw
    LDA.l $750001,X : STA.l !vmdatahw
    INX : INX
    CPX #$8000
    BNE .second
    RTS

; ---------------------------------------------------------------------------
; CGRAM, 512 bytes. $213B and $2122 each hold an internal low/high toggle that
; advances the colour address, so a flat byte loop covers all 256 colours.
; ---------------------------------------------------------------------------
cgram_to_sram:
    SEP #$20
    LDA #$00
    STA.l !cgadd
    REP #$10
    LDX #$0000
.loop:
    LDA.l !cgdatar
    STA.l $760000,X
    INX
    CPX #$0200
    BNE .loop
    RTS

sram_to_cgram:
    SEP #$20
    LDA #$00
    STA.l !cgadd
    REP #$10
    LDX #$0000
.loop:
    LDA.l $760000,X
    STA.l !cgdataw
    INX
    CPX #$0200
    BNE .loop
    RTS
