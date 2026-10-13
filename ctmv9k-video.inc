; ctmv9k-video.inc - Victor 9000 video layer for CTMV9K (plan sections 4.1-4.5)
;
; JWasm, 8086 only, resident code. Part of the CuteMouse port, GPL-2.
; Tested in DOSBox against the Python oracle (tools/video/, tools/v9kmouse.py).
;
; The file is included twice, selected by V9K_PART:
;   V9K_PART = 1   equates and macros only (no bytes): include near the top of the driver,
;                  after the POINT struc and the switches MODEGUARD / HWCURSOR.
;   V9K_PART = 2   the resident procs (drawcursor, restorescreen, checkifseen, v9k_*):
;                  include in the resident code where drawcursor .. checkifseen were.
;
;------------------------------------------------------------------------------------------------
; Glue for ctmv9k.asm
;------------------------------------------------------------------------------------------------
;  1. Top (after POINT struc):       V9K_PART = 1  /  include ctmv9k-video.inc
;  2. Uninitialized data, right after spritebuf (which must be 4*16 bytes, PSP 1Eh-5Dh):
;                                    V9K_UDATA
;     New resident variables (all uninitialized, 9 bytes, then `even` if wanted):
;       v9k_rid   dw  render target id recorded by the last mode detect (reset)
;       gc_x      dw  gx of the drawn graphics cursor (X - hotspot.X), for "position unchanged"
;       gc_y      dw  gy of the drawn graphics cursor
;       gc_rows   db  rows saved in spritebuf (1..16)
;       gc_lr     db  bit 0: left word saved/drawn, bit 1: right word saved/drawn
;       granx10   db  X divisor for @savecutpos: 10 in text mode, 0 in graphics mode
;     gc_off is cursor@ itself (offset of the first drawn row in the left strip, as a word;
;     -800+2y for strip -1, never -1 because it is even). gc_r0 is not needed: restore only
;     needs the offset, the row count and gc_lr.
;  3. DefArea: replace the 32 mask words with  V9K_DEFMASKS  (the arrow, pre-mirrored), and
;     the startscan/endscan defaults 77FFh,7700h with  0FFFFh,8000h  (plan 4.4).
;  4. Delete drawcursor, restorescreen, graphcursor, gettxtoffset and checkifseen (and the
;     bitmapshift / cursorwidth code variables in checkifseen); put
;                                    V9K_PART = 2  /  include ctmv9k-video.inc
;     there. drawcursor / restorescreen / checkifseen keep their names and entry conditions
;     (drawcursor: no input, ES/AX/BX/CX/DX/SI/DI clobbered; restorescreen: same, ES =
;     videoseg on return; @drawret:: is still defined).
;  5. Delete the scanline and screenheight variables (no user left).
;  6. softreset_21 @setvideo: replace everything from "@setvideo:: push si" up to and
;     including "pop si" (the @@setcommon block) with
;           @setvideo::  push si
;                        call v9k_detect_mode    ; videoseg, granumask.Y, granx10, v9k_rid
;                        mov  ax,800             ; screen width
;                        mov  di,400             ; screen height
;                        pop  si
;     and keep the range / centre code that follows (AX = width, DI = height).
;     v9k_detect_mode clobbers AX BX CX DX SI DI ES, not BP.
;  7. @savecutpos: insert  V9K_GRANX  between "and al,byte ptr granumask[bx]" and
;     "mov word ptr granpos[bx],ax" (text mode X := (X/10)*10, 18 bytes). Needs 0 <= pos.X
;     <= 2559, i.e. fn 7/8/17h must clamp rangemin/rangemax to 0..799/0..399 (plan 4.3).
;  8. graphcursor_09: replace the copy "mov cx,16+16 / rep movsw" with
;           mov  cx,16+16
;           V9K_MIRRORCOPY          ; DS:SI user masks -> ES:DI mirrored, clobbers AX CX DX
;     and delete the "compare user shape with internal area" block (it compares unmirrored
;     user words with mirrored internal ones), so fn 9 always copies and redraws.
;  9. textcursor_0A with HWCURSOR = 0: a request with BX <> 0 must not overwrite the software
;     masks with scan lines. Replace "jcxz @@tcacxz / mov cl,1" by
;           jcxz @@tcacxz
;           ret                     ; BX<>0: keep the software cursor and its masks
;     (cursortype then stays 0 and has no reader; it can be dropped.)
; 10. Optional (also an upstream bug): showcursor_01 parks the update region with
;     lowright.Y high byte = FFh, i.e. lowright.Y in -256..-1. A cursor with gy < 0 (hot spot
;     below the top) can then test as "inside the region" and vanish. "mov byte ptr
;     lowright.Y[1],80h" parks it at <= -32513 instead.
; 11. fn 20h (setupvideo) runs v9k_detect_mode without hiding the cursor. If the render id
;     changed, detect discards the saved background (cursor@ := -1); if it did not change,
;     the drawn cursor stays valid. Applications must call fn 0/21h after a mode change.
;
; Hardware access: CRTC index/data at V9K_IOSEG:8000h/8001h, read under pushf/cli/popf (safe
; inside the ISR). Note that an index write from our ISR between the console's own index and
; data writes would redirect the console's data write; the console is assumed to program the
; CRTC with interrupts off (as MOUSE.DEV assumes too).
;
; Test hooks (never in the driver): V9K_TESTCRTC defined -> R12:R13 come from the word
; [v9k_fakecrtc] (high byte R12); V9K_SCRSEG may be predefined (e.g. as <[fake_scrseg]>).

ifndef V9K_PART
.err <define V9K_PART = 1 or 2 before including ctmv9k-video.inc>
endif

;================================================================================================
if V9K_PART eq 1

ifndef MODEGUARD
MODEGUARD	equ 1
endif
ifndef HWCURSOR
HWCURSOR	equ 0
endif
if HWCURSOR
.err <ctmv9k-video.inc: HWCURSOR = 1 is not implemented (plan 4.4, decided off)>
endif

V9K_IOSEG	equ 0E000h		; CRTC_ADDR = E000:8000, CRTC_DATA = E000:8001
V9K_CRTC_ADDR	equ 8000h
V9K_CRTC_DATA	equ 8001h
ifndef V9K_SCRSEG
V9K_SCRSEG	equ 0F000h		; screen RAM, 2048 words
endif
V9K_STRIP	equ 800			; bytes per 16-pixel column strip (25 cells x 32)

;----- uninitialized resident variables (see the header)
V9K_UDATA	macro
v9k_rid		dw	?
gc_x		dw	?
gc_y		dw	?
gc_rows		db	?
gc_lr		db	?
granx10		db	?
		endm

;----- DefArea masks: CuteMouse's arrow, each word mirrored (bit 0 = leftmost pixel)
V9K_DEFMASKS	macro
		dw	0FFFCh,0FFF8h,0FFF0h,0FFE0h,0FFC0h,0FF80h,0FF00h,0FE00h ; screenmask
		dw	0FC00h,0F800h,0FF80h,0FF00h,0FF0Ch,0FE1Fh,0FE1Fh,0FF3Fh
		dw	00000h,00002h,00006h,0000Eh,0001Eh,0003Eh,0007Eh,000FEh ; cursormask
		dw	001FEh,0003Eh,00036h,00062h,00060h,000C0h,000C0h,00000h
		endm

;----- @savecutpos: text mode X granularity 10. In: AX = position (0..2559), BX = axis
;	(0 = X). Out: AX rounded down to a multiple of 10 if X and granx10 <> 0.
V9K_GRANX	macro
		local	done
		test	bx,bx
		jnz	done
		cmp	[granx10],bl		; BL=0
		je	done
		div	[granx10]		; AL = X/10 (< 256)
		mul	[granx10]		; AX = (X/10)*10
done:
		endm

;----- fn 9: copy CX mask words DS:SI -> ES:DI, mirroring each (bit 15 <-> bit 0).
;	Modf: AX, CX, DX, SI, DI. Uses no DS-relative data (DS is the caller's segment).
V9K_MIRRORCOPY	macro
		local	nextword,nextbit
nextword:	lodsw
		push	cx
		mov	cx,16
nextbit:	shr	ax,1
		rcl	dx,1
		loop	nextbit
		pop	cx
		xchg	ax,dx
		stosw
		loop	nextword
		endm

endif ; V9K_PART eq 1

;================================================================================================
if V9K_PART eq 2

v9k_video_start label byte

;========================================================================
;			Draw mouse cursor
;========================================================================
;
; In:	none (granpos, nocursorcnt, newcursor, videoseg, cursor@)
; Modf:	AX, BX, CX, DX, SI, DI, ES
;
drawcursor	proc
		mov	cx,[videoseg]
		jcxz	@@drawret		; exit if no supported mode

		xor	cx,cx
		cmp	[nocursorcnt],cl
		jnz	restorescreen		; jump if cursor disabled

		mov	ax,[granumask.Y]
		xchg	cl,[newcursor]		; CX = force redraw request
		inc	ax
		mov	bx,[granpos.Y]
		mov	ax,[granpos.X]
		jz	v9k_gcursor		; graphics mode: granumask.Y = FFFFh

;===== text mode cursor (cell 10x16, X multiple of 10, Y of 16)

		mov	dx,10
		mov	si,16
		call	checkifseen
		jc	restorescreen		; cell in the update region
		call	v9k_txtaddr		; DI = cell offset, CF = mode guard
		jc	restorescreen
		cmp	di,[cursor@]
		jnz	@@drnz
		jcxz	@@drawret		; same cell and not forced
@@drnz:		push	di
		call	restorescreen		; ES = videoseg
		pop	di

;----- draw software text mode cursor

		mov	[cursor@],di
		mov	ax,es:[di]		; save cell under cursor
		mov	textbuf[2],ax
		and	ax,[startscan]
		xor	ax,[endscan]
		stosw
		mov	textbuf[0],ax		; what we wrote
@@drawret:	ret
drawcursor	endp

;========================================================================
;			Restore old screen contents
;========================================================================
;
; Out:	ES = videoseg, cursor@ = -1
; Modf:	AX, DX, SI, DI (BX, CX preserved)
;
restorescreen	proc
if MODEGUARD
		call	v9k_getrid		; AX = current render target id
endif
		les	di,dword ptr [cursor@]
		assume	es:nothing
		inc	di
		jz	@@rsret			; not drawn
		sub	[cursor@],di		; cursor@ = -1
		dec	di
if MODEGUARD
		cmp	ax,[v9k_rid]
		jne	@@rsret			; target changed: discard the background
endif
		mov	ax,[granumask.Y]
		inc	ax
		jz	v9k_grestore		; graphics mode

;----- text mode: restore only if the cell still holds what we wrote

		mov	si,TSRdref:textbuf
		lodsw
		cmp	ax,es:[di]
		jnz	@@rsret
		movsw
@@rsret:
@drawret::	ret
restorescreen	endp

;========================================================================
;		Graphics restore: write the saved words back
;========================================================================
;
; In:	ES:DI = gc_off (cursor@ before it was cleared)
; Modf:	AX, CX(restored), DX, SI, DI
;
v9k_grestore	proc
		push	cx
		mov	si,TSRdref:spritebuf
		mov	cx,word ptr [gc_rows]	; CL = rows, CH = gc_lr
@@row:		test	ch,1
		jz	@@noleft
		lodsw
		mov	es:[di],ax
@@noleft:	test	ch,2
		jz	@@noright
		lodsw
		mov	es:[di+V9K_STRIP],ax
@@noright:	inc	di
		inc	di
		dec	cl
		jnz	@@row
		pop	cx
		ret
v9k_grestore	endp

;========================================================================
;		Draw graphics mode cursor (plan 4.4)
;========================================================================
;
; In:	AX/BX = X/Y (granpos), CX = force redraw request (CH = 0)
; Modf:	AX, BX, CX, DX, SI, DI, ES
;
v9k_gcursor	proc
		sub	ax,[hotspot.X]		; gx
		sub	bx,[hotspot.Y]		; gy
		mov	dx,16
		mov	si,dx
		call	checkifseen		; off screen or in the update region?
		jc	restorescreen
if MODEGUARD
		push	ax
		call	v9k_getrid
		cmp	ax,[v9k_rid]
		pop	ax
		jne	restorescreen		; mode changed since reset: do not draw
endif
		cmp	word ptr [cursor@],-1
		je	@@draw
		cmp	ax,[gc_x]
		jne	@@draw
		cmp	bx,[gc_y]
		jne	@@draw
		jcxz	@drawret			; same place and not forced
@@draw:		push	ax
		push	bx
		call	restorescreen		; ES = videoseg
		pop	bx
		pop	ax
		mov	[gc_x],ax
		mov	[gc_y],bx
		push	bp

;----- sh, fill, left/right flags

		mov	cx,ax
		and	cx,15			; CL = sh, CH = 0
		mov	bp,1
		shl	bp,cl
		dec	bp			; BP = (1 << sh) - 1
		xor	dx,dx
		test	ax,ax
		js	@@noleft		; strip -1: no left word
		inc	dx
@@noleft:	jcxz	@@noright		; aligned: no right word
		cmp	ax,800-16
		jge	@@noright		; strip 49: no strip 50
		or	dl,2
@@noright:	mov	[gc_lr],dl

;----- off = strip*800 + (gy+r0)*2, rows = r1-r0

		and	ax,0FFF0h
		mov	dx,V9K_STRIP/16
		mul	dx			; AX = strip*800 (mod 64K, strip -1 ok)
		xchg	di,ax
		mov	dx,bx
		neg	dx
		jns	@@r0			; gy <= 0: r0 = -gy
		xor	dx,dx			; gy > 0: r0 = 0
@@r0:		add	bx,dx			; BX = gy+r0 (first row on screen)
		add	di,bx
		add	di,bx
		mov	[cursor@],di		; gc_off
		mov	ax,400
		sub	ax,bx			; rows left below the first one
		mov	bx,16
		sub	bx,dx			; 16-r0
		cmp	ax,bx
		jl	@@rows
		xchg	ax,bx
@@rows:		mov	[gc_rows],al		; min(16-r0, 400-(gy+r0)) = r1-r0
		mov	ch,al
		mov	bx,dx
		shl	bx,1			; mask index 2*r0
		mov	si,TSRdref:spritebuf

;----- per row: rotate both masks by sh, then the left and right word

@@row:		mov	ax,word ptr screenmask[bx]
		rol	ax,cl
		mov	dx,word ptr cursormask[bx]
		rol	dx,cl
		test	[gc_lr],1
		jz	@@skipl
		call	@@word			; F = low fill
@@skipl:	not	bp			; F = high fill
		test	[gc_lr],2
		jz	@@skipr
		add	di,V9K_STRIP
		call	@@word
		sub	di,V9K_STRIP
@@skipr:	not	bp
		inc	bx
		inc	bx
		inc	di
		inc	di
		dec	ch
		jnz	@@row
		pop	bp
@@ret:		ret

; save ES:[DI] at [SI]++, then ES:[DI] = (w AND (AX OR F)) XOR (DX AND NOT F), F = BP
@@word:		push	word ptr es:[di]
		pop	word ptr [si]
		inc	si
		inc	si
		push	ax
		push	dx
		or	ax,bp
		not	bp
		and	dx,bp
		not	bp
		and	ax,es:[di]
		xor	ax,dx
		mov	es:[di],ax
		pop	dx
		pop	ax
		ret
v9k_gcursor	endp

;========================================================================
;		Check if cursor seen and not in update region
;========================================================================
;
; In:	AX/BX			(left/top pixel, signed)
;	DX/SI			(width/height in pixels)
; Out:	Carry flag		(off screen or overlaps the fn 10h region)
; Modf:	DX, SI
;
checkifseen	proc
		add	si,bx
		jle	@@unseen		; y+h <= 0
		cmp	bx,400
		jge	@@unseen
		add	dx,ax
		jle	@@unseen		; x+w <= 0
		cmp	ax,800
		jge	@@unseen

		cmp	bx,[lowright.Y]
		jg	@@seen			; below the region
		cmp	si,[upleft.Y]
		jle	@@seen			; above
		cmp	ax,[lowright.X]
		jg	@@seen			; right of it
		cmp	dx,[upleft.X]
		jle	@@seen			; left of it
@@unseen:	stc
		ret
@@seen:		clc
		ret
checkifseen	endp

;========================================================================
;		Text cell address (plan 4.2), replaces gettxtoffset
;========================================================================
;
; In:	AX/BX			(X 0..799 / Y 0..399)
; Out:	CF = 1			(MODEGUARD: render target changed, DI undefined)
;	DI			(2 * ((start + (Y/16)*80 + X/10) AND 7FFh))
; Modf:	AX, BX, DX, ES
;
v9k_txtaddr	proc
		push	ax
		call	v9k_getrid		; DX = R12:R13
if MODEGUARD
		cmp	ax,[v9k_rid]
		pop	ax
		stc
		jne	@@ret
else
		pop	ax
endif
		and	bx,0FFF0h
		mov	di,bx
		shl	di,1
		shl	di,1
		add	di,bx			; (Y/16)*80
		mov	bl,10
		div	bl			; AL = X/10
		cbw
		add	di,ax
		and	dh,7
		add	di,dx			; + start
		and	di,07FFh
		shl	di,1			; CF = 0
@@ret:		ret
v9k_txtaddr	endp

;========================================================================
;		Render target id
;========================================================================
;
; Out:	AX			(text: R12 AND 30h = 0/10h;
;				 graphics: bitmap_seg + 1, odd)
;	DX			(DH = R12, DL = R13)
;	ES			(graphics: V9K_SCRSEG, else undefined)
; Modf:	none else
;
v9k_getrid	proc
ifdef V9K_TESTCRTC
		mov	dx,[v9k_fakecrtc]
else
		mov	ax,V9K_IOSEG
		mov	es,ax
		mov	al,0Ch
		pushf
		cli
		mov	es:[V9K_CRTC_ADDR],al
		mov	dh,es:[V9K_CRTC_DATA]	; R12
		inc	ax
		mov	es:[V9K_CRTC_ADDR],al
		mov	dl,es:[V9K_CRTC_DATA]	; R13
		popf
endif
		mov	al,dh
		and	ax,30h
		test	al,20h
		jz	@@ret			; text
		mov	ax,V9K_SCRSEG
		mov	es,ax
		mov	ax,es:[0]		; screen word 0
		and	ah,7
		shl	ax,1			; 2*base
		inc	ax			; graphics marker
		test	dh,10h
		jz	@@ret
		add	ah,10h			; MA12: second 64 KB
@@ret:		ret
v9k_getrid	endp

;========================================================================
;		Mode detection (plan 4.1), called from @setvideo
;========================================================================
;
; Out:	v9k_rid, videoseg (0 = no cursor), granumask.Y low byte, granx10
; Modf:	AX, BX, CX, DX, SI, DI, ES
;
v9k_detect_mode	proc
		call	v9k_getrid
		cmp	ax,[v9k_rid]
		je	@@same
		mov	word ptr [cursor@],-1	; target changed: drop the background
@@same:		mov	[v9k_rid],ax
		test	al,1
		jnz	@@graph
		mov	ax,V9K_SCRSEG		; text: screen RAM, Y gran 16, X gran 10
		mov	cx,0F00Ah
		jmp	short @@set

@@graph:	mov	cx,0FF00h		; graphics: granularity 1/1
		dec	ax			; AX = bitmap_seg
		mov	bx,es:[0]
		and	bh,7			; base
		cmp	bx,2047-1249
		ja	@@bad			; 1250 cells do not fit
		push	ax
		mov	si,TSRdref:v9k_lchk
@@chk:		lodsw
		xchg	di,ax			; screen word offset
		lodsw
		add	ax,bx			; expected cell
		mov	dx,es:[di]
		and	dh,7
		cmp	dx,ax
		jne	@@bad1
		cmp	si,TSRdref:v9k_lchk+4*4
		jb	@@chk
		pop	ax
		jmp	short @@set
@@bad1:		pop	ax
@@bad:		xor	ax,ax			; unknown layout: no cursor
@@set:		mov	[videoseg],ax
		mov	byte ptr [granumask.Y],ch
		mov	[granx10],cl
		ret
v9k_detect_mode	endp

; layout samples: screen word w = r*50+c must hold cell base + c*25 + r
v9k_lchk	dw	2*1,25, 2*50,1, 2*49,49*25, 2*1249,1249

v9k_video_end	label byte

endif ; V9K_PART eq 2
