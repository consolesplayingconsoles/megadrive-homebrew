; ---------------------------------------------------------------------------
; Object 75 - Eggman (SYZ)
; ---------------------------------------------------------------------------

BossSpringYard:
		moveq	#0,d0
		move.b	obRoutine(a0),d0			; copy object routine
		move.w	BossSpringYard_Index(pc,d0.w),d1	; use the object routine index and BossStarLight_Index to calculate our offset
		jmp	BossSpringYard_Index(pc,d1.w)		; jump into the table and use our offset to pick a routine in the index to go to
; ===========================================================================
BossSpringYard_Index:
		dc.w BossSpringYard_Main-BossSpringYard_Index
		dc.w BossSpringYard_ShipMain-BossSpringYard_Index
		dc.w BossSpringYard_FaceMain-BossSpringYard_Index
		dc.w BossSpringYard_FlameMain-BossSpringYard_Index
		dc.w BossSpringYard_SpikeMain-BossSpringYard_Index

BossSpringYard_ChildCmd:	equ objoff_29			; offset used to communicate commands to Eggman's objects. 0 = normal -1 = grabbed/disable collision $A = break block
BossSpringYard_ParentObj:	equ objoff_34			; pointer to main boss controller
BossSpringYard_BlockIndex:	equ objoff_34			; used to hold the block index Eggman is working with/hovering over (same offset, different alias)
BossSpringYard_ObjPointer:	equ objoff_36			; pointer to memory address of spike object or block being grabbed. this is used as a general storage area for the boss controller object to send commands to, changing their behavior
BossSpringYard_GenericTimer:	equ objoff_3C			; timer for how many frames to do an action, whether its wait for explosions, or to move in a direction. also used for vertical displacement of spike
BossSpringYard_PhaseTimer:	equ objoff_3D			; lower byte of timer, used for shaking effect and also attack flag (memory optimization)
BossSpringYard_SineCounter:	equ objoff_3F			; sine counter for bobbing motion
; sonic-vs-robotnik: reload timer for the Swiss Army Knife ranged weapons (A fire / C bomb).
; objoff_2A is unused by this boss. Block smash (B) is not gated (its attack self-paces).
syz_reload:		equ objoff_2A
syz_reload_frames:	equ 24					; bomb: ~0.4s between shots (snappier again -- ball no longer carries the offense)
syz_fire_frames:	equ 48					; fire: ~0.8s (still slower than the bomb -- easy to spam otherwise -- but a lot more aggressive than the old 96)
; sonic-vs-robotnik: previous-frame P2 buttons, so A/C fire on a fresh PRESS (edge), not while
; held -- otherwise holding A auto-fires every reload and reads as un-cooldowned spam.
syz_prevbtn:		equ objoff_2B
syz_super_y:		equ boss_syz_y+$3C			; super Eggman's flight height. With the $44 orbit radius the ball's low point sits right at the floor ($8A) directly below him -- so under him it hits even a ducking Sonic, and the circle lifts it away to the sides. ($4DA unhittable, +$70 too low; +$30 rode the ball too high to connect, +$36 was still a touch high)
; sonic-vs-robotnik: when the Big Spiked Ball (obj 58) is spawned as Eggman's wrecking ball,
; this holds a pointer back to the boss so the ball can orbit him. 0 for ordinary level balls.
; objoff_34 is unused by obj 58 (it uses 38/3A/3C/3E/3F).
syz_ball_parent:	equ objoff_34
; ===========================================================================

BossSpringYard_ObjData:
		; routine number, animation, priority
		dc.b 2,	0, 5					; ship
		dc.b 4,	1, 5					; face
		dc.b 6,	7, 5					; flame
		dc.b 8,	0, 5					; spike
; ===========================================================================

BossSpringYard_Main:	; Routine 0
		move.w	#boss_syz_x+$1B0,obX(a0)		; set render position based on screen position + offset
		move.w	#boss_syz_y+$E,obY(a0)
		move.w	obX(a0),obBossX(a0)			; copy to boss position using scratch RAM (objoff_30 and 38 respectively)
		move.w	obY(a0),obBossY(a0)
		move.b	#col_48x48|col_boss,obColType(a0)	; set collision type: TTSS SSSS. T bits are for type, S is size of collision using table in sub ReactToItem.asm
		move.b	#8,obBossHits(a0) 			; set number of hits to 8
		; sonic-vs-robotnik: the SWISS ARMY KNIFE bonus is this same Spring Yard arena,
		; but picker row 4 (v_levselitem survives level-load). In "super" mode Robotnik is
		; tougher -- for now a 16-hit marker to prove the plumbing; weapons layer on next.
		cmpi.w	#4,(v_levselitem).w			; Swiss Army Knife (bonus row)?
		bne.s	.notsuper
		move.b	#16,obBossHits(a0)			; super: double the hits
		; super Eggman flies LOW so Sonic can actually reach him -- with ranged weapons he
		; never descends to grab blocks, so up high he'd be unhittable = unwinnable.
		move.w	#syz_super_y,obY(a0)
		move.w	#syz_super_y,obBossY(a0)
		clr.b	syz_reload(a0)				; ranged weapons ready to fire
		moveq	#plcid_SwissFire,d0			; queue the flamethrower art onto this arena
		jsr	(AddPLC).l
		; wrecking ball: the SYZ Big Spiked Ball (obj 58). Its art (ArtTile_SYZ_Big_Spikeball)
		; is ALREADY in this arena's VRAM, so no PLC/no chain-art clash -- the GHZ ball's chain
		; collided with the SYZ bumper at $380. We spawn it circling ($x3) and, via the parent
		; pointer we stash, have it orbit the moving Eggman and vanish while he's shooting.
		jsr	(FindNextFreeObj).l
		bne.s	.notsuper
		move.b	#id_BigSpikeBall,obID(a1)
		move.b	#$23,obSubtype(a1)			; circling motion, moderate swing speed
		move.w	obX(a0),obX(a1)
		move.w	obY(a0),obY(a1)
		move.l	a0,syz_ball_parent(a1)			; orbit THIS boss (0 for level spikeballs)
	.notsuper:
		lea	BossSpringYard_ObjData(pc),a2		; load routine data address
		movea.l	a0,a1					; copy boss object address into a1 so that LoadBoss on pass 1 uses the main boss object.
		moveq	#3,d1					; 4 slots of ObjData, so to load properly we must loop 4 times
		bra.s	BossSpringYard_LoadBoss
; ===========================================================================

BossSpringYard_Loop:
		jsr	(FindNextFreeObj).l			; are there any free objects?
		bne.s	BossSpringYard_ShipMain			; no, leave early
		move.b	#id_BossSpringYard,obID(a1)		; set object ID for this slot
		move.w	obX(a0),obX(a1)				; set object position to boss position
		move.w	obY(a0),obY(a1)

BossSpringYard_LoadBoss:
		bclr	#0,obStatus(a0)				; clear the X orientation bit
		clr.b	ob2ndRout(a1)				; clear second routine status (ShipIndex below)
		move.b	(a2)+,obRoutine(a1)			; load first objData byte and increment
		move.b	(a2)+,obAnim(a1)
		move.b	(a2)+,obPriority(a1)
		move.l	#Map_Eggman,obMap(a1)			; load mappings and graphics for the object
		move.w	#ArtTile_Eggman,obGfx(a1)
		move.b	#sprite_cam_field,obRender(a1)		; set the object to position based on where it is in the level and not a static position on screen
		move.b	#64/2,obActWid(a1)			; define horizontal width radius (used to hide objects when they leave the screen space)

; BossSpringYard_ParentObj is used here as a reference back to the main boss controller.
; This is because when we are in ExecuteObjects, a0 is set to each object and sub objects own slot, so we need a way to find the original boss object.
; On the first loop, this copies the address to itself, but the other loops are what it was intended for.
		move.l	a0,BossSpringYard_ParentObj(a1)

		dbf	d1,BossSpringYard_Loop			; repeat sequence 3 more times

BossSpringYard_ShipMain:	; Routine 2
		moveq	#0,d0
		move.b	ob2ndRout(a0),d0			; load secondary routine index of current object slot
		move.w	BossSpringYard_ShipIndex(pc,d0.w),d1	; use the secondary object routine index and ShipIndex to calculate our offset
		jsr	BossSpringYard_ShipIndex(pc,d1.w)	; jump into the table and use our offset to pick a routine in the index to go to
		lea	(Ani_Eggman).l,a1			; load Eggman's animations to animate
		jsr	(AnimateSprite).l

; obStatus stores the logical bits, but obRender is visual bits, so this simply moves them from one to the other

		moveq	#sprite_xflip|sprite_yflip,d0		; move first 2 bits into d0
		and.b	obStatus(a0),d0				; AND with obStatus so now d0 contains X and Y logical flip bits only
		andi.b	#~(sprite_xflip|sprite_yflip),obRender(a0) ; clear the x and y flip
		or.b	d0,obRender(a0)				; OR the two together, so now DisplaySprite has X and Y orientation and above render bits
		jmp	(DisplaySprite).l
; ===========================================================================
BossSpringYard_ShipIndex:
		dc.w BSYZ_ShipStart-BossSpringYard_ShipIndex
		dc.w BSYZ_ShipMove-BossSpringYard_ShipIndex
		dc.w BSYZ_Attack-BossSpringYard_ShipIndex
		dc.w BSYZ_Explode-BossSpringYard_ShipIndex
		dc.w BSYZ_Recover-BossSpringYard_ShipIndex
		dc.w BSYZ_Escape-BossSpringYard_ShipIndex
; ===========================================================================

; loc_191CC:
BSYZ_ShipStart:
		move.w	#-$100,obVelX(a0)			; start moving to the left
		cmpi.w	#boss_syz_x+$138,obBossX(a0)		; have we reached our left bound?
		bhs.s	BSYZ_CalcSine				; no, keep moving
		addq.b	#2,ob2ndRout(a0)			; advance object routine index, so now we go to ShipMove
; loc_191DE:
BSYZ_CalcSine:
		move.b	BossSpringYard_SineCounter(a0),d0
		addq.b	#2,BossSpringYard_SineCounter(a0)	; increment sine counter by 2 (to iterate through the sine table)
		jsr	(CalcSine).l				; unlike GHZ, this starts at 2 instead of 0
		asr.w	#2,d0					; shift right 2 bits (divide by 4), keeping signed number status
		move.w	d0,obVelY(a0)				; set the Y to the "bob" that was calculated
; ============================================================================

; loc_191F2:
BSYZ_MoveUpdate:
		bsr.w	BossMove
		move.w	obBossY(a0),obY(a0)			; copy y and x position
		move.w	obBossX(a0),obX(a0)

; loc_19202:
BSYZ_StatusUpdate:
		move.w	obX(a0),d0				; move x position
		subi.w	#boss_syz_x,d0				; offset x position with start of boss area
		lsr.w	#5,d0					; shift right 5 bits (divide by 32), this sets up the blocks that Eggman is going to look and see if he is over
		move.b	d0,BossSpringYard_BlockIndex(a0)	; move calculated value into offset
		cmpi.b	#6,ob2ndRout(a0)			; are we exploding?
		bhs.s	.exit					; yes, exit
		tst.b	obStatus(a0)				; has Eggman's defeated flag been set (bit 7)?
		bmi.s	BSYZ_Defeated				; if yes (negative number) branch
		tst.b	obColType(a0)				; is the boss hittable?
		bne.s	.exit					; if not, leave
		tst.b	obBossFlash(a0)				; is this a non-zero value (collision disabled if so, must mean boss is already flashing)
		bne.s	.flash					; we are flashing already, skip ahead
		move.b	#$20,obBossFlash(a0)			; set number of times to flash
		move.w	#sfx_HitBoss,d0
		jsr	(QueueSound2).l				; play boss damage sound

; loc_1923A:
.flash:
		lea	(v_palette+$22).w,a1			; load 2nd palette, 2nd entry
		moveq	#0,d0					; move 0 (black)
		tst.w	(a1)					; is the color here black? This is a cool trick, since tst will set its flags based on if the value is 0. What color is black? All 0s!
		bne.s	.writeColor				; if not black, already white, so branch
		move.w	#cWhite,d0				; move 0EEE (white) to d0

; loc_19248:
.writeColor:
		move.w	d0,(a1)					; load color stored in d0
		subq.b	#1,obBossFlash(a0)			; subtract 1 from flash timer
		bne.s	.exit					; keep flashing if obBossFlash is not 0
		move.b	#col_48x48|col_boss,obColType(a0)	; restore collision, the timer has hit 0
; locret_19256:
.exit:
		rts
; ===========================================================================

; loc_19258:
BSYZ_Defeated:
		moveq	#100,d0
		bsr.w	AddPoints
		move.b	#6,ob2ndRout(a0)			; set object routine to BSLZ_Recover
		move.w	#180,BossSpringYard_GenericTimer(a0)  ; set the boss timer
		clr.w	obVelX(a0)				; stop moving horizontally
		rts
; ===========================================================================

; loc_19270:
BSYZ_ShipMove:
		; sonic-vs-robotnik: P2 drives Eggman left/right; A/B/C (when stopped) smashes
		; the floor block under him -- if Sonic is on it, he drops into the pit. No
		; BossMove here (BSYZ_MoveUpdate via CalcSine applies obVelX), so the pad read
		; in d0 survives to the button check with no save needed.
		move.b	#0,(port_2_data).l			; poll pad 2, both TH phases
		nop
		nop
		move.b	(port_2_data).l,d0
		lsl.b	#2,d0					; A,Start -> bits 6,7
		andi.b	#$C0,d0
		move.b	#$40,(port_2_data).l
		nop
		nop
		move.b	(port_2_data).l,d1
		andi.b	#$3F,d1
		or.b	d1,d0					; d0 = Start A C B R L D U (active low)
		not.b	d0					; 1 = pressed
		move.b	syz_prevbtn(a0),d4			; d4 = buttons held last frame (weapon edge-detect)
		move.b	d0,syz_prevbtn(a0)			; remember this frame's buttons for next time
		move.w	#0,obVelX(a0)				; idle unless P2 pushes
		btst	#bitL,d0				; left?
		beq.s	.notleft
		cmpi.w	#boss_syz_x+8,obBossX(a0)		; already at the left wall?
		ble.s	.notleft
		move.w	#-$140,obVelX(a0)
		bclr	#0,obStatus(a0)				; face left
	.notleft:
		btst	#bitR,d0				; right?
		beq.s	.notright
		cmpi.w	#boss_syz_x+$138,obBossX(a0)		; already at the right wall?
		bge.s	.notright
		move.w	#$140,obVelX(a0)
		bset	#0,obStatus(a0)				; face right
	.notright:
		tst.w	obVelX(a0)				; only fire/smash when planted
		bne.w	BSYZ_CalcSine
		; sonic-vs-robotnik: in the SWISS ARMY KNIFE bonus (row 4), A = flamethrower;
		; B/C stay the block smash. In the plain Spring Yard duel, A/B/C all smash.
		cmpi.w	#4,(v_levselitem).w			; Swiss Army Knife?
		bne.s	.checksmash				; plain duel: A/B/C all smash
		btst	#bitB,d0				; super: B still smashes (no reload)
		bne.s	.smash
		tst.b	syz_reload(a0)				; A/C ranged weapons still reloading?
		beq.s	.superready
		subq.b	#1,syz_reload(a0)
		bra.w	BSYZ_CalcSine				; reloading -> A/C do nothing
	.superready:
		move.b	d0,d2					; edge = pressed-now AND NOT held-last-frame
		not.b	d4
		and.b	d4,d2					; d2 = buttons freshly pressed this frame
		btst	#bitA,d2				; A just pressed -> flamethrower
		bne.w	.superfire
		btst	#bitC,d2				; C just pressed -> bomb
		bne.w	.superbomb
		bra.w	BSYZ_CalcSine
	.checksmash:
		btst	#bitB,d0				; smash the block under Eggman
		bne.s	.smash
		btst	#bitC,d0
		bne.s	.smash
		btst	#bitA,d0
		beq.w	BSYZ_CalcSine
	.smash:
		move.w	obBossX(a0),d0				; which block is Eggman over?
		subi.w	#boss_syz_x,d0
		lsr.w	#5,d0					; /32 = block index
		move.b	d0,BossSpringYard_BlockIndex(a0)
		asl.w	#5,d0					; back to the block's centre X
		addi.w	#boss_syz_x+$10,d0
		move.w	d0,obBossX(a0)				; snap onto it
		bsr.w	BossSpringYard_FindBlocks		; -> ObjPointer = that floor block
		addq.b	#2,ob2ndRout(a0)			; ShipMove -> Attack (descend, grab, break)
		clr.w	obSubtype(a0)
		clr.w	obVelX(a0)
		bra.w	BSYZ_CalcSine
; ===========================================================================
	.superfire:
		move.b	#syz_fire_frames,syz_reload(a0)		; start the (longer) fire reload first (holds even if no free slot)
		jsr	(FindFreeObj).l				; drop a Marble-style fireball at Eggman
		bne.w	BSYZ_CalcSine
		move.w	obBossX(a0),obX(a1)
		move.w	obBossY(a0),obY(a1)
		addi.w	#$18,obY(a1)				; from just below the ship
		move.b	#id_BossFire,obID(a1)
		move.b	#1,obSubtype(a1)			; subtype 1 = real fire: falls, spreads on the floor
		bra.w	BSYZ_CalcSine
; ===========================================================================
	.superbomb:
		move.b	#syz_reload_frames,syz_reload(a0)	; start the reload first (holds even if no free slot)
		jsr	(FindFreeObj).l				; drop a spike bomb at Eggman (art loaded via PLC_Boss)
		bne.w	BSYZ_CalcSine
		move.w	obBossX(a0),obX(a1)
		move.w	obBossY(a0),obY(a1)
		addi.w	#$18,obY(a1)
		move.b	#id_BossSpikeball,obID(a1)		; standalone: its Main sees the SYZ arena, skips the seesaw
		bra.w	BSYZ_CalcSine
; ===========================================================================

; loc_192EC:
BSYZ_Attack:
		moveq	#0,d0
		move.b	obSubtype(a0),d0			; copy object routine
		move.w	BSYZ_Attack_Index(pc,d0.w),d0		; use the object routine index and Attack index to calculate our offset
		jmp	BSYZ_Attack_Index(pc,d0.w)		; jump into the table and use our offset to pick a routine in the index to go to
; ===========================================================================
BSYZ_Attack_Index:
		dc.w BSYZ_Descend-BSYZ_Attack_Index
		dc.w BSYZ_Lift-BSYZ_Attack_Index
		dc.w BSYZ_LiftStop-BSYZ_Attack_Index
		dc.w BSYZ_BreakBlock-BSYZ_Attack_Index
; ===========================================================================

; loc_19302:
BSYZ_Descend:
		move.w	#$180,obVelY(a0)			; start lowering
		move.w	obBossY(a0),d0				; copy boss position
		cmpi.w	#boss_syz_y+$8A,d0			; have we reached the blocks yet?
		blo.s	.exit					; if not, keep moving
		move.w	#boss_syz_y+$8A,obBossY(a0)		; snap Eggman onto floor
		clr.w	BossSpringYard_GenericTimer(a0)		; clear the timer
		moveq	#-1,d0
		move.w	BossSpringYard_ObjPointer(a0),d0	; copy memory address of block
		beq.s	.lift					; Defensive check, block object doesn't exist, so branch
		movea.l	d0,a1					; move address of block object
		move.b	#-1,BossSpringYard_ChildCmd(a1)		; set block to grabbed state
		move.b	#-1,BossSpringYard_ChildCmd(a0)		; turn off spike collision
		move.l	a0,BossSpringYard_ParentObj(a1)		; copy memory address of boss controller object
		move.w	#50,BossSpringYard_GenericTimer(a0)	; set a timer for 50 frames

; loc_1933C:
.lift:
		clr.w	obVelY(a0)				; stop moving downwards
		addq.b	#2,obSubtype(a0)			; increment routine

; loc_19344:
.exit:
		bra.w	BSYZ_MoveUpdate
; ===========================================================================

; loc_19348:
BSYZ_Lift:
		subq.w	#1,BossSpringYard_GenericTimer(a0)	; subtract 1 from timer (this updates PhaseTimer too because of where the offsets are located and big endian concepts!)
		bpl.s	.shakeCheck				; is timer still positive? if yes, branch
		addq.b	#2,obSubtype(a0)			; increment routine
		move.w	#-$800,obVelY(a0)			; start rising upwards rapidly
		tst.w	BossSpringYard_ObjPointer(a0)		; is a block present?
		bne.s	.skip					; yes, branch
		asr.w	obVelY(a0)				; divide by 2, slow velocity down in half

; loc_19362:
.skip:
		moveq	#0,d0					; clear in order to manipulate velocity
		bra.s	.movePosition
; ===========================================================================

; loc_19366:
.shakeCheck:
		moveq	#0,d0					; clear in order to manipulate velocity
		cmpi.w	#30,BossSpringYard_GenericTimer(a0)	; have we gone below 30 frames (we are subtracting above, so 50-20)
		bgt.s	.movePosition				; if not, branch, we have grabbed the block but we haven't started shaking yet
		moveq	#2,d0
		btst	#1,BossSpringYard_PhaseTimer(a0)	; has two frames passed?
		beq.s	.movePosition				; if so, branch
		neg.w	d0

; loc_1937C:
.movePosition:
		add.w	obBossY(a0),d0				; add boss position to calculated offset
		move.w	d0,obY(a0)				; move this offset into object Y position
		move.w	obBossX(a0),obX(a0)			; copy boss X position
		bra.w	BSYZ_StatusUpdate
; ===========================================================================

; loc_1938E:
BSYZ_LiftStop:
		move.w	#boss_syz_y+$E,d0			; move top bound plus offset
		cmpi.w	#4,(v_levselitem).w			; sonic-vs-robotnik: super Eggman rises back only to
		bne.s	.rhset					; the LOW super height (else B sends him back up high)
		move.w	#syz_super_y,d0
		bra.s	.checkPosition				; ...and skip the vanilla -$18 extra lift
	.rhset:
		tst.w	BossSpringYard_ObjPointer(a0)		; is the spike object present?
		beq.s	.checkPosition				; if not, branch
		subi.w	#$18,d0					; make Eggman lift slightly higher than usual with this offset

; loc_1939C:
.checkPosition:
		cmp.w	obBossY(a0),d0				; have we reached the offset?
		blt.s	.checkSpeed				; if yes, branch
		move.w	#8,BossSpringYard_GenericTimer(a0)	; set a timer for 8 frames
		tst.w	BossSpringYard_ObjPointer(a0)		; is the spike object present?
		beq.s	.skip					; if not, branch and skip new timer
		move.w	#45,BossSpringYard_GenericTimer(a0)	; set a timer for 45 frames (this makes him sit while the spike is retracting)

; loc_193B4
.skip:
		addq.b	#2,obSubtype(a0)			; increment routine
		clr.w	obVelY(a0)				; stop moving vertically
		bra.s	.exit
; ===========================================================================

; loc_193BE:
.checkSpeed:
		cmpi.w	#-$40,obVelY(a0)			; are we moving this speed or faster?
		bge.s	.exit					; if yes, branch
		addi.w	#$C,obVelY(a0)				; no, so speed up

; loc_193CC:
.exit:
		bra.w	BSYZ_MoveUpdate
; ===========================================================================

; loc_193D0:
BSYZ_BreakBlock:
		subq.w	#1,BossSpringYard_GenericTimer(a0)	; subtract 1 from timer
		bgt.s	.updatePosition				; has the timer hit 0? if not, branch
		bmi.s	.endAttack				; has the timer gone below 0? if so, branch
		moveq	#-1,d0
		move.w	BossSpringYard_ObjPointer(a0),d0	; set d1 to contain the exact RAM address of the block object
		beq.s	.skip					; if the object doesn't exist, branch (since its a word operation, it will return 0 if the first two bytes of the address are 0s)
		movea.l	d0,a1					; copy address
		move.b	#$A,BossSpringYard_ChildCmd(a1)		; send $A to the command offset for the object found above, now when that object's routine is ran, it will have this value in its own offset (because we are writing to the address in a1, which is our object)

; loc_193E8:
.skip:
		clr.w	BossSpringYard_ObjPointer(a0)		; remove reference to object (this sets up bobbing motion later)
		bra.s	.updatePosition
; ===========================================================================

; loc_193EE:
.endAttack
		cmpi.w	#-30,BossSpringYard_GenericTimer(a0)	; has the timer gone below -30?
		bne.s	.updatePosition				; if yes, branch
		clr.b	BossSpringYard_ChildCmd(a0)		; clear scratch RAM offset so that spike is dangerous again
		subq.b	#2,ob2ndRout(a0)			; decrement routine counter
		move.b	#-1,BossSpringYard_PhaseTimer(a0)	; set the phase timer to FF, this will cause him to not attack until he hits a screen boundary as shown above
		bra.s	.exit
; ===========================================================================

; loc_19406:
.updatePosition:
		moveq	#1,d0
		tst.w	BossSpringYard_ObjPointer(a0)		; does the block exist?
		beq.s	.clampRestY				; if not, branch
		moveq	#2,d0					; set offset to 2

; loc_19410:
.clampRestY:
		move.w	#boss_syz_y+$E,d1			; vanilla rest height (near the top)
		cmpi.w	#4,(v_levselitem).w			; sonic-vs-robotnik: super Eggman drifts back to the
		bne.s	.rhset2					; LOW rest height, so a block grab no longer drags
		move.w	#syz_super_y,d1				; him back up to the top after breaking it
	.rhset2:
		move.w	obBossY(a0),d3
		cmp.w	d1,d3					; has Eggman returned to his rest position?
		beq.s	.shakeOffset				; if yes, branch
		blt.s	.applyMove				; if he is higher, branch
		neg.w	d0					; negate d0 to move him up

; loc_1941C:
.applyMove:
		tst.w	BossSpringYard_ObjPointer(a0)		; does the block exist (dead code?)
		add.w	d0,obBossY(a0)				; add offset to Y position

; loc_19424
.shakeOffset:
		moveq	#0,d0
		tst.w	BossSpringYard_ObjPointer(a0)		; does the block exist?
		beq.s	.setPosition				; if not, branch, we don't shake if there is no block attached
		moveq	#2,d0
		btst	#0,BossSpringYard_PhaseTimer(a0)	; is the timer on an even frame (every other frame)?
		beq.s	.setPosition				; if yes, branch
		neg.w	d0					; negate to apply the shaking motion

; loc_19438:
.setPosition:
		add.w	obBossY(a0),d0				; add offset to Y position
		move.w	d0,obY(a0)				; copy Y position
		move.w	obBossX(a0),obX(a0)			; copy X position

; loc_19446:
.exit:
		bra.w	BSYZ_StatusUpdate
; ===========================================================================

BossSpringYard_FindBlocks:
		clr.w	BossSpringYard_ObjPointer(a0) 	; clear the spike pointer address
	if FixBugs
		lea	(v_lvlobjspace).w,a1
		moveq	#(v_lvlobjend-v_lvlobjspace)/object_size-1,d0
	else
		lea	(v_objspace+object_size*1).w,a1 ; Nonsensical starting point, since dynamic object allocations begin at v_lvlobjspace.
		moveq	#(v_objspace_end-(v_objspace+object_size*1))/object_size/2-1,d0	; Nonsensical length, it only covers the first half of object RAM.
	endif
		moveq	#id_BossBlock,d1			; set objectID for loop below
		move.b	BossSpringYard_BlockIndex(a0),d2	; copy index calculated up in StatusUpdate to d2 so d2 contains the block he is over

BossSpringYard_FindLoop:
		cmp.b	obID(a1),d1				; is object a SYZ boss block?
		bne.s	.skip					; if not, branch
		cmp.b	obSubtype(a1),d2			; is this the specific block we are hovering over? (in 76 SYZ Boss Blocks.asm each block's subtype contains its index)
		bne.s	.skip					; if not, branch
		move.w	a1,BossSpringYard_ObjPointer(a0)	; store block address
		bra.s	.exit					; proper block found, exit
; ===========================================================================

; loc_1946A:
.skip:
		lea	object_size(a1),a1			; next object RAM entry
		dbf	d0,BossSpringYard_FindLoop 		; move to next object in RAM and loop again

; locret_19472:
.exit:
		rts
; End of function BossSpringYard_FindBlocks

; ===========================================================================

; loc_19474:
BSYZ_Explode:
		subq.w	#1,BossSpringYard_GenericTimer(a0)	; are we done exploding?
		bmi.s	.transition				; yes, start transitioning to next routine/state
		bra.w	BossDefeated
; ===========================================================================

; loc_1947E:
.transition:
		addq.b	#2,ob2ndRout(a0)			; advance routine to Recover
		clr.w	obVelY(a0)				; stop vertical movement
		bset	#0,obStatus(a0)				; set the X flip bit so we are facing right
		bclr	#7,obStatus(a0)				; clear the defeated flag
		clr.w	obVelX(a0)				; stop horizontal movement
		move.w	#-1,BossSpringYard_GenericTimer(a0)	; set a timer for 1 frame
		tst.b	(v_bossstatus).w			; has boss been marked as defeated?
		bne.s	.skip					; yes, skip
		move.b	#1,(v_bossstatus).w			; no, mark it as defeated but not capsule opened

; loc_194A8:
.skip:
		bra.w	BSYZ_StatusUpdate
; ===========================================================================

; loc_194AC:
BSYZ_Recover:
		addq.w	#1,BossSpringYard_GenericTimer(a0)	; increment timer
		beq.s	.doneFalling				; if the timer has hit 0, branch here
		bpl.s	.timerPositive				; if the timer has hit a positive value, branch here
		addi.w	#$18,obVelY(a0)				; make Eggman fall a little faster
		bra.s	.exit
; ===========================================================================

; loc_194BC:
.doneFalling:
		clr.w	obVelY(a0)

; Because Eggman moves vertically in this fight, the timer above is so short, this makes sure he doesn't fall off the screen under any circumstances and just stays where he is
; They could have also checked his Y position to stop falling, but that is a minor detail.

		bra.s	.exit
; ===========================================================================

; loc_194C2:
.timerPositive:
		cmpi.w	#32,BossSpringYard_GenericTimer(a0)	; is the timer below 32?
		blo.s	.rise					; if yes, start to rise
		beq.s	.playMusic				; stop and play music
		cmpi.w	#42,BossSpringYard_GenericTimer(a0)	; is the timer below 42?
		blo.s	.exit					; if yes, come back later (we are still going to recover)
		addq.b	#2,ob2ndRout(a0)			; increment routine to Escape
		bra.s	.exit
; ===========================================================================

; loc_194DA:
.rise:
		subq.w	#8,obVelY(a0)				; slow down, eventually causing him to rise upwards (in this case, only rise for a little due to shortened timer)
		bra.s	.exit
; ===========================================================================

; loc_194E0
.playMusic:
		clr.w	obVelY(a0)				; clear Y velocity
		move.w	#bgm_SYZ,d0
		jsr	(QueueSound1).l				; play SYZ music

; loc_194EE:
.exit:
		bra.w	BSYZ_MoveUpdate
; ===========================================================================

; loc_194F2:
BSYZ_Escape:
		move.w	#$400,obVelX(a0)			; move to the right quickly
		move.w	#-$40,obVelY(a0)			; move up a little bit
		cmpi.w	#boss_syz_end,(v_limitright2).w		; have we finished scrolling to the right (reached level bounds)?
		bhs.s	.checkOffScreen				; if yes, branch
		addq.w	#2,(v_limitright2).w			; keep unlocking the bounds of the screen by 2 pixels
		bra.s	.flee
; ===========================================================================

; loc_1950C:
.checkOffScreen:
		tst.b	obRender(a0)
		bpl.s	BossSpringYard_ShipDelete

; loc_19512
.flee:
		bsr.w	BossMove
		bra.w	BSYZ_CalcSine
; ===========================================================================

BossSpringYard_ShipDelete:
		move.b	#id_Title,(v_gamemode).w		; sonic-vs-robotnik: Eggman fled -> P2 wins -> level picker
	if FixBugs
		; Avoid returning to BossSpringYard_ShipMain to prevent a
		; display-and-delete bug.
		addq.l	#4,sp
	endif
		jmp	(DeleteObject).l
; ===========================================================================

BossSpringYard_FaceMain:	; Routine 4
		moveq	#1,d1					; set up facenormal1 animation
		movea.l	BossSpringYard_ParentObj(a0),a1		; load the main boss controller
		moveq	#0,d0
		move.b	ob2ndRout(a1),d0			; load face phase
		move.w	BSYZ_FaceMain_Index(pc,d0.w),d0		; use the object routine index and BSYZ_FaceMain_Index to calculate our offset
		jsr	BSYZ_FaceMain_Index(pc,d0.w)		; jump into the table and use our offset to pick a routine in the index to go to
		move.b	d1,obAnim(a0)				; set facenormal1 animation
		move.b	(a0),d0					; copy boss object
		cmp.b	(a1),d0					; are the IDs the same?
		bne.s	BossSpringYard_FaceDelete		; if not, delete
		bra.s	BossSpringYard_SetupAnim				;
; ===========================================================================

BossSpringYard_FaceDelete:
		jmp	(DeleteObject).l
; ===========================================================================
BSYZ_FaceMain_Index:
		dc.w BSYZ_Face_ChkHit-BSYZ_FaceMain_Index
		dc.w BSYZ_Face_ChkHit-BSYZ_FaceMain_Index
		dc.w BSYZ_Face_Attack-BSYZ_FaceMain_Index
		dc.w BSYZ_Face_Defeat-BSYZ_FaceMain_Index
		dc.w BSYZ_Face_Defeat-BSYZ_FaceMain_Index
		dc.w BSYZ_Face_Escape-BSYZ_FaceMain_Index
; ===========================================================================

; loc_19552:
BSYZ_Face_Defeat:
		moveq	#$A,d1					; set defeated animation
		rts
; ===========================================================================

; loc_19556:
BSYZ_Face_Escape:
		moveq	#6,d1					; set panic/escape animation
		rts
; ===========================================================================

; loc_1955A:
BSYZ_Face_Attack:
		moveq	#0,d0
		move.b	obSubtype(a1),d0			; load obsubtype to use as indexer
		move.w	BSYZ_FaceAttack_Index(pc,d0.w),d0	; use the object routine index and BSYZ_FaceAttack_Index to calculate our offset
		jmp	BSYZ_FaceAttack_Index(pc,d0.w)		; jump into the table and use our offset to pick a routine in the index to go to
; ===========================================================================
BSYZ_FaceAttack_Index:
		dc.w BSYZ_Face_Attack_Other-BSYZ_FaceAttack_Index
		dc.w BSYZ_Face_Attack_Lift-BSYZ_FaceAttack_Index
		dc.w BSYZ_Face_Attack_Other-BSYZ_FaceAttack_Index
		dc.w BSYZ_Face_Attack_Other-BSYZ_FaceAttack_Index
; ===========================================================================

; loc_19570:
BSYZ_Face_Attack_Other:
		bra.s	BSYZ_Face_ChkHit
; ===========================================================================

; loc_19572:
BSYZ_Face_Attack_Lift:
		moveq	#6,d1					; set lifting block animation

; loc_19574:
BSYZ_Face_ChkHit:
		tst.b	obColType(a1)				; is the boss hittable?
		bne.s	.checkSonicState			; if not, branch
		moveq	#5,d1					; set animation to facehit
		rts
; ===========================================================================

; loc_1957E:
.checkSonicState:
		cmpi.b	#4,(v_player+obRoutine).w		; is sonic in his hurt state?
		blo.s	.exit					; if not, branch
		moveq	#4,d1					; set animation to facelaugh

; locret_19588:
.exit:
		rts
; ===========================================================================

BossSpringYard_FlameMain:; Routine 6
		move.b	#7,obAnim(a0)				; set animation state to 7 (default invisible state for flame)
		movea.l	BossSpringYard_ParentObj(a0),a1		; load main boss controller
		cmpi.b	#$A,ob2ndRout(a1)			; are we in escape state?
		bne.s	.checkMove				; no, check movement
		move.b	#$B,obAnim(a0)				; set thruster animation for takeoff
		tst.b	obRender(a0)				; what is our screen status?
		bpl.s	BossSpringYard_FlameDelete		; off screen, delete
		bra.s	.skip					; on screen, display
; ===========================================================================

; loc_195AA:
.checkMove:
		tst.w	obVelX(a1)				; are we currently moving?
		beq.s	.skip					; no, don't display flame
		move.b	#8,obAnim(a0)				; yes, display flame

; loc_195B6:
.skip:
		bra.s	BossSpringYard_SetupAnim
; ===========================================================================

BossSpringYard_FlameDelete:
		jmp	(DeleteObject).l
; ===========================================================================

; loc_195BE:
BossSpringYard_SetupAnim:
		lea	(Ani_Eggman).l,a1			; load animations
		jsr	(AnimateSprite).l
		movea.l	BossSpringYard_ParentObj(a0),a1		; load main boss controller
		move.w	obX(a1),obX(a0)				; copy boss positions to flame position
		move.w	obY(a1),obY(a0)

; loc_195DA:
BossSpringYard_Display:
		move.b	obStatus(a1),obStatus(a0)		; copy object status to boss object status
		moveq	#sprite_xflip|sprite_yflip,d0		; set a mask for both flip bits
		and.b	obStatus(a0),d0				; AND obstatus with those flip bits
		andi.b	#~(sprite_xflip|sprite_yflip),obRender(a0) ; clear the x and y flip
		or.b	d0,obRender(a0)				; OR the two together, so now DisplaySprite has X and Y orientation and above render bits
		jmp	(DisplaySprite).l
; ===========================================================================

BossSpringYard_SpikeMain:; Routine 8
		move.l	#Map_BossItems,obMap(a0)		; load mappings and art
		move.w	#ArtTile_Eggman_Weapons|Tile_Pal2,obGfx(a0)
		move.b	#5,obFrame(a0)				; set current animation frame
		movea.l	BossSpringYard_ParentObj(a0),a1		; load main boss controller
		cmpi.b	#$A,ob2ndRout(a1)			; are we in escape state?
		bne.s	.spikeMove				; no, run movement
		tst.b	obRender(a0)				; what is our screen status?
		bpl.s	BossSpringYard_SpikeDelete		; off screen, so delete

; loc_1961C:
.spikeMove:
		move.w	obX(a1),obX(a0)				; copy positions
		move.w	obY(a1),obY(a0)
		move.w	BossSpringYard_GenericTimer(a0),d0	; set up offset for use for vertical displacement of spike
		cmpi.b	#4,ob2ndRout(a1)			; are we in flame (aka currently moving?)
		bne.s	.retract				; no, need to retract spike
		cmpi.b	#6,obSubtype(a1)			; are we currently breaking a block (routine 6 of Attack_Index)
		beq.s	.checkBreakTimer			; if yes, branch
		tst.b	obSubtype(a1)				; are we in the descend phase?
		bne.s	.applyPosition				; if not, branch
		cmpi.w	#$94,d0					; has the spike fully extended?
		bge.s	.applyPosition				; if so, branch
		addq.w	#7,d0					; keep extending
		bra.s	.applyPosition
; ===========================================================================

; loc_1964C:
.checkBreakTimer:
		tst.w	BossSpringYard_GenericTimer(a1)		; is Eggman's timer negative?
		bpl.s	.applyPosition				; if not, branch

; loc_19652:
.retract:
		tst.w	d0					; has the spike fully retracted?
		ble.s	.applyPosition				; if so, branch
		subq.w	#5,d0					; keep retracting

; loc_19658:
.applyPosition:
		move.w	d0,BossSpringYard_GenericTimer(a0)	; copy back to offset for later
		asr.w	#2,d0					; divide by 4
		add.w	d0,obY(a0)				; add calculated position to Y
		move.b	#16/2,obActWid(a0)			; set radius of object in pixels
		move.b	#24/2,obHeight(a0)			; set height
		clr.b	obColType(a0)				; disable collision to start
		movea.l	BossSpringYard_ParentObj(a0),a1		; load boss controller
		tst.b	obColType(a1)				; does Eggman have collision?
		beq.s	.display				; if not, branch
		tst.b	BossSpringYard_ChildCmd(a1)		; are we currently breaking a block or holding one?
		bne.s	.display				; if yes, branch
		move.b	#col_8x32|col_hurt,obColType(a0)	; set collision type of spike

; loc_19688:
.display:
		bra.w	BossSpringYard_Display
; ===========================================================================

BossSpringYard_SpikeDelete:
		jmp	(DeleteObject).l


; ===========================================================================
; ---------------------------------------------------------------------------
; Object 76 - blocks that Eggman picks up (SYZ)
; ---------------------------------------------------------------------------

BossBlock:
		moveq	#0,d0
		move.b	obRoutine(a0),d0			; copy object routine
		move.w	BossBlock_Index(pc,d0.w),d1		; use the object routine index and BossBlock_Index to calculate our offset
		jmp	BossBlock_Index(pc,d1.w)		; jump into the table and use our offset to pick a routine in the index to go to
; ===========================================================================
BossBlock_Index:
		dc.w BossBlock_Main-BossBlock_Index
		dc.w BossBlock_Action-BossBlock_Index
		dc.w BossBlock_Frag-BossBlock_Index
; ===========================================================================

BossBlock_Main:	; Routine 0
		moveq	#0,d4					; clear register to set up for block index
		move.w	#boss_syz_x+$10,d5			; X position of very first block
		moveq	#9,d6					; set up loop total
		lea	(a0),a1					; load first block into next block (used to find a free object slot)
		bra.s	BossBlock_MakeBlock
; ===========================================================================

BossBlock_Loop:
		jsr	(FindFreeObj).l
		bne.s	BossBlock_ExitLoop

BossBlock_MakeBlock:
		move.b	#id_BossBlock,obID(a1)			; set object ID
		move.l	#Map_BossBlock,obMap(a1)		; set mappings, art, and render flags
		move.w	#ArtTile_Level|Tile_Pal3,obGfx(a1)
		move.b	#sprite_cam_field,obRender(a1)
		move.b	#32/2,obActWid(a1)			; set object radius and height
		move.b	#32/2,obHeight(a1)
		move.b	#3,obPriority(a1)			; set object priority (higher priority)
		move.w	d5,obX(a1)				; set x-position
		move.w	#$582,obY(a1)				; set Y position so all blocks are on the floor
		move.w	d4,obSubtype(a1)			; set subtype to 0 and childcmd to 0
		addi.w	#$101,d4				; increment both bytes (block 0 gets 0 0 block 1 gets 1 1 etc)
		addi.w	#$20,d5					; add $20 to next x-position
		addq.b	#2,obRoutine(a1)			; increment routine of clone (so that it doesn't start looping again)
		dbf	d6,BossBlock_Loop			; repeat sequence 9 more times

BossBlock_ExitLoop:
		rts
; ===========================================================================

BossBlock_Action:	; Routine 2
		move.b	BossSpringYard_ChildCmd(a0),d0		; copy command status
		cmp.b	obSubtype(a0),d0			; are we currently sending NO command to this current block index (so that we don't break or modify the wrong block, anything greater than -1 and less than 9 is treated as a solid block)
		beq.s	BossBlock_Solid				; if yes, branch
		tst.b	d0					; has the block been grabbed?
		bmi.s	.blockGrabbed				; if yes, branch

; loc_19712:
.break:
		bsr.w	BossBlock_Break				; block must be in state "break" so branch
		bra.s	BossBlock_Display
; ===========================================================================

; loc_19718:
.blockGrabbed:
		movea.l	BossSpringYard_ParentObj(a0),a1		; copy boss controller
		tst.b	obBossHits(a1)				; do we still have hits remaining?
		beq.s	.break					; if not, break anyways, boss was defeated mid grab
		move.w	obX(a1),obX(a0)				; copy positions
		move.w	obY(a1),obY(a0)
		addi.w	#44,obY(a0)				; set y to 44 pixels below boss
		cmpa.w	a0,a1					; is the boss address higher than the block address?
		blo.s	BossBlock_Display			; the boss address is lower, meaning the boss has already moved, so just branch
		move.w	obVelY(a1),d0				; the boss address is higher, Eggman has not been processed yet in the queue, so copy Y velocity
		ext.l	d0					; long-extend velocity
		asr.l	#8,d0					; divide by 256 to convert to pixels
		add.w	d0,obY(a0)				; copy back to Y and try to predict where boss will be
		bra.s	BossBlock_Display
; ===========================================================================

BossBlock_Solid:
		move.w	#16+sonic_solid_width,d1		; set half width + sonic's width
		move.w	#16,d2					; set top height
		move.w	#17,d3					; set bottom height
		move.w	obX(a0),d4				; copy center X
		jsr	(SolidObject).l

BossBlock_Display:
		jmp	(DisplaySprite).l
; ===========================================================================

; loc_19762:
BossBlock_Frag:	; Routine 4
		tst.b	obRender(a0)				; is the block currently visible?
		bpl.s	BossBlock_Delete			; if not, branch
		jsr	(ObjectFall).l
		jmp	(DisplaySprite).l
; ===========================================================================

BossBlock_Delete:
		jmp	(DeleteObject).l
; ===========================================================================

BossBlock_Break:
		lea	BossBlock_FragSpeed(pc),a4		; load speed and position table
		lea	BossBlock_FragPos(pc),a5
		moveq	#1,d4					; set inital frame for fragments to 1
		moveq	#3,d1					; set loop amount (4 for 4 fragments)
		moveq	#gravity,d2				; unused leftover from SmashObject
		addq.b	#2,obRoutine(a0)			; increment routine counter
		move.b	#16/2,obActWid(a0)			; set object radius to 8
		move.b	#16/2,obHeight(a0)			; set object height radius to 8
		lea	(a0),a1					; copy object
		bra.s	BossBlock_MakeFrag
; ===========================================================================

BossBlock_LoopFrag:
		jsr	(FindNextFreeObj).l
		bne.s	BossBlock_Done				; if no free objects are found, skip ahead

BossBlock_MakeFrag:
		lea	(a0),a2					; copy object
		lea	(a1),a3					; copy object's copy (this will contain a new object slot in future loops)
		moveq	#3,d3					; set first loop to 4

; loc_197AA:
.loop:
		move.l	(a2)+,(a3)+				; copy 4 bytes of original object to new object and increment pointer
		move.l	(a2)+,(a3)+
		move.l	(a2)+,(a3)+
		move.l	(a2)+,(a3)+				; 64 bytes total
		dbf	d3,.loop

		move.w	(a4)+,obVelX(a1)			; copy frag speed from table into new object
		move.w	(a4)+,obVelY(a1)
		move.w	(a5)+,d3				; copy frag pos X and increment table index
		add.w	d3,obX(a1)				; set new object position X
		move.w	(a5)+,d3				; copy frag pos Y and increment table index
		add.w	d3,obY(a1)				; set new object position Y
		move.b	d4,obFrame(a1)				; set frame for fragment
		addq.w	#1,d4					; increment frame counter for next fragment
		dbf	d1,BossBlock_LoopFrag 			; repeat sequence 3 more times

; loc_197D4:
BossBlock_Done:
		move.w	#sfx_WallSmash,d0
		jmp	(QueueSound2).l				; play smashing sound
; End of function BossBlock_Break

; ===========================================================================
BossBlock_FragSpeed:
		dc.w -$180, -$200				; top left
		dc.w $180, -$200				; top right
		dc.w -$100, -$100				; bottom left
		dc.w $100, -$100				; bottom right

BossBlock_FragPos:
		dc.w -8, -8					; top left
		dc.w $10, 0					; top right
		dc.w 0,	$10					; bottom left
		dc.w $10, $10					; bottom right
; ===========================================================================

Map_BossBlock:	include	"_maps/SYZ Boss Blocks.asm"
