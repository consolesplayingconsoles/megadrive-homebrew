; ===========================================================================
; ---------------------------------------------------------------------------
; Object 73 - Eggman (MZ)
; ---------------------------------------------------------------------------

BossMarble:
		moveq	#0,d0
		move.b	obRoutine(a0),d0			; copy object routine
		move.w	BossMarble_Index(pc,d0.w),d1		; use the object routine index and BossMarble_Index to calculate our offset
		jmp	BossMarble_Index(pc,d1.w)		; jump into the table and use our offset to pick a routine in the index to go to
; ===========================================================================
BossMarble_Index:
		dc.w BossMarble_Main-BossMarble_Index
		dc.w BossMarble_ShipMain-BossMarble_Index
		dc.w BossMarble_FaceMain-BossMarble_Index
		dc.w BossMarble_FlameMain-BossMarble_Index
		dc.w BossMarble_TubeMain-BossMarble_Index

BossFire_GenericTimer:	equ objoff_29				; timer used for fireball that is spawned by Eggman, as well as used for a counter
BossFire_SpreadX:	equ objoff_32				; scratch RAM used to save X of where the first fireball hit
BossMarble_ParentObj:	equ objoff_34 				; Pointer to main boss controller
BossMarble_LavaTimer:	equ objoff_34				; countdown for lava spawn timer
BossMarble_GenericTimer:equ objoff_3C				; timer for how many frames to do an action, whether its wait for explosions, or to move in a direction
BossMarble_SineCounter:	equ objoff_3F				; sine counter for bobbing motion

; sonic-vs-robotnik: player 2 drives the MZ boss. obSubtype drove the swoop/fire
; AI dispatch (gone here) and is cleared to 0 by ShipStart's transition, so reuse
; it as the flame-gun reload counter. (objoff_34 aliases the boss self-pointer
; ParentObj and was NOT a reliable zero, hence an earlier no-fire bug.)
mz_fire_reload:		equ obSubtype				; post-shot freeze counter (no move + no fire)
mz_reload_frames:	equ 48					; 0.8s frozen after each shot (snappy: fire's away, back in the fight)
; ===========================================================================

BossMarble_ObjData:
		; routine number, animation, priority
		dc.b 2,	0, 4
		dc.b 4,	1, 4
		dc.b 6,	7, 4
		dc.b 8,	0, 3
; ===========================================================================

BossMarble_Main:	; Routine 0
		move.w	obX(a0),obBossX(a0)			; copy to boss position using scratch RAM (objoff_30 and 38 respectively)
		move.w	obY(a0),obBossY(a0)
		move.b	#col_48x48|col_boss,obColType(a0)	; set collision type: TTSS SSSS. T bits are for type, S is size of collision using table in sub ReactToItem.asm
		move.b	#8,obBossHits(a0) 			; set number of hits to 8
		lea	BossMarble_ObjData(pc),a2		; load routine data address into a2 (this does one less memory access than the GHZ boss, its faster and it seems the developers wanted to stick with PC-relative going forward)
		movea.l	a0,a1					; copy boss object address into a1 so that LoadBoss on pass 1 uses the main boss object.
		moveq	#3,d1					; 4 slots of ObjData, so to load properly we must loop 4 times
		bra.s	BossMarble_LoadBoss
; ===========================================================================

BossMarble_Loop:
		jsr	(FindNextFreeObj).l			; are there any free objects?
		bne.s	BossMarble_ShipMain			; no, leave early
		_move.b	#id_BossMarble,obID(a1)			; set object ID for this slot
		move.w	obX(a0),obX(a1)				; set object position to boss position
		move.w	obY(a0),obY(a1)

BossMarble_LoadBoss:
		bclr	#0,obStatus(a0)				; clear the x orientation bit
		clr.b	ob2ndRout(a1)				; clear second routine status (ShipIndex below)
		move.b	(a2)+,obRoutine(a1)			; load first objData byte and increment
		move.b	(a2)+,obAnim(a1)
		move.b	(a2)+,obPriority(a1)
		move.l	#Map_Eggman,obMap(a1)			; load mappings and graphics for the object
		move.w	#ArtTile_Eggman,obGfx(a1)
		move.b	#sprite_cam_field,obRender(a1)		; set the object to position based on where it is in the level and not a static position on screen
		move.b	#64/2,obActWid(a1)			; set collision to 20 pixel radius box

; objoff_34 is used here as a reference back to the main boss controller.
; This is because when we are in ExecuteObjects, a0 is set to each object and sub objects own slot, so we need a way to find the original boss object.
; On the first loop, this copies the address to itself, but the other loops are what it was intended for.
		move.l	a0,BossMarble_ParentObj(a1)

		dbf	d1,BossMarble_Loop			; repeat sequence 3 more times

BossMarble_ShipMain:	; Routine 2
		moveq	#0,d0
		move.b	ob2ndRout(a0),d0			; load secondary routine index of current object slot into d0
		move.w	BossMarble_ShipIndex(pc,d0.w),d1	; use the secondary object routine index and ShipIndex to calculate our offset
		jsr	BossMarble_ShipIndex(pc,d1.w)		; jump into the table and use our offset to pick a routine in the index to go to
		lea	(Ani_Eggman).l,a1
		jsr	(AnimateSprite).l
; ---------------------------------------------------------------------------
; obStatus stores the logical bits, but obRender is visual bits, so this simply moves them from one to the other
; ---------------------------------------------------------------------------
		moveq	#sprite_xflip|sprite_yflip,d0		; move first two bits into d0
		and.b	obStatus(a0),d0				; AND with obStatus so now d0 contains X and Y logical flip bits only
		andi.b	#~(sprite_xflip|sprite_yflip),obRender(a0) ; clear the x and y flip
		or.b	d0,obRender(a0)				; OR the two together, so now DisplaySprite has X and Y orientation and above render bits
		jmp	(DisplaySprite).l
; ===========================================================================
BossMarble_ShipIndex:
		dc.w BMZ_ShipStart-BossMarble_ShipIndex
		dc.w BMZ_ShipMove-BossMarble_ShipIndex
		dc.w BMZ_Explode-BossMarble_ShipIndex
		dc.w BMZ_Recover-BossMarble_ShipIndex
		dc.w BMZ_Escape-BossMarble_ShipIndex
; ===========================================================================

; loc_18302:
BMZ_ShipStart:
		move.b	BossMarble_SineCounter(a0),d0
		addq.b	#2,BossMarble_SineCounter(a0)		; increment sine counter by 2 (to iterate through the sine table)
		jsr	(CalcSine).l				; unlike GHZ, this starts at 2 instead of 0
		asr.w	#2,d0					; shift right by 2 bits (divide by 4), keeping signed number status
		move.w	d0,obVelY(a0)				; offset Y position with sine value
		move.w	#-$100,obVelX(a0)			; set initial X speed (moving to the left)
		bsr.w	BossMove
		cmpi.w	#boss_mz_x+$110,obBossX(a0)		; have we reached our bounds?
		bne.s	.continue				; no, keep going
		addq.b	#2,ob2ndRout(a0)			; increment routine counter by 2 (now in ShipMove)
		clr.b	obSubtype(a0)				; clear object subtype
		clr.l	obVelX(a0)				; stop moving horizontally

; loc_18334
.continue:
		clr.b	mz_fire_reload(a0)			; sonic-vs-robotnik: hand P2 the gun ready to fire

; loc_1833E
BMZ_ShipUpdate:
		move.w	obBossY(a0),obY(a0)			; copy to boss position using scratch RAM (objoff_30 and 38 respectively)
		move.w	obBossX(a0),obX(a0)
		cmpi.b	#4,ob2ndRout(a0)			; are we exploding or escaping?
		bhs.s	.exit					; if yes, branch
		tst.b	obStatus(a0)				; has Eggman's defeated flag been set (bit 7)?
		bmi.s	BMZ_Defeated				; if yes (negative number) branch
		tst.b	obColType(a0)				; is the boss hittable?
		bne.s	.exit					; if not, leave
		tst.b	obBossFlash(a0)				; is this a non-zero value (collision disabled if so, must mean boss is already flashing)
		bne.s	.flash					; we are flashing already, skip ahead
		move.b	#$28,obBossFlash(a0)			; set number of times to flash (for some reason 8 more than most bosses)
		move.w	#sfx_HitBoss,d0
		jsr	(QueueSound2).l				; play boss damage sound

; loc_18374
.flash:
		lea	(v_palette+$22).w,a1			; load 2nd palette, 2nd entry
		moveq	#0,d0					; move 0 (black) to d0
		tst.w	(a1)					; is the color here black? This is a cool trick, since tst will set its flags based on if the value is 0. What color is black? All 0s!
		bne.s	.writeColor				; if not black, already white, so branch
		move.w	#cWhite,d0				; move 0EEE (white) to d0

; loc_18382
.writeColor:
		move.w	d0,(a1)					; load color stored in d0
		subq.b	#1,obBossFlash(a0)			; subtract 1 from flash timer
		bne.s	.exit					; keep flashing if obBossFlash is not 0
		move.b	#col_48x48|col_boss,obColType(a0)	; restore collision, the timer has hit 0

; locret_18390
.exit:
		rts
; ===========================================================================

; loc_18392
BMZ_Defeated:
		moveq	#100,d0
		bsr.w	AddPoints
		move.b	#4,ob2ndRout(a0)			; set object routine to BMZ_Recover
		move.w	#180,BossMarble_GenericTimer(a0)	; set the boss timer
		clr.w	obVelX(a0)				; stop moving horizontally
		rts
; ===========================================================================

; loc_183AA:
; sonic-vs-robotnik: player 2 IS the MZ boss. Left/right flies Eggman across the
; arena; B fires the flame gun (a dropping fireball that spreads along the floor),
; gated by a reload timer so P2 can't blanket the ground in flame. The scripted
; swoop/lava/auto-fire AI (BMZ_ChgDir/BMZ_DropFire below) is left in the file but
; never dispatched.
BMZ_ShipMove:
		; Poll pad 2 directly (Sonic clobbers v_jpadhold2), BOTH TH phases like
		; ReadJoypads, so we see A as well as B/C. Result d0 = Start A C B R L D U.
		move.b	#0,(port_2_data).l			; TH low -> A + Start
		nop
		nop
		move.b	(port_2_data).l,d0
		lsl.b	#2,d0					; shift A,Start up to bits 6,7
		andi.b	#$C0,d0
		move.b	#$40,(port_2_data).l			; TH high -> D-pad + B + C
		nop
		nop
		move.b	(port_2_data).l,d1
		andi.b	#$3F,d1
		or.b	d1,d0					; merge both polls
		not.b	d0					; 1 = pressed
		move.w	#0,obVelX(a0)				; idle unless P2 pushes
		tst.b	mz_fire_reload(a0)			; still frozen from the last shot? no moving
		bne.s	.notright				; (skip L/R; the gate below counts the freeze down)
		btst	#bitL,d0				; P2 holding left?
		beq.s	.notleft
		move.w	#-$140,obVelX(a0)
		bclr	#0,obStatus(a0)				; bit0 clear = facing left
	.notleft:
		btst	#bitR,d0				; P2 holding right?
		beq.s	.notright
		move.w	#$140,obVelX(a0)
		bset	#0,obStatus(a0)				; bit0 set = facing right
	.notright:
		move.w	d0,-(sp)				; BossMove clobbers d0 -- save the pad read
		bsr.w	BossMove				; apply obVelX to obBossX/obX
		move.w	(sp)+,d0				; restore the pad read for the fire check
		cmpi.w	#boss_mz_x+$30,obBossX(a0)		; clamp Eggman to the locked arena
		bge.s	.notpastleft
		move.w	#boss_mz_x+$30,obBossX(a0)
	.notpastleft:
		cmpi.w	#boss_mz_x+$110,obBossX(a0)
		ble.s	.notpastright
		move.w	#boss_mz_x+$110,obBossX(a0)
	.notpastright:
		tst.b	mz_fire_reload(a0)			; gun still reloading?
		beq.s	.canfire
		subq.b	#1,mz_fire_reload(a0)			; count the reload down, no fire this frame
		bra.w	BMZ_ShipUpdate
	.canfire:
		tst.w	obVelX(a0)				; Eggman must be planted (not sliding) to fire --
		bne.w	BMZ_ShipUpdate				; fairer, and stops the flame spawning behind him
		btst	#bitB,d0				; P2 pressing B (fire)?
		bne.s	.dofire
		btst	#bitC,d0				; ...or C...
		bne.s	.dofire
		btst	#bitA,d0				; ...or A -- any face button fires
		beq.w	BMZ_ShipUpdate
	.dofire:
		jsr	(FindFreeObj).l				; drop a flame-gun fireball under the ship
		bne.w	BMZ_ShipUpdate				; no free slot, skip
		move.w	obBossX(a0),obX(a1)
		move.w	obBossY(a0),obY(a1)
		addi.w	#$18,obY(a1)				; from just below Eggman
		move.b	#id_BossFire,obID(a1)
		move.b	#1,obSubtype(a1)			; subtype 1 = real fire: falls, then spreads along the floor
		move.b	#mz_reload_frames,mz_fire_reload(a0)	; start the reload (this is obSubtype on the SHIP, a0)
		bra.w	BMZ_ShipUpdate
; ===========================================================================

; loc_184F6:
BMZ_Explode:
		subq.w	#1,BossMarble_GenericTimer(a0)		; has the timer reached 0?
		bmi.s	.transition				; if yes, branch
		bra.w	BossDefeated				; explosions still going
; ===========================================================================

; loc_18500
.transition:
		bset	#0,obStatus(a0)				; set x flip bit so we face right
		bclr	#7,obStatus(a0)				; clear the defeated flag
		clr.w	obVelX(a0)				; stop horizontal movement
		addq.b	#2,ob2ndRout(a0)			; increment the routine counter
		move.w	#-38,BossMarble_GenericTimer(a0)	; set a timer for 38 frames
		tst.b	(v_bossstatus).w			; has boss been marked as defeated?
		bne.s	.skip					; yes, skip
		move.b	#1,(v_bossstatus).w			; no, mark it as defeated but not capsule open
		clr.w	obVelY(a0)				; stop vertical movement

; locret_1852A
.skip:
		rts
; ===========================================================================

; loc_1852C:
BMZ_Recover:
		addq.w	#1,BossMarble_GenericTimer(a0)		; has the timer reached 0?
		beq.s	.doneFalling				; if yes, branch
		bpl.s	.timerPositive				; if the timer is larger than 0, branch
		cmpi.w	#boss_mz_y+$60,obBossY(a0)		; have we reached the y boundary?
		bhs.s	.doneFalling				; if yes, branch
		addi.w	#$18,obVelY(a0)				; no, keep falling
		bra.s	.exit
; ===========================================================================

; loc_18544
.doneFalling:
		clr.w	obVelY(a0)				; stop vertical movement
		clr.w	BossMarble_GenericTimer(a0)		; clear the timer
		bra.s	.exit
; ===========================================================================

.timerPositive:
		cmpi.w	#48,BossMarble_GenericTimer(a0)		; has the timer reached 48 frames?
		blo.s	.rise					; if not, branch
		beq.s	.playMusic				; stop and play music
		cmpi.w	#56,BossMarble_GenericTimer(a0)		; has the timer reached 56 frames?
		blo.s	.exit					; if not, branch
		addq.b	#2,ob2ndRout(a0)			; increment routine counter
		bra.s	.exit
; ===========================================================================

; loc_18566
.rise:
		subq.w	#8,obVelY(a0)				; slow down, eventually causing him to rise
		bra.s	.exit
; ===========================================================================

.playMusic:
		clr.w	obVelY(a0)				; stop rising
		move.w	#bgm_MZ,d0
		jsr	(QueueSound1).l				; play MZ music

; loc_1857A
.exit:
		bsr.w	BossMove
		bra.w	BMZ_ShipUpdate
; ===========================================================================

; loc_18582:
BMZ_Escape:
		move.w	#$500,obVelX(a0)			; move to the right quickly
		move.w	#-$40,obVelY(a0)			; move up a little bit
		cmpi.w	#boss_mz_end,(v_limitright2).w		; have we finished scrolling to the right (reached level bounds)?
		bhs.s	.checkOffScreen				; if yes, branch
		addq.w	#2,(v_limitright2).w			; keep unlocking the bounds of the screen by 2 pixels
		bra.s	.flee
; ===========================================================================

; loc_1859C
.checkOffScreen:
		tst.b	obRender(a0)				; has Eggman left the screen (is bit 7 clear)?
		bpl.s	BossMarble_ShipDel			; yes, bit 7 is cleared, so we can delete the object (this leverages signed numbers!)

; loc_185A2
.flee:
		bsr.w	BossMove
		bra.w	BMZ_ShipUpdate
; ===========================================================================

BossMarble_ShipDel:
		move.b	#id_Title,(v_gamemode).w		; sonic-vs-robotnik: Eggman fled -> P2 wins -> back to level picker
	if FixBugs
		; Avoid returning to BossMarble_ShipMain to prevent a
		; display-and-delete bug.
		addq.l	#4,sp
	endif
		jmp	(DeleteObject).l
; ===========================================================================

BossMarble_FaceMain:	; Routine 4
		moveq	#0,d0
		moveq	#1,d1					; set facenormal1 animation
		movea.l	BossMarble_ParentObj(a0),a1		; load the main boss controller
		move.b	ob2ndRout(a1),d0			; load boss phase
		subq.w	#2,d0					; go back one routine
		bne.s	.checkSpecial				; were we at DropFire? if not, branch
		btst	#1,obSubtype(a1)			; are we on index 2 or 6?
		beq.s	.checkHitState				; if not, we are ChgDir, branch
		tst.w	obVelY(a1)				; are we moving vertically?
		bne.s	.checkHitState				; if yes, branch
		moveq	#4,d1					; set animation to facelaugh
		bra.s	.writeAnim
; ===========================================================================

; loc_185D2
.checkSpecial:
		subq.b	#2,d0					; are we in Recover or Escape state (if we looped around, we are negative, so must be in Recover or Escape)
		bmi.s	.checkHitState				; no, check if we have collided with Sonic
		moveq	#$A,d1					; set defeated animation
		bra.s	.writeAnim
; ===========================================================================

; loc_185DA
.checkHitState:
		tst.b	obColType(a1)				; is the boss currently being hit?
		bne.s	.checkSonicState			; if not, check Sonic's state
		moveq	#5,d1					; set animation to facehit
		bra.s	.writeAnim
; ===========================================================================

.checkSonicState:
		cmpi.b	#4,(v_player+obRoutine).w		; is Sonic in his hurt state?
		blo.s	.writeAnim				; if not, branch
		moveq	#4,d1					; set animation to facelaugh

; loc_185EE
.writeAnim:
		move.b	d1,obAnim(a0)				; move animation state into obAnim
; ----------------------------------------------------------------------------
; The below line checks: are we in the escape state?
; 8-2-2-4=0, so if we are in the escape state this is true, any other state would not result in a 0. If all this confuses you, review the _Index code throughout this file.
; ----------------------------------------------------------------------------
		subq.b	#4,d0
		bne.s	.skip					; we are not escaping, display normally
		move.b	#6,obAnim(a0)				; set animation state to facepanic
		tst.b	obRender(a0)				; has Eggman's face left the screen?
		bpl.s	BossMarble_FaceDel			; yes, delete his face

; loc_18602
.skip:
		bra.s	BossMarble_Display
; ===========================================================================

BossMarble_FaceDel:
		jmp	(DeleteObject).l
; ===========================================================================

BossMarble_FlameMain:; Routine 6
		move.b	#7,obAnim(a0)				; set animation state to 7 (default invisible state for flame)
		movea.l	BossMarble_ParentObj(a0),a1		; load main boss controller
		cmpi.b	#8,ob2ndRout(a1)			; are we in the Escape state?
		blt.s	.checkMove				; no, check movement
		move.b	#$B,obAnim(a0)				; set thruster animation for takeoff
		tst.b	obRender(a0)				; what is our screen status?
		bpl.s	BossMarble_FlameDel			; off screen, delete
		bra.s	BMZ_FlameDisp				; on screen, display
; ===========================================================================

; loc_1862A
.checkMove:
		tst.w	obVelX(a1)				; are we currently moving?
		beq.s	BMZ_FlameDisp				; no, don't display flame
		move.b	#8,obAnim(a0)				; yes, display flame

; loc_18636
BMZ_FlameDisp:
		bra.s	BossMarble_Display
; ===========================================================================

BossMarble_FlameDel:
		jmp	(DeleteObject).l
; ===========================================================================

BossMarble_Display:
		lea	(Ani_Eggman).l,a1
		jsr	(AnimateSprite).l

; loc_1864A
BossMarble_SetBits:
		movea.l	BossMarble_ParentObj(a0),a1		; load main boss controller
		move.w	obX(a1),obX(a0)				; copy positions
		move.w	obY(a1),obY(a0)
		move.b	obStatus(a1),obStatus(a0)		; move object status to boss object status
		moveq	#sprite_xflip|sprite_yflip,d0		; move first 2 bits into d0
		and.b	obStatus(a0),d0				; AND with obStatus so now do contains X and Y logical flip bits only
		andi.b	#~(sprite_xflip|sprite_yflip),obRender(a0) ; clear the X and Y flip
		or.b	d0,obRender(a0)				; OR the two together, so now DisplaySprite has X and Y orientation and above render bits
		jmp	(DisplaySprite).l
; ===========================================================================

BossMarble_TubeMain:	; Routine 8
		movea.l	BossMarble_ParentObj(a0),a1		; load main boss controller
		cmpi.b	#8,ob2ndRout(a1)			; are we currently in Escape state?
		bne.s	.skip					; if not, branch
		tst.b	obRender(a0)				; has the tube left the screen?
		bpl.s	BossMarble_TubeDel			; if so, branch

; loc_18688
.skip:
		move.l	#Map_BossItems,obMap(a0)		; load item mappings
		move.w	#ArtTile_Eggman_Weapons|Tile_Pal2,obGfx(a0) ; load weapons and pick the palette line
		move.b	#4,obFrame(a0)				; set frame to tube (found in Boss Items.asm)
		bra.s	BossMarble_SetBits
; ===========================================================================

BossMarble_TubeDel:
		jmp	(DeleteObject).l


; ===========================================================================
; ---------------------------------------------------------------------------
; Object 74 - lava that Eggman drops (MZ)
; ---------------------------------------------------------------------------

BossFire:
		moveq	#0,d0
		move.b	obRoutine(a0),d0			; copy object routine
		move.w	BossFire_Index(pc,d0.w),d0		; use the object routine index and BossFire_Index to calculate our offset
	if FixBugs
		; DisplaySprite has been moved to avoid a display-after-free bug.
		jmp	BossFire_Index(pc,d0.w)
	else
		jsr	BossFire_Index(pc,d0.w)			; jump into the table and use our offset to pick a routine in the index to go to
		jmp	(DisplaySprite).l
	endif
; ===========================================================================
BossFire_Index:	dc.w BossFire_Main-BossFire_Index
		dc.w BossFire_Action-BossFire_Index
		dc.w BossFire_TempFire-BossFire_Index
		dc.w BossFire_TempFireDel-BossFire_Index
; ===========================================================================

BossFire_Main:		; Routine 0
		move.b	#16/2,obHeight(a0)			; set object height and width
		move.b	#16/2,obWidth(a0)
		move.l	#Map_Fire,obMap(a0)			; load mappings, graphics, and set render style
		; sonic-vs-robotnik: Eggman's fire art lives at $530, NOT the vanilla $345. On the Swiss
		; Army Knife (Spring Yard) arena, $345 is a real Spring Yard background tile, so loading fire
		; there corrupted the sky. $530-$535 is a free 6-tile gap in every boss arena (between the
		; exhaust art at $52A-$52C and the shield art at $541, and clear of the title-card font at
		; $560+). PLC_MZ + PLC_SwissFire both load Nem_MzFire there. (Byte-neutral vs the vanilla
		; move -- keeps the KillSonic branch in range.) The MZ lava balls still use $345.
		move.w	#$530,obGfx(a0)
		move.b	#sprite_cam_field,obRender(a0)
		move.b	#5,obPriority(a0)			; set render priority (to allow to hide behind lava)
		move.w	obY(a0),obBossY(a0)			; copy Y
		move.b	#16/2,obActWid(a0)			; set object width
		addq.b	#2,obRoutine(a0)			; increment the object routine
		tst.b	obSubtype(a0)				; are we controlling temp fire (floor fire) or real fire (0 = temp fire)
		bne.s	.setupSpawn				; if real fire, branch
		move.b	#col_16x16|col_hurt,obColType(a0)	; set collision for Sonic so that it is 16x16 and hurts when touched
		addq.b	#2,obRoutine(a0)			; increment the routine to stay at TempFire until further incremented
		bra.w	BossFire_TempFire			; go to display temporary fire that indicates a fireball is incoming
; ===========================================================================

; loc_1870A:
.setupSpawn:
		move.b	#30,BossFire_GenericTimer(a0)		; set a timer for 30 frames
		move.w	#sfx_Fireball,d0
		jsr	(QueueSound2).l				; play lava sound

BossFire_Action:	; Routine 2
		moveq	#0,d0
		move.b	ob2ndRout(a0),d0			; copy 2nd object routine
		move.w	BossFire_Index2(pc,d0.w),d0		; use the object routine index and BossFire_Index2 to calculate our offset
		jsr	BossFire_Index2(pc,d0.w)		; jump into the table and use our offset to pick a routine in the index to go to
		jsr	(SpeedToPos).l				; calculate speed based on velocity
		lea	(Ani_Fire).l,a1				; load animations and send them off to be ran
		jsr	(AnimateSprite).l
		; sonic-vs-robotnik: arena-aware "fell past the floor" delete. On the Swiss Army
		; Knife (Spring Yard arena) the floor sits much lower than Marble's lava.
		move.w	#boss_mz_y+$D8,d1			; Marble lava level
		cmpi.w	#id_SYZ_act3,(v_zone_act).w		; Spring Yard (bonus) arena?
		bne.s	.floorset
		move.w	#boss_syz_y+$D8,d1			; Spring Yard floor level
	.floorset:
		cmp.w	obY(a0),d1				; has the fire fallen past it?
		bcs.s	BossFire_Delete				; if obY > threshold, delete
	if FixBugs
		; DisplaySprite has been moved to avoid a display-after-free bug.
		jmp	(DisplaySprite).l
	else
		rts
	endif
; ===========================================================================

BossFire_Delete:
		jmp	(DeleteObject).l
; ===========================================================================
BossFire_Index2:dc.w BossFire_Drop-BossFire_Index2
		dc.w BossFire_MakeFlame-BossFire_Index2
		dc.w BossFire_Duplicate-BossFire_Index2
		dc.w BossFire_FallEdge-BossFire_Index2
; ===========================================================================

BossFire_Drop:		; sub Routine 0
		bset	#1,obStatus(a0)				; flip the object vertically so that it is facing up
		subq.b	#1,BossFire_GenericTimer(a0)		; is Eggman done waiting to drop the fire?
		bpl.s	.exit					; if not, branch
		move.b	#col_16x16|col_hurt,obColType(a0)	; set collision
		clr.b	obSubtype(a0)				; clear subtype for later
		addi.w	#$18,obVelY(a0)				; start falling downwards and add on to it
		bclr	#1,obStatus(a0)				; clear the flip so now object is facing down
		bsr.w	ObjFloorDist
		tst.w	d1					; has the object reached the floor?
		bpl.s	.exit					; if not, branch
		addq.b	#2,ob2ndRout(a0)

; locret_18780:
.exit:
		rts
; ===========================================================================

BossFire_MakeFlame:	; sub Routine 2
		subq.w	#2,obY(a0)				; raise object up by 2 pixels
		bset	#7,obGfx(a0)				; set priority to high (in foreground)
		move.w	#$A0,obVelX(a0)				; set x velocity in preparation for spread
		clr.w	obVelY(a0)				; stop falling
		move.w	obX(a0),obBossX(a0)			; copy positions
		move.w	obY(a0),obBossY(a0)
		move.b	#3,BossFire_GenericTimer(a0)		; set a counter of 3
		jsr	(FindNextFreeObj).l			; find free object slots
		bne.s	.advance				; no object slots left, leave
		lea	(a1),a3					; load freshly allocated slot (destination)
		lea	(a0),a2					; load flame object (source)
		moveq	#3,d0					; set loop to loop 4 times

; BossFire_Loop:
.loop:
		move.l	(a2)+,(a3)+				; copy 4 bytes, advancing the pointers each time
		move.l	(a2)+,(a3)+
		move.l	(a2)+,(a3)+
		move.l	(a2)+,(a3)+
		dbf	d0,.loop

		neg.w	obVelX(a1)				; flip the clone's X velocity
		addq.b	#2,ob2ndRout(a1)			; advance the clone's routine

; loc_187CA:
.advance:
		addq.b	#2,ob2ndRout(a0)			; advance original
		rts
; ===========================================================================

BossFire_Duplicate2:
		jsr	(FindNextFreeObj).l			; find more free objects
		bne.s	.exit					; no free objects, leave
		move.w	obX(a0),obX(a1)				; copy X and Y
		move.w	obY(a0),obY(a1)
		move.b	#id_BossFire,obID(a1)			; set object to fireball
		move.w	#103,obSubtype(a1)			; set spawn type to floor fire fire (obSubtype=0) and timer to 103 frames (BossFire_GenericTimer=$67, this child object is used in TempFlame) in one word write. this will be ran the next time objects are executed

; locret_187EE:
.exit:
		rts
; End of function BossFire_Duplicate2

; ===========================================================================

BossFire_Duplicate:	; sub Routine 4
		bsr.w	ObjFloorDist
		tst.w	d1					; is the object on the floor?
		bpl.s	.advance2ndRout				; if not, leave and go to FallEdge
		move.w	obX(a0),d0				; copy X
		move.w	#boss_mz_x+$140,d1			; sonic-vs-robotnik: Marble right spread bound
		cmpi.w	#id_SYZ_act3,(v_zone_act).w		; ...or the Spring Yard (bonus) arena?
		bne.s	.rbset
		move.w	#boss_syz_x+$140,d1			; Spring Yard right bound
	.rbset:
		cmp.w	d1,d0					; has the flame traveled past the right boundary?
		bgt.s	.advanceRout				; if so, branch to get ready for deletion
		move.w	obBossX(a0),d1				; copy position
		cmp.w	d0,d1					; is the current X the same as the last X?
		beq.s	.copyPosition				; if yes, branch
		andi.w	#$10,d0					; AND the 16th bit of both positions
		andi.w	#$10,d1
		cmp.w	d0,d1					; have we moved 1 pixel AND crossed a 16 pixel boundary?
		beq.s	.copyPosition				; if not, branch
		bsr.s	BossFire_Duplicate2			; yes, spawn another object
		move.w	obX(a0),BossFire_SpreadX(a0)		; save current X as next reference

; loc_1881E:
.copyPosition:
		move.w	obX(a0),obBossX(a0)			; copy last spawn X to current position (to mark where a flame was last spawned)
		rts
; ===========================================================================

; loc_18826:
.advance2ndRout:
		addq.b	#2,ob2ndRout(a0)
		rts
; ===========================================================================

; loc_1882C:
.advanceRout:
		addq.b	#2,obRoutine(a0)
		rts

BossFire_FallEdge:	; sub Routine 6
		bclr	#1,obStatus(a0)				; clear Y flip bit
		addi.w	#$24,obVelY(a0)				; make flame fall
		move.w	obX(a0),d0				; copy last spawn X
		sub.w	BossFire_SpreadX(a0),d0			; subtract the spread value from last spawn X
		bpl.s	.checkLava				; if positive, branch, we are on the left platform moving right
		neg.w	d0					; we are on the right platform moving left, negate to get absolute value

; loc_1884A:
.checkLava:
		cmpi.w	#$12,d0					; are we 18 pixels away from last spawn?
		bne.s	.checkImpact				; if not, branch
		bclr	#7,obGfx(a0)				; set priority to low (behind foreground)

; loc_18856:
.checkImpact:
		bsr.w	ObjFloorDist
		tst.w	d1					; is the object touching the floor?
		bpl.s	.exit					; if not, branch
		subq.b	#1,BossFire_GenericTimer(a0)		; decrement counter
		beq.s	BossFire_Delete2			; if counter has reached 0, branch, all the fireballs that are supposed to fall have fallen, so time to delete
		clr.w	obVelY(a0)				; stop falling
		move.w	BossFire_SpreadX(a0),obX(a0)		; copy offset
		move.w	obBossY(a0),obY(a0)			; copy Y
		bset	#7,obGfx(a0)				; set priority to high (in foreground)
		subq.b	#2,ob2ndRout(a0)			; go back to BossFire_Duplicate to spawn another fireball on top of the fireball on the edge, and make it fall

; locret_1887E:
.exit:
		rts
; ===========================================================================

BossFire_Delete2:
	if FixBugs
		; Do not return to BossFire_Action, to avoid double-delete
		; and display-and-delete bugs.
		addq.l	#4,sp
	endif
		jmp	(DeleteObject).l
; ===========================================================================
; This controls the flames that never make it to the edge, and burn out on the platform. We branch here from setting the subtype and timer in Duplicate2
; ===========================================================================

; loc_18886:
BossFire_TempFire: 	; Routine 4
		bset	#7,obGfx(a0)				; set flame priority to high
		subq.b	#1,BossFire_GenericTimer(a0)		; has the timer hit 0?
		bne.s	BossFire_Animate			; if not, branch
		move.b	#1,obAnim(a0)				; switch animation to "flame out"
		subq.w	#4,obY(a0)				; move object upwards by 4 pixels
		clr.b	obColType(a0)				; clear any collision

BossFire_Animate:
		lea	(Ani_Fire).l,a1
	if FixBugs
		; DisplaySprite has been moved to avoid a display-after-free bug.
		jsr	(AnimateSprite).l
		jmp	(DisplaySprite).l
	else
		jmp	(AnimateSprite).l
	endif
; ===========================================================================

; BossFire_Delete3:
BossFire_TempFireDel:	; Routine 6
		jmp	(DeleteObject).l
