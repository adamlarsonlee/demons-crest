; Save state covering WRAM's dynamic halves and all of VRAM, in 128 KB of SRAM.
;
; Supersedes savestate_probe.asm, which saved all of WRAM and no VRAM. That was
; unsound: VRAM changes within a section as the camera scrolls (measured, ~2,665
; bytes over 550 frames), so a WRAM-only restore leaves the state against the
; wrong tiles.
;
; Budget. snes9x clamps SRAM to 128 KB regardless of the header, and it is the
; only core available that both honours a header SRAM declaration and exposes
; memory for verification (docs/emulators.md). So the state must fit 128 KB.
;
; What is saved, and why it fits:
;
;   WRAM $7E:0000-$7FFF  ->  SRAM $70:0000-$7FFF    dynamic
;   WRAM $7F:8000-$FFFF  ->  SRAM $71:0000-$7FFF    dynamic
;   VRAM $0000-$7FFF     ->  SRAM $72:0000-$7FFF    all of VRAM
;   VRAM $8000-$FFFF     ->  SRAM $73:0000-$7FFF
;                                            = 128 KB exactly
;
; What is excluded, on measurement rather than assumption. Over 2,050 frames of
; heavily varied play in area 1, $7E:8000-$FFFF and $7F:0000-$7FFF had **zero**
; dirty bytes. They are loaded once at section entry and not written during
; play: $7F:0000-$7FFF is per-area level data (36% of it differs between town
; and forest) and $7E:8000-$FFFF is global tables (12 bytes differ). Excluding
; them is therefore safe for a same-section restore and would NOT be safe
; across areas - which matches the agreed scope.
;
; Hotkeys: Select+R saves, Select+L loads, as RockmanX2Practice does.
;
; VRAM access. VRAM is not reachable with MVN; it is only addressable through
; the PPU. The copy sets forced blank so VRAM is accessible outside vblank, sets
; VMAIN to increment after the high byte, points VMADD at 0, and then moves
; words through $2139/$213A (read) or $2118/$2119 (write). With increment-on-
; high and a low-then-high access order no dummy read should be needed, but that
; is the one detail here taken from reference material rather than measured, so
; the test compares SRAM against the harness's own VRAM dump to catch an
; off-by-one-word error.
;
; Build  make rom ASM=src/asm/experiments/savestate_vram.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

!pad_held_hi = $7E0091          ; high byte of $0090; Select is bit 5
!pad_new_lo  = $7E0094          ; low byte of $0094; R is bit 4, L is bit 5
!loop_flag   = $7E0086

!inidisp     = $002100
!vmain       = $002115
!vmaddl      = $002116
!vmdatalr    = $002139          ; VMDATAREAD low
!vmdatahr    = $00213A          ; VMDATAREAD high, increments VMADD
!vmdatalw    = $002118
!vmdatahw    = $002119
!nmitimen    = $004200

assert read1($00FFD6) == $00, "header already declares a chipset"
assert read1($00FFD8) == $00, "header already declares SRAM"
assert read1($80B8F5) == $A9, "hook site changed: expected LDA #$FF at $80:B8F5"

; The chipset byte must also declare RAM; $00 means "ROM only".
org $00FFD6
    db $02                      ; ROM + RAM + battery
; 128 KB of SRAM.
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
.save:
    PHB                         ; not inside prologue: see the note there
    JSR prologue
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $70,$7E   ; $7E:0000-$7FFF
    LDX #$8000 : LDY #$0000 : LDA #$7FFF : MVN $71,$7F   ; $7F:8000-$FFFF
    SEP #$30
    JSR vram_to_sram
    JSR epilogue
    PLB
    RTL

; ---------------------------------------------------------------------------
.load:
    PHB
    JSR prologue
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $7E,$70
    LDX #$0000 : LDY #$8000 : LDA #$7FFF : MVN $7F,$71
    SEP #$30
    JSR sram_to_vram
    JSR epilogue
    PLB
    RTL

; ---------------------------------------------------------------------------
; PHB/PLB are deliberately in the callers, NOT here. A PHB before an RTS leaves
; the pushed bank byte on top of the return address and the RTS returns into
; garbage - the same hazard CLAUDE.md records for the $80:821E hook. An earlier
; version of this file had exactly that bug and froze the game.
;
; NMI must be off across the whole copy: MVN is interruptible, and an NMI
; landing on a half-restored stack would push onto corrupt memory. Forced blank
; makes VRAM accessible outside vblank. $4200 and $2100 are write-only, so
; neither can be read back and restored - $4200 goes back to $B1 and $2100 to
; $0F, the values the game itself uses.
; ---------------------------------------------------------------------------
prologue:
    SEP #$20
    LDA #$00
    STA.l !nmitimen             ; NMI off
    LDA #$8F
    STA.l !inidisp              ; forced blank
    RTS

epilogue:
    SEP #$30
    LDA #$0F
    STA.l !inidisp              ; screen back on
    LDA #$B1
    STA.l !nmitimen             ; NMI back on
    RTS

; ---------------------------------------------------------------------------
; VRAM -> SRAM. 32768 words, the first half into bank $72 and the second into
; $73, since LoROM SRAM is a 32 KB window per bank.
; ---------------------------------------------------------------------------
vram_to_sram:
    SEP #$20
    LDA #$80
    STA.l !vmain                ; increment after the high byte, step one word
    REP #$30
    LDA #$0000
    STA.l !vmaddl               ; VMADD = 0 (16-bit store covers $2116/$2117)
    SEP #$20
    REP #$10                    ; 8-bit A, 16-bit X

    LDX #$0000
.first:
    LDA.l !vmdatalr
    STA.l $720000,X
    LDA.l !vmdatahr
    STA.l $720001,X
    INX
    INX
    CPX #$8000
    BNE .first

    LDX #$0000
.second:
    LDA.l !vmdatalr
    STA.l $730000,X
    LDA.l !vmdatahr
    STA.l $730001,X
    INX
    INX
    CPX #$8000
    BNE .second
    RTS

; ---------------------------------------------------------------------------
; SRAM -> VRAM, the same traversal in reverse.
; ---------------------------------------------------------------------------
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
    LDA.l $720000,X
    STA.l !vmdatalw
    LDA.l $720001,X
    STA.l !vmdatahw
    INX
    INX
    CPX #$8000
    BNE .first

    LDX #$0000
.second:
    LDA.l $730000,X
    STA.l !vmdatalw
    LDA.l $730001,X
    STA.l !vmdatahw
    INX
    INX
    CPX #$8000
    BNE .second
    RTS
