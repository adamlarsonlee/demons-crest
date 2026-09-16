; Demon's Blazon (Japan) practice ROM
; Build with: make verify && make rom

incsrc "../../build/rom_config.inc"

!version_major = 0
!version_minor = 1

; Builds always patch a pristine copy of the ROM, so asar has no prior
; allocation to reclaim and its leak warning does not apply.
warnings disable Wfreespace_leaked

; Injected so a built ROM is identifiable in a hex editor without a full diff.
freedata
practice_signature:
    db "DCPRACTICE"
    db !version_major, !version_minor
    db 0

; ---------------------------------------------------------------------------
; Everything below awaits Phase 1 recon. Each entry needs a JP-verified
; address before any code can be written against it; guessing an address on
; real hardware crashes rather than misbehaves.
;
;   progress_state_base   contiguous progress-flag region (items/powers are at
;                         $1E30-$1E55 per memory-map/README.md; boss-defeated
;                         and stage-open flags are not yet located)
;   current_level         level index, for the warp target
;   level_load_entry      routine that loads a level
;   controller_1_new      newly-pressed buttons, for hotkey edge detection
;   frame_hook            NMI or main-loop site with cycle headroom to poll
;   rng_value             RNG state, for display and seeding
; ---------------------------------------------------------------------------
