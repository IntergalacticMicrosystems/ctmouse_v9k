; V9KMT.COM - INT 33h test client for CTMV9K (Victor 9000). NASM:
;     nasm -f bin -o utility/v9kmt.com utility/v9kmt.asm
; Uses INT 21h only (02h/09h output, 06h keyboard, 35h vector): no PC BIOS calls, so it runs
; under Victor DOS and, for the API checks, in DOSBox. Output goes to stdout (redirectable).
;
; Usage: V9KMT [keys]   keys on the command line are executed first, as if typed (for scripted
; runs, e.g. "V9KMT s78q > OUT.TXT"); then the keyboard is read until q. A leading '-' skips the
; fn 0 reset, so motion/presses made before V9KMT started show up (e.g. "V9KMT - lq").
; Status line: B buttons, X Y, W wheel (fn 3 BH, summed), M mickeys (fn 0Bh, summed), P/R presses
; and releases (fn 5/6, summed) as wheel/L/R/M. fn 3 and fn 5/6 BX=-1 all read and reset the same
; wheel counter, so the net wheel motion is W + P(wheel) + R(wheel).
; Keys: s show(1) h hide(2) 7 X range 100..699 8 Y range 50..349 n bad ranges (-50..900/-50..500)
;       9 graphics shape(9) a fn 0Ah BX=1 x exclusion box(10h) 4 fn 4 to 0,0 then 799,399
;       t save state(16h) r restore(17h) d disable(1Fh) e enable(20h) w wheel API(11h)
;       l print a status line with LF  q quit
        cpu 8086
        org 100h

start:  cld
        mov ax,3533h
        int 21h                         ; ES:BX = INT 33h
        mov [vseg],es
        mov [voff],bx
        mov dx,m_vec
        call puts
        mov ax,es
        call hex4
        mov dl,':'
        call putc
        mov ax,bx
        call hex4
        mov ax,es
        or ax,bx
        jnz .notnull
        mov dx,m_null
        call puts
        mov ax,4C01h
        int 21h
.notnull:
        cmp byte [es:bx],0CFh
        jne .noiret
        mov dx,m_iret
        call puts
.noiret:
        mov dx,m_nosig
        cmp bx,5
        jb .sigdone
        mov si,sig
        lea di,[bx-5]
        mov cx,5
        repe cmpsb                      ; DS:SI vs ES:DI
        jne .sigdone
        mov dx,m_sig
.sigdone:
        call puts
        cmp dx,m_nosig                  ; never call a vector without the signature
        jne .sigok                      ;  (Victor DOS leaves INT 33h = FFFF:FFFF)
        mov ax,4C01h
        int 21h
.sigok:

        ; fn 0, unless the command tail starts with '-' (keep the driver's counters/position)
        mov si,81h
.skp:   lodsb
        cmp al,' '
        je .skp
        cmp al,'-'
        jne .fn0
        mov dx,m_nofn0
        call puts
        jmp .fn24
.fn0:   xor ax,ax
        mov bx,1
        int 33h
        mov dx,m_fn0
        call puts
        call hex4
        mov dx,m_bx
        call puts
        mov ax,bx
        call hex4
        call crlf

.fn24:  ; fn 24h: BX version, CH type, CL IRQ, DL port, DH 'V'
        xor bx,bx
        xor cx,cx
        xor dx,dx
        mov ax,24h
        int 33h
        push dx
        push cx
        mov dx,m_fn24
        call puts
        mov ax,bx
        call hex4
        mov dx,m_cx
        call puts
        pop ax
        call hex4
        mov dx,m_dx
        call puts
        pop ax
        push ax
        call hex4
        pop ax
        cmp ah,'V'
        jne .nov
        push ax
        mov dx,m_port
        call puts
        pop dx
        add dl,'A'
        call putc
.nov:   call crlf

        ; fn 4Dh: ES:DI -> copyright string
        xor di,di
        mov es,di
        mov ax,4Dh
        int 33h
        mov dx,m_fn4d
        call puts
        mov ax,es
        call hex4
        mov dl,':'
        call putc
        mov ax,di
        call hex4
        mov ax,es
        or ax,di
        jz .nostr
        mov dl,' '
        call putc
        mov cx,64
.str:   mov dl,[es:di]
        or dl,dl
        jz .nostr
        cmp dl,' '
        jae .pc
        mov dl,'.'
.pc:    call putc
        inc di
        loop .str
.nostr: call crlf
        push cs
        pop es

        mov si,81h                      ; command tail = scripted keys
        mov [tailp],si

;----- main loop
main:   call status
        call getkey
        jz main
        mov di,keytab
.find:  cmp byte [di],0
        je main
        cmp al,[di]
        je .hit
        add di,3
        jmp .find
.hit:   call crlf
        call [di+1]
        jmp main

;----- keys
k_quit: mov ax,4C00h
        int 21h
k_show: mov ax,1
        jmp call33
k_hide: mov ax,2
        jmp call33
k_xr:   mov cx,100
        mov dx,699
        mov ax,7
        jmp call33
k_yr:   mov cx,50
        mov dx,349
        mov ax,8
        jmp call33
k_bad:  mov cx,-50
        mov dx,900
        mov ax,7
        int 33h
        mov cx,-50
        mov dx,500
        mov ax,8
        jmp call33
k_shape: mov bx,7                       ; hot spot 7,7 (centre of the cross)
        mov cx,7
        mov dx,shape
        mov ax,9
        jmp call33
k_hw:   mov bx,1
        xor cx,cx
        mov dx,7
        mov ax,0Ah
        jmp call33
k_excl: mov cx,400
        mov dx,200
        mov si,500
        mov di,300
        mov ax,10h
        jmp call33
k_pos:  xor cx,cx
        xor dx,dx
        call setpos
        mov cx,799
        mov dx,399
setpos: mov ax,4
        int 33h
        mov dx,m_set
        call puts
        jmp status_lf
k_save: mov ax,15h
        int 33h                         ; BX = state size
        mov dx,m_size
        call puts
        mov ax,bx
        call dec16
        cmp bx,bufsize
        jbe .ok
        mov dx,m_big
        jmp puts
.ok:    call crlf
        mov dx,buf
        mov ax,16h
        jmp call33
k_rest: mov dx,buf
        mov ax,17h
        jmp call33
k_dis:  mov ax,1Fh
        mov [fnum],ax
        int 33h
        push es
        call showfn
        pop es
        mov dx,m_esbx
        call puts
        mov ax,es
        call hex4
        mov dl,':'
        call putc
        mov ax,bx
        call hex4
        push cs
        pop es
        jmp crlf
k_en:   mov ax,20h
        jmp call33
k_wheel: mov ax,11h
        mov [fnum],ax
        int 33h
        call showfn
        mov dx,m_bx
        call puts
        mov ax,bx
        call hex4
        mov dx,m_cx
        call puts
        mov ax,cx
        call hex4
        jmp crlf
k_line: jmp status_lf

call33: mov [fnum],ax                   ; AX = function, other regs set
        int 33h
        call showfn
        jmp crlf
showfn: push cs                         ; print "fn NN AX=xxxx" (AX = result)
        pop es
        push ax
        mov dx,m_fn
        call puts
        mov ax,[fnum]
        call hex2
        mov dx,m_ax
        call puts
        pop ax
        jmp hex4

;----- status line: fn 3, fn 0Bh, fn 5/6 (accumulated), CR only
status_lf:
        call status
        jmp crlf
status: mov ax,3
        int 33h
        push bx
        push dx
        push cx
        mov dx,m_b
        call puts
        mov al,bl
        call hex2
        mov dx,m_x
        call puts
        pop ax
        call sdec
        mov dx,m_y
        call puts
        pop ax
        call sdec
        mov dx,m_wh
        call puts
        pop ax
        mov al,ah
        cbw
        add [wheels],ax                 ; fn 3 BH is reset on read: sum it
        mov ax,[wheels]
        call sdec
        mov ax,0Bh
        int 33h
        push dx
        mov dx,m_mk
        call puts
        mov ax,cx
        add [mickx],ax
        mov ax,[mickx]
        call sdec
        mov dl,','
        call putc
        pop ax
        add [micky],ax
        mov ax,[micky]
        call sdec
        mov dx,m_pr
        call puts
        mov di,presses
        mov bp,5
        call counts
        mov dx,m_rl
        call puts
        mov di,releases
        mov bp,6
        call counts
        mov dx,m_sp
        call puts
        mov dl,13
        jmp putc

counts: mov bx,-1                       ; BX = -1 (wheel), 0, 1, 2
.c:     push bx
        mov ax,bp
        int 33h
        mov ax,bx
        pop bx
        mov si,bx
        shl si,1
        push di
        add di,si
        add [di+2],ax
        mov ax,[di+2]
        pop di
        push bx
        call sdec
        pop bx
        inc bx
        cmp bx,3
        je .done
        mov dl,'/'
        call putc
        jmp .c
.done:  ret

;----- keyboard: command tail first, then INT 21h 06h. Out: ZF=0 and AL = key, or ZF=1
getkey: mov si,[tailp]
.t:     lodsb
        cmp al,' '
        je .t
        cmp al,13
        je .kbd
        cmp si,100h
        jae .kbd
        mov [tailp],si
        or al,20h                       ; lower case
        or al,al                        ; ZF = 0 (AL != 0)
        ret
.kbd:   dec si
        mov [tailp],si
        mov ah,6
        mov dl,0FFh
        int 21h
        jz .r
        or al,al
        jz .r                           ; extended key prefix: ignore
        or al,20h
.r:     ret

;----- output helpers (all preserve BX, CX, SI, DI, BP)
puts:   push ax
        mov ah,9
        int 21h
        pop ax
        ret
crlf:   mov dx,m_crlf
        jmp puts
putc:   push ax
        mov ah,2
        int 21h
        pop ax
        ret
hex4:   push ax
        mov al,ah
        call hex2
        pop ax
hex2:   push ax
        push cx
        mov cl,4
        shr al,cl
        call hex1
        pop cx
        pop ax
hex1:   push ax
        and al,0Fh
        add al,'0'
        cmp al,'9'
        jbe .p
        add al,7
.p:     mov dl,al
        call putc
        pop ax
        ret
sdec:   or ax,ax                        ; signed decimal
        jns dec16
        push ax
        mov dl,'-'
        call putc
        pop ax
        neg ax
dec16:  push ax                         ; unsigned decimal
        push bx
        push cx
        push dx
        mov bx,10
        xor cx,cx
.d:     xor dx,dx
        div bx
        push dx
        inc cx
        or ax,ax
        jnz .d
.o:     pop dx
        add dl,'0'
        call putc
        loop .o
        pop dx
        pop cx
        pop bx
        pop ax
        ret

;----- data
keytab: db 'q'
        dw k_quit
        db 's'
        dw k_show
        db 'h'
        dw k_hide
        db '7'
        dw k_xr
        db '8'
        dw k_yr
        db 'n'
        dw k_bad
        db '9'
        dw k_shape
        db 'a'
        dw k_hw
        db 'x'
        dw k_excl
        db '4'
        dw k_pos
        db 't'
        dw k_save
        db 'r'
        dw k_rest
        db 'd'
        dw k_dis
        db 'e'
        dw k_en
        db 'w'
        dw k_wheel
        db 'l'
        dw k_line
        db 0

sig:    db 'MOUSE'
m_vec:  db 'INT 33h = $'
m_null: db ' null vector, no driver',13,10,'$'
m_iret: db ' (IRET)$'
m_nosig: db ' no MOUSE signature',13,10,'$'
m_sig:  db ' MOUSE signature ok',13,10,'$'
m_nofn0: db 'fn 0 skipped (-)',13,10,'$'
m_fn0:  db 'fn 0: AX=$'
m_fn24: db 'fn 24h: BX=$'
m_fn4d: db 'fn 4Dh: ES:DI=$'
m_port: db ' port $'
m_ax:   db ' AX=$'
m_bx:   db ' BX=$'
m_cx:   db ' CX=$'
m_dx:   db ' DX=$'
m_esbx: db ' ES:BX=$'
m_fn:   db 'fn $'
m_set:  db 'fn 4 -> $'
m_size: db 'fn 15h size $'
m_big:  db ' > buffer, not saved',13,10,'$'
m_b:    db 'B=$'
m_x:    db ' X=$'
m_y:    db ' Y=$'
m_wh:   db ' W=$'
m_mk:   db ' M=$'
m_pr:   db ' P=$'
m_rl:   db ' R=$'
m_sp:   db '   $'
m_crlf: db 13,10,'$'

; fn 9 shape: 16 screen (AND) words, then 16 cursor (XOR) words; a 15x15 cross, hot spot 7,7
shape:  times 7 dw 0FE3Fh
        dw 0000h
        times 7 dw 0FE3Fh
        dw 0FFFFh
        times 7 dw 0180h
        dw 0FFFEh
        times 7 dw 0180h
        dw 0000h

tailp:  dw 81h
fnum:   dw 0
vseg:   dw 0
voff:   dw 0
mickx:  dw 0
wheels: dw 0
micky:  dw 0
presses: times 4 dw 0
releases: times 4 dw 0
bufsize equ 1024
buf:                            ; uninitialised, past the end of the image
