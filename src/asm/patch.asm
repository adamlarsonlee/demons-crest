; Demon's Blazon (Japan) practice ROM
; Build with: make verify && make rom
;
; Every change is described in plain language in docs/patches.md. Keep that
; document in step with this file.
;
; Three changes:
;   1. A new game starts on the overworld with the Initial Stage beaten.
;   2. Select+Start during gameplay exits the stage to the overworld.
;   3. Entering a stage presets the Any% route progress for that stage.

incsrc "../../build/rom_config.inc"

!version_major = 0
!version_minor = 2

; Builds always patch a pristine copy of the ROM, so asar has no prior
; allocation to reclaim and its leak warning does not apply. The hooks below
; also use hand-written JML/JSL that its freespace tracker cannot follow.
warnings disable Wfreespace_leaked

; Injected so a built ROM is identifiable in a hex editor without a full diff.
freedata
practice_signature:
    db "DCPRACTICE"
    db !version_major, !version_minor
    db 0

; ---------------------------------------------------------------------------
; Addresses. See memory-map/README.md.
; ---------------------------------------------------------------------------
!progress_base = $7E1E50        ; $1E50-$1E58, nine bytes
!block_size    = 9
!current_hp    = $7E1062
!destination   = $7E1326        ; overworld destination index, load-time only
!return_loc    = $7E0EA6        ; overworld return location, 0-15
!pad_held_hi   = $7E0091        ; high byte of $0090; Select is bit 5
!pad_new_hi    = $7E0095        ; high byte of $0094; Start  is bit 4
!loop_flag     = $7E0086

!password_tail = $84C18F        ; the password path's setup phase
!exit_entry    = $80BB07        ; the exit-area routine's real entry

; Refuse to build if any hook site is not the instructions that were measured.
; A shifted hook would corrupt a routine rather than fail visibly.
assert read1($848906) == $A9, "boot hook: expected LDA #$04 at $84:8906"
assert read1($84C18F) == $9C, "password tail: expected STZ $0EA6 at $84:C18F"
assert read1($84C1BB) == $AD, "password tail: expected LDA $1E50 at $84:C1BB"
assert read1($80B8F5) == $A9, "exit hook: expected LDA #$FF at $80:B8F5"
assert read1($80BB07) == $29, "exit entry: expected AND #$0F at $80:BB07"
assert read1($85B097) == $AD, "preset hook: expected LDA $1E50 at $85:B097"
assert read1($85B09A) == $8D, "preset hook: expected STA $1062 at $85:B09A"

; ---------------------------------------------------------------------------
; 1. New game starts on the overworld
;
; Replaces LDA #$04 / STA $1E50 in the new-game progress init. Writes the
; route's opening block and hands control to the password path, which already
; knows how to put a player on the overworld with arbitrary progress. Its tail
; tests $1E54 bit 0 — the Somulo upgrade, i.e. "Initial Stage finished" — and
; dispatches to the overworld when set.
; ---------------------------------------------------------------------------
org $848906
    JSL boot_hook
    NOP

freecode
boot_hook:
    SEP #$30                    ; 8-bit A and X, as the password tail expects
    LDX #$00
.copy:
    LDA.l block_town,X
    STA.l !progress_base,X
    INX
    CPX #!block_size
    BNE .copy
    JML !password_tail

; ---------------------------------------------------------------------------
; 2. Exit the current stage to the overworld
;
; Replaces LDA #$FF / STA $0086 in the level gameplay loop. Select held plus
; Start newly pressed hands control to the game's own exit-area routine. The
; game computes pad edge detection itself at $0094, so this does not.
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

    ; Consume Start so the crest/vellum screen does not also open.
    LDA.l !pad_new_hi
    AND #$EF
    STA.l !pad_new_hi

    ; Discard our JSL return address; the exit sequence never returns.
    PLA
    PLA
    PLA

    LDA.l !return_loc
    JML !exit_entry

.no_hotkey:
    RTL

; ---------------------------------------------------------------------------
; 3. Preset the route progress for the stage being entered
;
; Replaces LDA $1E50 / STA $1062 at the very start of the level-load entry.
; Reads the overworld destination and writes that stage's Any% block before any
; of the load consumes progress. This must happen here and not later: the tier
; calculation at $85:B09D reads the progress block, and it is what redirects
; destination 6 to the Any% castle (area 42) rather than the late-game castle
; section (area 37).
;
; Destinations with no route entry are left untouched, so stages the route does
; not visit keep whatever progress the player had.
; ---------------------------------------------------------------------------
org $85B097
    JSL preset_hook
    NOP
    NOP

freecode
preset_hook:
    PHP
    SEP #$30                    ; 8-bit A and X
    PHB
    PHX
    PHY

    LDA.l !destination
    CMP #$07                    ; table covers destinations 0-6 only
    BCS .apply_done

    ASL A                       ; index * 16, the table's stride
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l route_table,X
    BEQ .apply_done             ; leading 0 means "no route entry, skip"
    INX                         ; past the validity byte

    ; Two independent indices are needed - one into the table, one into the
    ; block - and the 65816 has no STA long,Y. So set DB to $7E and use
    ; absolute,Y for the stores.
    LDA #$7E
    PHA
    PLB
    LDY #$00
.copy:
    LDA.l route_table,X
    STA $1E50,Y
    INX
    INY
    CPY #!block_size
    BNE .copy

.apply_done:
    ; The displaced instructions, now reading whatever block is in place.
    ; Long addressing, so the DB above does not matter here.
    LDA.l !progress_base
    STA.l !current_hp

    PLY
    PLX
    PLB
    PLP
    RTL

; ---------------------------------------------------------------------------
; Any% route state blocks. From docs/route-any.md, measured from route dumps
; rather than derived. Max HP is 4 + the number of HP-up bits, which is why
; these are authentic values and not hand-picked bits.
; ---------------------------------------------------------------------------
block_town:
    db $06, $10, $00, $00, $03, $00, $00, $00, $00

; Indexed by destination, stride 16. First byte of each entry: $01 apply,
; $00 skip. Destinations 4 and 5 are stages the Any% route never enters.
route_table:
    ; 0 — stage 1 revisit, post-Somulo
    db $01,  $05, $00, $00, $00, $01, $00, $00, $00, $00,  $00,$00,$00,$00,$00,$00
    ; 1 — Town
    db $01,  $06, $10, $00, $00, $03, $00, $00, $00, $00,  $00,$00,$00,$00,$00,$00
    ; 2 — Forest
    db $01,  $08, $10, $00, $00, $07, $01, $00, $00, $00,  $00,$00,$00,$00,$00,$00
    ; 3 — Tower
    db $01,  $08, $12, $00, $00, $07, $01, $00, $00, $00,  $00,$00,$00,$00,$00,$00
    ; 4 — not on the route
    db $00,  $00, $00, $00, $00, $00, $00, $00, $00, $00,  $00,$00,$00,$00,$00,$00
    ; 5 — not on the route
    db $00,  $00, $00, $00, $00, $00, $00, $00, $00, $00,  $00,$00,$00,$00,$00,$00
    ; 6 — Castle
    db $01,  $08, $16, $00, $00, $07, $01, $00, $00, $00,  $00,$00,$00,$00,$00,$00
