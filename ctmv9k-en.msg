; This file is a part of Cute Mouse source (Victor 9000 port)
; Here are messages in English

E_error		db nl,'Error: Invalid option'
E_option	db eos
E_argument	db ' argument',eos
E_help		db 1,nl,'Enter /? on command line for help',eos

E_nomouse	db 2,'No mouse detected on serial port '
E_port		db 'A',eos
E_mousedev	db 1,'Error: another MOUSE driver is already installed',eos
E_noreload	db 2,'Error: resident driver not reset: some interrupts intercepted...',eos

E_nocute	db 1,'CuteMouse driver is not installed!',eos
E_notunload	db 2,'Driver unload failed: some interrupts intercepted...',eos
S_unloaded	db 0,'Driver successfully unloaded...',eos

S_replace	db 'Note: another INT 33h mouse handler is installed and will be replaced',nl,eos
S_reset		db 'Resident part reset to ',eos
S_installed	db 'Installed at ',eos
S_atport	db 'serial port '
S_port		db 'A in ',eos
if USE_MSYS
S_inMSYS	db 'Mouse Systems mode',eos
endif
S_inMS		db 'Microsoft mode',eos
S_inLT		db 'Logitech mode',eos
S_wheel		db ' (wheel present)'
S_CRLF		db nl,eos

Copyright	db nl,'CuteMouse v',CTMRELEASE,' [FreeDOS] for the Victor 9000',nl,eos
Syntax		label byte
    db 1,'Usage: CTMV9K /SA | /SB [/3] [/L] [/R[h[v]]]     CTMV9K /U     CTMV9K /?',nl,nl
    db '  /SA, /SB - serial mouse on port A or B (A or B alone also works)',nl
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
