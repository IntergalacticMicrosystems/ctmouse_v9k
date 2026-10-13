; TEST.COM - DOSBox smoke test for CTMOUSEV.EXE (see run.sh). Adapted from
; Victor9000-Software/mouse/dosbox_test/harness.asm (the MOUSE.COM test).
; Redirects stdout to OUT.TXT, then EXECs, logging INT 33h (+ 5 signature bytes), INT 41h, the
; IMR byte E000:0001, the largest free block (48h BX=FFFFh) and the child return code:
;   run 1  no argument                  -> usage, rc 1, nothing changed
;   run 2  /SA, nothing on the "port"   -> "No mouse detected", rc 2, INT 41h/IMR unchanged
;   run 3  /SA, INT 08h hook from tick 9 on keeps RR0A bit 0 (E000:0042) set and the data
;          byte E000:0040 = 'M'        -> installed (rc 0300), INT 33h has 'MOUSE', INT 41h hooked
;   run 4  V9KMT.COM with scripted keys (no cursor shown: F000h is ROM in DOSBox)
;   run 5  /SA again (same port)        -> reload over ours
;   run 6  INT 41h taken by this harness, then /U -> refused, rc 2, vectors untouched
;   run 7  INT 41h given back, /U       -> unloaded, rc 0, INT 33h/41h restored, memory freed
; Lines start with "#n" so run.sh can find them.
        cpu 8086
        org 0x100
start:
        mov bx,0x100                    ; keep 4 KB so EXEC has room
        mov ah,0x4a
        int 0x21
        mov dx,fname
        xor cx,cx
        mov ah,0x3c
        int 0x21
        mov bx,ax
        mov cx,1
        mov ah,0x46
        int 0x21                        ; handle 1 := OUT.TXT
        push ds
        mov ax,0xe000
        mov ds,ax
        mov byte [0x01],0xff            ; "IMR" (RAM here): all masked
        mov byte [0x42],0               ; "RR0A": nothing received
        pop ds
        mov ax,0x3508
        int 0x21
        mov [old08],bx
        mov [old08+2],es
        mov dx,new08
        mov ax,0x2508
        int 0x21

        mov byte [runno],'0'
        call log_vec
        mov dx,tail_none                ; 1
        call run_drv
        mov dx,tail_sa                  ; 2
        call run_drv
        mov word [ticks],0              ; 3
        mov byte [armed],1
        mov dx,tail_sa
        call run_drv
        mov byte [armed],0
        mov dx,prog_mt                  ; 4
        mov si,tail_mt
        call run
        mov dx,tail_sa                  ; 5
        call run_drv
        mov ax,0x3541                   ; 6: take INT 41h away from the driver
        int 0x21
        mov [save41],bx
        mov [save41+2],es
        mov dx,stub41
        mov ax,0x2541
        int 0x21
        mov dx,tail_u
        call run_drv
        push ds
        lds dx,[save41]
        mov ax,0x2541
        int 0x21
        pop ds
        mov dx,tail_u                   ; 7
        call run_drv

        lds dx,[old08]
        mov ax,0x2508
        int 0x21
        mov ax,0x4c00
        int 0x21

stub41: iret

new08:  cmp byte [cs:armed],0
        jz .chain
        inc word [cs:ticks]
        cmp word [cs:ticks],9
        jb .chain
        push es
        push ax
        mov ax,0xe000
        mov es,ax
        mov byte [es:0x40],'M'          ; data byte
        or byte [es:0x42],1             ; RR0 bit 0 = Rx character available
        pop ax
        pop es
.chain: jmp far [cs:old08]

run_drv:                                ; DX -> command tail, runs CTMOUSEV.EXE
        mov si,dx
        mov dx,prog
run:                                    ; DX -> program name, SI -> tail
        inc byte [runno]
        mov [pb_tail],si
        mov [pb_tail+2],cs
        mov word [pb_env],0             ; inherit our environment
        mov word [pb_fcb1],0x5c
        mov [pb_fcb1+2],cs
        mov word [pb_fcb2],0x6c
        mov [pb_fcb2+2],cs
        push dx
        mov dx,m_run
        call puts
        mov dl,[runno]
        call putc
        mov dl,' '
        call putc
        pop dx
        push dx
        call putz
        inc si
        mov dl,'"'
        call putc
.t:     lodsb
        cmp al,13
        je .te
        mov dl,al
        call putc
        jmp .t
.te:    mov dl,'"'
        call putc
        call crlf
        pop dx
        mov [save_ss],ss
        mov [save_sp],sp
        push cs
        pop es
        mov bx,pblock
        mov ax,0x4b00
        int 0x21
        cli
        mov ss,[cs:save_ss]
        mov sp,[cs:save_sp]
        sti
        push cs
        pop ds
        push cs
        pop es
        cld
        jc .fail
        mov ah,0x4d
        int 0x21                        ; AX = child return code (AH=3 if TSR)
        push ax
        call crlf
        call tag
        mov dx,m_rc
        call puts
        pop ax
        call hex4
        jmp short .done
.fail:  push ax
        call crlf
        call tag
        mov dx,m_execfail
        call puts
        pop ax
        call hex4
.done:  call crlf
        ; fall into log_vec

log_vec:
        call tag
        mov dx,m_vec
        call puts
        mov ax,0x3533
        int 0x21
        mov ax,es
        call hex4
        mov dl,':'
        call putc
        mov ax,bx
        call hex4
        mov dl,' '
        call putc
        mov cx,5
        sub bx,5
.sig:   mov dl,[es:bx]
        cmp dl,' '
        jb .dot
        cmp dl,7eh
        jbe .ok
.dot:   mov dl,'.'
.ok:    call putc
        inc bx
        loop .sig
        mov dx,m_vec41
        call puts
        mov ax,0x3541
        int 0x21
        mov ax,es
        call hex4
        mov dl,':'
        call putc
        mov ax,bx
        call hex4
        mov dx,m_imr
        call puts
        mov ax,0xe000
        mov es,ax
        mov al,[es:0x01]
        call hex2
        mov dx,m_free
        call puts
        mov bx,0xffff
        mov ah,0x48
        int 0x21                        ; fails, BX = largest block
        mov ax,bx
        call hex4
        push cs
        pop es
        jmp crlf

tag:    mov dl,'#'
        call putc
        mov dl,[runno]
        call putc
        mov dl,' '
        jmp putc
putz:   push si                         ; ASCIIZ at DX
        mov si,dx
.l:     lodsb
        or al,al
        jz .e
        mov dl,al
        call putc
        jmp .l
.e:     mov dl,' '
        call putc
        pop si
        ret
puts:   mov ah,9
        int 0x21
        ret
crlf:   mov dx,m_crlf
        jmp puts
putc:   mov ah,2
        int 0x21
        ret
hex4:   push ax
        mov al,ah
        call hex2
        pop ax
hex2:   push ax
        mov cl,4
        shr al,cl
        call hex1
        pop ax
hex1:   and al,0xf
        add al,'0'
        cmp al,'9'
        jbe .p
        add al,7
.p:     mov dl,al
        jmp putc

fname:  db 'OUT.TXT',0
prog:   db 'CTMOUSEV.EXE',0
prog_mt: db 'V9KMT.COM',0
tail_none: db 0,13
tail_sa: db 4,' /SA',13
tail_u: db 3,' /U',13
tail_mt: db 13,' 78n94trdewlq',13
m_run:  db '=== run $'
m_vec:  db 'INT33=$'
m_vec41: db ' INT41=$'
m_imr:  db ' IMR=$'
m_free: db ' free=$'
m_rc:   db 'child rc=$'
m_execfail: db 'EXEC FAILED ax=$'
m_crlf: db 13,10,'$'
runno:  db '0'
armed:  db 0
ticks:  dw 0
old08:  dd 0
save41: dd 0
save_ss: dw 0
save_sp: dw 0
pblock:
pb_env:  dw 0
pb_tail: dd 0
pb_fcb1: dd 0
pb_fcb2: dd 0
