
;***********************************************************
;*
;*	This is the Recieve and Transmit skeleton file for Lab 7 of ECE 375
;*
;*  	Rock Paper Scissors
;* 	Requirement:
;* 	1. USART1 communication
;* 	2. Timer/counter1 Normal mode to create a 1.5-sec delay
;***********************************************************
;*
;*	 Author: Silas Waxter and Isaac Guzman
;*	   Date: 11/16/2022
;*
;***********************************************************

.include "m32U4def.inc"				; Include definition file

;***********************************************************
;*  Internal Register Definitions and Constants
;***********************************************************
.def    mpr = r16					; Multi-Purpose Register
.def wait_count_r = r17			; wait function parameter
.def wait_inner_loop_r = r18
.def wait_outter_loop_r = r19

.def flag_r = r24

; Describe the LEDs used for the countdown indicator. 
.equ countdown_indicator_ddrx = DDRB
.equ countdown_indicator_portx = PORTB
.equ countdown_indicator_lowest_bit = 4
.equ countdown_indicator_mask = 0xF0
.equ countdown_indicator_equal_1 = 0b0001
.equ countdown_indicator_equal_2 = 0b0011
.equ countdown_indicator_equal_3 = 0b0111
.equ countdown_indicator_equal_4 = 0b1111


; Use this signal code between two boards for their game ready
.equ    ready_signal = 0xFF
.equ	maxCharacter = 16
.equ	readyButton = 7
.equ	gestureButton = 4

;----------------------------------------------------------------
; Desc: set the countdown indicator LEDs to the passed setting.
; Ex:	`set_countdown_indicator countdown_indicator_equal_3`
; Param:
;		@0 = const. countdown indicator bits (non-shifted)
;----------------------------------------------------------------
.macro set_countdown_indicator
	push mpr
	in mpr, countdown_indicator_portx
	andi mpr, ~(countdown_indicator_mask)	; select only-masked bits
	ori mpr, (@0<<countdown_indicator_lowest_bit)
	out countdown_indicator_portx, mpr
	pop mpr
.endmacro

;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg								; Beginning of code segment

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org    $0000						; Beginning of IVs
	    rjmp    INIT            	; Reset interrupt

.org	$003C
		rjmp	uart1_receive_isr
		reti



.org    $0056						; End of Interrupt Vectors

;***********************************************************
;*  Program Initialization
;***********************************************************
INIT:
	;Stack Pointer (VERY IMPORTANT!!!!)
	ldi	mpr, high(RAMEND)
	out	SPH, mpr

	ldi	mpr, low(RAMEND)
	out	SPL, mpr

	;I/O Ports
	; set countdown indicators as output pins
	in mpr, countdown_indicator_ddrx
	sbr mpr, countdown_indicator_mask
	out countdown_indicator_ddrx, mpr

	
	;Port D (TX and RX)
	ldi	mpr, (1<<PD3)
	out	DDRD, mpr
	ldi	mpr, (0<<PD2)
	out	DDRD, mpr
	
	;Port B (LEDS)
	ldi	mpr, 0xFF
	out	DDRB, mpr
	;PORT D (Buttons)
	
	ldi	mpr, (0<<readyButton)|(0<<gestureButton)
	out	DDRD,mpr

	ldi	mpr, (1<<readyButton)|(1<<gestureButton)
	out	PORTD, mpr
	;USART1
	;Set baudrate at 2400bps
	
	ldi	mpr, high(207)
	sts	UBRR1H,mpr

	ldi	mpr, low(207)
	sts	UBRR1L,mpr
	
	;Enable receiver and transmitter
	ldi	mpr, (1<<RXEN1)|(1<<TXEN1)|(1<<RXCIE1)|(0<<UCSZ12)
	sts	UCSR1B, mpr

	;Set frame format: 8 data bits, 2 stop bits
	ldi	mpr, (0<<UMSEL11)|(0<<UMSEL10)|(0<<UPM11)|(0<<UPM10)|(1<<USBS1)|(1<<UCSZ11)|(1<<UCSZ10)|(0<<UCPOL1)
	sts	UCSR1C, mpr


	;TIMER/COUNTER1
	;Set Normal mode
	ldi 	mpr, 0b00000000
	sts	TCCR1A, mpr

	ldi 	mpr, 0b00000100
	sts 	TCCR1A, mpr
		
	ldi 	mpr, high(0xFFFF)
	sts	OCR1AH, mpr

	ldi	mpr, low(0xFFFF)
	sts 	OCR1AL, mpr

	set_countdown_indicator countdown_indicator_equal_1

	;Other
	sei

;***********************************************************
;*  Main Program
;***********************************************************
MAIN:


	; transmit ready signal when ready button is pressed
	ldi mpr, 11
	sbis PIND, readyButton
	rcall uart1_transmit

	rjmp MAIN




;***********************************************************
;*	Functions and Subroutines
;***********************************************************
;***********************************************************
; Desc:  Transmits the data stored in mpr over uart1. Blocks
;		 until prior transmit is completed and transmit
;        buffer is empty.
; Param: mpr = data to transmit
;***********************************************************
uart1_transmit:
	push mpr
	push r17

	; copy the data to transmit
	mov r17, mpr
		
	uart1_transmit_await_empty_transmit_buffer:
		; Wait for empty transmit buffer
		lds mpr, UCSR1A
		andi mpr, 1<<UDRE1
		cpi mpr, 1<<UDRE1
		brne uart1_transmit_await_empty_transmit_buffer
	
	; transmit data
	sts	UDR1, r17

	pop r17
	pop mpr
	ret
		
;***********************************************************
; Desc:  The isr for receive on uart1.
;***********************************************************
uart1_receive_isr:
	push mpr

	lds	mpr, UDR1			;Load in message from other board (ready, Input, etc.)

	cpi mpr, ready_signal
	breq receive_good

	receive_bad:
		set_countdown_indicator countdown_indicator_equal_2
		rjmp recieve_return

	receive_good:
		set_countdown_indicator countdown_indicator_equal_3
		rjmp recieve_return
	
	recieve_return:
		pop	mpr				; restore states
		ret

;----------------------------------------------------------------
; Func:		Wait
; Desc:		A wait loop that does nothing for approximately 
;			n*10ms where n is determined by the value stored in 
;			waitcnt_r.
;			The general equation for number of clock cycles 
;			consumed by this function is as follows:
;				(((((3*r18)-1+4)*r17)-1+4)*waitcnt)-1+16
; Note:		No registers used by function are destroyed.
;----------------------------------------------------------------
wait:
    push wait_count_r
	push wait_inner_loop_r
	push wait_outter_loop_r
loop:  
    ldi wait_outter_loop_r, 224		; load outter loop regisster
outter_loop:  
    ldi wait_inner_loop_r, 237		; load inner loop register
inner_loop:  
    dec    wait_inner_loop_r
    brne   inner_loop				; Continue inner loop
    dec    wait_outter_loop_r
    brne   outter_loop				; Continue outer loop
    dec    wait_count_r
    brne   loop						; Continue wait loop

    pop wait_outter_loop_r
    pop wait_inner_loop_r
    pop wait_count_r
    ret
	
;***********************************************************
;* SubRoutine: Gesture
;* Description: This routine recieves and decodes what the 
;*				other board choose for gesture
;***********************************************************
Gesture:
	ret

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "LCDDriver.asm"			; Include the LCD Driver

