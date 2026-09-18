; Demon's Blazon (Japan) practice ROM
; Build with: make verify && make rom
;
; Every change is described in plain language in docs/patches.md. Keep that
; document in step with this file.
;
; Four changes:
;   1. A new game starts on the overworld with the Initial Stage beaten.
;   2. Entering a stage presets the Any% route progress for that stage.
;   3. Select+Start during gameplay exits the stage to the overworld.
;   4. Select+R saves a state, Select+L loads it.

incsrc "../../build/rom_config.inc"

!version_major = 0
!version_minor = 7

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
!pad_held_hi   = $7E0091        ; high byte of $0090; Select $20, Start $10
!pad_new_hi    = $7E0095        ; high byte of $0094; Start is bit 4
!pad_new_lo    = $7E0094        ; low byte of $0094;  R is bit 4, L is bit 5
!loop_flag     = $7E0086

!inidisp       = $002100
!vmain         = $002115
!vmaddl        = $002116
!vmdatalr      = $002139
!cgadd         = $002121
!nmitimen      = $004200

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
assert read1($00FFD6) == $00, "header already declares a chipset"
assert read1($00FFD8) == $00, "header already declares SRAM"

; ---------------------------------------------------------------------------
; Cartridge header: declare RAM so the save state has somewhere to live. Both
; bytes are needed - a size with the chipset still saying "ROM only" is not
; enough. $09 is 512 KB, the largest snes9x accepts; the state uses 192.5 KB.
; ---------------------------------------------------------------------------
org $00FFD6
    db $02                      ; ROM + RAM + battery
org $00FFD8
    db $09

; ---------------------------------------------------------------------------
; 5. Defeat the cartridge's copier detection
;
; The game tests twice whether writable memory exists at $70:1FFF - the LoROM
; SRAM window - because a genuine Demon's Blazon cartridge has no SRAM there:
;
;   $80:8746  LDA $701FFF / INC A / STA $701FFF / CMP $701FFF
;   $80:8753  BNE +6                  ; read-back differs: genuine cart
;   $80:8755  LDA #$FF / STA $0EEB    ; read-back matched: copier detected
;
; and the same sequence at $80:E543 setting $0EEC instead. On a real cart the
; write lands in open bus, the read-back mismatches, and neither flag is set.
;
; Declaring SRAM for the save state makes $70:1FFF genuinely writable, so both
; checks conclude the cartridge is a copy. $82:88F5 then reads $0EEC (and
; $0EEE) and, when either is set, branches over the `SBC $0000,Y` that subtracts
; damage from an enemy - so shots stop hurting anything. The crest menu fails
; the same way.
;
; Confirmed from the reporter's own bus dumps: $70:1FFF incremented C6 -> C7
; between two captures while $0EEC went $00 -> $FF.
;
; Turning each BNE into BRA makes the copier-detected path unreachable. Two
; bytes. The checks still touch $70:1FFF, which is why the save state must not
; keep anything there - see the note on bank $70 below.
;
; $0EEE is left alone: it comes from a ROM-mirror comparison at $BE:E3C3
; ($80:FFC1 against $40:FFC1), which this patch does not disturb.
;
; This is not about circumventing anything: the check exists to spot a cartridge
; with unexpected RAM, and ours has unexpected RAM by design.
; ---------------------------------------------------------------------------
assert read1($808746) == $AF, "protection site 1 moved: expected LDA $701FFF at $80:8746"
assert read1($808753) == $D0, "protection site 1 moved: expected BNE at $80:8753"
assert read1($80E543) == $AF, "protection site 2 moved: expected LDA $701FFF at $80:E543"
assert read1($80E550) == $D0, "protection site 2 moved: expected BNE at $80:E550"

org $808753
    db $80                      ; BNE -> BRA
org $80E550
    db $80                      ; BNE -> BRA

; ---------------------------------------------------------------------------
; 1. New game starts on the overworld
;
; Replaces LDA #$04 / STA $1E50 in the new-game progress init. Writes the
; route's opening block and hands control to the password path, which already
; knows how to put a player on the overworld with arbitrary progress. Its tail
; tests $1E54 bit 0 — the Somulo upgrade, i.e. "Initial Stage finished" — and
; dispatches to the overworld when set.
;
; The block written here is the route's final state, not its opening one - see
; block_boot below for why.
; ---------------------------------------------------------------------------
; Entered with JML, not JSL: this routine never comes back, it hands off to the
; password tail. A JSL would push a three-byte return address that nothing ever
; pops, leaving the stack pointer three bytes lower for the rest of the session
; - and the password tail's own RTS/RTL would then return through our address
; instead of its caller's.
org $848906
    JML boot_hook
    NOP

freecode
boot_hook:
    SEP #$30                    ; 8-bit A and X, as the password tail expects
    LDX #$00
.copy:
    LDA.l block_boot,X
    STA.l !progress_base,X
    INX
    CPX #!block_size
    BNE .copy
    JML !password_tail

; ---------------------------------------------------------------------------
; 3 and 4. Level-loop hotkeys
;
; Replaces LDA #$FF / STA $0086 in the level gameplay loop, the only per-frame
; site in task context. The NMI hook cannot serve: neither the exit nor the
; state copy may run from inside an interrupt.
;
;   Select + Start   exit the stage to the overworld
;   Select + R       save state
;   Select + L       load state
;
; The game computes pad edge detection itself at $0094, so this does not.
; ---------------------------------------------------------------------------
org $80B8F5
    JSL level_hook
    NOP

freecode
level_hook:
    ; The displaced instructions, run unconditionally.
    LDA #$FF
    STA.l !loop_flag

    LDA.l !pad_held_hi
    AND #$20                    ; Select held?
    BEQ .no_hotkey

    LDA.l !pad_new_hi
    AND #$10                    ; Start newly pressed?
    BNE .exit
    LDA.l !pad_new_lo
    AND #$10                    ; R newly pressed?
    BNE .save
    LDA.l !pad_new_lo
    AND #$20                    ; L newly pressed?
    BNE .load
.no_hotkey:
    RTL

; ---------------------------------------------------------------------------
.exit:
    ; Consume Start so the crest/vellum screen does not also open.
    LDA.l !pad_new_hi
    AND #$EF
    STA.l !pad_new_hi

    ; Restore the route's final state on the way out. Without this the player
    ; arrives on the overworld carrying whatever the preset hook wrote for the
    ; stage they just left, and the map then only offers the stages reachable
    ; at that progress - so after one visit to Town the castle would vanish.
    SEP #$30
    LDX #$00
.restore:
    LDA.l block_boot,X
    STA.l !progress_base,X
    INX
    CPX #!block_size
    BNE .restore

    ; Discard our JSL return address; the exit sequence never returns.
    PLA
    PLA
    PLA

    LDA.l !return_loc
    JML !exit_entry

; ---------------------------------------------------------------------------
.save:
    PHB
    JSR ss_prologue
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $70,$7E
    LDX #$8000 : LDY #$0000 : LDA #$7FFF : MVN $71,$7E
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $72,$7F
    LDX #$8000 : LDY #$0000 : LDA #$7FFF : MVN $73,$7F
    SEP #$30
    JSR vram_to_sram
    JSR cgram_to_sram
    JSR ss_epilogue
    PLB
    RTL

.load:
    PHB
    JSR ss_prologue
    REP #$30
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $7E,$70
    LDX #$0000 : LDY #$8000 : LDA #$7FFF : MVN $7E,$71
    LDX #$0000 : LDY #$0000 : LDA #$7FFF : MVN $7F,$72
    LDX #$0000 : LDY #$8000 : LDA #$7FFF : MVN $7F,$73
    SEP #$30
    JSR sram_to_vram
    JSR sram_to_cgram
    JSR ss_epilogue
    PLB
    RTL

; ---------------------------------------------------------------------------
; Save-state support. SRAM layout, using the LoROM offset formula
;   (((Address & $ff0000) >> 1) | (Address & $7fff)) & SRAMMask
; so each bank from $70 owns a distinct 32 KB window:
;
;   WRAM $7E:0000-$7FFF <-> $70     VRAM $0000-$7FFF <-> $74
;   WRAM $7E:8000-$FFFF <-> $71     VRAM $8000-$FFFF <-> $75
;   WRAM $7F:0000-$7FFF <-> $72     CGRAM            <-> $76
;   WRAM $7F:8000-$FFFF <-> $73                  = 192.5 KB of 512 KB
;
; NMI is off for the whole copy, because MVN is interruptible and an NMI
; landing on a half-restored stack would push onto corrupt memory. Forced blank
; makes VRAM and CGRAM accessible outside vblank. Neither $4200 nor $2100 can
; be read back, so they are restored to $B1 and $0F, the values the game writes.
;
; PHB/PLB stay in the callers. A PHB before an RTS leaves the pushed bank byte
; on top of the return address - the hazard CLAUDE.md records for the $80:821E
; hook, which froze the game in an earlier version of this code.
; ---------------------------------------------------------------------------
ss_prologue:
    SEP #$20
    LDA #$00
    STA.l !nmitimen
    LDA #$8F
    STA.l !inidisp
    RTS

ss_epilogue:
    SEP #$30
    LDA #$0F
    STA.l !inidisp
    LDA #$B1
    STA.l !nmitimen
    RTS

; VRAM and CGRAM move by DMA on channel 1, following RockmanX2Practice. Three
; details matter, all of which a hand-written loop got wrong first: VMAIN must
; be $00 so the address increments after the LOW byte, VMADD takes WORD
; addresses so the second half is $4000, and the dummy read of $2139 after
; setting VMADD is required.
;
; Register packing: a 16-bit store to $4312 sets A1T low and high, to $4314 the
; A bank and DAS low, to $4315 DAS low and high. DAS $8000 is one SRAM window.
vram_to_sram:
    SEP #$30
    LDA #$00 : STA.l !vmain
    LDA #$81 : STA.l $004310        ; DMAP: B->A, word, two registers
    LDA #$39 : STA.l $004311        ; BBAD = $2139, VRAM read
    REP #$20 : LDA #$0000 : STA.l !vmaddl : SEP #$20
    LDA.l !vmdatalr                 ; required dummy read
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$74 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    REP #$20 : LDA #$4000 : STA.l !vmaddl : SEP #$20
    LDA.l !vmdatalr
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$75 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS

sram_to_vram:
    SEP #$30
    LDA #$00 : STA.l !vmain
    LDA #$01 : STA.l $004310        ; DMAP: A->B, word, two registers
    LDA #$18 : STA.l $004311        ; BBAD = $2118, VRAM write
    REP #$20 : LDA #$0000 : STA.l !vmaddl : SEP #$20
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$74 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    REP #$20 : LDA #$4000 : STA.l !vmaddl : SEP #$20
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$75 : STA.l $004314
    REP #$20 : LDA #$8000 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS

cgram_to_sram:
    SEP #$30
    LDA #$00 : STA.l !cgadd
    LDA #$80 : STA.l $004310        ; DMAP: B->A, byte, one register
    LDA #$3B : STA.l $004311        ; BBAD = $213B, CGRAM read
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$76 : STA.l $004314
    REP #$20 : LDA #$0200 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS

sram_to_cgram:
    SEP #$30
    LDA #$00 : STA.l !cgadd
    LDA #$00 : STA.l $004310        ; DMAP: A->B, byte, one register
    LDA #$22 : STA.l $004311        ; BBAD = $2122, CGRAM write
    REP #$20 : LDA #$0000 : STA.l $004312 : SEP #$20
    LDA #$76 : STA.l $004314
    REP #$20 : LDA #$0200 : STA.l $004315 : SEP #$20
    LDA #$02 : STA.l $00420B
    RTS

; ---------------------------------------------------------------------------
; 2. Preset the route progress for the stage being entered
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
; The block a new game boots with. This is the route's FINAL state - after
; Flier, the last boss before the castle - not its opening state. The overworld
; only offers a stage once the progress to reach it exists, and the castle in
; particular is unavailable until Flier is dead. Booting with the final block
; makes every route stage selectable; the preset hook then writes the correct
; per-stage progress on entry, so the generous boot state is never played with.
; Taken from the overworld-castle route dump.
block_boot:
    db $08, $16, $00, $00, $07, $01, $00, $00, $00

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
