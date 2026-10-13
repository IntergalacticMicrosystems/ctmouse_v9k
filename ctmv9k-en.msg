; This file is a part of CuteMouse source
; Here are messages in English

E_error		db nl,'Error: Invalid option'
E_option	db eos
E_argument	db ' argument',eos
E_help		db 5,nl,'Enter /? on command line for help',eos

E_notfound	db 5,'Error: device not found',eos
;;+E_noIRQ	db 5,'Error: IRQ line not detected',eos

E_nocute	db 1,'CuteMouse driver is not installed!',eos
E_notunload	db 2,'Driver unload failed: some interrupts intercepted...',eos
S_unloaded	db 0,'Driver successfully unloaded...',eos

S_reset		db 'Resident part reset to ',eos
S_installed	db 'Installed at ',eos
S_atCOM		db 'serial port in ',eos	; PHASE2: name the 7201 channel
if USE_MSYS
S_inMSYS	db 'Mouse Systems mode',eos
endif
S_inMS		db 'Microsoft mode',eos
S_inLT		db 'Logitech mode',eos
S_wheel		db ' (wheel present)'
S_CRLF		db nl,eos

Copyright	db nl,'CuteMouse v',CTMRELEASE,' [FreeDOS]',nl,eos
Syntax		label byte
    db 0,nl,'Options:',nl
; PHASE2: /S becomes /SA /SB (7201 channel A/B)
    db '  /S[c[i]] - force serial mouse mode at COM port c (1-4) with IRQ i (1-7)',nl
    db '  /3	   - force 3-button mode if Microsoft mouse found',nl
if USE_MSYS
    db '  /M       - try *old* Mouse Systems / Genius for non-PnP mice',nl
endif
    db nl
    db '  /R[h[v]] - horizontal / vertical resolution: h,v = 1-9, or 0 for auto',nl
    db '	     (no value = use default: auto for h, or "as h" for v)',nl
    db '  /L	   - swap left and right button',nl,nl
    db '  /U	   - uninstall driver, remove TSR from memory',nl
    db '  /?	   - show this help',eos
