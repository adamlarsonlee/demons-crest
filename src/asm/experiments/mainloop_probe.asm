; A once-per-frame hook in the main loop rather than in NMI, so per-frame work
; does not compete with the game's vblank DMA. The NMI hook is functionally
; transparent but shifts the game by one frame at load transitions; this site
; should not, because it runs outside vblank.
;
; Replaces seven bytes at $80:AFF0 -- INC $0073 plus JSL $849C04 -- with a JSL
; to our routine and three NOPs. The routine performs both displaced operations
; and returns to $80:AFF4, so the NOPs run and execution resumes at $80:AFF7.

incsrc "../../../build/rom_config.inc"

!frame_counter = $7FC704

org $80AFF0
    JSL main_loop_hook
    NOP
    NOP
    NOP

freecode
main_loop_hook:
    INC $0073           ; the game's own frame counter, displaced

    PHP
    REP #$20
    PHA
    LDA.l !frame_counter
    INC A
    STA.l !frame_counter
    PLA
    PLP

    JSL $849C04         ; the call we displaced
    RTL
