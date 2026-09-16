; Proves injected code executes on real hardware terms: chain the NMI vector
; through our own routine, which counts frames into WRAM the game leaves alone.
;
; $7F:C668-$7F:C802 reads as zero across title, cinematic and gameplay states.
; If the counter ends up equal to the NMI count, nothing else contended it.

incsrc "../../../build/rom_config.inc"

; The hook is reached through a hand-written JML, not a pointer asar tracks,
; so its freespace reachability check does not apply.
warnings disable Wfreespace_leaked

!nmi_counter = $7FC700
!orig_nmi    = $808329

; $80:FFA4 is a JML stub the CPU reaches via the native NMI vector.
org $80FFA4
    JML nmi_hook

freecode
nmi_hook:
    PHP
    REP #$20
    PHA
    LDA.l !nmi_counter
    INC A
    STA.l !nmi_counter
    PLA
    PLP
    JML !orig_nmi
