; FREE.COM - print the largest free DOS memory block (INT 21h 48h BX=FFFFh) in paragraphs (hex).
; nasm -f bin -o ../disk/FREE.COM free.asm
        cpu 8086
        org 100h
        mov sp,stk_top
        mov bx,(stk_top-$$+100h+15)/16         ; shrink our own block (a .COM owns all memory)
        mov ah,4Ah
        int 21h
        mov bx,0FFFFh
        mov ah,48h
        int 21h                         ; fails, BX = largest block
        mov dx,msg
        mov ah,9
        int 21h
        mov cx,4
.h:     mov dl,bh
        shr dl,1
        shr dl,1
        shr dl,1
        shr dl,1
        add dl,'0'
        cmp dl,'9'
        jbe .p
        add dl,7
.p:     mov ah,2
        int 21h
        shl bx,1
        shl bx,1
        shl bx,1
        shl bx,1
        loop .h
        mov dx,crlf
        mov ah,9
        int 21h
        mov ax,4C00h
        int 21h
msg:    db 'FREE paragraphs=$'
crlf:   db 13,10,'$'
        align 2
        times 128 db 0
stk_top:
