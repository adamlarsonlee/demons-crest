; Probe: start a new game on the overworld with the Initial Stage already
; beaten, by writing a route starting block over the new-game progress init.
;
; The game decides where a fresh start goes from $1E54 bit 0 — the Somulo
; HP-up. $84:C1EF dispatches to the overworld when it is set and into area 0,
; the Somulo arena, when it is clear. So skipping the intro is a data write, not
; a transition: write a block with that bit set and the game does the rest.
;
; Hook   $84:8906, in the new-game init:
;
;          $84:88E2  STZ $008D      ; area 0
;          $84:88E8  STZ $1E51      ; ... through $1E57
;          $84:8906  LDA #$04       <- 5 bytes, replaced
;          $84:8908  STA $1E50      ; max HP 4
;          $84:890B  JSL $809A42
;
;        The seven STZ stores above it have already cleared $1E51-$1E57 by the
;        time we run, which is harmless: the block below overwrites all nine
;        bytes including $1E50, so it subsumes the two instructions displaced.
;
; Block  The Town row from docs/route-any.md, i.e. progress as of finishing the
;        Initial Stage: Earth Crest, two HP-ups, max HP 6. Measured from the
;        arma-dead-overworld route dump rather than derived.
;
; PASS   A new game starts on the overworld, not in area 0, with max HP 6 and
;        the Earth Crest held.
; FAIL   Landing in area 0 anyway would mean a new game does not pass through
;        the $84:C1EF gate at all — that gate was found on the password path,
;        and its use by the new-game path is an assumption this probe tests.
;
; Build  make rom ASM=src/asm/experiments/boot_overworld.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

!progress_base = $7E1E50
!block_size    = 9

assert read1($848906) == $A9, "hook site changed: expected LDA #$04 at $84:8906"
assert read1($848908) == $8D, "hook site changed: expected STA $1E50 at $84:8908"

org $848906
    JSL boot_hook
    NOP

freecode
boot_hook:
    PHP
    SEP #$30                    ; 8-bit A and X, whatever the caller had
    PHX
    LDX #$00
.copy:
    LDA.l start_block,X
    STA.l !progress_base,X
    INX
    CPX #!block_size
    BNE .copy
    PLX
    PLP
    RTL

; $1E50-$1E58 as of finishing the Initial Stage. $1E54 bit 0 is the bit that
; sends the new game to the overworld, and it doubles as the first HP-up.
start_block:
    db $06      ; $1E50  max HP 6 = 4 + two HP-ups
    db $10      ; $1E51  Earth Crest
    db $00      ; $1E52
    db $00      ; $1E53
    db $03      ; $1E54  HP-ups 1 and 2; bit 0 is Somulo / Initial Stage done
    db $00      ; $1E55
    db $00      ; $1E56
    db $00      ; $1E57
    db $00      ; $1E58
