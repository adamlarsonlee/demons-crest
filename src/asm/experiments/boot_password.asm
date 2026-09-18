; Probe: start a new game on the overworld by handing control to the password
; path, instead of hacking the intro.
;
; The password path already does exactly what is wanted — it writes a progress
; block and then dispatches to the overworld — and every documented password is
; recorded as "loads overworld", so the behaviour is proven. Rather than find
; and change the new-game dispatch, or fight the intro stage's loop, write the
; route block and jump into the password path's tail.
;
; Supersedes two earlier attempts:
;   boot_overworld.asm    wrote the block at the new-game init. The block landed
;                         correctly but the game still started in area 0,
;                         because a new game never reaches the $84:C1EF gate.
;   boot_exit_combo.asm   tried to exit from area 0 with the hotkey. Three hook
;                         sites all failed; area 0's loop is not understood.
;
; Hook   $84:8906, the new-game progress init, same five-byte slot as before.
;        Write the route block, then JML into the password tail.
;
; Entry  $84:C18F, chosen as the start of the password path's *setup* rather
;        than further down it — the death probe established that entering a
;        sequence partway in is what breaks. Everything above $84:C18F is
;        password decoding we do not want:
;
;          $84:C178  TXA / CLC / ADC #$0004 / STA $1E50   ; 4 + HP-up count
;          $84:C182  STA $1062 / STZ $1061
;          $84:C188  LDA $15 / AND #$0F / STA $1E58       ; from the password
;          $84:C18F  STZ $0EA6                            <- enter here
;          $84:C192  LDA #$1C / STA $00F9 / STZ $09F7 / STZ $008D
;          $84:C1A3  JSL $848938
;          $84:C1A9  STZ $1E30,X  x10                     ; scrolls and phials
;          $84:C1B3  STZ $1000,X  x$80                    ; covers $1061/$1062
;          $84:C1BB  LDA $1E50 / STA $1062                ; HP from our block
;          $84:C1C1  JSL $809A42
;          $84:C1EF  LDA $1E54 / AND #$01 -> $10 overworld, else $04
;
;        Skipping $84:C17F-$84:C18E is deliberate: those write $1E50 from the
;        decoded password and $1E58 from $15, both of which we supply ourselves.
;        $1061/$1062 are cleared by the $1000 loop and HP is re-derived at
;        $84:C1BB, so nothing is lost by not running $84:C182.
;
; Stack  We JML out of a routine reached by JSR from a JSL stub, stranding
;        return addresses. Harmless: the tail ends in JML $80829B, which resets
;        the stack pointer from $0034,Y. Same reasoning as the working exit
;        hook.
;
; PASS   A new game starts on the overworld with max HP 6 and the Earth Crest.
; FAIL   Landing in area 0 would mean $1E54 bit 0 is not sufficient even here;
;        a hang would mean $84:C18F needs more context than the block.
;
; Build  make rom ASM=src/asm/experiments/boot_password.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

!progress_base   = $7E1E50
!block_size      = 9
!password_tail   = $84C18F

assert read1($848906) == $A9, "boot hook site changed: expected LDA #$04 at $84:8906"
assert read1($84C18F) == $9C, "password tail changed: expected STZ $0EA6 at $84:C18F"
assert read1($84C1BB) == $AD, "password tail changed: expected LDA $1E50 at $84:C1BB"

org $848906
    JSL boot_hook
    NOP

freecode
boot_hook:
    SEP #$30                    ; 8-bit A and X, as the password tail expects
    LDX #$00
.copy:
    LDA.l start_block,X
    STA.l !progress_base,X
    INX
    CPX #!block_size
    BNE .copy
    JML !password_tail

; $1E50-$1E58 as of finishing the Initial Stage, from the route dumps.
; $1E54 bit 0 is what makes the tail's gate choose the overworld.
start_block:
    db $06, $10, $00, $00, $03, $00, $00, $00, $00
