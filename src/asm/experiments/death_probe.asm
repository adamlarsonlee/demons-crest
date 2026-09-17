; Probe: can Firebrand be killed outright by jumping to the game's own death
; entry, from a hook in the level gameplay loop?
;
; This is the smallest possible test of the "make the game do the work"
; principle. If it passes, the practice ROM's retry feature is ~10 instructions
; and the animation, the HP restore from $1E50, the three-option menu and the
; state dispatch afterwards are all the game's own code.
;
; Target   $80:E602, the death entry. Reached in normal play only by two
;          branches out of the damage handler ($80:E5C8 BEQ / $80:E5CA BMI).
;          It clears HP as STZ $62 / STZ $61, i.e. direct-page relative, so it
;          needs D = $1000. It never returns: both its exits are JMP $EFD3.
;
; Hook     $80:B8F5, inside the level gameplay loop ($80:B843-$80:B905, closed
;          by JMP $B843). The loop runs once per frame in task context with
;          M=8 X=8 and D=0. LDA #$FF / STA $0086 there is five bytes, which
;          takes a JSL plus a NOP with the two instructions moved in here.
;
; Hotkey   Start newly pressed while Select is held. $7E:0094 is the game's own
;          newly-pressed word and $7E:0090 the held word, so no edge detection
;          is needed here.
;
; PASS     Firebrand dies and the three-option menu appears.
; FAIL     Anything else. A hang or corruption means $80:E602 needs more of the
;          player-update context than the direct page alone - it also touches
;          $3C, $05, $06 and $04 on that page and calls JSR $BD76. The
;          documented fallback is to enter the damage path at $80:E56B with
;          lethal damage in A instead, letting the game build its own context.
;
; Build    make rom ASM=src/asm/experiments/death_probe.asm

incsrc "../../../build/rom_config.inc"

; The death jump is a hand-written JML that asar's freespace tracker cannot
; follow, so its leak check does not apply.
warnings disable Wfreespace_leaked

; High bytes of the game's 16-bit pad words, so every test below is 8-bit and
; the loop's register widths are left untouched.
!pad_new_hi  = $7E0095          ; high byte of $0094; Start  is bit 4 ($1000)
!pad_held_hi = $7E0091          ; high byte of $0090; Select is bit 5 ($2000)
!loop_flag   = $7E0086          ; what the displaced instructions write
!death_entry = $80E602
!player_dp   = $1000

; Refuse to build if the hook site is not the two instructions that were
; measured. A silently shifted hook would corrupt the loop rather than fail.
assert read1($80B8F5) == $A9, "hook site changed: expected LDA #$FF at $80:B8F5"
assert read1($80B8F7) == $8D, "hook site changed: expected STA $0086 at $80:B8F7"

org $80B8F5
    JSL death_hook
    NOP

freecode
death_hook:
    ; The displaced instructions first, so they run whether or not the hotkey
    ; fires. Long addressing keeps this independent of DB.
    LDA #$FF
    STA.l !loop_flag

    ; Start newly pressed?
    LDA.l !pad_new_hi
    AND #$10
    BEQ .no_hotkey
    ; Select held?
    LDA.l !pad_held_hi
    AND #$20
    BEQ .no_hotkey

    ; Consume Start so the crest/vellum screen does not also open this frame.
    LDA.l !pad_new_hi
    AND #$EF
    STA.l !pad_new_hi

    ; Discard our JSL return address. The death entry never returns, and the
    ; eventual mode change resets SP from $0034,Y anyway, but leaving the
    ; stack tidy keeps the failure mode readable if this probe misbehaves.
    PLA
    PLA
    PLA

    ; Point the direct page at the player variables the death code addresses,
    ; then hand over. JML rather than JMP so the program bank becomes $80 and
    ; the death code's own JSR $BD76 resolves inside bank $80.
    REP #$20
    LDA #!player_dp
    TCD
    SEP #$20
    JML !death_entry

.no_hotkey:
    RTL
