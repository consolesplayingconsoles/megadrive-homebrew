; =============== S U B R O U T I N E =======================================
; InitPlayers — PATCHED for character selection
; Replaces vanilla InitPlayers at ~line 5177
; Reads v_current_char_p1/p2 and spawns correct character objects

InitPlayers:
	; Read P1 character selection
	move.b	(v_current_char_p1).w, d0

	; Branch based on character ID
	cmp.b	#0, d0
	beq.s	.p1_sonic
	cmp.b	#1, d0
	beq.s	.p1_tails
	cmp.b	#2, d0
	beq.s	.p1_knuckles

	; Default to Sonic
	.p1_sonic:
	move.b	#ObjID_Sonic,(MainCharacter+id).w
	move.b	#ObjID_SpindashDust,(Sonic_Dust+id).w
	bra.s	.load_p2

	.p1_tails:
	move.b	#ObjID_Tails,(MainCharacter+id).w
	move.b	#ObjID_SpindashDust,(Tails_Dust+id).w
	bra.s	.load_p2

	.p1_knuckles:
	move.b	#$4C,(MainCharacter+id).w		; Obj4C = Knuckles
	bra.s	.load_p2

	; Load P2 (Sidekick) — same pattern
	.load_p2:
	move.b	(v_current_char_p2).w, d0

	cmp.b	#0, d0
	beq.s	.p2_sonic
	cmp.b	#1, d0
	beq.s	.p2_tails
	cmp.b	#2, d0
	beq.s	.p2_knuckles

	; Default to Tails for P2
	.p2_tails:
	move.b	#ObjID_Tails,(Sidekick+id).w
	move.b	#ObjID_SpindashDust,(Tails_Dust+id).w
	rts

	.p2_sonic:
	move.b	#ObjID_Sonic,(Sidekick+id).w
	move.b	#ObjID_SpindashDust,(Sonic_Dust+id).w
	rts

	.p2_knuckles:
	move.b	#$4C,(Sidekick+id).w			; Obj4C = Knuckles
	rts
