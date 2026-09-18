; Probe: the intended first-run experience, end to end.
;
; A new game starts in area 0 (the Somulo arena) carrying the route's starting
; progress, and the player presses Select+Start to leave for the overworld. That
; is option 2 from docs/route-any.md: rather than hunting the new-game dispatch,
; accept one visit to Somulo and exit from it.
;
; Combines two hooks already probed separately:
;
;   $84:8906   new-game progress init. Writes the route starting block instead
;              of max HP 4 and zeros. Verified in boot_overworld.asm.
;   $80:B8F5   level gameplay loop. Select+Start enters the game's own exit
;              sequence at $80:BB07. Verified in exit_probe.asm, but only ever
;              from area 1.
;
; PASS   New game lands in area 0 with the route block, Select+Start reaches the
;        overworld, and the block is intact afterwards.
; FAIL   If the exit does not work from area 0 specifically, the overworld is
;        likely not yet initialised on a fresh start, and option 2 is dead -
;        which would send us back to locating the new-game dispatch.
;
; Build  make rom ASM=src/asm/experiments/boot_exit_combo.asm

incsrc "../../../build/rom_config.inc"

warnings disable Wfreespace_leaked

!progress_base = $7E1E50
!block_size    = 9
!pad_new_hi    = $7E0095        ; high byte of $0094; Start  is bit 4 ($1000)
!pad_held_hi   = $7E0091        ; high byte of $0090; Select is bit 5 ($2000)
!loop_flag     = $7E0086
!exit_entry    = $80BB07
!return_loc    = $7E0EA6

assert read1($848906) == $A9, "boot hook site changed: expected LDA #$04 at $84:8906"
assert read1($80B8F5) == $A9, "loop hook site changed: expected LDA #$FF at $80:B8F5"
assert read1($80BB07) == $29, "exit entry changed: expected AND #$0F at $80:BB07"



; ---------------------------------------------------------------------------
; New-game progress init
; ---------------------------------------------------------------------------
org $848906
    JSL boot_hook
    NOP

freecode
boot_hook:
    PHP
    SEP #$30
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

; $1E50-$1E58 as of finishing the Initial Stage, from the route dumps.
start_block:
    db $06, $10, $00, $00, $03, $00, $00, $00, $00

; ---------------------------------------------------------------------------
; Exit hotkey, in the level gameplay loop
; ---------------------------------------------------------------------------
org $80B8F5
    JSL exit_hook
    NOP

freecode
exit_hook:
    ; The displaced instructions, run unconditionally.
    LDA #$FF
    STA.l !loop_flag

    LDA.l !pad_new_hi
    AND #$10                    ; Start newly pressed?
    BEQ .no_hotkey
    LDA.l !pad_held_hi
    AND #$20                    ; Select held?
    BEQ .no_hotkey

    ; Consume Start so the crest screen does not also open.
    LDA.l !pad_new_hi
    AND #$EF
    STA.l !pad_new_hi

    ; Drop our JSL return address; the exit never comes back.
    PLA
    PLA
    PLA

    LDA.l !return_loc
    JML !exit_entry

.no_hotkey:
    RTL

; ---------------------------------------------------------------------------
; Exit hotkey, in the intro stage's own loop
;
; Area 0 does not run the level gameplay loop - $0073 is incremented at
; $80:A90B there, not $80:B8FA - so a second hook is needed.
;
; An earlier attempt hooked LDA $00F9 / CMP #$1A at $80:A8EE and never fired: a
; marker proved the hook never executed, so the loop branches around that path.
; $80:A90B is the site the $0073 watch actually observed, 599 times.
;
; The slot is INC $0073 / JMP $A8A8 at $80:A90B, six bytes, replaced by a JML.
; The hook reproduces the increment, tests the hotkey, then jumps back to the
; top of the loop itself. Nothing is pushed, so the exit path needs no stack
; cleanup.
; ---------------------------------------------------------------------------
org $80A90B
    JML intro_hook

freecode
intro_hook:
    ; Reproduce INC $0073. M is 8 here, from the SEP #$30 at $80:A903.
    LDA.l $7E0073
    INC A
    STA.l $7E0073

    ; The intro loop runs about once every nine frames - $0073 advanced 152
    ; times over 1338 - so the one-frame edge at $0094 is nearly always missed.
    ; Test both buttons HELD instead. Retriggering does not matter because the
    ; exit leaves immediately.
    LDA.l !pad_held_hi
    AND #$30                    ; Select ($20) and Start ($10) both held?
    CMP #$30
    BNE .resume

    LDA.l !pad_new_hi
    AND #$EF                    ; consume Start
    STA.l !pad_new_hi

    LDA.l !return_loc
    JML !exit_entry

.resume:
    JML $80A8A8                 ; back to the top of the intro loop
