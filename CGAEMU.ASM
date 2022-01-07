;
; CGA emulator for ISA_VG75 hw:2.0
; sw: 1.2b
; (c) Tronix 2022
;
; history
; 1.0b - initial release
; 1.1b - change sqr() with IMUL to abs() with CBW/XOR/SUB
; 1.2b - clear video memory before enter and before exit graph mode

SKIP_FRAMES     = 1                     ; skip some frames
USE_286         = 1                     ; use 186+ opcodes
USE_DOSBOX      = 1                     ; DOSBOX or real ISA_VG75
;HOOK_08_INSTEAD_1C = 1                  ; Hook Int 08h instead Int 1Ch

JUMPS
.MODEL Tiny
.CODE
.STARTUP
ifdef USE_286
.286
endif

ifdef USE_DOSBOX
text_page_size  equ     2000h           ; 80x50 text page size
vid_page_num    equ     4               ; Visible text page
else
text_page_size  equ     2040h           ; 80x50 text page size
vid_page_num    equ     2               ; Visible text page
endif
start:          jmp set_1c

; Magic const for already set checking
magic           dw '75'

; Run-time variables
tick            db  0                   ; Tick counter
can_run         db  0                   ; Int 1C semaphore
int10_in_use    db  0                   ; Int 10 reentrancy counter

; Palette conversion table
normal_pal      db 00h, 03h, 05h, 0fh

; New INT 1Ch interrupt handler
int_1c:
		pushf
                cmp     byte ptr cs:can_run,0   ; Check we are in graphics mode?
                je      int1c_exit
ifdef SKIP_FRAMES
                inc CS:Tick
                cmp byte ptr cs:Tick,2
                jng int1c_exit
                mov CS:Tick,0
endif
                push    ds
                push    es
ifdef USE_286
                pusha
else
                push    si
                push    di
                push    bx
                push    dx
                push    ax
                push    cx
                push    bp
endif
                mov     ax,0b800h
                mov     ds,ax
                xor     si,si                   ; DS:SI = B80000

                mov     ax,0b800h
                mov     es,ax
                mov     di,text_page_size*2     ; ES:DI = B80000 + text_page_size*2

                xor     bp,bp                   ; BP as lines counter
                cld

;inner loop
start_loop:
                cli
                mov     bh,ds:[si]              ; Get 4x4 px block into BX,DX
                mov     bl,ds:[si+2000h]
                mov     dh,ds:[si+80];
                mov     dl,ds:[si+2000h+80]

                mov     ah,bh                   ; (block1 & 0xc0) >> 6
                and     ah,0c0h
ifdef USE_286
                shr     ah,6
else
                mov     cl,6
                shr     ah,cl
endif

                mov     al,bh                   ; (block1 & 0x30) >> 4
                and     al,030h
ifdef USE_286
                shr     al,4
else
                mov     cl,4
                shr     al,cl
endif
                add     ah,al

                mov     al,bl                   ; (block2 & 0xc0) >> 6
                and     al,0c0h
ifdef USE_286
                shr     al,6
else
                mov     cl,6
                shr     al,cl
endif
                add     ah,al

                mov     al,bl                   ; (block2 & 0x30) >> 4
                and     al,030h
ifdef USE_286
                shr     al,4
else
                mov     cl,4
                shr     al,cl
endif
                add     ah,al

                shr     ah,2                    ; divide for 4
                mov     ch,ah                   ; CH = c1

                mov     ah,bh                   ; (block1 & 0x0c) >> 2
                and     ah,0ch
                shr     ah,2

                mov     al,bh                   ; block1 & 0x03
                and     al,03h
                add     ah,al

                mov     al,bl                   ; (block2 & 0x0c) >> 2
                and     al,0ch
                shr     al,2
                add     ah,al

                mov     al,bl                   ; block1 & 0x03
                and     al,03h
                add     ah,al

                shr     ah,2                    ; divide for 4
ifdef USE_286
                mov     cl,ah                   ; CL = c2
else
                mov     bh,ah                   ; (need CL) BH = c2
endif

                mov     ah,dh                   ; (block3 & 0xc0) >> 6
                and     ah,0c0h
ifdef USE_286
                shr     ah,6
else
                mov     cl,6
                shr     ah,cl
endif

                mov     al,dh                   ; (block3 & 0x30) >> 4
                and     al,030h
ifdef USE_286
                shr     al,4
else
                mov     cl,4
                shr     al,cl
endif
                add     ah,al

                mov     al,dl                   ; (block4 & 0xc0) >> 6
                and     al,0c0h
ifdef USE_286
                shr     al,6
else
                mov     cl,6
                shr     al,cl
endif
                add     ah,al

                mov     al,dl                   ; (block4 & 0x30) >> 4
                and     al,030h
ifdef USE_286
                shr     al,4
else
                mov     cl,4
                shr     al,cl
endif
                add     ah,al

                shr     ah,2                    ; divide for 4
ifndef USE_286
                mov     cl,bh                   ; restore CL = c2
endif
                mov     bh,ah                   ; BH = c3

                mov     ah,dh                   ; (block3 & 0x0c) >> 2
                and     ah,0ch
                shr     ah,2

                mov     al,dh                   ; block3 & 0x03
                and     al,03h
                add     ah,al

                mov     al,dl                   ; (block4 &0x0c) >> 2
                and     al,0ch
                shr     al,2
                add     ah,al

                mov     al,dl                   ; block4 & 0x03
                and     al,03h
                add     ah,al

                shr     ah,2                    ; divide for 4
                mov     bl,ah                   ; BL = c4

                ; CH = c1; CL = c2; BH = c3; BL = c4

                mov     dl,ch
                add     dl,bh
                shr     dl,1                    ; DL = (c1 + c3) / 2

                mov     dh,cl
                add     dh,bl
                shr     dh,1                    ; DH = (c2 + c4) / 2

                mov     al,ch
                add     al,cl
                shr     al,1                    ; AL = (c1 + c2) / 2

                mov     ah,bh
                add     ah,bl
                shr     ah,1                    ; AH = (c3 + c4) / 2

                mov     bx,ax

                ; DL = color1w; DH = color2w; BL - color1h; BH - color2h

                mov     al,dl
                sub     al,dh			; AL = color1w-color2w
		cbw
		xor	al,ah
		sub	al,ah			; d_w = abs(color1w-color2w)
                mov     cl,al                   ; CL = d_w

                mov     al,bl
                sub     al,bh			; AL = color1h-color2h
		cbw
		xor	al,ah
		sub	al,ah			; d_h = abs(color1h-color2h)
                mov     ch,al                   ; CH = d_h

                ; CL = d_w; CH = d_h

                push    ds
                push    cx
                mov     cx,bx                   ; save BX (color1h,color2h)

                push    cs
                pop     ds                      ; DS = code seg
                mov     bx,offset normal_pal    ; Convert all colors to TXT
                mov     al,dl
                xlat
                mov     dl,al

                mov     al,dh
                xlat
                mov     dh,al

                mov     al,cl
                xlat
                mov     cl,al

                mov     al,ch
                xlat
                mov     ch,al

                mov     bx,cx                   ; restore BX (color1h,color2h)
                pop     cx
                pop     ds

                ; DL = Pal[color1w]; DH = Pal[color2w]; BL - Pal[color1h]; BH - Pal[color2h]

                cmp     cl,ch                   ; d_w < d_h - best horizontal fit
                jae     best_vert

                xor     ah,ah
                mov     al,bh
ifdef USE_286
                shl     ax,8                    ; AX = color2h shl 8
else
                mov     cl,8
                shl     ax,cl
endif

                xor     bh,bh
ifdef USE_286
                shl     bx,12                   ; BX = color1h shl 12
else
                mov     cl,12
                shl     bx,cl
endif

                or      ax,bx
                mov     bx,220
                or      ax,bx                   ; AX = AX | BX | 220

                stosw                           ; store chr and attr to mem
                jmp     done_cycle
best_vert:
                xor     ah,ah
                mov     al,dh
ifdef USE_286
                shl     ax,12                   ; AX = color2w shl 12
else
                mov     cl,12
                shl     ax,cl
endif

                xor     dh,dh
ifdef USE_286
                shl     dx,8                    ; DX = color1w shl 8
else
                mov     cl,8
                shl     dx,cl
endif

                or      ax,dx
                mov     dx,221
                or      ax,dx                   ; AX = AX | DX | 221

                stosw                           ; store chr and attr to mem
done_cycle:
                sti
                inc     si
                inc     bp
                cmp     bp,80
                jne     check_for_end
                add     si,80
                xor     bp,bp
check_for_end:
                cmp     si,2000h
                jge     nothing_to_do
                jmp     start_loop

nothing_to_do:
ifdef USE_286
                popa
else
                pop     bp
                pop     cx
                pop     ax
                pop     dx
                pop     bx
                pop     di
                pop     si
endif
                pop     es
                pop     ds
int1c_exit:
		popf
               ;;;; iret
                db 0eah         ; jmp far
old_1c_offset   dw  ?
old_1c_segment  dw  ?


; INT 10h interrupt handler
int_10:
                pushf
                cmp     cs:int10_in_use,0       ; Reentrancy?
                jne     int10_return

                test    ah,ah
                jz      int10_fn00              ; AH = 00h (set video mode)

                cmp     cs:can_run,0            ; We are in graph mode?
                je      int10_return            ; No - nothing to handle
                                                ; Call old INT 10h service

                jmp     int10_exit              ; Ignore all functions
                                                ; in graph mode, exit

int10_fn00:
                cmp     al,2                    ; Text mode?
                je      its_text
                cmp     al,3                    ; Text mode?
                jne     check_graph
its_text:
                push    ds
                push    es
ifdef USE_286
                pusha
else
                push    si
                push    di
                push    bx
                push    dx
                push    ax
                push    cx
endif

                mov     cs:can_run,0            ; Stop Int 1C
                mov     ax,1202h
                mov     bl,30h
                inc     cs:int10_in_use
                pushf
                call    cs:old_10

                mov     ax,0500h                ; set active page to 0
                pushf
                call    cs:old_10

                dec     cs:int10_in_use

                mov     ax,0b800h		; clear video
                mov     es,ax
		xor	di,di			; ES:DI = B80000
		xor	ax,ax
		mov	cx,2000h
		rep	stosw
                mov     di,text_page_size*2     ; ES:DI = B80000 + text_page_size*2
		mov	cx,text_page_size/2
		rep	stosw

ifdef USE_286
                popa
else
                pop     cx
                pop     ax
                pop     dx
                pop     bx
                pop     di
                pop     si
endif
                pop     es
                pop     ds

                jmp     int10_return
check_graph:
                cmp     al,4
                je      switch_to_graph
                cmp     al,5
                jne     int10_return
switch_to_graph:
                push    ds
                push    es
ifdef USE_286
                pusha
else
                push    si
                push    di
                push    bx
                push    dx
                push    ax
                push    cx
endif
                inc     cs:int10_in_use
                mov     ax,1112h
                pushf
                call    cs:old_10

                mov     ax,1003h
                xor     bx,bx
                pushf
                call    cs:old_10

                mov     ah,05
                mov     al,vid_page_num         ; set active visible page
                pushf
                call    cs:old_10

                dec     cs:int10_in_use

                mov     ax,0b800h		; clear video
                mov     es,ax
		xor	di,di			; ES:DI = B80000
		xor	ax,ax
		mov	cx,2000h
		rep	stosw
                mov     di,text_page_size*2     ; ES:DI = B80000 + text_page_size*2
		mov	cx,text_page_size/2
		rep	stosw

                mov     cs:can_run,1            ; Start Int 1C
ifdef USE_286
                popa
else
                pop     cx
                pop     ax
                pop     dx
                pop     bx
                pop     di
                pop     si
endif
                pop     es
                pop     ds
int10_exit:
                popf
                iret
int10_return:
                popf
                db 0eah         ; jmp far
old_10 label dword
old_10_offset   dw  ?
old_10_segment  dw  ?
;-----------------------------------------;
set_1c:         mov     dx,offset Copyr
                mov     ah,9
                int     21h
ifdef HOOK_08_INSTEAD_1C
                mov     ax,3508h
else
                mov     ax,351ch
endif
                int     21h
                cmp     byte ptr ds:[82h],'-'
                je      remove
                cmp     word ptr es:magic,'75'
                je      already
                mov     cs:old_1c_offset,bx
                mov     cs:old_1c_segment,es
ifdef HOOK_08_INSTEAD_1C
                mov     ax,2508h
else
                mov     ax,251ch
endif
                mov     dx,offset int_1c
                int     21h

                mov     ax,3510h
                int     21h
                mov     cs:old_10_offset,bx
                mov     cs:old_10_segment,es
                mov     ax,2510h
                mov     dx,offset int_10
                int     21h

                mov     dx,offset inst
                mov     ah,9
                int     21h
                mov     dx,offset set_1c
                int     27h

inst    DB 'Installed!$'

already:
                mov     dx,offset M_alr
                mov     ah,9
                int     21h
                int     20h

M_alr   DB 'Already installed!$'

remove:         cmp     word ptr es:magic,'75'
                jne     not_installed
                push    es
                push    ds
                mov     dx,es:old_1c_offset
                mov     ds,es:old_1c_segment
ifdef HOOK_08_INSTEAD_1C
                mov     ax,2508h
else
                mov     ax,251ch
endif
                int     21h
                mov     dx,es:old_10_offset
                mov     ds,es:old_10_segment
                mov     ax,2510h
                int     21h
                pop     ds
                pop     es
                mov     ah,49h
                int     21h
                mov     dx,offset removed
                mov     ah,9
                int     21h
                int     20h

Removed DB 'Removed from mem!!!$'

not_installed:
                mov     dx,offset n_i
                mov     ah,9
                int     21h
                int     20h

n_i     DB 'Not installed!$'
Copyr   DB 'CGAEMU CGA emulator for ISA_VG75 videocard',13,10
        DB 'v1.2 '
ifdef USE_286
        DB '[286+]'
else
        DB '[8088]'
endif
ifdef USE_DOSBOX
        DB ' [DOSBOX]'
else
        DB ' [ISA_VG75]'
endif
        DB ' (c) Tronix 2022',13,10,'$'
END
