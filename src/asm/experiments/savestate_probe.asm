; Probe: a WRAM-only save state in SRAM.
;
; Scope, agreed: the state is saved and restored within the same section, not
; across areas. That is what makes WRAM-only viable — VRAM already holds the
; right graphics, so it does not need saving, which matters because the
; emulated SRAM ceiling is 128 KB (sram_probe.asm) and WRAM is exactly 128 KB.
;
; Hotkeys, matching RockmanX2Practice:
;   Select + R   save
;   Select + L   load
;
; Layout. LoROM maps SRAM at banks $70-$7D, $0000-$7FFF, so 128 KB spans four
; banks and WRAM is copied in four 32 KB chunks:
;
;   $7E:0000-$7FFF  <->  $70:0000-$7FFF
;   $7E:8000-$FFFF  <->  $71:0000-$7FFF
;   $7F:0000-$7FFF  <->  $72:0000-$7FFF
;   $7F:8000-$FFFF  <->  $73:0000-$7FFF
;
; Why the stack survives a load. Restoring WRAM overwrites the stack we are
; standing on. That is safe only because save and load happen at the *same*
; hook site: SP and our own return address are identical both times, so the
; bytes written over the stack are the bytes that were already there. A general
; save state cannot rely on this — X2 keeps a separate saved SP — but a
; same-section state can.
;
; Why NMI is disabled. MVN is interruptible between iterations. An NMI firing
; while the stack is half-restored would push onto corrupt memory, so NMI is
; masked through $4200 for the duration and restored afterwards. The copy costs
; roughly 917,000 cycles, about a quarter second, so ~15 NMIs are missed.
;
; PASS   WRAM after a load matches WRAM as it was at the save, and the game
;        keeps running.
; FAIL   A hang points at the stack assumption or the NMI masking; graphical
;        corruption that persists points at VRAM mattering after all.
;
; Build  make rom ASM=src/asm/experiments/savestate_probe.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

!pad_held_hi = $7E0091          ; high byte of $0090; Select is bit 5
!pad_new_lo  = $7E0094          ; low byte of $0094; R is bit 4, L is bit 5
!loop_flag   = $7E0086
!nmitimen    = $4200

assert read1($00FFD8) == $00, "header already declares SRAM"
assert read1($80B8F5) == $A9, "hook site changed: expected LDA #$FF at $80:B8F5"

; Declare 128 KB of SRAM. $07 is the largest the emulator honours.
org $00FFD8
    db $07

org $80B8F5
    JSL state_hook
    NOP

freecode
state_hook:
    ; The displaced instructions, run unconditionally.
    LDA #$FF
    STA.l !loop_flag

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
; $4200 is write-only, so its previous value cannot be read back, and there is
; nowhere in WRAM to stash it because WRAM is what gets overwritten. The game
; sets $4200 = $B1 during level setup at $80:B7BA, so that constant is restored
; instead. Long addressing is used so the bank asar placed this code in does
; not matter.
; ---------------------------------------------------------------------------
.save:
    SEP #$20
    LDA #$00
    STA.l $004200               ; NMI off: MVN is interruptible
    PHB
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $70,$7E
    LDX #$8000 : LDY #$0000 : LDA #$7FFF : MVN $71,$7E
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $72,$7F
    LDX #$8000 : LDY #$0000 : LDA #$7FFF : MVN $73,$7F
    SEP #$30
    PLB                         ; MVN left DBR as the destination bank
    LDA #$B1
    STA.l $004200               ; NMI back on
    RTL

; ---------------------------------------------------------------------------
.load:
    SEP #$20
    LDA #$00
    STA.l $004200
    PHB
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $7E,$70
    LDX #$0000 : LDY #$8000 : LDA #$7FFF : MVN $7E,$71
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $7F,$72
    LDX #$0000 : LDY #$8000 : LDA #$7FFF : MVN $7F,$73
    SEP #$30
    PLB
    LDA #$B1
    STA.l $004200
    RTL
