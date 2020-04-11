
;;27.05.99
;;program for remote controlled audio unit
;; init ports
;; act_kbd
;; store_memory
;; read_memory
;; 28.5.99
;; errors removed
;; logic checked by vinay
;;
;; 29.5.99
;;      delayed save/repeat keys/key release/tim_int
;;      functions added
;;      all functions tested except 7215 programming
;; 31.5.99
;; to test audio functions
;; file size 2860
;; total bytes 3fe
;; check sum b6b9
;; total files/size -3/34471
;; 31.7.99
;; kbd codes changed
;; scl/sda position interchanged due to pcb design
;; fault analysis added - led blinks if error
;; unit will work even if memory ic is bad
;; by selecting default values for audio ics
;; and skipping writing into memory
;; similarly audio ic bad will not stop the system
;; remote can still be checked with all leds glowing as programmed

;; bug of loudness led not getting off solved by adding chk_set_bb in
;; flat routine
;; also audio center will cancel mute led and mute status
;;
;; s19 file size
;; total files   3
;; total size 3,522bytes
;; starting byte 49b
;; check sum 3daa
;; total bytes 4ef
;; 4.8.99
;; if new eeprom is used
;; set all values as def values
;; to avoid any problems of dec/inc volume/other tone parameters
;; s19 file size 3522
;; total size 3/41125
;; check sum 3a2d
;; total bytes 4ef
;; starting byte 49b



;;
;;      key release function
;;              when a key is presed remsen.asm sets rem_timeout for
;;              250 mseconds as another key press may come within that time
;;              after the expiry of 250 msecs
;;              timer routines decrement rem_timeout if not zero
;;              when rem_timeout reaches a value of zero
;;              this means key is released
;;              so set a key_release flag or do the job reqd for key release
;;              ie clear vol/tre/bal/bass leds (do not change mute/flat leds)

;;      continous press
;;              if a key is pressed remote handset will send command after
;;              every 250 mseconds. remsen program will increment byte_cnt
;;              after every 250 msecs. chkbd program can check byte_cnt
;;              and after certain byte_cnts for certain keys act_kbd is called
;;              again even when new_key_found is not set
;;              this repeat key is performed for vol/tre/bal/bass
;;              and not for bass_boost/power/mute keys
;;
;;
;;      delayed save
;;              when ever a key is pressed set a save_timeout = 6 seconds
;;              in time routine decrements (if not zero) after every second
;;              when this value reaches to zero either set a flag or do
;;              necessary jobs.
;;              in main routine check for flag
;;              if set do necessary job and clear flag
;;              for power do it immediately
;;
;;      tim_int
;;              at power on set timer int after every 8.2 msec
;;              set tim_int vector at 7f8h
;;              in int ser routine
;;              decrement rem_timeout if not zero
;;              if zero after decrementing set flag/act as reqd
;;              count seconds
;;              after evry one seccond decrement save_timeout if not zero
;;              if zero after decrementing then set flag/act as reqd



                org     0c0h

kbd_pos         db      00

;; bytes to read from eeprom
;; current status in memory

status          db      00
save_reqd       equ     4
mute            equ     2
on_offb         equ     1
bass_boost      equ     3
bass_boostbyte  equ     08h
new_key_found   equ     0
status_bits     equ     0eh
nomem_memb      equ     5               ; no memory high
noaud_audb      equ     6               ; no audio ic high






mutebyte        equ     04h
on_offbyte      equ     02h
new_keybyte     equ     01h

volume          db      00              ; attn
treble          db      00
bass            db      00
balance_l       db      00              ; attn
balance_r       db      00
max_mem_bytes   equ     6

max_tone        db      00

k_on_off        equ     0bh
k_volup         equ     00
k_voldn         equ     01
k_treup         equ     02
k_tredn         equ     03
k_ball          equ     04
k_balr          equ     05
k_bassup        equ     06
k_bassdn        equ     07
k_flat          equ     08
k_bassboost     equ     09
k_mute          equ     0ah

def_volume      equ     1fh
max_volume      equ     3fh
max_treble      equ     0eh
max_bass        equ     0eh
def_treble      equ     7t
def_bass        equ     7t
max_balance     equ     1fh


def_initpa      equ     0feh

led_port        equ     porta
relay_port      equ     porta
led_volume      equ     7
led_treble      equ     6
led_balance     equ     5
led_bass        equ     4
led_flat        equ     3
led_mute        equ     2
led_bassboost   equ     1
relay           equ     0


scl             equ     2
sda             equ     3
iicport         equ     portb
iicont          equ     ddrb

temp            db      00
blink_data
e_add           db      00
blink_counter
e_dat           db      00


;; for remote
custcode0       equ     81h             ; second code on rem tester
custcode1       equ     00h             ; fisrt code on rem tester
rem_bits        db      00
remcnt          db      00
rem_timeout     db      00
byte_cnt        db      00
dat_buf0        db      00
dat_buf1        db      00
cust_buf0       db      00
cust_buf1       db      00
incode          db      00
rem_timeout_cnt equ     50
repeat_tocnt   equ      30


def_timer       equ     14h
ticks           db      00
save_timeout    db      00
def_save_to     equ     6t

;; for 7315
max_attn        equ     00h
min_attn        equ     0c0h

                org     300h

$include        "remsen.asm"
$include        "iic.asm"

dly_hsec        clr     ticks
wait_hsec       lda     ticks
                cmp     #61t
                bne     wait_hsec
                rts

start:          rsp                     ; reset stack pointer
                lda     #0ffh           ; set porta as output
                sta     ddra
                lda     #def_initpa     ; set all leds off, relay off
                sta     porta
                lda     #03fh           ; set portb as output
                sta     ddrb
                sta     portb

                lda     #def_timer
                sta     tscr
                cli


                ldx     #50h
clr_nxt_mem     clr     ,x
                incx
                bne     clr_nxt_mem


;; test programs

chk_mem         jsr     gen_start       ; give start pulse
                lda     #0a0h           ; write in memory
                jsr     byte_iic
                bcc     chk_7315        ; if no error check audio
mem_bad         bclr    led_volume,led_port ; if mem error set led_volum
                bset    nomem_memb,status

chk_7315        jsr     gen_start       ; check audio ic
                lda     #80h
                jsr     byte_iic
                bcc     chk_error       ; no audio error
aud_bad         bclr    led_treble,led_port ; error - set treble led
                bset    noaud_audb,status

chk_error       lda     led_port        ; read back led port
                cmp     #def_initpa     ; if same as data written ie no error
                bne     set_blink_data  ;
                clra                    ; set all leds on
set_blink_data  sta     blink_data      ; and store in blink_data

blink_status    lda     blink_data      ; get temp value which is status led
                sta     led_port        ; status led(s) on for half sec
                bsr     dly_hsec
                lda     #def_initpa
                sta     led_port
                bsr     dly_hsec

                inc     blink_counter   ; repeat this three times
                lda     blink_counter   ; to indicate unit ok
                cmp     #3t
                bne     blink_status



;;read status & other 5 bytes from memory
;; only if nomem_memb is low
;; if vol/tre/bass/status/bal_l/bal_r is ff then goto set_def_tome
;; this is useful for new eeprom
read_memory     brset   nomem_memb,status,set_def_tone
                clr     e_add
next_rm         jsr     get_eeprom_info
                ldx     e_add
                lda     e_dat
                cmp     #0ffh           ;; if data if ff ie new data
                beq     set_def_tone    ;; goto set_def_tone ie select def values
                sta     status,x
                inc     e_add
                lda     e_add
                cmp     #max_mem_bytes
                bne     next_rm

                lda     status
                and     #status_bits
                sta     status
                bra     act_mem_nomem


set_def_tone    jsr     set_all_def
                lda     #def_volume
                sta     volume

act_mem_nomem   jsr     proc_power

;; check keyboard if new_key_found/if a key is repeatedly pressed 4 times

chkbd           lda     byte_cnt
                cmp     #4
                beq     repeat_key_press
                brset   new_key_found,status,act_kbd
                brclr   save_reqd,status,chkbd
                jsr     store_memory
                bra     chkbd
;; if key is pressed repeatedly 4 times then set byte_cnt to 2 & go to chk_
;; on_off(skip power key sensing)

repeat_key_press lda     #2
                sta     byte_cnt
                lda     kbd_pos
                bra     chk_on_off      ; skip power key sensing

;; clear flag

act_kbd

;; check for key code
;; if not stdby goto chk_on_off
;; else toggle on off bit in status
;; call proc_power
;; goto store_memory
                lda     #max_bass
                sta     max_tone
                lda     kbd_pos
                cmp     #k_on_off
                bne     chk_on_off
                lda     status
                eor     #on_offbyte
                sta     status
                jsr     proc_power
                jsr     store_memory
                jmp     ret_chkbd

;; is unit off - yes goto ret_chkbd

chk_on_off      brset   on_offb,status,cmp_volup
                jmp     ret_chkbd

;; unit on
;; check all keys
;; if not vol up key then goto chk_voldn
;; set volume led
;; if volume >= max_volume
;;      volume = max_volume
;;;; else
;;      volume = volume + 1
;; goto proc_7215

cmp_volup       cmp     #k_volup
                bne     cmp_voldn
                bclr    led_volume,led_port
                lda     #max_volume
                sta     max_tone
                lda     volume
                bsr     comup_vtb
                sta     volume
                bra     com_tone2

;; if volume down key pressed, set volume key on if volume is 0 go to com_tone
;;                                               else decrement volume & go to
;;                                                      com_tone.
cmp_voldn       cmp     #k_voldn
                bne     cmp_trebleup
                bclr    led_volume,led_port

                lda     volume
                bsr     comdn_vtb
                sta     volume
                bra     com_tone2


;; value to be modified in acc
;; maximum value is stored in max_tone
;;
comdn_tb        bset    led_flat,led_port
comdn_vtb       bclr    mute,status
                jsr     chk_set_mute
                tsta
                bne     dec_tone
                rts
dec_tone        deca
                rts

comup_tb        bset    led_flat,led_port
comup_vtb       bclr    mute,status
                jsr     chk_set_mute
                cmp     max_tone
                blo     inc_tone
                lda     max_tone
                rts
inc_tone        inca
                rts

;; if trebleup key pressed set treble led on,if max_treble set treble to max_
;; treble
;; else increment treble
;; go to com_tone

cmp_trebleup    cmp     #k_treup
                bne     cmp_tredn
                bclr    led_treble,led_port
                lda     treble
                bsr     comup_tb
                sta     treble
com_tone2       bra     com_tone1



cmp_tredn       cmp     #k_tredn
                bne     cmp_bassdn
                bclr    led_treble,led_port
                lda     treble
                bsr     comdn_tb
                sta     treble
                bra     com_tone1

cmp_bassdn      cmp     #k_bassdn
                bne     cmp_bassup
                bclr    led_bass,led_port
                lda     bass
                bsr     comdn_tb
                sta     bass
                bra     com_tone1

cmp_bassup      cmp     #k_bassup
                bne     cmp_balr
                bclr    led_bass,led_port
                lda     bass
                bsr     comup_tb
                sta     bass
                bra     com_tone1

;; if balance_r key pressed set balance led on
;; if balance_r is zero then increment balance_l (if less than max_balance)
;; else balance_l = 0 and dec balance_r & go to com_tone

cmp_balr        cmp     #k_balr
                bne     cmp_ball
                lda     balance_r
                tsta
                beq     inc_ball
                clr     balance_l
                dec     balance_r
                bra     com_bal

inc_ball        inc     balance_l
                lda     #max_balance
                cmp     balance_l
                bhs     com_bal
                sta     balance_l
com_bal         bclr    mute,status
                jsr     chk_set_mute
                bset    led_flat,led_port
                bclr    led_balance,led_port
com_tone1       bra     com_tone

;; if balance_l key pressed, set balance led on, if balance_l is 0 then
;;                                                       increment balance_r
;;                                               else set balance_r to 0 &
;;                                               decrement balance_l
;; else go to cmp_flat
;; go to com_tone

cmp_ball        cmp     #k_ball
                bne     cmp_flat
                lda     balance_l
                tsta
                beq     inc_balr
                clr     balance_r
                dec     balance_l
                bra     com_bal

inc_balr        inc     balance_r
                lda     #max_balance
                cmp     balance_r
                bhs     com_bal
                sta     balance_r
                bra     com_bal

;; check flat/mute/bass boost only first time
;; and not in repeat mode
;;
cmp_flat        brclr   new_key_found,status,ret_chkbd
                cmp     #k_flat
                bne     cmp_bassboost
                bclr    led_flat,led_port
                bsr     set_all_def
                bra     com_tone1

;; if bassboost key pressed, toggle the bassboost bit in status & go to
;; chk_set_bb & then to com_tone

cmp_bassboost   cmp     #k_bassboost
                bne     cmp_mute
                lda     status
                eor     #bass_boostbyte
                sta     status
                jsr     chk_set_bb
                bra     com_tone1

;; if mute key pressed toggle the mute bit in status, go to chk_set_mute &
;; then go to com_tone

cmp_mute        cmp     #k_mute
                bne     ret_chkbd
                lda     status
                eor     #mutebyte
                sta     status
                jsr     chk_set_mute
                bra     com_tone1

;; go to proc_7215 & store def_save_to in save_timeout
;; clear new_key_found bit in status & go to chkbd

com_tone        bsr     proc_7215
                lda     #def_save_to
                sta     save_timeout
ret_chkbd       bclr    new_key_found,status
                jmp     chkbd


;; set all parameters at standard value
;; bass/treble at 0 db, balance at 0-0, mute off, loudness off


set_all_def     lda     #def_treble
                sta     treble
                lda     #def_bass
                sta     bass
                bclr    bass_boost,status
                jsr     chk_set_bb
                bclr    mute,status
                jsr     chk_set_mute
                clr     balance_l
                clr     balance_r
                rts
;; if audio not present exit
;; proc_7215
;; gen start
;; 80h
;; if power off then tx max attn for vol/spk l/spk r
;; if mute then copy tx max attn for vol/spk l/spk r
;; else
;; copy volume
;; copy balance_l
;; copy balance_r
;; copy bass after calculation
;; copy treble after calculation
;; copy bass boost byte as per bass boost bit
;; gen stop


proc_7215       brset   noaud_audb,status,ret_7215
                jsr     gen_start
                lda     #80h
                jsr     byte_iic
                bcs     proc_7215

                brclr   on_offb,status,mute_attn
                brset   mute,status,mute_attn

user_attn:      lda     volume
                and     #3fh
                jsr     byte_iic
                bcs     proc_7215

                lda     balance_l
                and     #1fh
                ora     #80h
                jsr     byte_iic
                bcs     proc_7215

                lda     balance_r
                and     #1fh
                ora     #0a0h
                jsr     byte_iic
                bcs     proc_7215
                bra     user_loudness

mute_attn       lda     #max_attn
                jsr     byte_iic
                bcs     proc_7215

                lda     #max_balance
                ora     #80h
                jsr     byte_iic
                bcs     proc_7215

                lda     #max_balance
                ora     #0a0h
                jsr     byte_iic
                bcs     proc_7215


user_loudness   lda     #40h
                brset   bass_boost,status,user_bb
                lda     #44h
user_bb         jsr     byte_iic
                bcs     proc_7215

                lda     bass                    ; if val is < 8 then
                and     #0fh
                cmp     #8                      ; transfer as it is
                blo     user_bass               ; else 0F-(Bass-7)
                lda     #16h                    ; or 16H-Bass
                sub     bass                    ; add 60H as per 7215 data

user_bass       ora     #60h
                jsr     byte_iic
                bcs     proc_7215

                lda     treble
                and     #0fh
                cmp     #8
                blo     user_treble
                lda     #16h
                sub     treble

user_treble     ora     #70h
                jsr     byte_iic
                bcs     proc_7215
                jsr     gen_stop
ret_7215        rts

;; if on_off bit set in status then go to unit_on
;; else store def_initpa to led_port & go to proc_7215

proc_power      brset   on_offb,status,unit_on
unit_off        lda     #def_initpa
                sta     led_port
                jsr     proc_7215
                rts

;; if unit found on then set relay on
;; call chk_set_mute
;; call chk_set_bb
;; call proc_7215
;; go to ret_chkbd

unit_on         bset    relay,relay_port
                bsr     chk_set_mute
                bsr     chk_set_bb
                jsr     proc_7215
                rts

;; if bassboost bit set in status go to bb_act
;; else set bass_boost led off

chk_set_bb      brset   bass_boost,status,bb_act
                bset    led_bassboost,led_port
                rts

;; set bass_boost led on
bb_act          bclr    led_bassboost,led_port
                rts

;; if mute bit set in status then go to mute_act
;; else set mute led off

chk_set_mute    brset   mute,status,mute_act
                bset    led_mute,led_port
                rts

;; set mute led on

mute_act        bclr    led_mute,led_port
                rts

;; if memory not present exit
;; clear save_reqd bit in status
;; e_add=0
;; store status onwards upto max_mem_bytes into memory
;; go to ret_chkbd

store_memory    brset   nomem_memb,status,ret_store
                bclr    save_reqd,status
                clr     e_add
next_sm         ldx     e_add
                lda     status,x
                sta     e_dat
                jsr     set_eeprom_info
                inc     e_add
                lda     e_add
                cmp     #max_mem_bytes
                bne     next_sm
ret_store       rts

;; increment ticks when ticks=1sec(122*8.2ms) set ticks to 0 if save_timeout
;; is 0 go to chk_set_rem_to else decrement save_timeout, if 0 set save_reqd
;; bit in status
;; else go to chk_set_rem_to

tim_int:        lda     #def_timer
                sta     tscr

                inc     ticks
                lda     ticks
                cmp     #122t
                bne     chk_set_rem_to
                clr     ticks
                tst     save_timeout
                beq     chk_set_rem_to
                dec     save_timeout
                tst     save_timeout
                bne     chk_set_rem_to
                bset    save_reqd,status

;;if rem_timeout is 0 then come out of the loop
;;else decrement rem_timeout,if 0, set vol/tre/bass/bal led off
;;                           else  come out of the loop

chk_set_rem_to  tst     rem_timeout
                beq     ret_timint
                dec     rem_timeout
                tst     rem_timeout
                bne     ret_timint
                bset    led_volume,led_port
                bset    led_treble,led_port
                bset    led_bass,led_port
                clr     byte_cnt
                bset    led_balance,led_port
ret_timint
dummy           rti
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop
                nop

                nop
                nop
                nop
                nop
                nop
                nop





                org     7cdh
                jmp     start

                org     7f1
                db      60h

                org     7f8h

                fdb     tim_int
                fdb     hwirq_int
                fdb     dummy
                fdb     start
