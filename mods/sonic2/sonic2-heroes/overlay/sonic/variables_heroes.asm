; =============== S U B R O U T I N E =======================================
; Sonic 2 Heroes — RAM Variables

; Character selection (added to RAM)
; These persist across level loads, reset at level end
v_current_char_p1:  ds.b 1  ; P1 character index (0=Sonic, 1=Tails, 2=Knuckles, etc.)
v_current_char_p2:  ds.b 1  ; P2 character index
v_char_count:       ds.b 1  ; Total available characters (initialized at startup)
