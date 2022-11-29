
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

.def	send = r17					; Signal sent
.def	recieved = r18				; Signal Recieved
.def	TEMP = r19					; Multi-Purpose Register 2
.def    flag = r24

; Use this signal code between two boards for their game ready
.equ    SendReady = 0b11111111
.equ	maxCharacter = 16
.equ	readyButton = 7
.equ	gestureButton = 4
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
		rjmp	RECEIVE				; USART recieve routine
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


	;Other
	sei
;***********************************************************
;*  Main Program
;***********************************************************
MAIN:
	inc mpr
	rcall uart1_transmit

	rjmp MAIN






	;Get Button inputs
	in	mpr, PIND

	andi	mpr, (1<<readyButton)|(1<<gestureButton)
	cpi	mpr, (1<<readyButton)
	brne	Step
	rcall	ReadySig
	rjmp	MAIN

Step:
	cpi	mpr, (1<<gestureButton)
	brne	MAIN
	rcall	Gesture
	rjmp	MAIN

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
;* SubRoutine: ReadySig
;* Description: This routine transmits the ready signal to 
;*				the other board			
;***********************************************************
ReadySig:

	ldi	send, SendReady
	sts	UDR1, send
		
	pop	mpr
	ret 
		
;***********************************************************
;* SubRoutine: Recieve
;* Description: This routine recieves and decodes what the 
;*				other board choose for gesture
;***********************************************************
RECEIVE:
	push	mpr ; Save states

	lds	recieved, UDR1			;Load in message from other board (ready, Input, etc.)

;Check to see if other board is ready
	ldi	mpr, 0b11111111
	and	mpr, recieved
	breq	readyCheck			; If mpr is equal to recieved then it is sent to the readyCheck
	rjmp	CheckInput			; Jump to decode the command

readyCheck:
	cpi	recieved, SendReady 
	breq	setReadyFlag			; If ID matches then set flag to true
	clr	flag				; clear existing flag if incoming ready is not true
	rjmp	RecieveEND

;Set Flag to true if ready signal is sent
setReadyFlag:
	ldi	flag, 0x01			; Load flag with true
	rjmp	CheckInput			; jump to input decoder


;Decode inputs
CheckInput:
	cpi	flag, 0x01			; Check if ready flag is true
	brne	RecieveEND			; Branch to end of recieve routine if flag is not set


	
RecieveEND:
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

