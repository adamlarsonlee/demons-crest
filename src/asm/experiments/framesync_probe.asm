; Per-frame hook in the shared frame-sync routine $80:821E, which every game
; mode calls once per iteration of its own loop. Unlike the NMI hook this runs
; outside vblank, so it does not compete with the game's DMA.
;
; The hook goes after $80:821E's register-save prologue, not at its start:
; displacing PHB/PHD/PHP into a subroutine would leave those pushes stacked on
; top of the JSL return address and break the RTL.
;
; Five bytes at $80:822D -- LDY $0072 and LDA #$01 -- become a JSL plus a NOP.
; Both are replayed at the end of the hook. Neither touches the stack, and the
; full 16-bit accumulator is preserved because the XBA at $80:8235 brings its
; high byte back into play and $80:8239 branches on the result.

incsrc "../../../build/rom_config.inc"

!frame_counter = $7FC708

org $80822D
    JSL framesync_hook
    NOP

freecode
framesync_hook:
    PHP
    REP #$20
    PHA
    LDA.l !frame_counter
    INC A
    STA.l !frame_counter
    PLA
    PLP

    LDY $0072           ; displaced; absolute, resolved through DB = $81
    LDA #$01            ; displaced
    RTL
