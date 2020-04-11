;; PROGRM TO SENSE THE IR CODE AND STORE TO A RAM LOCATION

;; variables used :     rem_bits, remcnt, rem_timeout, byte_cnt, temp
;;                      dat_buf0, dat_buf1, cust_buf0, cust_buf1
;;                      incode, new_data in hw_status                   ( 11)
;; constants      :     custcode0, custcode1, repeat_tocnt,rem_timeout_cnt (4)

;; remote sense routine
;; check the interrupt pin level
;; if the pin is high, return
;; else check for leader code

hwirq_int:
                lda     iscr            ; interrupt status register
                ora     #02h            ; clear irq flag
                sta     iscr

rem_sen:        bil     chk_leader      ; if intrupt is low detected,chk leader
ret_remsen:     rti

;; chk_leader
;; set a counter (remcnt) for 5msec
;; check the rem_line low after every 100usec
;; if the line found high, return immediately
;; keep on checking at least for 5 msec
chk_leader:     lda     #50t            ; load a counter with 5 msec
                sta     remcnt
chk_leader_again:bih    ret_remsen      ; if interrupt high in between, return
                bsr     dly_100u        ; call delay 100 usecs
                dec     remcnt
                lda     remcnt
                bne     chk_leader_again ; if 5msec not over, chk leader again

;; valid leader pulse is found
;; wait for leader to go high. However if leader is high for more than 15 msecs,
;; invalid leader,return
                lda     #100t           ; load counter with 10 msec
                sta     remcnt
wait_leader_gap:bih     chk_leader_gap  ; if rem line goes high, goto chk gap
                bsr     dly_100u
                dec     remcnt
                lda     remcnt          ; is 10msec over ?
                bne     wait_leader_gap ; no, go back to wait for leader gap
                bra     ret_remsen      ; yes, invalid pulse, return

;; now check for leader gap
;; wait for 100usec before proceding, rem_line should be high
;; if leader is high for more than 3 msec, this is a 1st command code
;; if rem_line goes low before 3 msec, check it for repeat code
chk_leader_gap:         jsr     dly_100u        ; give a 100 usec delay
                        lda     #30t            ; set counter for 3 msec
                        sta     remcnt
leader_gap_again:       bil     chk_repeat_code     ; if rem_line low, it is
                        bsr     dly_100u            ; repeat code
leader_gap_nxt:         dec     remcnt
                        lda     remcnt              ; is 3 msec over ?
                        bne     leader_gap_again    ; no, chk leader gap again
                        bra     chk_new_data        ; yes, chk it is new code

;; chk_repeat_code
;; rem_line goes low before 3 msec
;; check for genuine low by checking again after 100usec delay
;; if still low - can be a repeat code
;; if not low -ignore thos pulse and continue with chk leader_gap_nxt
;; wait for 1msec
;; now rem_line should be high ti show a ganuine repeat code
;; if not high, ignore and go back to calling program
chk_repeat_code:        bsr     dly_100u        ; 100usec delay to avoid noise
                        bih     leader_gap_nxt  ; if rem pin level high,go one
                        lda     #10t            ; step back to continue again
wait_1msec:             sta     remcnt          ; load counter for 1 msec delay
                        bsr     dly_100u
                        dec     remcnt
                        lda     remcnt
                        bne     wait_1msec      ; wait for 1 msec
                        bih     repeat_found    ; now pin level should go high
                        bra     ret_remsen      ; if low, return
repeat_found:           inc     byte_cnt        ; once repeat code detected,
                        lda     #repeat_tocnt   ; update the set parameters
                        sta     rem_timeout
                        bra     ret_remsen

;; dly_100u
;; 100 usec delay routine
dly_100u:       lda     #10t
dly100_nxt:     sta     temp
                nop
                dec     temp
                lda     temp
                bne     dly100_nxt
                rts

;; chk_new_data
;; if leader_gap is more than 3 msec - this must be a new data
;; still wait for 3msec more
;; if low level not found within 3 msec, declare wrong code and quit
;; else collect custom codes and data codes
chk_new_data:           lda     #30t            ; load counter for 3msec
                        sta     remcnt
chk_newgap_again:       bil     chk_gap_over    ; if pin level goes low,leader
                        bsr     dly_100u        ; gap check part is over
chk_new_gap_nxt:        dec     remcnt
                        lda     remcnt          ; check if 3 msec over ?
                        bne     chk_newgap_again; no, go back to check next
                        bra     ret_remsen      ; else wrong data, return
chk_gap_over:           bsr     dly_100u        ; give delay to avoid noise
                        bih     chk_new_gap_nxt ; if goes high, go back for next

;; 1st command leader is found
;; now receive custom code and data codes (all 32 bits) and save to memory
;; program reaches here after sensing first low after leader code gap
;; count the time till rem_line remains low
;; if time is more than 3 msec, wrong data type - quit

                        lda     #32t            ; counter to receive custom and
                        sta     rem_bits        ; data codes ( 4 words )
cod_wait_nxt_bit:       lda     #30t            ; set counter for 3 msec
                        sta     remcnt
code_waitil_low:        jsr     dly_100u        ; wait for code till low
cod_waitlow_toe:        dec     remcnt
                        lda     remcnt          ; if 3 msec has not past, check
                        bne     cod_chk_for_low ; for line to go high*
                        jmp     ret_remsen      ; else if 3 msec over, quit
cod_chk_for_low:        bil     code_waitil_low ; wait till code is low
                        bsr     dly_100u
                        bil     cod_waitlow_toe

;; now wait till it remains high
;; if time exceeds 3msec, cancel the process and quit
code_waitil_high:       bsr     dly_100u        ; wait for code till high
cod_waithigh_toe:       dec     remcnt
                        lda     remcnt          ; if 3 msec not elapsed til yet,
                        bne     cod_chk_for_high; check for pin to go low*
                        jmp     ret_remsen      ; else if 3 msec over, return
cod_chk_for_high:       bih     code_waitil_high; wait here till code is high
                        bsr     dly_100u
                        bih     cod_waithigh_toe

;; now rem_line has gone low
;; check total time since last low
;; it time > 1.7 msec   - treat it as low
;; if time < 1.7 msec   - treat it high

                lda     remcnt          ; rem counter has counts (30-counts)
                cmp     #17t            ; compare it with 1.7 msec
                blo     bit1_recd       ; if it has value less than 1.7msec,bit1
bit0_recd:      clc                     ; else bit0 is recd.
                bra     shift_bit       ; clear carry if bit 0 recd
bit1_recd:      sec                     ; set carry if bit 1 recd
shift_bit:      ror     dat_buf0        ; dat_buf0 is inverted (i,e. dat_bufb)
                ror     dat_buf1
                ror     cust_buf0       ; cust_buf0 is inverted code (cust_bufb)
                ror     cust_buf1       ; rotate all values accordingly to left

chk_rem_bits:   dec     rem_bits        ; if all bits not recd, go back to
                lda     rem_bits        ; receive more bits
                bne     cod_wait_nxt_bit

;; all 32 bits are recd
;; check for accuracy of code and data bytes
;; and set new_data and incode variables
chk_data_recd:
                lda     #custcode1      ; compare custcode1 with cust_buf1
                cmp     cust_buf1       ; if o.k,
                bne     code_error
                lda     cust_buf0       ; compare custcode0 with invert of
                coma                    ; custcodeb
                cmp     #custcode0      ; if not equal,error, return
                bne     code_error      ; else
                lda     dat_buf0        ; compre dat_buf1 with inverted dat_buf0
                coma
                cmp     dat_buf1
                bne     code_error      ; if not equal, it is error
                lda     dat_buf1        ; else if all o.k,
                sta     incode          ; store dat_buf1 to incode

incode2kbdpos   clrx
chk_nxt         cmp     kbd_table,x
                beq     upd_kbdpos
                incx
                cmpx    #10h
                bls     chk_nxt
upd_kbdpos      stx     kbd_pos

                bset    new_key_found,status      ; set status bit (new_data = 1)
                lda     #rem_timeout_cnt        ; set other parameters too
                sta     rem_timeout
code_error:     jmp     ret_remsen


kbd_table:      db     97h                    ;; code for attn up
                db     93h                    ;; code for attn dn
                db     88h                    ;; code for trebleup
                db     8bh                    ;; code for trebledn
                db     94h                    ;; code for ball
                db     90h                    ;; code for balr
                db     81h                    ;; code for bassup
                db     83h                    ;; code for bassdn
                db     86h                    ;; code for flat
                db     80h                    ;; code for bassboost
                db     8fh                    ;; code for mute
                db     85h                    ;; code for on_off

;;kbD_table       db      0,1,2,3,4,5,6,7,8,9
                db      1ch,16h,17h,19h,0ch,0dh



;kbd_table       db      83h,82h,81h,87h,86h,84h,8bh,8ah,88h,8eh
;                       1   2   3   4   5   6   7   8   9   10

;               db      89h,85h
;                       on  off

