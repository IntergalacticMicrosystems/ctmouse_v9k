; HK41.COM - test TSR: hooks INT 41h with a stub that jumps to the old vector, stays resident.
; nasm -f bin -o ../disk/HK41.COM hook41.asm
        cpu 8086
        org 100h
        jmp init
stub:   jmp far [cs:old41]
old41:  dd 0
resend:
init:   mov ax,3541h
        int 21h
        mov [old41],bx
        mov [old41+2],es
        mov dx,stub
        mov ax,2541h
        int 21h
        mov dx,msg
        mov ah,9
        int 21h
        mov dx,(resend-$$+100h+15)/16
        mov ax,3100h
        int 21h
msg:    db 'HK41 resident, INT 41h hooked',13,10,'$'
