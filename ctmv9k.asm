; Cute Mouse Driver - a tiny mouse driver
;
; Copyright (c) 1997-2002 Nagy Daniel <nagyd@users.sourceforge.net>
;
; BIOS wheel mouse support: Ported from Konstantin Koll's public
; domain code into Cute Mouse by Eric Auer 2007 (places marked -X-)
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin St - Fifth Floor, Boston, MA 02110-1301 USA
; -X- no longer: 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
;

; NOTE: memcopy and MOVSEG_ have "assume..." as side effects!
; %pagesize 255
; %noincl
;%macs
; %nosyms
;%depth 0
; %linum 0
;%pcnt 0
;%bin 0
; warn
; locals

CTMVER		equ <"2.1">		; major driver version
CTMRELEASE	equ <"2.1 beta4-V9K">	; full driver version with suffixes
driverversion	equ 705h		; imitated Microsoft driver version
; at least 705h because our int 33 function _26 operates in 7.05+ style

FASTER_CODE	 = 0		; optimize by speed instead size
OVERFLOW_PROTECT = 0		; prevent variables overflow
FOOLPROOF	 = 1		; check driver arguments validness
USE_MSYS	 equ 0		; include Mouse Systems decoder and /M option
USE_WHEEL	 equ 1		; include MS wheel mouse (4th byte) support
MODEGUARD	 equ 1		; render target guard on draw/restore
CHAIN41		 equ 0		; chain the old INT 41h handler (phase 3)
HWCURSOR	 equ 0		; 6845 hardware text cursor in fn 0Ah (must be 0)

;------------------------------------------------------------------------

include asmlib/asm.mac
; *** include asmlib/hll.mac	; if_ loop_ countloop_ etc - TASM specific
include asmlib/code.def
include asmlib/code.mac
include asmlib/macro.mac
include asmlib/dos/psp.def	; ** only DOS_exit env_seg cmdline_len PSP_TSR used
; include asmlib/dos/file.mac	; was only used once - DOSCloseFile
include asmlib/dos/mem.mac

if @CPU and 4
.err <ctmv9k is an 8086 build>
endif

;----- Victor 9000 hardware (all memory-mapped, offsets in segment IO_SEG)

IO_SEG		equ 0E000h
PIC_OCW		equ 0000h	; 8259A A0=0: OCW2
PIC_IMR		equ 0001h	; 8259A A0=1: IMR (OCW1), IR1 = bit 1
PIC_EOI_IR1	equ 61h		; OCW2: specific EOI, level 1
PIC_IR1		equ 02h		; IMR bit 1: 7201 (INT 41h)
PIT_CNT0	equ 0020h	; 8253 counter 0: baud clock of 7201 channel A
PIT_CNT1	equ 0021h	; 8253 counter 1: baud clock of 7201 channel B
PIT_CTRL	equ 0023h	; 8253 mode word: 36h counter 0, 76h counter 1
BAUD_COUNT	equ 65		; x16 clock -> 1200 baud (MOUSE.DEV value)
SIO_DATA_A	equ 0040h	; uPD7201 data, channel A
SIO_DATA_B	equ 0041h	; uPD7201 data, channel B
SIO_CTRL_A	equ 0042h	; uPD7201 control, channel A (pointer, then value)
SIO_CTRL_B	equ 0043h	; uPD7201 control, channel B
IVT_INT41	equ 0104h	; 0000:0104h, INT 41h = 8259 base 40h + IR1

; uPD7201 register values
WR0_RESEXT	equ 10h		; WR0 command 2: reset external/status interrupts
WR0_CHRESET	equ 18h		; WR0 command 3: channel reset
WR0_ERRRES	equ 30h		; WR0 command 6: error reset
WR0_EOI		equ 38h		; WR0 command 7: end of interrupt (channel A only)
WR1_RXALL	equ 10h		; WR1: Rx interrupt on every character, Tx/ext off
WR2A_VAL	equ 14h		; WR2A: both channels interrupt driven, priority
WR3_VAL		equ 41h		; WR3: Rx 7 bits, Rx enable, no auto enables
WR3_VAL8	equ 0C1h	; WR3: Rx 8 bits, Rx enable (Mouse Systems 8N1)
WR4_VAL		equ 44h		; WR4: x16 clock, 1 stop bit, no parity
WR5_RTSOFF	equ 0E8h	; WR5: DTR, Tx 8 bits, Tx enable, RTS off
WR5_RTSON	equ 0EAh	; WR5: same + RTS on (mouse powered)
RR0_RXAVAIL	equ 01h		; RR0 bit 0: Rx character available
RR0_INTPEND	equ 02h		; RR0 bit 1: interrupt pending (channel A only)
RR1_ERRORS	equ 70h		; RR1 bits 4-6: parity, overrun, framing error

_ARG_DI_	equ <word ptr [bp]>
_ARG_SI_	equ <word ptr [bp+2]>
_ARG_BP_	equ <word ptr [bp+4]>

_ARG_BX_	equ <word ptr [bp+6]>
_ARG_DX_	equ <word ptr [bp+8]>
_ARG_CX_	equ <word ptr [bp+10]>
_ARG_AX_	equ <word ptr [bp+12]>
_ARG_ES_	equ <word ptr [bp+14]>
_ARG_DS_	equ <word ptr [bp+16]>
_ARG_OFFS_	=   22

PUSHALL		macro
		push	ax
		push	cx
		push	dx
		push	bx
		push	bp
		push	si
		push	di
endm
POPALL		macro
		pop	di
		pop	si
		pop	bp
		pop	bx
		pop	dx
		pop	cx
		pop	ax
endm

nl		equ <13,10>
eos		equ <0>

POINT		struc
  X		dw ?
  Y		dw ?
POINT ends

V9K_PART	= 1			; video layer: equates and macros
include ctmv9k-video.inc


;========================== SEGMENTS DEFINITION ==========================

.model tiny
assume ss:nothing

@TSRcode equ <DGROUP>
@TSRdata equ <DGROUP>
; TSR ends at TSRend, roughly line 3000 of the 4000 lines of ctmouse

TSRcref	equ <offset @TSRcode>	; offset relative TSR code group
TSRdref	equ <offset @TSRdata>	;	- " -	      data
coderef	equ <offset @code>	; offset relative main code group
dataref	equ <offset @data>	;	- " -	       data

.code
		org	0
TSRstart	label byte
		org	100h		; .COM style program
start:		jmp	real_start
TSRavail	label byte			; initialized data may come from here


;========================== UNINITIALIZED DATA ==========================

;!!! WARNING: don't init variables in uninitialized section because
;		they will not be present in the executable image

		org	PSP_TSR-3*16	; reuse part of PSP
spritebuf	db	4*16 dup (?)	; graphics cursor save buffer (1Eh-5Dh)
		V9K_UDATA		; v9k_rid, gc_x/y, gc_rows, gc_lr, granx10

;----- application state -----

;!!! WARNING: variables order between RedefArea and szDefArea must be
;		syncronized with variables order after DefArea

		even
SaveArea = $
RedefArea = $

mickey8		POINT	<>		; mickeys per 8 pixel ratios
;;*doublespeed	dw	?		; double-speed threshold (mickeys/sec)
senscoeff	POINT	<>		; mickeys sensitivity, ~[1/3..3.0]*256
sensval		POINT	<>		; original 001A sensitivity values-1
startscan	dw	?		; screen mask/cursor start scanline
endscan		dw	?		; cursor mask/cursor end scanline

;----- hotspot, screenmask and cursormask must follow as is -----

hotspot		POINT	<>		; cursor bitmap hot spot
screenmask	db	2*16 dup (?)	; user defined screen mask
cursormask	db	2*16 dup (?)	; user defined cursor mask
nocursorcnt	db	?		; 0=cursor enabled, else hide counter
;;*nolightpen?	db	?		; 0=emulate light pen
		even
szDefArea = $ - RedefArea		; initialized by softreset_21

rangemax	POINT	<>		; horizontal/vertical range max
upleft		POINT	<>		; upper left of update region
lowright	POINT	<>		; lower right of update region
pos		POINT	<>		; virtual cursor position
granpos		POINT	<>		; granulated virtual cursor position
UIR@		dd	?		; user interrupt routine address

		even
ClearArea = $

sensround	POINT	<>		; rounding error in applying
					;  sensitivity for mickeys
rounderr	POINT	<>		; same in conversion mickeys to pixels
		even
szClearArea1 = $ - ClearArea		; cleared by setpos_04

rangemin	POINT	<>		; horizontal/vertical range min
		even
szClearArea2 = $ - ClearArea		; cleared by setupvideo

mickeys		POINT	<>		; mouse move since last access
BUTTLASTSTATE	struc
  counter	dw	?
  lastrow	dw	?
  lastcol	dw	?
BUTTLASTSTATE ends
buttpress	BUTTLASTSTATE <>,<>,<>
buttrelease	BUTTLASTSTATE <>,<>,<>
wheel		BUTTLASTSTATE <>		; wheel counter since last access
wheelUIR	db	?		; wheel counter for UIR
callmask	db	?		; user interrupt routine call mask
		even
szClearArea3 = $ - ClearArea		; cleared by softreset_21
szSaveArea = $ - SaveArea

;----- old interrupt vectors -----

oldint33	dd	?		; old INT 33 handler address
oldIRQaddr	dd	?		; old INT 41h handler address
oldIMR		db	?		; 8259 IMR found at install (bit 1 used)


;=========================== INITIALIZED DATA ===========================

		even
TSRdata		label byte

; TSRdata must not be below TSRavail (the initialized data would overwrite
; the entry jmp). The assembler's conditionals see unreliable pass values
; here, so tools/ressize.py checks the overlap in the built binary instead
; (RESSZ marker).

DefArea = $
		POINT	<8,16>			; mickey8
		POINT	<1*256,1*256>		; senscoeff
		POINT	<49,49>			; sensval
;;*		dw	64			; doublespeed
		dw	0FFFFh,8000h		; startscan, endscan (plan 4.4)
		POINT	<0,0>			; hotspot
		V9K_DEFMASKS			; screenmask, cursormask (mirrored)
		db	1			; nocursorcnt
;;*		db	0			; nolightpen?
	db 0	; JWASM would use 0fch, "CLD" as pad byte??
		even
; ERRIF ($-DefArea ne szDefArea) "Defaults area contents corrupted!"

;----- driver and video state begins here -----

		even
granumask	POINT	<-1,-1>

textbuf		dw	?,?		; text cursor: written cell, saved cell
cursor@		dw	-1,0		; cursor sprite offset in videoseg;
					; -1=cursor not drawn
videoseg	equ <cursor@[2]>	; 0=not supported video mode

UIRunlock	db	1		; 0=user intr routine is in progress
videolock	db	1		; drawing: 1=ready,0=busy,-1=busy+queue
newcursor	db	0		; 1=force cursor redraw
pendevents	db	0		; events accounted, UIR/redraw pending
if CHAIN41
chain_ok	db	0		; 1=old INT 41h handler may be chained
endif
maxcoord	POINT	<799,399>	; screen limits for ranges (fn 7/8/17/26)


;============================= IRQ HANDLERS =============================

;========================================================================

IRQhandler	proc
		assume	ds:nothing,es:nothing
		cld
		push ds
		push es
		PUSHALL
		MOVSEG	ds,cs,,@TSRdata
		mov	ax,IO_SEG
		mov	es,ax

;----- drain our Rx FIFO completely (IF=0: pointer pairs are atomic)

@@drain:
;	CODE_	MOV_BX	IOctrl,<dw ?>		; SIO_CTRL_A/B, set at install
		OPCODE_MOV_BX
IOctrl		dw SIO_CTRL_A
		test	byte ptr es:[bx],RR0_RXAVAIL ; RR0 bit 0: Rx char available?
		jz	@@drained
		mov	byte ptr es:[bx],1	; WR0: pointer 1
		mov	ah,es:[bx]		; RR1: bits 4-6 parity/overrun/framing
		mov	al,es:[bx-2]		; SIO_DATA_A/B: received byte
;	CODE_	MOV_CX	IOdone,<db ?,0>		; processed bytes counter
		OPCODE_MOV_CX
IOdone		db ?,0
		test	ah,RR1_ERRORS
		jnz	@@rxerror
if USE_MSYS
		call_	mouseproc,MSMproc
else
		call_	mouseproc,MSLTproc
endif
		j	@@drain

@@rxerror:	mov	byte ptr es:[bx],WR0_ERRRES ; WR0: error reset, byte dropped
		mov	[IOdone],ch		; CH=0: resync on next sync byte
		j	@@drain

@@drained:
if CHAIN41
		test	byte ptr es:[SIO_CTRL_A],RR0_INTPEND ; RR0A bit 1: any
		jz	@@eoi			;  interrupt still pending (ours is
		cmp	[chain_ok],0		;  drained: the other channel's)
		je	@@eoi
		pushf
		call	[oldIRQaddr]		; owner serves it and sends both EOIs
		j	@@notify
@@eoi:
endif
		mov	byte ptr es:[SIO_CTRL_A],WR0_EOI ; WR0A: end of interrupt
		mov	byte ptr es:[PIC_OCW],PIC_EOI_IR1 ; 8259 OCW2: EOI IR1
@@notify:	call	mousenotify		; UIR and cursor redraw (may STI)
		jmp	rethandler
IRQhandler	endp
		assume	ds:@TSRdata

;========================================================================
;		Enable 7201 Rx interrupts and hook INT 41h
;========================================================================
;
; In:	none
; Out:	none
; Use:	IOctrl
; Modf:	AX, CX, BX, ES, IOdone
; Call:	none
;
enable7201	proc
		xor	ax,ax
		mov	es,ax			; ES=0: interrupt vector table
		pushf
		cli				; keep the caller's IF (popf)
		mov	word ptr es:[IVT_INT41],TSRcref:IRQhandler
		mov	es:[IVT_INT41+2],cs	; INT 41h -> IRQhandler (no INT 21h)
		mov	ax,IO_SEG
		mov	es,ax
		mov	bx,[IOctrl]
		mov	cx,4			; FIFO holds 3 bytes: bounded drain
@@en_drain:	test	byte ptr es:[bx],RR0_RXAVAIL ; RR0 bit 0: Rx char available?
		jz	@@en_empty
		mov	al,es:[bx-2]		; SIO_DATA_A/B: discard the byte
		loop	@@en_drain
@@en_empty:	mov	byte ptr es:[bx],1	; WR0: pointer 1
		mov	byte ptr es:[bx],WR1_RXALL ; WR1: Rx interrupt on every char
		mov	byte ptr es:[PIC_OCW],PIC_EOI_IR1 ; 8259 OCW2: clear a stale IR1
		and	byte ptr es:[PIC_IMR],not PIC_IR1 ; 8259 IMR: unmask IR1
		mov	[IOdone],0		; next byte must be a sync byte
		popf
		ret
enable7201	endp

;========================================================================
;		Disable 7201 Rx interrupts and unhook INT 41h
;========================================================================
;
; In:	none			(called only after the ownership check)
; Out:	none
; Use:	IOctrl, oldIRQaddr, oldIMR
; Modf:	AX, BX, SI, DI, ES
; Call:	none
;
disable7201	proc
		pushf
		cli				; keep the caller's IF (popf)
		mov	ax,IO_SEG
		mov	es,ax
		mov	bx,[IOctrl]
		mov	byte ptr es:[bx],1	; WR0: pointer 1
		mov	byte ptr es:[bx],0	; WR1: all 7201 interrupts off
		mov	al,[oldIMR]		; 8259 IMR bit 1 := bit 1 found at
		xor	al,es:[PIC_IMR]		;  install. The vector handed back
		and	al,PIC_IR1		;  below is always that found at
		xor	es:[PIC_IMR],al		;  install (ownership checked first)
		xor	ax,ax
		mov	es,ax			; ES=0: interrupt vector table
		mov	si,TSRdref:oldIRQaddr
		mov	di,IVT_INT41
		movsw				; restore old INT 41h vector
		movsw
		popf
		ret
disable7201	endp

;========================================================================
;		Process the Microsoft/Logitech packet bytes
;========================================================================

MSLTproc	proc
;	CODE_	MOV_DL	MSLTbuttons,<db ?>	; buttons state for MS3/LT/WM
		OPCODE_MOV_DL
MSLTbuttons	db ?
		test	al,01000000b	; =40h	; synchro check
;	if_ nz					; if first byte
	jz @@msltz
		mov	[IOdone],1		; request next 2/3 bytes
		mov	[MSLT_1],al
MSLTCODE1	label	byte			; "ret" if not LT/WM
		xchg	ax,cx			; OPTIMIZE: instead MOV AL,CL
		sub	al,3			; if first byte after 3 bytes
		jz	@@LTWMbutton3		;  then release middle button
		ret
;	end_
@@msltz:

;	if_ ncxz				; skip nonfirst byte at start
	jcxz @@msltcxz
		inc	[IOdone]		; request next byte
		loop	@@MSLT_3
		mov	[MSLT_X],al		; keep X movement LO
;	end_
@@msltcxz:
@@LTret:	ret

@@MSLT_3:	loop	@@LTWM_4
		;mov	cl,0
;	CODE_	MOV_BX	MSLT_1,<db ?,0>		; mouse packet first byte
		OPCODE_MOV_BX
MSLT_1		db ?,0
		ror	bx,1
		ror	bx,1
;		xchg	cl,bh			; bits 1-0: X movement HI
		xchg	bh,cl	; TASM and JWASM use opposite encoding
		ror	bx,1			; bits 5-4: LR buttons
		ror	bx,1
		or	al,bh			; bits 3-2: Y movement HI
		cbw
		 xchg	cx,ax			; CX=Y movement
;	CODE_	OR_AL	MSLT_X,<db ?>
		OPCODE_OR_AL
MSLT_X		db ?
		cbw
		 xchg	bx,ax			; BX=X movement

		;cbw				; clear wheel value
		xor	al,dl
		 and	al,00000011b	; =3	; LR buttons change mask
		mov	dh,al
		 or	dh,bl			; nonzero if LR buttons state
		 or	dh,cl			;  changed or mouse moved
MSLTCODE2	label	byte
		j	@@MSLTupdate		; "jnz" if MS3
		or	al,00000100b	; =4	; empty event toggles button
		j	@@MSLTupdate

@@LTWM_4:	;mov	ch,0
		mov	[IOdone],ch		; request next packet
MSLTCODE3	label	byte			; if LT "mov cl,3" else
@@LTWMbutton3:	mov	cl,3			; if WM "mov cl,2" else "ret"
		mov	ah,al
		shr	al,cl
		xor	al,dl
		and	ax,111100000100b ; =0F04h
if FASTER_CODE
		jz	@@LTret			; exit if button 3 not changed
endif
		xor	bx,bx
		xor	cx,cx

@@MSLTupdate:	xor	al,dl			; new buttons state
		mov	[MSLTbuttons],al
		j	swapbuttons
MSLTproc	endp

if USE_MSYS
;========================================================================
;		Process the Mouse Systems packet bytes
;========================================================================

MSMproc		proc
		jcxz	@@MSM_1
		cbw
		dec	cx
		jz	@@MSM_2
		dec	cx
		jz	@@MSM_3
		loop	@@MSM_5

@@MSM_4:	add	ax,[MSM_X]
@@MSM_2:	mov	[MSM_X],ax
		j	@@MSMnext

@@MSM_1:	xor	al,10000111b	; =87h	; sync check: AL should
		test	al,11111000b	; =0F8h	;  be equal to 10000lmr
;	if_ zero
	jnz @@msmnz
		test	al,00000110b	; =6	; check the L and M buttons
;	 if_ odd				; if buttons not same
	jpe @@msmeven
		xor	al,00000110b	; =6	; swap them
;	 end_
@@msmeven:
		mov	[MSM_buttons],al	; bits 2-0: MLR buttons
		;j	@@MSMnext

@@MSM_3:	mov	[MSM_Y],ax
@@MSMnext:	inc	[IOdone]		; request next byte
;	end_
@@msmnz:
		ret

@@MSM_5:	;mov	ch,0
		mov	[IOdone],ch		; request next packet
;	CODE_	ADD_AX	MSM_Y,<dw ?>
		OPCODE_ADD_AX
MSM_Y		dw ?
;	CODE_	MOV_BX	MSM_X,<dw ?>
		OPCODE_MOV_BX
MSM_X		dw ?
		xchg	cx,ax			; OPTIMIZE: instead MOV CX,AX
;	CODE_	MOV_AL	MSM_buttons,<db ?>
		OPCODE_MOV_AL
MSM_buttons	db ?
		;j	reverseY		; reverseY is next line anyway
MSMproc		endp
endif ; USE_MSYS

;========================================================================
;			Update mouse status
;========================================================================
;
; In:	AL			(new buttons state, 2 or 3 LSB used)
;	AH			(wheel movemement)
;	BX			(X mouse movement)
;	CX			(Y mouse movement)
; Out:	none			(IF=0, before the EOIs: no UIR, no redraw)
; Use:	granpos, mickeys
; Modf:	AX, CX, DX, BX, SI, DI, wheel, wheelUIR, pendevents
; Call:	updateposition, updatebutton
;
if USE_MSYS
reverseY	proc
		neg	cx			; reverse Y movement
		;j	swapbuttons
reverseY	endp
endif ; USE_MSYS

swapbuttons	proc
		test	al,00000011b	; =3	; check the L and R buttons
;	if_ odd					; if buttons not same
	jpe @@swapeven
;	CODE_	XOR_AL	swapmask,<db 00000011b>	; 0 if LEFTHAND
		OPCODE_XOR_AL
swapmask	db 00000011b
;	end_
@@swapeven:
		;j	mouseaccount
swapbuttons	endp

mouseaccount	proc
;	CODE_	AND_AX
		OPCODE_AND_AX
buttonsmask	db	00000111b	; =8
wheelmask	db	0
		xchg	di,ax			; keep btn, wheel state in DI

;----- update mickey counters and screen position

		xchg	ax,bx			; OPTIMIZE: instead MOV AX,BX
;		MOVREG_	bx,<offset X>
	xor bx,bx	; MOVREG optimizes mov bx,offset POINT.X into this
		call	updateposition

		xchg	ax,cx
;		MOVREG_	bl,<offset Y>		; OPTIMIZE: BL instead BX
	mov bl,offset POINT.Y
		call	updateposition
		or	cl,al			; bit 0=mickeys change flag

;----- update wheel movement

		mov	ax,[mickeys.Y]
		xchg	ax,di			; retrieve button, wheel info
		xchg	dx,ax			; OPTIMIZE: instead MOV DX,AX
if USE_WHEEL
		mov	al,dh			; wheel: signed 4 bit value
		xor	al,00001000b	; =8
		sub	al,00001000b	; =8	; sign extension AL[0:3]->AL
;	if_ nz					; if wheel moved
	jz @@wheelz
		cbw
		mov	si,TSRdref:wheel
		add	[si + offset BUTTLASTSTATE.counter],ax	; wheel counter
		add	[wheelUIR],al		; same, but used for the UIR
		mov	al,10000000b	; =80h	; bit 7=wheel movement flag
		xor	bx,bx
		call	@lastpos
;	end_
@@wheelz:
endif ; USE_WHEEL

;----- update buttons state

		mov	dh,dl			; DH=buttons new state
		xchg	dl,[buttstatus]
		xor	dl,dh			; DL=buttons change state
if FASTER_CODE
;	if_ nz
	jz @@btnfastz
endif
		xor	bx,bx			; buttpress array index
		mov	al,00000010b		; mask for button 1
		call	updatebutton
		mov	al,00001000b		; mask for button 2
		call	updatebutton
		mov	al,00100000b		; mask for button 3
		call	updatebutton
if FASTER_CODE
;	end_
@@btnfastz:
endif

;----- events are reported by mousenotify after the EOI

		or	[pendevents],cl
		ret
mouseaccount	endp

;========================================================================
;		Call User Interrupt Routine and redraw cursor
;========================================================================
;
; In:	none			(IF=0, called from IRQhandler after the EOIs)
; Out:	none
; Use:	pendevents, callmask, granpos, mickeys, UIR@
; Modf:	AX, CX, DX, BX, SI, DI, wheelUIR, UIRunlock
; Call:	refreshcursor
;
mousenotify	proc
		dec	[UIRunlock]
;	if_ zero				; if user proc not running
	jnz @@uirnz
;	loop_					; until no events pending
@@notifyloop:	cli
		xor	cx,cx
		xchg	cl,[pendevents]
		jcxz	@@uirnz
		and	cl,[callmask]
;	 if_ nz					; if there is a user events
	jz @@maskz
;	CODE_	MOV_BX	buttstatus,<db 0,0>	; buttons status
		OPCODE_MOV_BX
buttstatus	db 0,0
		xchg	bh,[wheelUIR]
		mov	ax,[granpos.X]
		mov	dx,[granpos.Y]
		xchg	ax,cx
		mov	si,[mickeys.X]
		mov	di,[mickeys.Y]
		push	ds
		sti
		call	[UIR@]
		pop	ds
;	 end_
@@maskz:
		call	refreshcursor
		j	@@notifyloop
;	end_
@@uirnz:
		inc	[UIRunlock]
		ret
mousenotify	endp


;========================================================================
; In:	AX			(mouse movement)
;	BX			(offset X/offset Y)
; Out:	AX			(1 - mickey counter changed)
; Use:	mickey8, rangemax, rangemin, granumask, senscoeff
; Modf:	DX, SI, sensround, mickeys, rounderr, pos, granpos
;
updateposition	proc
		test	ax,ax
		jz	@@uposret
		mov	si,ax
;	if_ sign
	jns @@upns
		neg	ax
;	end_
@@upns:

;----- apply sensitivity (SI=movement, AX=abs(SI))

		mov	dx,word ptr senscoeff[bx] ; ~[1/3..3.0]*256
;		cmp	ax,4	; JWASM uses "signed byte" variant
	db 03dh, 4, 0	; "cmp ax, word 4"
;	if_ be
	ja @@upa
		 mov	ax,si
		 cmp	dh,1		; skip [-4..4] movements
		 jae	@@newmickeys	;  when sensitivity >= 1.0
		 imul	dx		; =mickeys*sensitivity
;	else_
	jmp short @@upbe
@@upa:
;		cmp	ax,12	; JWASM uses "signed byte" variant
	db 03dh, 12, 0	; "cmp ax, word 12"
;	 if_ ae
if FASTER_CODE
	jb @@up2b
		 mov	ax,dx
		 shl	ax,1
		 add	ax,dx		; =sensitivity*3
;	 else_
	jmp short @@up2ae
@@up2b:
		mul	dx
		shr	ax,1		; =sensitivity*min(12,abs(mickeys))/4
		shr	ax,1
;	 end_
@@up2ae:
else
	jb @@up2ae
		 mov	ax,12
;	 end_
@@up2ae:
		mul	dx
		shr	ax,1		; =sensitivity*min(12,abs(mickeys))/4
		shr	ax,1
endif
		imul	si		; DX:AX=mickeys*newsensitivity
;	end_
@@upbe:
		add	al,byte ptr sensround[bx]
		mov	byte ptr sensround[bx],al
		mov	al,ah		; remove 256 multiplier from
		mov	ah,dl		;  sensitivity: AX=DX:AX/256
;		adc	ax,0		; add carry from previous adding
	db 15h, 0, 0	; JWASM uses signed byte variant, same length

;----- apply mickeys per 8 pixels ratio to calculate cursor position

@@newmickeys:	add	word ptr mickeys[bx],ax
if FASTER_CODE
		mov	si,word ptr mickey8[bx]
		cmp	si,8
;	if_ ne
	je @@upeq
		shl	ax,1
		shl	ax,1
		shl	ax,1
		dec	si
;	andif_ gt
	jle @@upeq
		add	ax,word ptr rounderr[bx]
		inc	si
		cwd
		idiv	si
		mov	word ptr rounderr[bx],dx
		test	ax,ax
		jz	@@uposdone
;	end_
@@upeq:
else
		shl	ax,1
		shl	ax,1
		shl	ax,1
		add	ax,word ptr rounderr[bx]
		cwd
		idiv	word ptr mickey8[bx]
		mov	word ptr rounderr[bx],dx
endif
		add	ax,word ptr pos[bx]

;----- cut new position by virtual ranges and save

@savecutpos::	mov	dx,word ptr rangemax[bx]
		cmp	ax,dx
		jge	@@cutpos
		mov	dx,word ptr rangemin[bx]
		cmp	ax,dx
;	if_ le
	jg @@cpg
@@cutpos:	xchg	ax,dx			; OPTIMIZE: instead MOV AX,DX
;	end_
@@cpg:
		mov	word ptr pos[bx],ax	; new position
		and	al,byte ptr granumask[bx]
		V9K_GRANX			; text mode: X multiple of 10
		mov	word ptr granpos[bx],ax	; new granulated position
@@uposdone:	mov	ax,1
@@uposret:	ret
updateposition	endp

;========================================================================
; In:	AL			(unrolled press bit mask)
;	CL			(unrolled buttons change state)
;	DL			(buttons change state)
;	DH			(buttons new state)
;	BX			(buttpress array index)
; Out:	CL
;	DX			(shifted state)
;	BX			(next index)
; Use:	granpos
; Modf:	AX, SI, buttpress, buttrelease
;
updatebutton	proc
		shr	dx,1
;	if_ carry				; if button changed
	jnc @@ubnc
		mov	si,TSRdref:buttpress
		test	dl,dl
;	 if_ ns					; if button not pressed
	js @@ubs
		add	al,al			; indicate that it released
		mov	si,TSRdref:buttrelease
;	 end_
@@ubs:
		inc	word ptr [si + bx + offset BUTTLASTSTATE.counter]
@lastpos::	or	cl,al
		mov	ax,[granpos.Y]
		mov	[si + bx + offset BUTTLASTSTATE.lastrow],ax
		mov	ax,[granpos.X]
		mov	[si + bx + offset BUTTLASTSTATE.lastcol],ax
;	end_
@@ubnc:
		add	bx,size BUTTLASTSTATE	; next button
		ret
updatebutton	endp

;========================= END OF IRQ HANDLERS ==========================


V9K_PART	= 2			; video layer: drawcursor .. v9k_detect_mode
include ctmv9k-video.inc


;======================= INT 33 HANDLER SERVICES ========================

;========================================================================

setupvideo	proc
		mov	si,szClearArea2/2	; clear area 2
; ERRIF (szClearArea2 mod 2 ne 0) "szClearArea2 must be even!"
		j	@setvideo
setupvideo	endp

;========================================================================
; 21 - Software reset
;========================================================================
;
; In:	none
; Out:	[AX] = 21h/FFFFh	(not installed/installed)
;	[BX] = 2/3/FFFFh	(number of buttons)
; Use:	none
; Modf:	RedefArea, granumask, videoseg, granx10, v9k_rid, rangemax,
;	ClearArea
; Call:	hidecursor, @savecutpos
;
softreset_21	proc
		mov	[_ARG_BX_],3
buttonscnt	equ	byte ptr [$-2]		; buttons count (2/3)
		mov	[_ARG_AX_],0FFFFh
						; restore default area
		memcopy	szDefArea,ds,@TSRdata,@TSRdata:RedefArea,,,@TSRdata:DefArea
		call	hidecursor		; restore screen contents
		mov	si,szClearArea3/2	; clear area 3
; ERRIF (szClearArea3 mod 2 ne 0) "szClearArea3 must be even!"

;----- set parameters for current video mode

@setvideo::	push	si
		call	v9k_detect_mode		; videoseg, granumask.Y, granx10, v9k_rid
		mov	ax,800			; screen width
		mov	di,400			; screen height
		pop	si

;----- set ranges and center cursor (AX=screenwidth, DI=screenheight)

		mov	cx,ax
		dec	ax
		mov	[rangemax.X],ax		; set right X range
		shr	cx,1			; X middle

		mov	dx,di
		dec	di
		mov	[rangemax.Y],di		; set lower Y range
		shr	dx,1			; Y middle

;----- set cursor position (CX=X, DX=Y, SI=area size to clear)

@setpos::	nop	;cli			; -X-
		MOVSEG	es,ds,,@TSRdata
		mov	di,TSRdref:ClearArea
;		xchg	cx,si
		xchg	si,cx	; JWASM and TASM use opposite encoding
		xor	ax,ax
		rep	stosw

		xchg	ax,dx			; OPTIMIZE: instead MOV AX,DX
;		MOVREG_	bx,<offset Y>
		mov	bx,offset POINT.Y
		call	@savecutpos
		xchg	ax,si			; OPTIMIZE: instead MOV AX,SI
;		MOVREG_	bl,<offset X>		; OPTIMIZE: BL instead BX
		mov	bl,offset POINT.X
		jmp	@savecutpos
softreset_21	endp

;========================================================================
; 1F - Disable mouse driver and unhook IRQ
;========================================================================
;
; In:	none
; Out:	[AX] = 1Fh/FFFFh	(success/unsuccess)
;	[ES:BX]			(old int33 handler)
; Use:	oldint33
; Modf:	AX, CX, BX, SI, DI, ES, disabled?, nocursorcnt
; Call:	disable7201, hidecursor
;
disabledrv_1F	proc
		les	ax,[oldint33]
		assume	es:nothing
		mov	[_ARG_ES_],es
		mov	[_ARG_BX_],ax

;----- ownership first: INT 33h (and INT 41h, if enabled) must still
;	point to us, else refuse and change nothing

		mov	cx,cs
		xor	ax,ax
		mov	es,ax			; ES=0: interrupt vector table
		pushf
		cli
		cmp	word ptr es:[33h*4],TSRcref:handler33
		jne	@@ddrvfail
		cmp	es:[33h*4+2],cx
		jne	@@ddrvfail
		cmp	[disabled?],al		; OPTIMIZE: AL instead 0
		jne	@@ddrvok		; already disabled: nothing to undo
		cmp	word ptr es:[IVT_INT41],TSRcref:IRQhandler
		jne	@@ddrvfail
		cmp	es:[IVT_INT41+2],cx
		jne	@@ddrvfail

		mov	[buttstatus],al
		inc	ax			; OPTIMIZE: instead MOV AL,1
		mov	[nocursorcnt],al	; normalize hide counter
		mov	[disabled?],al
		call_	disableproc,disable7201	; can change ES!
		popf
		jmp	hidecursor		; restore screen contents

@@ddrvfail:	popf
		j	althandler_18		; [AX]=FFFFh
@@ddrvok:	popf
		ret
disabledrv_1F	endp

;========================================================================
; 18 - Set alternate User Interrupt Routine
;========================================================================
;
; In:	CX			(call mask)
;	ES:DX			(FAR routine)
; Out:	[AX] = 18h/FFFFh	(success/unsuccess)
;
althandler_18	proc
		assume	es:nothing
		mov	[_ARG_AX_],0FFFFh
		ret
althandler_18	endp

;========================================================================
; 19 - Get alternate User Interrupt Routine
;========================================================================
;
; In:	CX			(call mask)
; Out:	[CX]			(0=not found)
;	[BX:DX]			(FAR routine)
;
althandler_19	proc
		mov	[_ARG_CX_],0
		ret
althandler_19	endp

;========================================================================
; 00 - Reset driver and read status
;========================================================================
;
; In:	none
; Out:	[AX] = 0/FFFFh		(not installed/installed)
;	[BX] = 2/3/FFFFh	(number of buttons)
; Use:	none
; Modf:	none
; Call:	softreset_21, enabledriver_20
;
resetdriver_00	proc
		call	softreset_21
		;j	enabledriver_20
resetdriver_00	endp

;========================================================================
; 20 - Enable mouse driver and hook IRQ
;========================================================================
;
; In:	none
; Out:	[AX] = 20h/FFFFh	(success/unsuccess)
; Use:	none
; Modf:	AX, CX, DX, BX, ES, disabled?
; Call:	setupvideo, enable7201
;
enabledriver_20	proc
		mov	[disabled?],0
		call	setupvideo
		jmp_	enableproc,enable7201	; can change ES!
enabledriver_20	endp

;========================================================================
; 03 - Get cursor position, buttons status and wheel counter
;========================================================================
;
; In:	none
; Out:	[BL]			(buttons status)
;	[BH]			(wheel movement counter)
;	[CX]			(X - column)
;	[DX]			(Y - row)
; Use:	buttstatus, granpos
; Modf:	AX, CX, DX, wheel.counter
; Call:	@retBCDX
;
status_03	proc
		xor	ax,ax
		xchg	ax,[wheel.counter]
		mov	ah,al
		mov	al,[buttstatus]
		mov	cx,[granpos.X]
		mov	dx,[granpos.Y]
		j	@retBCDX
status_03	endp

;========================================================================
; 05 - Get button press data
;========================================================================
;
; In:	BX			(button number; -1 for wheel)
; Out:	[AL]			(buttons status)
;	[AH]			(wheel movement counter)
;	[BX]			(press times or wheel counter, if BX was -1)
;	[CX]			(last press X)
;	[DX]			(last press Y)
; Use:	none
; Modf:	CX, buttpress, wheel
; Call:	@retbuttstat
;
pressdata_05	proc
		mov	cx,TSRdref:buttpress-(size BUTTLASTSTATE)
		j	@retbuttstat
pressdata_05	endp

;========================================================================
; 06 - Get button release data
;========================================================================
;
; In:	BX			(button number; -1 for wheel)
; Out:	[AL]			(buttons status)
;	[AH]			(wheel movement counter)
;	[BX]			(release times or wheel counter, if BX was -1)
;	[CX]			(last release X)
;	[DX]			(last release Y)
; Use:	buttstatus
; Modf:	AX, CX, DX, BX, SI, buttrelease, wheel
; Call:	none
;
releasedata_06	proc
		mov	cx,TSRdref:buttrelease-(size BUTTLASTSTATE)
@retbuttstat::	mov	ah,byte ptr [wheel.counter]
		mov	al,[buttstatus]		;X={-1, 0, 1, 2}	-1-wheel, 0-left, 1-right, 2-middle button
		mov	[_ARG_AX_],ax
		xor	ax,ax

		inc	bx			; bx is {0, 1, 2, 3}
		mov	si,TSRdref:wheel
		jz	@@retlastpos		; jump if BX was -1
		mov	si,cx			; bx is {1, 2, 3}	1-left, 2-right, 3-middle button

		xor	cx,cx
		xor	dx,dx
		cmp	bx,2+1
;	if_ be
	ja @@rlpa
; ERRIF (6 ne size BUTTLASTSTATE) "BUTTLASTSTATE structure size changed!"
		add	bx,bx			; BX= X*2
		add	si,bx			; SI+BX=buttrelease		SI= X*2
		add	bx,bx			; BX= X*4 
; si + bx = (X*2) + (X*4) = X*6
; Y = (X+1)*6 + buttrelease - 6 
; 0-left   = buttrelease		;buttrelease	BUTTLASTSTATE <>,...,...		
; 1-right  = buttrelease + 6		;buttrelease	BUTTLASTSTATE ...,<>,...
; 2-middle = buttrelease + 12		;buttrelease	BUTTLASTSTATE ...,...,<>
@@retlastpos:	xchg	[si + bx + offset BUTTLASTSTATE.counter],ax
		mov	cx,[si+bx + offset BUTTLASTSTATE.lastcol]
		mov	dx,[si+bx + offset BUTTLASTSTATE.lastrow]
;	end_ if
@@rlpa:
@retBCDX::	mov	[_ARG_DX_],dx
@retBCX::	mov	[_ARG_CX_],cx
@retBX::	mov	[_ARG_BX_],ax
		ret
releasedata_06	endp

;========================================================================
; 0B - Get motion counters
;========================================================================
;
; In:	none
; Out:	[CX]			(number of mickeys mouse moved
;	[DX]			 horizontally/vertically since last call)
; Use:	none
; Modf:	mickeys
; Call:	@retBCDX
;
mickeys_0B	proc
		xchg	ax,bx			; OPTIMIZE: instead MOV AX,BX
		xor	cx,cx
		xor	dx,dx
		xchg	[mickeys.X],cx
		xchg	[mickeys.Y],dx
		j	@retBCDX
mickeys_0B	endp

;========================================================================
; 11 - Check wheel support and get capabilities flags
;========================================================================
;
; In:	none
; Out:	[AX] = 574Dh ('WM')
;	[CX]			(capabilities flag, bits 1..15 reserved)
;	[BX]			(capabilities flag, all bits reserved)
; Use:	none
; Modf:	AX
; Call:	@retBCX
;
if USE_WHEEL
wheelAPI_11	proc
		mov	[_ARG_AX_],574Dh
;	CODE_	MOV_CX	wheelflags,<db 0,0>
		OPCODE_MOV_CX
wheelflags	db 0,0
		xor	ax,ax
		j	@retBCX
wheelAPI_11	endp
endif ; USE_WHEEL

;========================================================================
; 15 - Get driver storage requirements
;========================================================================
;
; In:	none
; Out:	[BX]			(buffer size)
; Use:	szSaveArea
; Modf:	AX
; Call:	@retBX
;
storagereq_15	proc
		mov	ax,szSaveArea
		j	@retBX
storagereq_15	endp

;========================================================================
; 1B - Get mouse sensitivity
;========================================================================
;
; In:	none
; Out:	[BX]			(horizontal sensitivity, 1..100)
;	[CX]			(vertical sensitivity, 1..100)
;	[DX]			(speed threshold in mickeys/second)
; Use:	sensval, /doublespeed/
; Modf:	AX, CX, DX
; Call:	@retBCDX
;
sensitivity_1B	proc
		mov	ax,[sensval.X]
		mov	cx,[sensval.Y]
		inc	ax
		inc	cx
		xor	dx,dx
;;*		mov	dx,[doublespeed]
		j	@retBCDX
sensitivity_1B	endp

;========================================================================
; 1E - Get display page
;========================================================================
;
; In:	none
; Out:	[BX]			(display page number)
; Use:	none
; Modf:	AX
; Call:	@retBX
;
videopage_1E	proc
		xor	ax,ax			; one display page
		j	@retBX
videopage_1E	endp

;========================================================================
; 01 - Show mouse cursor
;========================================================================
;
; In:	none
; Out:	none
; Use:	none
; Modf:	AX, lowright.Y
; Call:	cursorstatus
;
showcursor_01	proc
		neg	ax			; AL=AH=-1
		mov	byte ptr lowright.Y[1],80h ; place update region far
		j	cursorstatus		;  above the screen (gy >= -15)
showcursor_01	endp

;========================================================================
; 02 - Hide mouse cursor
;========================================================================
;
; In:	none
; Out:	none
; Use:	none
; Modf:	AX
; Call:	cursorstatus
;
hidecursor_02	proc
		dec	ax			; AL=1,AH=0
		;j	cursorstatus
hidecursor_02	endp

;========================================================================
; Hint:	request to cursor redraw (instead refresh) is useful in cases when
;	interrupt handlers try to hide, then show cursor while cursor
;	drawing is in progress
;
cursorstatus	proc
		add	al,[nocursorcnt]
		sub	ah,al			; exit if "already enabled"
		jz	@showret		;   or "counter overflow"
		mov	[nocursorcnt],al
		inc	ah			; jump if cursor changed
		jz	redrawcursor		;  between enabled/disabled
		ret
cursorstatus	endp

;========================================================================
; 07 - Set horizontal cursor range
;========================================================================
;
; In:	CX			(min X)
;	DX			(max X)
; Out:	none
; Use:	none
; Modf:	BX
; Call:	@setnewrange
;
hrange_07	proc
;		MOVREG_	bx,<offset X>
		xor bx,bx	; MOVREG optimizes mov bx,offset POINT.X ...
		j	@setnewrange
hrange_07	endp

;========================================================================
; 08 - Set vertical cursor range
;========================================================================
;
; In:	CX			(min Y)
;	DX			(max Y)
; Out:	none
; Use:	pos
; Modf:	CX, DX, BX, rangemin, rangemax
; Call:	setpos_04
;
vrange_08	proc
;		MOVREG_	bx,<offset Y>
		mov	bx,offset POINT.Y
@setnewrange::	call	setrange
		mov	cx,[pos.X]
		mov	dx,[pos.Y]
		;j	setpos_04
vrange_08	endp

;========================================================================
; 04 - Position mouse cursor
;========================================================================
;
; In:	CX			(X - column)
;	DX			(Y - row)
; Out:	none
; Use:	none
; Modf:	SI
; Call:	@setpos, refreshcursor
;
setpos_04	proc
		mov	si,szClearArea1/2	; clear area 1
; ERRIF (szClearArea1 mod 2 ne 0) "szClearArea1 must be even!"
		call	@setpos
		;j	refreshcursor
setpos_04	endp

;========================================================================

refreshcursor	proc
		sub	[videolock],1
		jc	@showret		; was 0: drawing in progress
		js	@@refreshdone		; was -1: queue already used
		sti

;	loop_
@@rcloop:
		call	drawcursor
@@refreshdone:	inc	[videolock]		; drawing stopped
;	until_ nz				; loop until queue empty
	jz @@rcloop

		cli
@showret::	ret
refreshcursor	endp

;========================================================================
; 09 - Define graphics cursor
;========================================================================
;
; In:	BX			(hot spot X)
;	CX			(hot spot Y)
;	ES:DX			(pointer to bitmaps)
; Out:	none
; Use:	none
; Modf:	AX, CX, DX, BX, SI, DI, ES, hotspot, screenmask, cursormask
; Call:	redrawcursor
;
graphcursor_09	proc
		assume	es:nothing

;----- copy user shape to internal area

		push	ds
		push	ds
		push	es
		pop	ds
		pop	es
		mov	di,TSRdref:hotspot
		xchg	ax,bx			; OPTIMIZE: instead MOV AX,BX
		stosw
		xchg	ax,cx			; OPTIMIZE: instead MOV AX,CX
		stosw
;		memcopy	2*(16+16),,,,,,dx
		mov si,dx
		mov	cx,16+16
		V9K_MIRRORCOPY			; bit 0 = leftmost pixel
		pop	ds
		;j	redrawcursor
graphcursor_09	endp

;========================================================================

redrawcursor	proc
hidecursor::	mov	[newcursor],1		; force cursor redraw
		j	refreshcursor
redrawcursor	endp

;========================================================================
; 0A - Define text cursor
;========================================================================
;
; In:	BX			(0 - SW, else HW text cursor: ignored)
;	CX			(screen mask/start scanline)
;	DX			(cursor mask/end scanline)
; Out:	none
; Use:	none
; Modf:	startscan, endscan
; Call:	@showret, redrawcursor
;
textcursor_0A	proc
		test	bx,bx			; hardware cursor (HWCURSOR=0):
		jnz	@showret		;  keep the software cursor masks
		cmp	cx,[startscan]
;	if_ eq
	jnz @@tcanz
		cmp	dx,[endscan]
		je	@showret		; exit if cursor not changed
;	end_
@@tcanz:
		mov	[startscan],cx
		mov	[endscan],dx
		j	redrawcursor
textcursor_0A	endp

;========================================================================
; 10 - Define screen region for updating
;========================================================================
;
; In:	CX, DX			(X/Y of upper left corner)
;	SI, DI			(X/Y of lower right corner)
; Out:	none
; Use:	none
; Modf:	AX, CX, DX, DI, upleft, lowright
; Call:	redrawcursor
;
updateregion_10	proc
		mov	ax,[_ARG_SI_]
if FOOLPROOF
		cmp	cx,ax
;	if_ ge
	jl @@ur10l
		xchg	cx,ax
;	end_
@@ur10l:
		mov	[upleft.X],cx
		mov	[lowright.X],ax
		xchg	ax,di			; OPTIMIZE: instead MOV AX,DI
		cmp	dx,ax
;	if_ ge
	jl @@ur10l2
		xchg	dx,ax
;	end_
@@ur10l2:
		mov	[upleft.Y],dx
		mov	[lowright.Y],ax
else
		mov	[upleft.X],cx
		mov	[upleft.Y],dx
		mov	[lowright.X],ax
		mov	[lowright.Y],di
endif
		j	redrawcursor
updateregion_10	endp

;========================================================================
; 16 - Save driver state
;========================================================================
;
; In:	BX			(buffer size)
;	ES:DX			(buffer)
; Out:	none
; Use:	SaveArea
; Modf:	CX, SI, DI
; Call:	none
;
savestate_16	proc
		assume	es:nothing
if FOOLPROOF
;;-		cmp	bx,szSaveArea		;!!! TurboPascal IDE
;;-		jb	@stateret		;  workaround: garbage in BX
endif
;		memcopy	szSaveArea,,,dx,,,@TSRdata:SaveArea
		mov di,dx
		mov si,@TSRdata:SaveArea
		mov cx,szSaveArea/2	; happens to be even
		rep movsw
@stateret:	ret
savestate_16	endp

;========================================================================
; 17 - Restore driver state
;========================================================================
;
; In:	BX			(buffer size)
;	ES:DX			(saved state buffer)
; Out:	none
; Use:	none
; Modf:	SI, DI, DS, ES, SaveArea
; Call:	@stateret, redrawcursor
;
restorestate_17	proc
		assume	es:nothing
if FOOLPROOF
;;-		cmp	bx,szSaveArea		;!!! TurboPascal IDE
;;-		jb	@stateret		;  workaround: garbage in BX
endif

;----- do nothing if SaveArea is not changed

;;*		mov	si,TSRdref:SaveArea
;;*		mov	di,dx
;;*		mov	cx,szSaveArea/2
;;*ERRIF (szSaveArea mod 2 ne 0) "szSaveArea must be even!"
;;*		repe	cmpsw
;;*		je	@stateret

;----- change SaveArea

		push	es
		push	dx
		MOVSEG	es,ds,,@TSRdata
		pop	si
		pop	ds
		assume	ds:nothing
		memcopy	szSaveArea,,,@TSRdata:SaveArea
		MOVSEG	ds,es,,@TSRdata
		xor	bx,bx			; offset POINT.X
		call	@restrange		; clamp the restored ranges
		mov	bl,offset POINT.Y
		call	@restrange
		j	redrawcursor
restorestate_17	endp

;========================================================================
;		Set cursor range clamped to the screen
;========================================================================
;
; In:	CX			(min)
;	DX			(max)
;	BX			(offset X/offset Y)
; Out:	none
; Use:	maxcoord
; Modf:	AX, DX, rangemin, rangemax
; Call:	clampcoord
;
@restrange:	mov	cx,word ptr rangemin[bx]
		mov	dx,word ptr rangemax[bx]
setrange	proc
		xchg	ax,cx			; OPTIMIZE: instead MOV AX,CX
if FOOLPROOF
		cmp	ax,dx
;	if_ ge
	jl @@snrl
		xchg	ax,dx
;	end_
@@snrl:
endif
		call	clampcoord
		mov	word ptr rangemin[bx],ax
		xchg	ax,dx
		call	clampcoord
		mov	word ptr rangemax[bx],ax
		ret
setrange	endp

;========================================================================
; In:	AX			(coordinate)
;	BX			(offset X/offset Y)
; Out:	AX			(clamped to 0..maxcoord)
;
clampcoord	proc
		test	ax,ax
;	if_ sign
	jns @@ccns
		xor	ax,ax
;	end_
@@ccns:
		cmp	ax,word ptr maxcoord[bx]
;	if_ gt
	jle @@ccle
		mov	ax,word ptr maxcoord[bx]
;	end_
@@ccle:
		ret
clampcoord	endp

;========================================================================
; 0D - Light pen emulation ON
;========================================================================
;
; In:	none
; Out:	none
; Use:	none
; Modf:	none
; Call:	lightpenoff_0E
;
;;*lightpenon_0D	proc
;;*		mov	al,0
;;*		;j	lightpenoff_0E
;;*lightpenon_0D	endp

;========================================================================
; 0E - Light pen emulation OFF
;========================================================================
;
; In:	none
; Out:	none
; Use:	none
; Modf:	nolightpen?
; Call:	none
;
;;*lightpenoff_0E	proc
;;*		mov	[nolightpen?],al	; OPTIMIZE: AL instead nonzero
;;*		ret
;;*lightpenoff_0E	endp

;========================================================================
; 14 - Exchange User Interrupt Routines
;========================================================================
;
; In:	CX			(new call mask)
;	ES:DX			(new FAR routine)
; Out:	[CX]			(old call mask)
;	[ES:DX]			(old FAR routine)
; Use:	callmask, UIR@
; Modf:	AX
; Call:	UIR_0C
;
exchangeUIR_14	proc
		assume	es:nothing
		;mov	ah,0
		mov	al,[callmask]
		mov	[_ARG_CX_],ax
		mov	ax,word ptr UIR@[0]
		mov	[_ARG_DX_],ax
		mov	ax,word ptr UIR@[2]
		mov	[_ARG_ES_],ax
		;j	UIR_0C
exchangeUIR_14	endp

;========================================================================
; 0C - Define User Interrupt Routine
;========================================================================
;
; In:	CX			(call mask)
;	ES:DX			(FAR routine)
; Out:	none
; Use:	none
; Modf:	UIR@, callmask
; Call:	none
;
UIR_0C		proc
		assume	es:nothing
		saveFAR [UIR@],es,dx
		mov	[callmask],cl
		ret
UIR_0C		endp

;========================================================================
; 0F - Set mickeys/pixels ratios
;========================================================================
;
; In:	CX			(number of mickeys per 8 pix
;	DX			 horizontally/vertically)
; Out:	none
; Use:	none
; Modf:	mickey8
; Call:	none
;
sensitivity_0F	proc
if FOOLPROOF
		test	dx,dx
;	if_ nz					; ignore wrong ratio
	jz @@sensfp
;	andif_ ncxz				; ignore wrong ratio
	jcxz @@sensfp
endif
		mov	[mickey8.X],cx
		mov	[mickey8.Y],dx
if FOOLPROOF
;	end_
@@sensfp:
endif
		ret
sensitivity_0F	endp

;========================================================================
; 1A - Set mouse sensitivity
;========================================================================
;
; In:	BX			(horizontal sensitivity, 1..100)
;	CX			(vertical sensitivity, 1..100)
;	DX			(speed threshold in mickeys/second, ignored)
; Out:	none
; Use:	none
; Modf:	AX, CX, BX
; Call:	senscalc
;
sensitivity_1A	proc
		xchg	ax,bx			; OPTIMIZE: instead MOV AX,BX
;		MOVREG_	bx,<offset X>
	xor bx,bx	; MOVREG optimizes	mov bx,offset POINT.X
		call	senscalc
		xchg	ax,cx			; OPTIMIZE: instead MOV AX,CX
;		MOVREG_	bl,<offset Y>		; OPTIMIZE: BL instead BX
	mov bl,offset POINT.Y
		;j	senscalc
sensitivity_1A	endp

;========================================================================
; In:	AX			(001A value)
;	BX			(offset X/offset Y)
; Out:	none
; Modf:	AX, DX, DI, sensval, senscoeff
; Call:	none
; Hint:	sensval=AX-1, senscoeff=[(sensval^2/3600+1/3)*256]
;
senscalc	proc
		dec	ax
;		cmp	ax,100			; ignore original values
	db 3dh, 100, 0	; "cmp ax, word 100"
		; JWASM encodes this in the "byte 100" syntax, same size
;	if_ below				;  outside [1..100]
	jnc @@scnc
		mov	word ptr sensval[bx],ax
		mul	ax			; DX:AX=V^2 (0<=X^2<10000)
		add	ax,3600/3
		;adc	dx,0			; DX:AX=V^2+1200
		;mov	dh,0
		;xchg	dh,dl
;		xchg	dl,al
		xchg	al,dl	; JWASM and TASM use opposite encoding
;		xchg	dl,ah			; DX:AX=(V^2+1200)*256
		xchg	ah,dl	; JWASM and TASM use opposite encoding
		mov	di,3600
		div	di			; AX=(V^2+1200)*256/3600
		mov	word ptr senscoeff[bx],ax
;	end_
@@scnc:
		ret
senscalc	endp

;========================================================================
; 13 - Define double-speed threshold
;========================================================================
;
; In:	DX			(speed threshold in mickeys/second)
; Out:	none
; Use:	none
; Modf:	/DX/, /doublespeed/
; Call:	none
;
doublespeed_13	proc
;;*		test	dx,dx
;;*	if_ zero
;;*		mov	dl,64
;;*	end_
;;*		mov	[doublespeed],dx
		;ret
doublespeed_13	endp

;========================================================================
; 0D 0E 11 12 18 19 1C 1D - Null function for not implemented calls
;========================================================================

nullfunc	proc
		ret
nullfunc	endp

;========================================================================
;				INT 33 handler
;========================================================================

		even
handler33table	dw TSRcref:resetdriver_00
		dw TSRcref:showcursor_01
		dw TSRcref:hidecursor_02
		dw TSRcref:status_03
		dw TSRcref:setpos_04
		dw TSRcref:pressdata_05
		dw TSRcref:releasedata_06
		dw TSRcref:hrange_07
		dw TSRcref:vrange_08
		dw TSRcref:graphcursor_09
		dw TSRcref:textcursor_0A
		dw TSRcref:mickeys_0B
		dw TSRcref:UIR_0C
		dw TSRcref:nullfunc		;lightpenon_0D
		dw TSRcref:nullfunc		;lightpenoff_0E
		dw TSRcref:sensitivity_0F
		dw TSRcref:updateregion_10
if USE_WHEEL
		dw	TSRcref:wheelAPI_11
else
		dw	TSRcref:nullfunc		;11 - wheel API
endif
		dw TSRcref:nullfunc		;12 - large graphics cursor
		dw TSRcref:doublespeed_13
		dw TSRcref:exchangeUIR_14
		dw TSRcref:storagereq_15
		dw TSRcref:savestate_16
		dw TSRcref:restorestate_17
		dw TSRcref:althandler_18
		dw TSRcref:althandler_19
		dw TSRcref:sensitivity_1A
		dw TSRcref:sensitivity_1B
		dw TSRcref:nullfunc		;1C - InPort mouse only
		dw TSRcref:nullfunc		;1D - define display page #
		dw TSRcref:videopage_1E
		dw TSRcref:disabledrv_1F
		dw TSRcref:enabledriver_20
		dw TSRcref:softreset_21

		db	'MOUSE'			; signature right before the entry
handler33	proc
		assume	ds:nothing,es:nothing
		cld
		test	ah,ah
;	if_ zero
	jnz @@h33nz
		push	ds
		MOVSEG	ds,cs,,@TSRdata
		cmp	al,21h
		ja	language_23
		push	es
		PUSHALL
		mov	si,ax			;!!! AX must be unchanged
		mov	bp,sp
		add	si,si
		call	handler33table[si]	; call by calculated offset
rethandler::	POPALL
		pop	es
		pop	ds
;	end_
@@h33nz:
		iret
		assume	ds:@TSRdata

;========================================================================
; 23 - Get language for messages
; Out:	[BX]			(language code: 0 - English)
;
language_23:	cmp	al,23h
		je	@iretBX0

;========================================================================
; 24 - Get software version, mouse type and IRQ
; Out:	[AX] = 24h/FFFFh	(installed/error)
;	[BX]			(version)
;	[CL] = 1		(8259 IR1)
;	[CH] = 2		(mouse type: serial)
;	[DL]			(V9K: 7201 channel, 0=A, 1=B)
;	[DH] = 'V'		(V9K: DL is valid)
; Use:	driverversion
;
version_24:	cmp	al,24h
;	if_ eq
	jnz @@v24nz
		mov	bx,driverversion
		mov	cx,0201h		; CH=2 serial, CL=1 IR1
;	CODE_	MOV_DX	v9kport,<db ?,'V'>
		OPCODE_MOV_DX
v9kport		db 0FFh,'V'		; 0=A, 1=B, set at install
;	end_
@@v24nz:

;========================================================================
; 26 - Get maximum virtual screen coordinates
; Out:	[BX]			(mouse disabled flag)
;	[CX] = 799		(max virtual screen X)
;	[DX] = 399		(max virtual screen Y)
; Use:	maxcoord
;
maxscreen_26:	cmp	al,26h
;	if_ eq
	jnz @@m26nz
		lds	cx,[maxcoord]		; DS is restored at the exit
		mov	dx,ds
;	CODE_	MOV_BX	disabled?,<db 1,0>	; 1=driver disabled
		OPCODE_MOV_BX
disabled?	db 1,0
;	end_
@@m26nz:

;========================================================================
; 27 - Get screen/cursor masks and mickey counters
; Out:	[AX]			(screen mask/start scanline)
;	[BX]			(cursor mask/end scanline)
;	[CX]			(number of mickeys mouse moved
;	[DX]			 horizontally/vertically since last call)
; Use:	startscan, endscan
; Modf:	mickeys
;
cursor_27:	cmp	al,27h
;	if_ eq
	jnz @@c27nz
		mov	ax,[startscan]
		mov	bx,[endscan]
		xor	cx,cx
		xor	dx,dx
		xchg	cx,[mickeys.X]
		xchg	dx,[mickeys.Y]
		pop	ds
		iret
;	end_
@@c27nz:

;========================================================================
; 31 - Get current virtual cursor coordinates
; Out:	[AX]			(min virtual cursor X)
;	[BX]			(min virtual cursor Y)
;	[CX]			(max virtual cursor X)
;	[DX]			(max virtual cursor Y)
; Use:	rangemin, rangemax
;
cursrange_31:	cmp	al,31h
;	if_ eq
	jnz @@c31nz
		mov	ax,[rangemin.X]
		mov	bx,[rangemin.Y]
		lds	cx,[rangemax]
		mov	dx,ds
		pop	ds
		iret
;	end_
@@c31nz:

;========================================================================
; 32 - Get supported advanced functions flag
; Out:	[AX]			(bits 15-0=function 25h-34h supported)
;	[CX] = 0
;	[DX] = 0
;	[BX] = 0
;
active_32:	cmp	al,32h
;	if_ eq
	jnz @@a32nz
		mov	ax,0110010000001100b	; active: 26 27 2A 31 32
		xor	cx,cx
		xor	dx,dx
@iretBX0:	xor	bx,bx
		pop	ds
		iret
;	end_
@@a32nz:

;========================================================================
; 4D - Get pointer to copyright string
; Out:	[ES:DI]			(copyright string)
; Use:	IDstring
;
copyright_4D:	cmp	al,4Dh
;	if_ eq
	jnz @@c4dnz
		MOVSEG	es,cs,,@TSRcode
		mov	di,TSRcref:IDstring
;	end_
@@c4dnz:

;========================================================================
; 6D - Get pointer to version
; Out:	[ES:DI]			(version string)
; Use:	msversion
;
version_6D:	cmp	al,6Dh
;	if_ eq
	jnz @@v6dnz
		MOVSEG	es,cs,,@TSRcode
		mov	di,TSRcref:msversion
;	end_
@@v6dnz:


;========================================================================
; 2A - Get cursor hot spot
; Out:	[AX]			(cursor visibility counter)
;	[BX]			(hot spot X)
;	[CX]			(hot spot Y)
;	[DX] = 1=bus/2=serial/3=InPort/4=PS2/5=HP (mouse type)
; Use:	nocursorcnt, hotspot
;
hotspot_2A:	cmp	al,2Ah
;	if_ eq
	jnz @@h2anz
		;mov	ah,0
		mov	al,[nocursorcnt]
		lds	bx,[hotspot]
		mov	cx,ds
;	CODE_	MOV_DX	mouseinfo1,<db 4,0>
		OPCODE_MOV_DX
mouseinfo1	db 2,0			; serial
;	end_
@@h2anz:

		pop	ds
		iret
handler33	endp

;======================== END OF INT 33 SERVICES ========================


msversion	db driverversion / 100h,driverversion mod 100h
IDstring	db 'CuteMouse V9K ',CTMVER,0
szIDstring = $ - IDstring

TSRend		label byte

; Resident size gate (Victor 9000 port): tools/ressize.py reads the RESSZ marker
; (in the transient .data below) from the built .bin and fails the build above LIMIT.
; The assembler's own `if`/%echo cannot be used: they see pass-1 addresses, which
; are short by the later short->near jump extensions (3108 vs the real 3134).
; LIMIT is 0C20h (MOUSE.DEV's 3104 bytes) from phase 1 on (0C40h in phase 0).
LIMIT		equ 0C20h


;======================= INITIALIZATION PART DATA =======================

.const

; messages segment virtual ; place at the end of current bsegment
%include ?LANG.msg
; messages ends

S_mousetype	dw 0			; 0 was PS/2
if USE_MSYS
		dw dataref:S_inMSYS
else
		dw 0
endif
		dw dataref:S_inLT
		dw dataref:S_inMS

.data

ressize_marker	db 'RESSZ'		; read by tools/ressize.py
		dw TSRend-TSRstart	; resident bytes (PSP included)
		dw LIMIT
		dw TSRdata-TSRstart	; must not be below TSRavail
		dw TSRavail-TSRstart

options		dw 0
OPT_3button	equ	10000b
if USE_MSYS
OPT_MSYS	equ    100000b
endif
OPT_lefthand	equ   1000000b

h33class	db 0			; 0=no INT 33h driver, 1=unknown handler
tstart		dw 0			; detection timer: start, 1/100 s
tlimit		dw 0			;  in the minute; timeout, 1/100 s;
tcap		dw 0			;  iteration cap (DOS clock may stop)

WRinit		db 4,WR4_VAL		; WR4: x16 clock, 1 stop bit, no parity
		db 3			; WR3: Rx 7 bits (8 with /M),
WR3init		db WR3_VAL		;  Rx enable, no auto enables
		db 5,WR5_RTSOFF		; WR5: DTR, Tx 8 bits, Tx enable, RTS off
		db WR0_RESEXT		; WR0: reset ext/status interrupts
		db 1,0			; WR1: no interrupts (polled detection)
szWRinit = $ - WRinit


;============================== REAL START ==============================

.code

say		macro	stroff ; :vararg
;		MOVOFF_	di,<stroff>
		mov	di,offset stroff
		call	sayASCIIZ
endm

real_start:	cld
		DOSGetIntr 33h
		saveFAR [oldint33],es,bx	; save old INT 33h handler

;----- parse command line

		say	@data:Copyright		; 'Cute Mouse Driver'
		mov	si,offset PSP:cmdline_len
		lodsb
		cbw				; OPTIMIZE: instead MOV AH,0
		mov	bx,ax
		mov	[si+bx],ah		; OPTIMIZE: AH instead 0
		call	commandline		; examine command line (/U, /? exit)
		mov	di,dataref:Syntax	; no port: usage screen, exit 1
		cmp	[v9kport],1
		ja	@@exitmsg

;----- classify INT 33h: never call a stray vector

		call	getCuteMouse
		je	@@reload		; jump if our driver (in ES)
		mov	di,dataref:E_mousedev	; 'MOUSE' driver, not ours: exit 1
		cmp	bl,2
		je	@@exitmsg
		mov	[h33class],bl

;----- transaction 1: fresh install

		DOSGetIntr 41h
		saveFAR [oldIRQaddr],es,bx	; handed back by disable7201
		mov	ax,IO_SEG
		mov	es,ax
		mov	al,es:[PIC_IMR]		; 8259 IMR (bit 1 = IR1)
		mov	[oldIMR],al
		call	detectmouse
		jc	@@nomouse
		mov	[mousetype],bl

		cmp	[h33class],1
;	if_ eq					; if unknown INT 33h handler
	jne @@noreplace
		say	@data:S_replace		; 'it will be replaced'
;	end_
@@noreplace:

;----- set INT 33 handler (the TSR stays in place)

		mov	bx,(TSRend-TSRstart+15)/16
		push	bx
		call	prepareTSR		; memory segment in ES
		push	ds
		MOVSEG	ds,es,,@TSRcode
		mov	[disabled?],1		; copied back in setupdriver
		DOSSetIntr 33h,,,@TSRcode:handler33
		POPSEG	ds,@data
		pop	ax
		mov	di,dataref:S_installed	; 'Installed at '
		mov	cl,0			; errorlevel
		j	@@setup

@@nomouse:	mov	di,dataref:E_nomouse	; 'No mouse detected...': exit 2
@@exitmsg:	jmp	EXITMSG

;----- transaction 2: reload over our resident driver (in ES)

@@reload:	mov	al,es:[v9kport]
		cmp	al,[v9kport]
		jne	@@otherport
						; same port: the resident driver
						;  proved the mouse, no init and
						;  no detection; its type is read
						;  back from its patched code
if USE_MSYS
		mov	bl,1
		cmp	word ptr es:[mouseproc],MSMproc-mouseproc-2
		je	@@gottype		; Mouse Systems
endif
		mov	bl,3
		cmp	byte ptr es:[MSLTCODE3],0C3h
		je	@@gottype		; RET: Microsoft
		dec	bx
		cmp	byte ptr es:[MSLTCODE3+1],3
		je	@@gottype		; "mov cl,3": Logitech
		mov	bl,83h			; "mov cl,2": Microsoft+wheel
		j	@@gottype

@@otherport:	push	es			; init and detect on the new
		call	detectmouse		;  channel only, the old driver
		pop	es			;  keeps running on its own
		jc	@@nomouse
@@gottype:	mov	[mousetype],bl
		mov	di,dataref:S_reset	; 'Resident part reset to '
		mov	cx,4C00h		; terminate, errorlevel 0

;-----

@@setup:	push	ax			; size of TSR for INT 21/31
		push	cx			; exit function and errorlevel
		push	di
		call	setupdriver		; reload: fn 1Fh first (may exit)
		pop	di
		call	sayASCIIZ		; 'Installed at '/'Resident part...'
		say	@data:S_atport		; 'serial port X in '
		mov	al,[mousetype]
		mov	bx,dataref:S_CRLF
		add	al,al
;	if_ carry				; if wheel (=8xh)
	jnc @@mfnc
		mov	bx,dataref:S_wheel
;	end_
@@mfnc:
		cbw				; OPTIMIZE: instead MOV AH,0
		xchg	si,ax			; OPTIMIZE: instead MOV SI,AX
;		say	S_mousetype[si]
		mov	di, S_mousetype[si]
		call	sayASCIIZ
;		say	bx
		mov	di,bx
		call    sayASCIIZ

;----- close all handles (20 pieces) to prevent decreasing system
;	pool of handles if INT 21/31 used

		mov	bx,19
;	loop_
@@mfns:
;		DOSCloseFile
		mov	ah,3eh
		int	21h
		dec	bx
;	until_ sign
	jns @@mfns

;-----

		pop	ax			; AH=31h (TSR) or 4Ch (EXIT)
		pop	dx
		int	21h

;========================================================================
;		Setup resident driver code and parameters
;========================================================================
;
; In:	ES			(driver segment, ES=DS for a fresh install)
; Out:	none			(exits with errorlevel 2 if the resident
;				 driver refuses fn 1Fh)
;
setupdriver	proc

;----- setup left hand mode handling

;	CODE_	MOV_CX	mousetype,<db ?,0>	; 1=MSys,2=LT,3=MS,83h=MS+wheel
		OPCODE_MOV_CX
mousetype	db ?,0
		mov	al,00000011b	; =3
;		testflag [options],OPT_lefthand
		test byte ptr [options], OPT_lefthand	; 40h, TASM optimizes
;	if_ nz
	jz @@mtz2
		xor	al,00000011b	; =3
;	end_
@@mtz2:
		mov	[swapmask],al

;----- setup buttons count, mask and wheel flags

		mov	al,3
;		testflag [options],OPT_3button
		test byte ptr [options], OPT_3button	; 10h, TASM optimizes
;	if_ zero
	jnz @@mtnz
		cmp	cl,al			; OPTIMIZE: AL instead 3
;	andif_ eq				; if MS mode (=3)
	jnz @@mtnz
@@setbuttons:	mov	[buttonsmask],al	; OPTIMIZE: AL instead 0011b
		dec	ax
		mov	[buttonscnt],al		; OPTIMIZE: AL instead 2
;	end_
@@mtnz:

if USE_WHEEL
		cmp	cl,80h			; if some wheel protocol
;	if_ ae
	jb @@mtb
		inc	wheelflags[0]		; report "wheel present"
		mov	[wheelmask],00001111b	; =0Fh
;	end_
@@mtb:
endif ; USE_WHEEL

;----- setup mouse handlers code

;	block_
		fixnear	enableproc,enable7201
		fixnear	disableproc,disable7201
		dec	cx
if USE_MSYS
;	 breakif_ zero				; break if Mouse Systems mode (=1)
	jz @@mtblock

		fixnear	mouseproc,MSLTproc
endif ; USE_MSYS
		dec	cx
;	 breakif_ zero				; break if Logitech mode (=2)
	jz @@mtblock

		fixcode	MSLTCODE3,,2
		loop	@@setother		; break if wheel mode (=83h)

		cmp	al,2			; OPTIMIZE: AL instead [buttonscnt]
;	 if_ ne					; if not MS2
	jz @@mtbz
		fixcode	MSLTCODE2,075h		; JNZ
;	 end_
@@mtbz:
		mov	al,0C3h			; RET
		fixcode	MSLTCODE1,al
		fixcode	MSLTCODE3,al
;	end_ block
@@mtblock:

;----- setup, if required, other parameters

@@setother:
if CHAIN41
		push	es			; chain the old INT 41h only if
		mov	dx,es			;  it is non-null, outside the
		les	si,es:[oldIRQaddr]	;  driver and not a bare IRET
		assume	es:nothing
		mov	cl,0
		mov	ax,es
		or	ax,si
		jz	@@nochain
		mov	ax,es
		cmp	ax,dx
		je	@@nochain
		cmp	byte ptr es:[si],0CFh	; IRET
		je	@@nochain
		inc	cx
@@nochain:	pop	es
		mov	[chain_ok],cl
endif ; CHAIN41

;----- reload: disable the resident driver immediately before the copy

		mov	ax,es
		mov	cx,ds
		cmp	ax,cx
;	if_ ne					; if driver already resident
	je @@fresh
		push	es
		mov	al,1Fh			; ownership checked first: on a
		call	mousedrv		;  refusal nothing was changed
		pop	es
		cmp	al,1Fh
		mov	di,dataref:E_noreload	; 'reload refused': exit 2
		jne	@@refused
;	end_
@@fresh:
		mov	al,es:[disabled?]	; get back [disabled?]
		mov	[disabled?],al

;----- copy TSR image (even if ES=DS - this is admissible)

		memcopy	((TSRend-TSRdata+1)/2)*2,es,,@TSRdata:TSRdata,ds,,@TSRdata:TSRdata

;----- call INT 33/0000 (Reset driver)

		pop	ax
		pushf				;!!! Logitech MouseWare
		push	cs
		push	ax			;  Windows driver workaround
		mov	ax,TSRcref:handler33
		push	es
		push	ax
		xor	ax,ax			; reset driver
		nop				; -X-
		retf				; jump to relocated INT33

@@refused:	jmp	EXITMSG
setupdriver	endp

;========================================================================
;		Initialise the 7201 channel and detect the mouse
;========================================================================
;
; In:	IOctrl, v9kport		(channel, set by the command line)
; Out:	Carry flag		(no mouse found; channel reset, RTS off)
;	BL			(mouse type: 2=Logitech,3=MS,83h=MS+wheel)
; Use:	WRinit, options
; Modf:	AX, CX, DX, BX, SI, DI, ES, tstart, tlimit, tcap
; Call:	starttimer, pollrx
;
detectmouse	proc
if USE_MSYS
		test	byte ptr [options],OPT_MSYS
;	if_ nz					; Mouse Systems: 8N1
	jz @@dm7bits
		mov	[WR3init],WR3_VAL8
;	end_
@@dm7bits:
endif
		mov	ax,IO_SEG
		mov	es,ax
		mov	bx,[IOctrl]		; SIO_CTRL_A/B of our channel
		mov	al,[v9kport]
		cbw
		xchg	di,ax			; DI=0/1: 8253 counter offset

;----- program the channel (polled, IF=0 around the pointer pairs)

		cli
		mov	al,es:[bx]		; RR0: two dummy reads reset a
		mov	al,es:[bx]		;  pointer left set by somebody
		mov	byte ptr es:[bx],WR0_CHRESET ; WR0: reset our channel only
		mov	ax,di
		mov	cl,6
		shl	al,cl
		or	al,36h			; 8253: counter 0 (36h) or 1 (76h),
		mov	es:[PIT_CTRL],al	;  LSB+MSB, mode 3, binary
		mov	byte ptr es:[di+PIT_CNT0],BAUD_COUNT and 0FFh ; count LSB
		mov	byte ptr es:[di+PIT_CNT0],BAUD_COUNT shr 8 ; count MSB
		mov	byte ptr es:[SIO_CTRL_A],2 ; WR0A: pointer 2
		mov	byte ptr es:[SIO_CTRL_A],WR2A_VAL ; WR2A (both channels)
		mov	si,dataref:WRinit
		mov	cx,szWRinit
;	countloop_
@@wrloop:	lodsb				; WR4, WR3, WR5 (RTS off), WR0, WR1
		mov	es:[bx],al		; pointer/value pairs on our port
		loop	@@wrloop
		sti

;----- hold RTS off for 300 ms (mouse unpowered), drain the receiver

		mov	ax,30
		call	starttimer
;	loop_
@@drain:	call	pollrx
;	until_ carry
	jnc @@drain
		cli
		mov	byte ptr es:[bx],5	; WR0: pointer 5
		mov	byte ptr es:[bx],WR5_RTSON ; WR5: RTS on, the mouse powers up
		sti

;----- detect if Microsoft or Logitech mouse present

		mov	dx,0103h		; DL=mouse type, DH=1: no traffic
		mov	ax,200			; 2.0 s for the first byte
;	countloop_ 4,cx				; scan 4 first bytes
	mov cx,4
@@detloop:	call	starttimer
		call	pollrx
		jc	@@detdone		; timeout: no (more) data
		mov	dh,0			; any traffic counts as a mouse
		cmp	al,'('-20h
;	 breakif_ eq				; break if PnP data starts
	jz @@detdone
		cmp	al,'Z'			; PnP: wheel?
;	 if_ eq
	jnz @@prsnz2
		mov	dl,83h			; ...MS mouse+wheel found
;	 end_
@@prsnz2:
		cmp	al,'3'			; PnP: logitech?
;	 if_ eq
	jnz @@prsnz3
		mov	dl,2			; ...Logitech mouse found
;	 end_
@@prsnz3:
		mov	ax,20			; then 0.2 s of silence ends it
;	end_ countloop
	loop @@detloop
@@detdone:

if USE_MSYS
		test	byte ptr [options],OPT_MSYS
;	if_ nz					; Mouse Systems sends no PnP ID
	jz @@dmnotmsys
		mov	dx,1
;	end_
@@dmnotmsys:
endif
		shr	dh,1			; 1 makes carry flag
;	if_ carry				; if nothing received
	jnc @@detfound
		mov	byte ptr es:[bx],WR0_CHRESET ; WR0: channel reset (WR1 is
;	end_					;  already 0): RTS off, port quiet
@@detfound:
		mov	bl,dl			; keeps CF
		ret
detectmouse	endp

;========================================================================
; In:	AX			(timeout, 1/100 s)
; Out:	none
; Modf:	AX, tstart, tlimit, tcap
; Call:	gettime
;
starttimer	proc
		mov	[tlimit],ax
		mov	[tcap],0		; 65536 polls at most
		call	gettime
		mov	[tstart],ax
		ret
starttimer	endp

;========================================================================
; In:	ES:BX			(SIO_CTRL_A/B)
; Out:	Carry flag		(timeout)
;	AL			(received byte if no carry)
; Modf:	AX, tcap
; Call:	gettime
;
pollrx		proc
;	loop_					; time is checked even while
@@pollloop:	dec	[tcap]			;  bytes arrive: a babbling line
		jz	@@polltimeout		;  cannot stall the drain
		call	gettime
		sub	ax,[tstart]
;	 if_ carry				; the minute (or hour, or
	jnc @@pollnc
		add	ax,60*100		;  midnight) wrapped
;	 end_
@@pollnc:
		cmp	ax,[tlimit]
		jae	@@polltimeout
		test	byte ptr es:[bx],RR0_RXAVAIL ; RR0 bit 0: Rx char available?
;	until_ nz
	jz @@pollloop
		mov	al,es:[bx-2]		; SIO_DATA_A/B (CF=0 from TEST)
		ret
@@polltimeout:	stc
		ret
pollrx		endp

;========================================================================
; Out:	AX			(time in the current minute, 1/100 s)
; Modf:	none
; Call:	INT 21/2C
;
gettime		proc
		push	cx
		push	dx
		mov	ah,2Ch
		int	21h			; DH=seconds, DL=1/100 seconds
		mov	al,100
		mul	dh
		mov	dh,0
		add	ax,dx
		pop	dx
		pop	cx
		ret
gettime		endp

;========================================================================
;		Check if CuteMouse driver is installed
;========================================================================
;
; In:	oldint33		(current INT 33h vector)
; Out:	Zero flag		(ZF=1 if our driver with this exact layout)
;	BL			(0=no driver: null or offset<5,
;				 1=unknown handler: no 'MOUSE' signature,
;				 2=other 'MOUSE' driver, 3=ours)
;	ES			(driver segment)
; Use:	IDstring
; Modf:	AX, CX, SI, DI
; Call:	mousedrv
;
getCuteMouse	proc
		xor	bx,bx			; no driver
		les	di,[oldint33]
		assume	es:nothing
		cmp	di,5
		jb	@@gcmret		; null vector or offset < 5
		inc	bx			; unknown handler: never call it
		sub	di,5
		mov	si,TSRcref:handler33-5	; our own 'MOUSE' signature
		mov	cx,5
		repe	cmpsb
		jne	@@gcmret
		inc	bx			; 'MOUSE' driver
		xor	di,di
		mov	es,di			; ES:DI=0 preset for fn 4Dh
		mov	al,4Dh			; get copyright string
		push	bx
		call	mousedrv
		pop	bx
		mov	si,TSRcref:IDstring
		cmp	di,si
;	if_ eq					; exact layout: same offset
	jnz @@gcmret
		mov	cx,szIDstring
		repe	cmpsb
;	 if_ eq
	jnz @@gcmret
		inc	bx			; ours
;	 end_
;	end_
@@gcmret:	cmp	bl,3
		ret
getCuteMouse	endp

;========================================================================
;			Call mouse driver if present
;========================================================================
;
; In:	AL			(function)
; Out:	results of INT 33h, if driver installed
; Use:	oldint33
; Modf:	AH
; Call:	INT 33		(only a vector classified by getCuteMouse)
;
mousedrv	proc
		mov	cx,word ptr oldint33[2]
;	if_ ncxz
	jcxz @@mdcxz
		mov	ah,0
		pushf				;!!! Logitech MouseWare
		call	[oldint33]		;  Windows driver workaround
;	end_
@@mdcxz:
		ret
mousedrv	endp


;========================= COMMAND LINE PARSING =========================

;========================================================================
;		Parse Serial option: /SA, /SB (7201 channel A/B)
;========================================================================

_serialopt	proc
		lodsb
@setport::	and	al,not 20h		; uppercase
		sub	al,'A'
		cmp	al,1
		mov	cx,dataref:E_argument	; 'Error: Invalid argument'
		ja	BADOPTION		; only A or B
		mov	[v9kport],al		; 0=A, 1=B
		add	al,SIO_CTRL_A
		mov	byte ptr [IOctrl],al	; SIO_CTRL_A/B for the ISR
		add	al,'A'-SIO_CTRL_A
		mov	[S_port],al		; port letter in the messages
		mov	[E_port],al
		ret
_serialopt	endp

;========================================================================
;			Parse Resolution option
;========================================================================

_resolution	proc
		;mov	ah,0
		mov	bx,(9 shl 8)+0
		call	parsedigit		; first argument
;	if_ nc
	jc @@resc
		mov	ah,al
		;mov	bx,(9 shl 8)+0
		call	parsedigit		; second argument
		jnc	@@setres		; jump if digit present
;	end_
@@resc:
		mov	al,ah			; replicate missing argument

@@setres:	add	ax,0101h
		push	ax			; AL=RY+1, AH=RX+1
		mov	al,10
		mul	ah			; AX=10*(RX+1)
		mov	bx,offset POINT.X+(DefArea-SaveArea)
		call	senscalc
		pop	ax
		mov	ah,10
		mul	ah			; AX=10*(RY+1)
		mov	bx,offset POINT.Y+(DefArea-SaveArea)
		jmp	senscalc
_resolution	endp

;========================================================================
; In:	DS:SI			(string pointer)
;	BL			(low bound)
;	BH			(upper bound)
; Out:	DS:SI			(pointer after digit)
;	Carry flag		(no digit)
;	AL			(digit if no carry)
; Use:	none
; Modf:	CX
; Call:	BADOPTION
;
parsedigit	proc
		lodsb
		;_ch2digit
		sub	al,'0'
		cmp	al,bh
;	if_ be
	ja @@pda
		cmp	al,bl
		jae	@ret			; JAE mean CF=0
;	end_
@@pda:
		cmp	al,10
		mov	cx,dataref:E_argument	; 'Error: Invalid argument'
		jb	BADOPTION		; error if decimal digit
		dec	si
		stc
@ret::		ret
parsedigit	endp

;========================================================================
.const

cmOPTION	struc	; OPTION is a reserved word in some MASM / TASM
  optchar	db ?
  optmask	dw 0
  optproc@	dw ?
cmOPTION ends

OPTABLE		cmOPTION <'S',,				_serialopt>
		cmOPTION <'3' and not 20h,OPT_3button,	@ret>
		cmOPTION <'R',,				_resolution>
		cmOPTION <'L',OPT_lefthand,		@ret>
		cmOPTION <'U',,				unloadTSR>
		cmOPTION <'?' and not 20h,,		EXITMSG>
if USE_MSYS
		cmOPTION <'M',OPT_MSYS,			@ret>
endif
OPTABLEend	label byte

.code

;========================================================================
; In:	DS:SI			(null terminated command line)
;
commandline	proc
;	loop_
@@clloop:
		lodsb
		test	al,al
		jz	@ret			; exit if end of command line
		cmp	al,' '
;	until_ above				; skips spaces and controls
	jbe @@clloop

		cmp	al,'/'			; option character?
;	if_ eq
	jnz @@clnz
		lodsb
		and	al,not 20h		; uppercase
		mov	di,dataref:Syntax	; 'Options:'
		mov	bx,dataref:OPTABLE
;	 loop_
@@cloloop:
		cmp	al,[bx + offset cmOPTION.optchar]
;	  if_ eq
	jnz @@clonz
		mov	ax,[bx + offset cmOPTION.optmask]
		or	[options],ax
;		call	[bx + offset cmOPTION.optproc@]
		call	[bx + cmOPTION.optproc@]
		j	commandline
;	  end_
@@clonz:
		add	bx,size cmOPTION
		cmp	bx,dataref:OPTABLEend
;	 until_ ae
	jb @@cloloop
		j	@@badopt
;	end_ if
@@clnz:
		call	@setport		; bare A or B word
		j	commandline

@@badopt:	mov	cx,dataref:E_option	; 'Error: Invalid option'
BADOPTION::	say	@data:E_error		; 'Error: Invalid '
;		say	cx			; 'option'/'argument'
		mov	di,cx
		call	sayASCIIZ
		mov	di,dataref:E_help	; 'Enter /? on command line'

EXITMSG::	mov	bl,[di]
		inc	di
;		say	di
		call	sayASCIIZ
		say	@data:S_CRLF
		xchg	ax,bx			; OPTIMIZE: instead MOV AL,BL
		.exit				; terminate, al=return code
commandline	endp

;========================================================================
; In:	DS:DI			(null terminated string)
; Out:	none
; Use:	none
; Modf:	AH, DL, DI
; Call:	none
;
sayASCIIZ_	proc
;	loop_
@@sazloop:
		mov	ah,2
		int	21h		; write character in DL to stdout
		inc	di
sayASCIIZ::	mov	dl,[di]
		test	dl,dl
;	until_ zero
	jnz @@sazloop
		ret
sayASCIIZ_	endp


;============================ TSR MANAGEMENT ============================

;========================================================================
;			Unload driver and quit
;========================================================================

unloadTSR	proc
		call	getCuteMouse		; check if CTMV9K installed
		mov	di,dataref:E_nocute	; 'CuteMouse driver is not installed!'
		jne	EXITMSG

		push	es
		mov	al,1Fh			; disable CuteMouse driver
		call	mousedrv		;  (ownership checked first)
		mov	cx,es
		pop	es

		cmp	al,1Fh
		mov	di,dataref:E_notunload	; 'Driver unload failed...'
		jne	EXITMSG			; refused: nothing was changed
		push	ds
;		DOSSetIntr 33h,cx,,bx		; restore old int33 handler
		mov	dx,bx
		mov	ax,2533h
		mov	ds,cx
		int	21h
		pop	ds
		mov	bx,es:[IOctrl]		; channel of the resident driver
		call	FreeMem
		mov	ax,IO_SEG
		mov	es,ax
		mov	byte ptr es:[bx],WR0_CHRESET ; WR0: channel reset, RTS off
		mov	di,dataref:S_unloaded	; 'Driver successfully unloaded...'
		j	EXITMSG
unloadTSR	endp

;========================================================================
; Prepare memory for TSR (the TSR always stays in place)
;
; In:	BX			(TSR size)
;	DS			(PSP segment)
; Out:	ES			(memory segment to be TSR)
;	CH			(exit code for INT 21)
; Use:	PSP:2Ch
; Modf:	AH
; Call:	INT 21/49
;
prepareTSR	proc
		assume	ds:PSP
		mov	cx,[env_seg]
;	if_ ncxz				; suggested by Matthias Paul
	jcxz @@prepcxz
		DOSFreeMem cx			; release environment block
;	end_
@@prepcxz:
		assume	ds:@data
		mov	ch,31h			; TSR exit, al=return code
		push	ds
		pop	es
;		mov	es:[PSP:DOS_exit],cx	; memory shouldn't be
						;  interpreted as PSP
						;  (CX != 20CDh)
		mov	es:[0],cx	; JWASM complains about es:PSP:...
		ret
prepareTSR	endp


;=========================== MEMORY HANDLING ============================

;========================================================================
; In:	ES			(segment to free)
; Out:	none
; Use:	none
; Modf:	AH
; Call:	INT 21/49
;
FreeMem		proc
		assume	es:nothing
		DOSFreeMem			; free allocated memory
		ret
FreeMem		endp

;========================================================================

end start
