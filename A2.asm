; N76E003 ADC test program: Reads channel 7 on P1.1, pin 14(Cold Junction)
; Reads channel 1 on P3.0, Pin3.0(hot junction)

$NOLIST
$MODN76E003
$LIST

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))
TIMER2_RATE       EQU 100      ; 100Hz or 10ms
TIMER2_RELOAD     EQU (65536-(CLK/(16*TIMER2_RATE))) ; Need to change timer 2 input divide to 16 in T2MOD

; Output
PWM_OUT    EQU P1.0 ; Logic 1=oven on

BSEG
s_flag: dbit 1 ; set to 1 every time a second has passed

mf: dbit 1 ; £¿£¿£¿
beep: dbit 1

; These five bit variables store the value of the pushbuttons after calling 'LCD_PB' below
PB0: dbit 1
PB1: dbit 1
PB2: dbit 1
PB3: dbit 1
PB4: dbit 1


DSEG at 0x30
pwm_counter:  ds 1 ; Free running counter 0, 1, 2, ..., 100, 0
pwm:          ds 1 ; pwm percentage
seconds:      ds 1 ; a seconds counter attached to Timer 2 ISR
sec:          ds 1
FSM1_state:   ds 1

temp: ds 1

temp_soak: ds 2

time_soak: ds 2

temp_refl: ds 2

time_refl: ds 2

temp_cool: ds 1

safetemp: ds 1

; These register definitions needed by 'math32.inc'
x:   ds 4
y:   ds 4
bcd: ds 5


cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
;LCD_RW equ PX.X ; Not used in this code, connect the pin to GND
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3


; Reset vector
org 0x0000
    ljmp main

; External interrupt 0 vector (not used in this code)
org 0x0003
	reti

; Timer/Counter 0 overflow interrupt vector (not used in this code)
org 0x000B
	reti

; External interrupt 1 vector (not used in this code)
org 0x0013
	reti

; Timer/Counter 1 overflow interrupt vector (not used in this code)
org 0x001B
	reti

; Serial port receive/transmit interrupt vector (not used in this code)
org 0x0023 
	reti
	
; Timer/Counter 2 overflow interrupt vector
org 0x002B
	ljmp Timer2_ISR


$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$include(math32.inc);A library of mathematic calculation of variables
$LIST


Left_blank mac
	mov a, %0
	anl a, #0xf0
	swap a
	jz Left_blank_%M_a
	ljmp %1
Left_blank_%M_a:
	Display_char(#' ')
	mov a, %0
	anl a, #0x0f
	jz Left_blank_%M_b
	ljmp %1
Left_blank_%M_b:
	Display_char(#' ')
endmac

Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1
	
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer
	
	; Initialize timer 2 for periodic interrupts
	mov T2CON, #0 ; Stop timer/counter.  Autoreload mode.
	mov TH2, #high(TIMER2_RELOAD)
	mov TL2, #low(TIMER2_RELOAD)
	; Set the reload value
	mov T2MOD, #0b1010_0000 ; Enable timer 2 autoreload, and clock divider is 16
	mov RCMP2H, #high(TIMER2_RELOAD)
	mov RCMP2L, #low(TIMER2_RELOAD)
	; Init the free running 10 ms counter to zero
	mov pwm_counter, #0
	; Enable the timer and interrupts
	orl EIE, #0x80 ; Enable timer 2 interrupt ET2=1
    setb TR2  ; Enable timer 2

	
	
	; Initialize the pin used by the ADC (P1.1) as input.
	orl	P1M1, #0b00000010
	anl	P1M2, #0b11111101
	
	; Initialize and start the ADC:
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x01 ; Select channel 7
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b00000001 ; P1.1 is analog input/Activate AIN0 and AIN7 channel inputs
	orl ADCCON1, #0x01 ; Enable ADC
	
	setb EA ; Enable global interrupts
	ret


;---------------------------------;
; ISR for timer 2                 ;
;---------------------------------;
Timer2_ISR:
	clr TF2  ; Timer 2 doesn't clear TF2 automatically. Do it in the ISR.  It is bit addressable.
	push psw
	push acc
	
	inc pwm_counter
	clr c
	mov a, pwm
	subb a, pwm_counter ; If pwm_counter <= pwm then c=1
	cpl c
	mov PWM_OUT, c
	
	mov a, pwm_counter
	cjne a, #100, exit_a
	sjmp exit1_b
	
exit_a:
    ljmp Timer2_ISR_done
exit1_b:
    mov pwm_counter, #0
    
	inc sec ; It is super easy to keep a seconds count here
    clr a
    mov a,seconds
    add a,#1
    da a
    mov seconds, a
    clr a
	setb s_flag	
	
Timer2_ISR_done:
	pop acc
	pop psw
	reti
	
wait_1ms:
	clr	TR0 ; Stop timer 0
	clr	TF0 ; Clear overflow flag
	mov	TH0, #high(TIMER0_RELOAD_1MS)
	mov	TL0,#low(TIMER0_RELOAD_1MS)
	setb TR0
	jnb	TF0, $ ; Wait for overflow
	ret

; Wait the number of miliseconds in R2
waitms:
	lcall wait_1ms
	djnz R2, waitms
	ret

; function for pushbutton
LCD_PB:
	; Set variables to 1: 'no push button pressed'
	setb PB0
	setb PB1
	setb PB2
	setb PB3
	setb PB4
	; The input pin used to check set to '1'
	setb P1.5
	
	; Check if any push button is pressed
	clr P0.0
	clr P0.1
	clr P0.2
	clr P0.3
	clr P1.3
	jb P1.5, LCD_PB_Done

	; Debounce
	mov R2, #50
	lcall waitms
	jb P1.5, LCD_PB_Done

	; Set the LCD data pins to logic 1
	setb P0.0
	setb P0.1
	setb P0.2
	setb P0.3
	setb P1.3
	
	; Check the push buttons one by one
	clr P1.3
	mov c, P1.5
	mov PB4, c
	setb P1.3

	clr P0.0
	mov c, P1.5
	mov PB3, c
	setb P0.0
	
	clr P0.1
	mov c, P1.5
	mov PB2, c
	setb P0.1
	
	clr P0.2
	mov c, P1.5
	mov PB1, c
	setb P0.2
	
	clr P0.3
	mov c, P1.5
	mov PB0, c
	setb P0.3

LCD_PB_Done:		
	ret
	

	
;---------------------------------;
; Send a BCD number to PuTTY????? ;
;---------------------------------;
Send_BCD mac
push ar0
mov r0, %0
lcall ?Send_BCD
pop ar0
endmac
?Send_BCD:
push acc
; Write most significant digit
mov a, r0
swap a
anl a, #0fh
orl a, #30h
lcall putchar
; write least significant digit
mov a, r0
anl a, #0fh
orl a, #30h
lcall putchar
pop acc
ret

	
; We can display a number any way we want.  In this case with
; four decimal places.
Display_formated_BCD:
	Set_Cursor(1, 4)
    Display_BCD(bcd+3)
	Display_BCD(bcd+2)
	; Replace all the zeros to the left with blanks
	Set_Cursor(1, 4)

	Left_blank(bcd+3, skip_blank)
	Left_blank(bcd+2, skip_blank)
	Left_blank(bcd+1, skip_blank)
	Left_blank(bcd+0, skip_blank)
	mov a, bcd+0
	anl a, #0f0h
	swap a
	jnz skip_blank
	Display_char(#' ')
skip_blank:
	ret
	

putchar:
    jnb TI, putchar
    clr TI
    mov SBUF, a
    ret

Read_temp:    
    ;receive temperature data
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, ADCRL
    mov R0, A
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	mov x+2, #0
	mov x+3, #0
	Load_y(50300) ; VCC voltage measured
	lcall mul32
	Load_y(4095) ; 2^12-1
	lcall div32
	
	Load_y(100000) ; 
	lcall mul32
	
	Load_y(1353) ; 
	lcall div32
	
	Load_y(230000) ; 
	lcall add32	
    
    lcall wait_1ms 
 
	mov temp,x+0
	
	; Convert to BCD and display
	lcall hex2bcd
	lcall Display_formated_BCD
	;Send value to putty
	Send_BCD(bcd+3)
	Send_BCD(bcd+2)
	
	mov a, #'\r'
	lcall putchar
	   
	mov a, #'\n'
	lcall putchar
	; Wait 500 ms between conversions
	mov R2, #250
	lcall waitms
	mov R2, #250
	lcall waitms
	ret
	    
;                     1234567890123456    <- This helps determine the location of the counter
soak_time_msg:    db 'St:****', 0
soak_temp_msg:    db 'ST:****', 0
      
reflow_time_msg:  db          'Rt:****', 0
reflow_temp_msg:  db          'RT:****', 0

start_msg:        db 'STARTING...', 0
clear:            db '                ', 0
fsm_message:      db 'FSM', 0

test_message:     db 'To=    C  ', 0
value_message:    db '', 0
blank:            db '                ', 0    
state0:           db 'set up',0
state1:           db 'State1',0
state2:           db 'State2',0
state3:           db 'State3',0
state4:           db 'State4',0
state5:           db 'State5',0
safety_measure:	  db 'safety',0
complete:         db 'Reflow Complete', 0

main:
	
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
    
    
    ; initial messages in LCD
	Set_Cursor(1,1)
    Send_Constant_String(#soak_temp_msg)
    Set_Cursor(2,1)
    Send_Constant_String(#soak_time_msg)
	Set_Cursor(1,10)
    Send_Constant_String(#reflow_temp_msg)
    Set_cursor(2,10)
    Send_Constant_String(#reflow_time_msg)
	
	clr beep
	
	mov FSM1_state,#0
	;mov pwm_counter,#0x00 ; Free running counter 0, 1, 2, ..., 100, 0
    mov pwm, #0        ; pwm percentage
    mov seconds, #0x00    ; a seconds counter attached to Timer 2 ISR
    ;mov sec,#0x00
    
    mov temp,#0x00
    
    mov temp_cool,#0x00
    mov a,temp_cool
    add a,#0x60
    da a
    mov temp_cool,a
    
	mov safetemp, #0x0
	mov a, safetemp
	add a, #0x50
	da a
	mov safetemp, a
    
    
    mov temp_soak+0,#0x00
    mov temp_soak+1,#0x00
    mov time_soak+0,#0x00
    mov time_soak+1,#0x00
    mov temp_refl+0,#0x00
    mov temp_refl+1,#0x00
    mov time_refl+0,#0x00
    mov time_refl+1,#0x00
      
loop1:
    lcall LCD_PB
	jb PB4, loop2  
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb PB4, loop2
	
	clr a
	mov a, temp_soak+0
    add a, #1
    da a
    mov temp_soak+0,a
    cjne a, #0x99,exit1
    mov temp_soak+0, #0
    clr a
    mov a,temp_soak+1
    add a,#1
    da a
    mov temp_soak+1,a
    cjne a, #0x99,exit1
    mov temp_soak+1, #0
    sjmp loop2
exit1: 
    nop
     
loop2:
    lcall LCD_PB
	jb PB3, loop3  
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb PB3, loop3
	
	clr a
	mov a, time_soak+0
    add a, #1
    da a
    mov time_soak+0,a
    cjne a, #0x99, exit2
    mov time_soak+0, #0
    clr a
    mov a,time_soak+1
    add a,#1
    da a
    mov time_soak+1,a
    cjne a, #0x99,exit2
    mov time_soak+1, #0
    sjmp loop3	
exit2: 
    nop	

loop3:
    lcall LCD_PB
	jb PB2, loop4  
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb PB2, loop4
	
	clr a
	mov a, temp_refl+0
    add a, #1
    da a
    mov temp_refl+0,a
    cjne a, #0x99, exit3
    mov temp_refl+0, #0
    clr a
    mov a,temp_refl+1
    add a,#1
    da a
    mov temp_refl+1,a
    cjne a, #0x99,exit3
    mov temp_refl+1, #0
    sjmp loop4	
exit3: 
    nop	

loop4:
    lcall LCD_PB
	jb PB1, loop5 
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb PB1, loop5
	
	clr a
	mov a, time_refl+0
    add a, #1
    da a
    mov time_refl+0,a
    cjne a, #0x99, exit4
    mov time_refl+0, #0x00
    clr a
    mov a,time_refl+1
    add a,#0x01
    da a
    mov time_refl+1,a
    cjne a, #0x99,exit4
    mov time_refl+1, #0
    sjmp loop5	
exit4: 
    nop	
    
loop5:
    lcall LCD_PB
	
	jb PB0, loop_b ; if the 'CLEAR' button is not pressed skip
	Wait_Milli_Seconds(#50)	; Debounce delay.  This macro is also in 'LCD_4bit.inc'
	jb PB0, loop_b ; if the 'CLEAR' button is not pressed skip
	ljmp fsm_start 
      
loop_b:
           
    Set_Cursor(1,4)
    Display_BCD(temp_soak+1)
    Set_Cursor(1,6)
    Display_BCD(temp_soak+0)
    Set_Cursor(2,4)
    Display_BCD(time_soak+1)
	Set_Cursor(2,6)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(time_soak+0) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(1,13)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(temp_refl+1) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(1,15)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(temp_refl+0) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2,13)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(time_refl+1) ; This macro is also in 'LCD_4bit.inc'
	Set_Cursor(2,15)     ; the place in the LCD where we want the BCD counter value
	Display_BCD(time_refl+0) ; This macro is also in 'LCD_4bit.inc'
	ljmp loop1
	
fsm_start:
	
	mov pwm, #0
	Set_Cursor(1, 1)
	Send_Constant_String(#clear)
	Set_Cursor(2, 1)
	Send_Constant_String(#clear)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)

	Set_Cursor(2, 1)
	Send_Constant_String(#start_msg)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	
	; initial messages in LCD
	Set_Cursor(2, 1)
	Send_Constant_String(#clear)
	Wait_Milli_Seconds(#250)
	Wait_Milli_Seconds(#250)
	Set_Cursor(1, 1)
    Send_Constant_String(#test_message)
	Set_Cursor(2, 1)
    Send_Constant_String(#value_message)
    mov seconds, #0x00
	sjmp Forever
				

    
Forever:
    Set_Cursor(2,10)
	Display_BCD(seconds)
	lcall Read_temp
	sjmp FSM1
	
FSM1:
    mov a, FSM1_state
	    
FSM1_state0:
    cjne a, #0, FSM1_safety 
    Set_Cursor(2, 1)
    Send_Constant_String(#state0)
    mov pwm, #0
    mov seconds, #0
    lcall LCD_PB
    mov R2, #50
	lcall waitms
    jb PB0, FSM1_state0_done
    mov FSM1_state, #6
   
FSM1_state0_done:
    ljmp FSM2
    
FSM1_safety:
	cjne a, #6, FSM1_state1	
    mov pwm, #100
    ;mov seconds, #0
	Set_Cursor(2,1)
	Send_Constant_String(#safety_measure)
		

	;lcall soak_time_check ;check to see if the maximum time for soaking has been reached
	;jb abort, FSM1_state1 ;abort if abort bit set to 1

	mov a, temp_cool
	clr c
	subb a, seconds ;check if time has been exceeded threshold
	jnc jump_temp
	
	mov a, safetemp
	clr c
	subb a, bcd+2
	jnc jump_state
	mov FSM1_state, #1
	ljmp safety_done

jump_state:
	mov FSM1_state, #0
	ljmp safety_done
jump_temp:
	mov a, safetemp
	clr c
	subb a, bcd+2
	jnc safety_done
	mov FSM1_state, #1
	ljmp safety_done

safety_done:
	ljmp FSM2
    
FSM1_state1:
    cjne a, #1, FSM1_state2
    Set_Cursor(2, 1)
    Send_Constant_String(#state1)
    mov pwm, #100
    mov seconds, #0
    mov sec, #0
    clr a
    clr c
    mov a,temp_soak+1
    mov R0,bcd+3
    subb a,R0
    jnc FSM1_state1_done   
    clr a
    mov a, temp_soak+0
    mov R0,bcd+2
    clr c
    subb a, R0   
    jnc FSM1_state1_done
    mov FSM1_state, #2
FSM1_state1_done:
    ljmp FSM2 
    
FSM1_state2:
    cjne a, #2, FSM1_state3
    Set_Cursor(2, 1)
    Send_Constant_String(#state2)
    mov pwm, #20
    mov a, time_soak+0
    clr c
    subb a, seconds
    jnc FSM1_state2_done
    mov FSM1_state, #3
FSM1_state2_done:
    ljmp FSM2
    
FSM1_state3:
    
    cjne a, #3, FSM1_state4
    Set_Cursor(2, 1)
    Send_Constant_String(#state3)
    mov pwm, #100
    mov seconds, #0
    mov sec, #0
    clr a
    clr c
    mov a,temp_refl+1
    mov R0,bcd+3
    subb a,R0
    jnc FSM1_state3_done   
    clr a
    mov a, temp_refl+0
    mov R0,bcd+2
    clr c
    subb a, R0 
    jnc FSM1_state3_done  
    mov FSM1_state,#4 
FSM1_state3_done:
    ljmp FSM2     
    
FSM1_state4:
    cjne a, #4, FSM1_state5
    Set_Cursor(2, 1)
    Send_Constant_String(#state4)
    mov pwm, #20
    mov a,time_refl+0
    clr c
    subb a,seconds
    jnc FSM1_state4_done
    mov FSM1_state,#5
FSM1_state4_done:
    ljmp FSM2

FSM1_state5:
    cjne a, #5, FSM1_state5
    Set_Cursor(2, 1)
    Send_Constant_String(#state5)
    mov pwm, #0
    
    clr a
    mov a,bcd+3
    cjne a,#0,FSM1_state5_done
      
    clr a
    mov a, temp_cool
    mov R0,bcd+2
    clr c
    subb a, R0 
    jc FSM1_state5_done
    mov FSM1_state,#0
    mov seconds,#0
    mov sec, #0
;    mov temp,#0
    mov pwm,#0
FSM1_state5_done:
    ljmp FSM2
    

FSM2:
    
	lcall LCD_PB
	jb PB1, FSM1_state_done
    mov seconds,#0
    mov sec,#0
    mov pwm,#0
    mov FSM1_state, #0
    
FSM1_state_done:    	
	ljmp Forever
	
END	
	
	


	