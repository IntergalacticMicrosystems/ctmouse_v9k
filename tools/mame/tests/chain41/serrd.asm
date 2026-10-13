; SERRD.COM - read a DOS character device 1 byte at a time (polled drivers such as PORTA.EXE's
; SERIALA), echo it, count it, stop on ^Z or a key. NASM: nasm -f bin -o serrd.com serrd.asm
; Usage: SERRD devname [Q]     Q = quiet (no echo)
; Bytes are masked to 7 bits. Exit line: N=count S=sum (16-bit sum of bytes, ^Z excluded) T=timeouts, then INT 33h fn 0Bh
; mickeys X,Y since start and fn 3 BX/CX/DX (if INT 33h segment is not 0/FFFFh).
        cpu 8086
        org 100h
start:  cld
        mov si,81h
.skip:  lodsb
        cmp al,' '
        je .skip
        cmp al,13
        je usage
        lea dx,[si-1]
.name:  lodsb
        cmp al,' '
        je .end
        cmp al,13
        jne .name
        mov byte [si-1],0
        jmp .open
.end:   mov byte [si-1],0
.q:     lodsb
        cmp al,' '
        je .q
        and al,0DFh
        cmp al,'Q'
        jne .open
        mov byte [quiet],1
.open:  mov ax,3D00h
        int 21h
        jc openerr
        mov [hnd],ax
        mov bx,ax
        mov ax,4400h
        int 21h
        xor dh,dh
        or dl,20h                       ; raw mode
        mov ax,4401h
        int 21h
        mov ax,3533h
        int 21h
        mov ax,es                       ; Victor DOS: unused vectors are FFFF:FFFF
        inc ax
        cmp ax,1
        jbe .no33                       ; segment 0 or FFFFh: no INT 33h driver
        mov [has33],ax
.no33:
        push ds
        pop es
        call mick                       ; zero the mickey counters
        mov dx,m_go
        call puts
loop_:  mov ah,3Fh
        mov bx,[hnd]
        mov cx,1
        mov dx,buf
        int 21h
        jc rderr
        or ax,ax
        jnz .got
        inc word [tmo]                  ; driver timed out: check the keyboard
        mov ah,0Bh
        int 21h
        or al,al
        jnz key
        jmp loop_
.got:   mov al,[buf]
        and al,7Fh                      ; 7-bit data; MAME sets bit 7 on some bytes
        cmp al,1Ah
        je done
        inc word [cnt]
        xor ah,ah
        add [sum],ax
        cmp byte [quiet],0
        jne loop_
        mov dl,al
        mov ah,2
        int 21h
        jmp loop_
key:    mov ah,8
        int 21h
        jmp done
rderr:  mov [err],ax
done:   mov dx,m_n
        call puts
        mov ax,[cnt]
        call hex4
        mov dx,m_s
        call puts
        mov ax,[sum]
        call hex4
        mov dx,m_t
        call puts
        mov ax,[tmo]
        call hex4
        mov dx,m_e
        call puts
        mov ax,[err]
        call hex4
        cmp word [has33],0
        je .x
        call mick
        mov dx,m_m
        call puts
        mov ax,[mx]
        call hex4
        mov dl,','
        call putc
        mov ax,[my]
        call hex4
        mov ax,3
        int 33h
        push dx
        push cx
        mov dx,m_b
        call puts
        mov ax,bx
        call hex4
        mov dl,' '
        call putc
        pop ax
        call hex4
        mov dl,','
        call putc
        pop ax
        call hex4
.x:     mov dx,m_crlf
        call puts
        mov ax,4C00h
        int 21h
mick:   cmp word [has33],0
        je .r
        mov ax,0Bh
        int 33h
        mov [mx],cx
        mov [my],dx
.r:     ret
usage:  mov dx,m_use
        call puts
        mov ax,4C01h
        int 21h
openerr: mov dx,m_oerr
        call puts
        mov ax,4C02h
        int 21h
puts:   mov ah,9
        int 21h
        ret
putc:   mov ah,2
        int 21h
        ret
hex4:   push cx
        push dx
        mov cx,4
.l:     push cx
        mov cl,4
        rol ax,cl
        pop cx
        push ax
        and al,0Fh
        add al,'0'
        cmp al,'9'
        jbe .p
        add al,7
.p:     mov dl,al
        mov ah,2
        int 21h
        pop ax
        loop .l
        pop dx
        pop cx
        ret
m_use:  db 'usage: SERRD devname [Q]',13,10,'$'
m_oerr: db 'open failed',13,10,'$'
m_go:   db 'SERRD reading',13,10,'$'
m_n:    db 13,10,'SERRD N=$'
m_s:    db ' S=$'
m_t:    db ' T=$'
m_e:    db ' E=$'
m_m:    db ' M=$'
m_b:    db ' B=$'
m_crlf: db 13,10,'$'
quiet:  db 0
hnd:    dw 0
cnt:    dw 0
sum:    dw 0
tmo:    dw 0
err:    dw 0
has33:  dw 0
mx:     dw 0
my:     dw 0
buf:    db 0
