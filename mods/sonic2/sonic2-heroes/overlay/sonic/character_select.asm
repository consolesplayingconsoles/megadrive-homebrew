; Sonic 2 Heroes — Character Select
;
; Handles character switching via X+Y input (emulator) / L+R (GBA future)
; Character selection persists across level (reset at level end)

; Character roster (0-indexed)
; 0 = Sonic (default)
; 1 = Tails
; 2 = Knuckles
; 3+ = others as ported

; RAM locations for character slots (add to _variables.asm)
; v_current_char_p1: 1 byte (P1 character index, 0-based)
; v_current_char_p2: 1 byte (P2 character index, 0-based)
; v_char_count:      1 byte (total available characters)
; Note: Both can pick the same character (overlap allowed)

; ============================================================================
; Init character select (both players)
; Called at level start (LevelInit or equivalent)
; ============================================================================
CharacterSelect_Init:
	; Initialize both character slots to 0 (Sonic) if not set
	tst.b	(v_current_char_p1).w
	bne.s	.skip_p1
	clr.b	(v_current_char_p1).w
	.skip_p1:
	tst.b	(v_current_char_p2).w
	bne.s	.skip_p2
	clr.b	(v_current_char_p2).w
	.skip_p2:
	rts

; ============================================================================
; Handle button input to cycle characters
; Press C to cycle through available characters
; Called each frame during level (in main VInt handler)
; ============================================================================
CharacterSelect_CheckInput:
	; P1: Check C button press
	move.b	(Ctrl_1_Press).w, d0
	btst	#button_C, d0			; Is C pressed?
	beq.s	.check_p2
	addq.b	#1, (v_current_char_p1).w
	cmpi.b	#3, (v_current_char_p1).w	; Wrap at 3 (Sonic, Tails, Knuckles)
	blo.s	.check_p2
	clr.b	(v_current_char_p1).w

	; P2: Check B button press (different from P1)
	.check_p2:
	move.b	(Ctrl_2_Press).w, d0
	btst	#button_B, d0			; Is B pressed?
	beq.s	.done
	addq.b	#1, (v_current_char_p2).w
	cmpi.b	#3, (v_current_char_p2).w	; Wrap at 3
	blo.s	.done
	clr.b	(v_current_char_p2).w

	.done:
	rts

; ============================================================================
; Load character-specific objects (P1 and P2 independently)
; Called at level load time for each player
; Input: a1 = object slot for character, d0 = player (0=P1, 1=P2)
; ============================================================================
CharacterSelect_LoadCharacterP1:
	move.b	(v_current_char_p1).w, d0
	bra.s	CharacterSelect_LoadCharacter_Common

CharacterSelect_LoadCharacterP2:
	move.b	(v_current_char_p2).w, d0

	; Common loading logic
CharacterSelect_LoadCharacter_Common:
	cmp.b	#0, d0
	beq.s	.load_sonic
	cmp.b	#1, d0
	beq.s	.load_tails
	cmp.b	#2, d0
	beq.s	.load_knuckles
	; Add more as implemented

	; Default to Sonic
	.load_sonic:
	jsr	Sonic_Init		; Sonic character code (vanilla S2)
	rts

	.load_tails:
	jsr	Tails_Init		; Tails character code (vanilla S2)
	rts

	.load_knuckles:
	jsr	Obj4C			; Knuckles object (Obj4C in S2+K disasm)
	rts

; ============================================================================
; TODO: Integrate with level loader
; - Call CharacterSelect_Init at LevelInit
; - Call CharacterSelect_CheckInput in main input loop
; - Call CharacterSelect_LoadCharacter before character object spawns
; ============================================================================
