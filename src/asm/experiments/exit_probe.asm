; Probe: can a hotkey exit the current stage to the overworld by entering the
; game's own exit-area sequence?
;
; Companion to death_probe.asm, which FAILED - see its header. Jumping straight
; to the death entry $80:E602 skipped the player-state setup the damage handler
; does between $80:E578 and $80:E5C6, and the screen went black within 20
; frames. This probe targets a sequence that is self-contained instead.
;
; Target   $80:BB30, the exit-area sequence:
;
;            $80:BB30  JSL $84851C     ; teardown
;            $80:BB34  LDX #$10
;            $80:BB36  JSL $808212
;            $80:BB3A  LDA #$10        ; state index x 2 = the overworld
;            $80:BB3C  JML $80829B     ; state change; A carries the state
;
;          Two JSLs do the teardown before the state change, which is the kind
;          of context the death entry turned out to need. $80:829B opens with
;          SEP #$30 / PHA, so it takes the state in A and sets its own widths.
;
; Hook     $80:B8F5, in the level gameplay loop ($80:B843-$80:B905), same slot
;          as death_probe. The loop runs with M=8 X=8 D=0, and $80:BB30 is
;          normally reached from level code, so D=0 should be what it expects -
;          no TCD here, unlike the death probe.
;
; Hotkey   Start newly pressed while Select is held.
;
; PASS     The overworld appears, Firebrand placed by the game, and flying and
;          re-entering a stage both work.
; FAIL     A black screen means the teardown wants more context still. A
;          rendered but unresponsive overworld would mean the same problem the
;          $0036 poke had, and would point at $80:8212 or $84:851C needing
;          arguments we are not supplying.
;
; Build    make rom ASM=src/asm/experiments/exit_probe.asm

incsrc "../../../build/rom_config.inc"

; The exit jump is a hand-written JML that asar's freespace tracker cannot
; follow, so its leak check does not apply.
warnings disable Wfreespace_leaked

!pad_new_hi  = $7E0095          ; high byte of $0094; Start  is bit 4 ($1000)
!pad_held_hi = $7E0091          ; high byte of $0090; Select is bit 5 ($2000)
!loop_flag   = $7E0086
!exit_entry  = $80BB07          ; the routine's real entry, not $80:BB30
!return_loc  = $7E0EA6          ; per-stage overworld return location

assert read1($80B8F5) == $A9, "hook site changed: expected LDA #$FF at $80:B8F5"
assert read1($80B8F7) == $8D, "hook site changed: expected STA $0086 at $80:B8F7"
assert read1($80BB07) == $29, "exit entry changed: expected AND #$0F at $80:BB07"

org $80B8F5
    JSL exit_hook
    NOP

freecode
exit_hook:
    ; The displaced instructions first, so they run whether or not we exit.
    LDA #$FF
    STA.l !loop_flag

    LDA.l !pad_new_hi
    AND #$10                    ; Start newly pressed?
    BEQ .no_hotkey
    LDA.l !pad_held_hi
    AND #$20                    ; Select held?
    BEQ .no_hotkey

    ; Consume Start so the crest/vellum screen does not also open this frame.
    LDA.l !pad_new_hi
    AND #$EF
    STA.l !pad_new_hi

    ; Discard our JSL return address; the exit sequence never comes back, and
    ; the state change resets SP from $0034,Y regardless.
    PLA
    PLA
    PLA

    ; Hand over to the game's own exit, at its real entry rather than 0x29
    ; bytes in. $80:BB07 takes a 0-15 return location in A, ANDs it and stores
    ; it to $0EA6; passing back the value already there is idempotent and
    ; keeps the three calls that entering at $80:BB30 skipped.
    LDA.l !return_loc
    JML !exit_entry

.no_hotkey:
    RTL
