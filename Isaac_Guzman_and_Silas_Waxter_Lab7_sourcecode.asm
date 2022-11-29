;
; Lab7.asm
;
; Created: 11/16/2022 2:24:24 PM
; Author : Isaac Guzman & Silas Waxter
;
;***********************************************************
;*	Internal Register Definitions and Constants
;***********************************************************
.def mpr = r16
.def wait_count_r = r17			; wait function parameter
.def wait_inner_loop_r = r18
.def wait_outter_loop_r = r19

; Holds a value between 0 and 4
; Holds the current countdown indicator. After changing this 
; value, the time remaining in the countdown is equal to 
; approximately 1.5*countdown_indicator_r seconds.
.def countdown_indicator_r = r24

; Describe the LEDs used for the countdown indicator. 
.equ countdown_indicator_ddrx = DDRB
.equ countdown_indicator_portx = PORTB
.equ countdown_indicator_mask = 0b1111
.equ countdown_indicator_equal_1 = 0b0001
.equ countdown_indicator_equal_2 = 0b0011
.equ countdown_indicator_equal_3 = 0b0111
.equ countdown_indicator_equal_4 = 0b1111

.equ button_ddrx = DDRD
.equ button_portx = PORTD
.equ button_pinx = PIND
.equ button_ready_bit = 4
.equ button_move_bit = 7

; used to add some latency to debounce buttons
.macro debounce_button
	ldi wait_count_r, 40
	rcall wait
.endmacro

init:
	; Initialize the stack pointer.
	;-----
	ldi mpr, high(RAMEND)
	out sph, mpr
	ldi mpr, low(RAMEND)
	out spl, mpr

	;--------------------------------------------------------
	; NOTE: You should do read -> manipulate -> write for 
	;       the I/O registers. This allows the order of 
	;       initialization to not matter and decouples the
	;       code. It may ease debugging.
	;--------------------------------------------------------
	; Initialize LCD Display
	rcall LCDInit
	rcall LCDBacklightOn
	rcall LCDClr

	; Initialize I/0 Pins
	;-----
	; set countdown indicators as output pins
	in mpr, countdown_indicator_ddrx
	sbr mpr, countdown_indicator_mask
	out countdown_indicator_ddrx, mpr

	; set buttons as inputs with pull-up enabled
	in mpr, button_ddrx
	cbr mpr, ((1<<button_ready_bit) | (1<<button_move_bit))
	out button_ddrx, mpr
	in mpr, button_portx
	sbr mpr, ((1<<button_ready_bit) | (1<<button_move_bit))
	out button_portx, mpr


	; Initialize USART1
	;-----

	; Initialize Timer1
	;-----

main:
	in mpr, countdown_indicator_portx
	andi mpr, ~(countdown_indicator_mask)	; clear masked bits
	ori mpr, countdown_indicator_equal_4
	out countdown_indicator_portx, mpr

	rcall welcome_state

	rcall LCDClr
	temp:
	rjmp temp

; displays welcome message and blocks until button is pressed
welcome_state:
	push mpr

	; copy welcome message to lcd buffer
	ldi mpr, 32
	push mpr
	ldi mpr, low(WELCOME_STRING)
	push mpr
	ldi mpr, high(WELCOME_STRING)
	push mpr
	ldi mpr, low(lcd_buffer_address_start_line_1)
	push mpr
	ldi mpr, high(lcd_buffer_address_start_line_1)
	push mpr
	rcall copy_prog_to_data_16

	; synchronize LCD with its buffer
	rcall LCDWrite

	welcome_state_await_button_press:
		sbic button_pinx, button_move_bit
		rjmp welcome_state_await_button_press
	
	pop mpr
	ret

;***********************************************************
;*	Stored Program Data
;***********************************************************
; LCD buffer size is 15 characters. Ensure strings are the 
; same size to avoid writing garbage characters.
WELCOME_STRING:
.DB "Welcome!        " \
    "Please press PD7"
WAITING_STRING:
.DB "Ready. Waiting  " \
    "for the opponent"
START_STRING:
.DB "Game start      " \
    "                "
ROCK_STRING:
.DB "Rock            "
PAPER_STRING:
.DB "Paper           "
SCISSORS_STRING:
.DB "Scissors        "
WIN_STRING:
.DB "You won!        "
LOOSE_STRING:
.DB "You lost!       "

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "lcd_extended.asm"
.include "LCDDriver.asm"
