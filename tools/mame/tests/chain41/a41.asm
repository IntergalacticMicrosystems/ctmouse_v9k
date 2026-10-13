; A41.COM - minimal interrupt-driven receiver for 7201 channel A: a test INT 41h owner for the
; CHAIN41 test (PORTA.EXE/PORTB.EXE are polled and never hook INT 41h). NASM:
;     nasm -f bin -o a41.com a41.asm
; A41      install: INT 41h -> isr (old vector not chained), INT 60h -> stats, WR1A = 10h
;          (Rx interrupt on every char), specific EOI 61h, IMR bit 1 cleared. Channel A baud/format
;          must already be set (PORTA.EXE in CONFIG.SYS: baud(1200) bits(7) stop(1) parity(none)).
; A41 S    print the resident stats: N bytes, S 16-bit sum, E rx errors, I isr entries, last 48 bytes.
; ISR: drain RR0A bit 0 (RR1 errors -> error reset), then WR0A = 38h (7201 EOI), OCW2 61h.
        cpu 8086
        org 100h
start:  jmp init
isr:    push ax
        push ds
        push es
        push cs
        pop ds
        mov ax,0E000h
        mov es,ax
        inc word [calls]
.d:     test byte [es:42h],1
        jz .x
        mov byte [es:42h],1
        mov ah,[es:42h]
        mov al,[es:40h]
        test ah,70h
        jz .g
        inc word [errs]
        mov byte [es:42h],30h
        jmp .d
.g:     and al,7Fh                      ; 7-bit data (MAME sets bit 7 on some bytes)
        push bx
        mov bx,[head]
        mov [ring+bx],al
        inc bx
        cmp bx,48
        jb .h
        xor bx,bx
.h:     mov [head],bx
        pop bx
        inc word [cnt]
        xor ah,ah
        add [sum],ax
        jmp .d
.x:     mov byte [es:42h],38h
        mov byte [es:0],61h
        pop es
        pop ds
        pop ax
        iret
stats:  db 'A41'
cnt:    dw 0
sum:    dw 0
errs:   dw 0
calls:  dw 0
head:   dw 0
old41:  dd 0
ring:   times 48 db 0
resend:

init:   mov si,81h
.s:     lodsb
        cmp al,' '
        je .s
        and al,0DFh
        cmp al,'S'
        je show
        mov ax,3541h
        int 21h
        mov [old41],bx
        mov [old41+2],es
        mov ax,2541h
        mov dx,isr
        int 21h
        mov ax,2560h
        mov dx,stats
        int 21h
        mov ax,0E000h
        mov es,ax
        cli
.dr:    test byte [es:42h],1            ; discard stale bytes
        jz .e
        mov al,[es:40h]
        jmp .dr
.e:     mov byte [es:42h],1
        mov byte [es:42h],10h           ; WR1A: Rx int on every char
        mov byte [es:0],61h
        and byte [es:1],0FDh
        sti
        mov dx,m_inst
        mov ah,9
        int 21h
        mov ax,cs
        call hex4
        mov dx,m_crlf
        mov ah,9
        int 21h
        mov dx,resend+15
        mov cl,4
        shr dx,cl
        mov ax,3100h
        int 21h
show:   mov ax,3560h
        int 21h
        cmp word [es:bx],'A4'
        jne .no
        mov si,bx
        mov dx,m_n
        call puts
        mov ax,[es:si+3]
        call hex4
        mov dx,m_s
        call puts
        mov ax,[es:si+5]
        call hex4
        mov dx,m_e
        call puts
        mov ax,[es:si+7]
        call hex4
        mov dx,m_i
        call puts
        mov ax,[es:si+9]
        call hex4
        mov dx,m_r
        call puts
        mov bx,[es:si+11]               ; head: oldest byte first
        mov cx,48
.r:     mov dl,[es:si+17+bx]
        cmp dl,' '
        jae .p
        mov dl,'.'
.p:     mov ah,2
        int 21h
        inc bx
        cmp bx,48
        jb .n
        xor bx,bx
.n:     loop .r
        mov dx,m_crlf
        call puts
        mov ax,4C00h
        int 21h
.no:    mov dx,m_none
        call puts
        mov ax,4C01h
        int 21h
puts:   push ds
        push cs
        pop ds
        mov ah,9
        int 21h
        pop ds
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
m_inst: db 'A41 installed at $'
m_none: db 'A41 not resident',13,10,'$'
m_n:    db 'A41 N=$'
m_s:    db ' S=$'
m_e:    db ' E=$'
m_i:    db ' I=$'
m_r:    db 13,10,'[$'
m_crlf: db 13,10,'$'
