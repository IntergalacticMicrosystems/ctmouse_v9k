; VTEST.COM - DOSBox test bench for ctmousev-video.inc (see README.md, check.py)
;
; Reads CMDS.BIN (written by check.py), runs each command against the real include code with a
; fake CRTC (V9K_TESTCRTC: R12:R13 from a variable) and a fake screen RAM / bitmap in
; conventional memory, and appends the results to OUT.BIN. check.py replays the same commands
; on the Python oracle (tools/v9kmouse.py) and compares.
;
; Command = 5 words: op, a, b, c, d. SETMASK is followed by 32 mask words (fn 9 order).
; Build: jwasm -c -bin -0 -I<repo> -Fovtest.com tools/video/vtest.asm

POINT		struc
  X		dw ?
  Y		dw ?
POINT ends

TSRdref		equ <offset DGROUP>
V9K_TESTCRTC	equ 1
V9K_SCRSEG	equ <[fake_scrseg]>
MODEGUARD	equ 1
HWCURSOR	equ 0

V9K_PART = 1
include ctmousev-video.inc

.model tiny
.code
		org	100h
start:		jmp	main

;----- driver state mock (names and types as in ctmousev.asm)

		even
spritebuf	db	4*16 dup (0)
		V9K_UDATA
		even
startscan	dw	0FFFFh
endscan		dw	8000h
hotspot		POINT	<0,0>
screenmask	db	2*16 dup (0)
cursormask	db	2*16 dup (0)
nocursorcnt	db	1
		even
upleft		POINT	<0,0>
lowright	POINT	<8000h,8000h>
granpos		POINT	<0,0>
granumask	POINT	<-1,-1>
textbuf		label	word
buffer@		dd	0
cursor@		dw	-1,0
videoseg	equ <cursor@[2]>
newcursor	db	0
		even
v9k_fakecrtc	dw	0
fake_scrseg	dw	0
defmasks	label	word
		V9K_DEFMASKS

V9K_PART = 2
include ctmousev-video.inc

;----- test bench

base		dw	0		; graphics base cell chosen by SETUPG
bmpseg		dw	0		; 1000h + 2*base
outh		dw	0
cmdend		dw	0
fcmds		db	'CMDS.BIN',0
fout		db	'OUT.BIN',0
result		dw	8 dup (0)

main:		cld
		mov	ax,cs
		inc	ax
		shr	ax,1			; base = ceil(CS/2) -> bmpseg >= CS+1000h
		mov	[base],ax
		shl	ax,1
		add	ah,10h
		mov	[bmpseg],ax
		add	ax,40000/16+1
		mov	[fake_scrseg],ax

		mov	dx,offset fcmds
		mov	ax,3D00h
		int	21h
		jc	@@exit
		xchg	bx,ax
		mov	dx,offset cmdbuf
		mov	cx,0F000h
		sub	cx,dx
		mov	ah,3Fh
		int	21h
		jc	@@exit
		add	ax,offset cmdbuf
		mov	[cmdend],ax
		mov	ah,3Eh
		int	21h
		mov	dx,offset fout
		xor	cx,cx
		mov	ah,3Ch
		int	21h
		jc	@@exit
		mov	[outh],ax

		mov	si,offset cmdbuf
@@next:		cmp	si,[cmdend]
		jae	@@done
		lodsw
		mov	bx,ax
		lodsw
		xchg	ax,cx			; a
		lodsw
		xchg	ax,dx			; b
		lodsw
		mov	di,ax			; c
		lodsw				; d in AX
		test	bx,bx
		jz	@@done
		cmp	bx,ntab
		jae	@@done
		shl	bx,1
		push	si
		call	word ptr optab[bx]
		pop	si
		cmp	byte ptr [lastop],5
		jne	@@next
		mov	byte ptr [lastop],0
		add	si,64			; SETMASK payload
		jmp	@@next
@@done:		mov	bx,[outh]
		mov	ah,3Eh
		int	21h
@@exit:		mov	ax,4C00h
		int	21h

lastop		db	0
optab		dw	op_end, op_crtc, op_poke, op_detect, op_setupg, op_setmask
		dw	op_defmask, op_hot, op_box, op_draw, op_dumpbmp, op_dumpscr
		dw	op_tmask, op_granx, op_txtaddr, op_state, op_loadbmp
ntab		equ	($-optab)/2

; write CX bytes from DS:DX
outwrite	proc
		mov	bx,cs:[outh]
		mov	ah,40h
		int	21h
		ret
outwrite	endp

op_end:		ret

op_crtc:	mov	[v9k_fakecrtc],cx	; a = R12:R13
		ret

op_poke:	mov	es,[fake_scrseg]	; a = word index, b = value, c <> 0: add base
		mov	bx,cx
		shl	bx,1
		test	di,di
		jz	@@pk
		add	dx,[base]
@@pk:		mov	es:[bx],dx
		ret

op_detect:	call	v9k_detect_mode
		jmp	op_state

; graphics screen RAM: word w < 1250 = base + c*25 + r (w = r*50+c) with attribute bits
; ((w*7) & 1Fh) << 11, other words w*13; R12 = 30h, R13 = 0
op_setupg:	mov	es,[fake_scrseg]
		xor	di,di
		xor	cx,cx			; w
@@sg:		mov	ax,cx
		cmp	ax,1250
		jae	@@sgx
		mov	bl,50
		div	bl			; AL = r, AH = c
		mov	bl,ah
		mov	bh,0
		mov	dx,bx
		shl	bx,1
		shl	bx,1
		shl	bx,1
		add	bx,dx			; 9c
		shl	dx,1
		shl	dx,1
		shl	dx,1
		shl	dx,1
		add	bx,dx			; 25c
		mov	ah,0
		add	ax,bx
		add	ax,[base]
		push	ax
		mov	ax,cx
		mov	dx,7
		mul	dx
		and	ax,1Fh
		mov	dl,11
		xchg	cx,dx
		shl	ax,cl
		xchg	cx,dx
		pop	dx
		or	ax,dx
		jmp	short @@sgs
@@sgx:		mov	dx,13
		mul	dx
@@sgs:		stosw
		inc	cx
		cmp	cx,2048
		jb	@@sg
		mov	[v9k_fakecrtc],3000h
		mov	ax,[base]
		mov	[result],ax
		mov	ax,[bmpseg]
		mov	[result+2],ax
		mov	ax,[fake_scrseg]
		mov	[result+4],ax
		mov	dx,offset result
		mov	cx,6
		jmp	outwrite

op_setmask:	mov	byte ptr [lastop],5
		mov	si,sp
		mov	si,ss:[si+2]		; command pointer (pushed SI)
		push	ds
		pop	es
		mov	di,offset screenmask
		mov	cx,32
		V9K_MIRRORCOPY
		ret

op_defmask:	push	ds
		pop	es
		mov	si,offset defmasks
		mov	di,offset screenmask
		mov	cx,32
		rep	movsw
		ret

op_hot:		mov	[hotspot.X],cx
		mov	[hotspot.Y],dx
		ret

op_box:		mov	[upleft.X],cx
		mov	[upleft.Y],dx
		mov	[lowright.X],di
		mov	[lowright.Y],ax
		ret

op_draw:	mov	[granpos.X],cx		; a = X, b = Y, c = force, d = hidden
		mov	[granpos.Y],dx
		xchg	ax,di
		mov	[newcursor],al
		xchg	ax,di
		mov	[nocursorcnt],al
		call	drawcursor
		ret

op_dumpbmp:	push	ds
		mov	ds,[bmpseg]
		xor	dx,dx
		mov	cx,40000
		call	outwrite
		pop	ds
		ret

op_dumpscr:	push	ds
		mov	ds,[fake_scrseg]
		xor	dx,dx
		mov	cx,4096
		call	outwrite
		pop	ds
		ret

op_tmask:	mov	[startscan],cx
		mov	[endscan],dx
		ret

; granx10 = a; X = 0..b-1 through V9K_GRANX (BX = c), 2 bytes each
op_granx:	mov	[granx10],cl
		mov	cx,dx
		mov	bx,di
		xor	dx,dx
@@gx:		push	cx
		push	dx
		mov	ax,dx
		push	bx
		V9K_GRANX
		pop	bx
		mov	[result],ax
		mov	dx,offset result
		mov	cx,2
		push	bx
		call	outwrite
		pop	bx
		pop	dx
		pop	cx
		inc	dx
		cmp	dx,cx
		jb	@@gx
		ret

op_txtaddr:	mov	ax,cx
		mov	bx,dx
		call	v9k_txtaddr
		sbb	ax,ax
		mov	[result],di
		mov	[result+2],ax
		mov	dx,offset result
		mov	cx,4
		jmp	outwrite

op_state:	mov	ax,[cursor@]
		mov	[result],ax
		mov	ax,[videoseg]
		mov	[result+2],ax
		mov	ax,[v9k_rid]
		mov	[result+4],ax
		mov	ax,[granumask.Y]
		mov	[result+6],ax
		mov	al,[granx10]
		mov	ah,[gc_lr]
		mov	[result+8],ax
		mov	al,[gc_rows]
		mov	ah,0
		mov	[result+10],ax
		mov	ax,[gc_x]
		mov	[result+12],ax
		mov	ax,[gc_y]
		mov	[result+14],ax
		mov	dx,offset result
		mov	cx,16
		jmp	outwrite

; fill the bitmap with an LCG: w(n+1) = w(n)*25173 + 13849, w(0) = a
op_loadbmp:	mov	es,[bmpseg]
		xor	di,di
		mov	ax,cx
		mov	cx,20000
@@lb:		mov	dx,25173
		mul	dx
		add	ax,13849
		stosw
		loop	@@lb
		ret

		even
cmdbuf		label	byte

		end	start
