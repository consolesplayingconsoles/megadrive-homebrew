; ===========================================================================
; ---------------------------------------------------------------------------
; Subroutine to pause the game
; ---------------------------------------------------------------------------

; sonic-vs-robotnik: edge-detect state for Robotnik's (P2) Start button. v_jpadpress2 is unusable
; at the pause trigger (Sonic overwrites it during ExecuteObjects, which runs between the VBlank
; joypad read and the next PauseGame), so we poll port 2 directly and remember last frame here.
; f_pause is a word; the 4 bytes after it are unused RAM.
f_p2startprev:	equ f_pause+2

PauseGame:
		nop						; useless nop (probably so an rts could easily be inserted here)
		tst.b	(v_lives).w				; do you have any lives left?
		beq.w	.unpauseGame				; if not, branch (.w: our P2 poll pushed .unpauseGame out of short range)
		tst.w	(f_pause).w				; is game already paused?
		bne.s	.startPause				; if yes, branch
		btst	#bitStart,(v_jpadpress1).w		; has P1 Start been pressed?
		bne.s	.startPause
		; sonic-vs-robotnik: P2 (Robotnik) Start -- poll port 2 directly (TH low -> Start on bit5)
		; and fire only on a fresh press (edge) so a held Start doesn't thrash pause on/off.
		move.b	#0,(port_2_data).l
		nop
		nop
		move.b	(port_2_data).l,d0
		not.b	d0					; 1 = pressed
		andi.b	#$20,d0					; isolate Start (bit5 in the TH-low phase)
		move.b	(f_p2startprev).w,d1			; Start state last frame
		move.b	d0,(f_p2startprev).w			; remember for next frame
		tst.b	d0
		beq.w	.return					; not held now -> nothing (.w: .return is past the pause loop)
		tst.b	d1
		bne.w	.return					; already held last frame -> not a fresh press

	; Pause_StopGame:
	.startPause:
		move.w	#1,(f_pause).w				; pause the game
		move.b	#1,(v_snddriver_ram.f_pausemusic).w	; pause music
; ---------------------------------------------------------------------------

; Pause_Loop:
.pauseLoop:
		move.b	#id_VBlank_Paused,(v_vblank_routine).w	; run routine $10 in VBlank
		bsr.w	WaitForVBlank				; wait until VBlank has finished

		tst.b	(f_slomocheat).w			; is slow-motion cheat on?
		beq.s	.checkUnpausing				; if not, branch
		btst	#bitA,(v_jpadpress1).w			; is button A pressed?
		beq.s	.checkSlowMotion			; if not, branch
		move.b	#id_Title,(v_gamemode).w		; return to title screen
		nop						; useless nop
		bra.s	.unpauseMusic				; unpause music
; ---------------------------------------------------------------------------

	; Pause_ChkBC:
	.checkSlowMotion:
		btst	#bitB,(v_jpadhold1).w			; is button B held down?
		bne.s	.slowMotion				; if yes, do continuous slow-motion
		btst	#bitC,(v_jpadpress1).w			; is button C pressed?
		bne.s	.slowMotion				; if yes, advance one frame

	; Pause_ChkStart:
	.checkUnpausing:
		btst	#bitStart,(v_jpadpress1).w		; is P1 Start pressed?
		bne.s	.unpauseMusic
		; sonic-vs-robotnik: P2 (Robotnik) unpause -- poll port 2 directly (same reliable read as the
		; pause trigger), edge-detected, instead of v_jpadpress2 (which didn't register the unpause).
		move.b	#0,(port_2_data).l
		nop
		nop
		move.b	(port_2_data).l,d0
		not.b	d0
		andi.b	#$20,d0					; isolate Start (bit5, TH-low phase)
		move.b	(f_p2startprev).w,d1			; Start state last frame
		move.b	d0,(f_p2startprev).w			; remember for next frame
		tst.b	d0
		beq.s	.pauseLoop				; not held -> keep paused
		tst.b	d1
		bne.s	.pauseLoop				; already held last frame -> not a fresh press -> keep paused
; ---------------------------------------------------------------------------

	; Pause_EndMusic:
	.unpauseMusic:
		move.b	#$80,(v_snddriver_ram.f_pausemusic).w	; unpause the music

	; Unpause:
	.unpauseGame:
		move.w	#0,(f_pause).w				; unpause the game

	; Pause_DoNothing:
	.return:
		rts						; return to main level loop
; ===========================================================================

; Pause_SlowMo:
.slowMotion:
		move.w	#1,(f_pause).w				; keep flag set so pause is triggered on next frame again
		move.b	#$80,(v_snddriver_ram.f_pausemusic).w	; unpause the music
		rts						; return to main level loop
; End of function PauseGame
