; =============== S U B R O U T I N E =======================================
; Sonic 2 Heroes — Object Pointer Table Patch
;
; Replaces the ObjNull entries at Obj4C/4D/4E with Knuckles pointer
; This gets included in s2.asm to add Knuckles to the object dispatch table

; Original (vanilla s2disasm line 29992-29994):
;			dc.l ObjNull	; Used to be the "BBat" badnik from HPZ
;			dc.l ObjNull	; Used to be the "Stego" badnik
;			dc.l ObjNull	; Used to be the "Gator" badnik

; Patched:
ObjPtr_Knuckles:	dc.l Obj4C	; Knuckles (ported from S2+K)
				dc.l ObjNull	; (was Stego)
				dc.l ObjNull	; (was Gator)
