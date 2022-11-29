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
.def countdown_indicator_r = r25

; Holds the game state of both players.
.def remote_game_state_r = r23
.def local_game_state_r = r24		; only tracks rock, paper, scissor moves
.equ game_state_ready_bit = 4
.equ game_state_rock_bit = 1
.equ game_state_paper_bit = 2
.equ game_state_scissors_bit = 3

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
.equ button_ready_bit = 7
.equ button_move_bit = 4

; <<< DELETE ME ONCE UART IS READY
.equ button_test1_bit = 5
.equ button_test2_bit = 6
; <<< DELETE ME ONCE UART IS READY

; used to add some latency to debounce buttons
.macro debounce_button
	ldi wait_count_r, 15	;150ms delay
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

	; <<< DELETE ME ONCE TESTING IS COMPLETE
	; set buttons as inputs with pull-up enabled
	in mpr, button_ddrx
	cbr mpr, ((1<<button_test1_bit) | (1<<button_test2_bit))
	out button_ddrx, mpr
	in mpr, button_portx
	sbr mpr, ((1<<button_test1_bit) | (1<<button_test2_bit))
	out button_portx, mpr
	; <<< DELETE ME ONCE TESTING IS COMPLETE

	clr local_game_state_r
	clr remote_game_state_r

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

	rcall wait_state

	rcall start_state

	; show move choices for both players

	; display winner

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
		sbic button_pinx, button_ready_bit
		rjmp welcome_state_await_button_press
	
	pop mpr
	ret

wait_state:
	push mpr

	; copy wait message to lcd buffer
	ldi mpr, 32
	push mpr
	ldi mpr, low(WAIT_STRING)
	push mpr
	ldi mpr, high(WAIT_STRING)
	push mpr
	ldi mpr, low(lcd_buffer_address_start_line_1)
	push mpr
	ldi mpr, high(lcd_buffer_address_start_line_1)
	push mpr
	rcall copy_prog_to_data_16

	; synchronize LCD with its buffer
	rcall LCDWrite

	; block until receive opponenet ready message
	ldi mpr, game_state_ready_bit
	wait_state_await_remote_ready:
		cp remote_game_state_r, mpr
		; TODO: send ready message to remote using UART Transmitt
		; <<< DELETE ME ONCE UART ISR IMPLEMENTED
		sbic button_pinx, button_test1_bit
		; <<< DELETE ME ONCE UART ISR IMPLEMENTED
		brne wait_state_await_remote_ready
	
	pop mpr
	ret

start_state:
	push mpr

	; copy wait message to lcd buffer
	ldi mpr, 32
	push mpr
	ldi mpr, low(START_STRING)
	push mpr
	ldi mpr, high(START_STRING)
	push mpr
	ldi mpr, low(lcd_buffer_address_start_line_1)
	push mpr
	ldi mpr, high(lcd_buffer_address_start_line_1)
	push mpr
	rcall copy_prog_to_data_16

	; synchronize LCD with its buffer
	rcall LCDWrite

	; block until timer expires
	start_state_await_timer_expire:
		; continously poll button. once pressed change move state to next
		sbic button_pinx, button_move_bit
		rjmp start_state_finished_move_change

		debounce_button

		; if game state doesn't have a move set, set it to rock
		andi local_game_state_r, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)
		brne start_state_next_move
		ldi local_game_state_r, (1<<game_state_rock_bit)
		rjmp start_state_finished_move_change

		start_state_next_move:
			sbrc local_game_state_r, game_state_rock_bit
			ldi local_game_state_r, 1<<game_state_paper_bit
			sbrc local_game_state_r, game_state_paper_bit
			ldi local_game_state_r, 1<<game_state_scissors_bit
			sbrc local_game_state_r, game_state_scissors_bit
			ldi local_game_state_r, 1<<game_state_rock_bit
			
		start_state_finished_move_change:
			rcall display_local_move
			; <<< DELETE ME ONCE UART ISR IMPLEMENTED
			sbic button_pinx, button_test2_bit
			; <<< DELETE ME ONCE UART ISR IMPLEMENTED
			rjmp start_state_await_timer_expire
	
	pop mpr
	ret

display_local_move:
	push mpr
	push XL
	push XH

	sbrs local_game_state_r, game_state_rock_bit
	rjmp display_local_move_rock

	sbrs local_game_state_r, game_state_paper_bit
	rjmp display_local_move_paper

	sbrs local_game_state_r, game_state_scissors_bit
	rjmp display_local_move_scissors

	display_local_move_rock:
		ldi XL, low(ROCK_STRING)
		ldi XH, high(ROCK_STRING)
		rjmp display_local_move_display

	display_local_move_paper:
		ldi XL, low(PAPER_STRING)
		ldi XH, high(PAPER_STRING)
		rjmp display_local_move_display

	display_local_move_scissors:
		ldi XL, low(SCISSORS_STRING)
		ldi XH, high(SCISSORS_STRING)
		rjmp display_local_move_display

	display_local_move_display:
		ldi mpr, 16
		push mpr
		mov mpr, XL
		push mpr
		mov mpr, XH
		push mpr
		ldi mpr, low(lcd_buffer_address_start_line_2)
		push mpr
		ldi mpr, high(lcd_buffer_address_start_line_2)
		push mpr
		rcall copy_prog_to_data_16

	rcall LCDWrite

	pop XH
	pop XL
	pop mpr
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
;*	Stored Program Data
;***********************************************************
; LCD buffer size is 15 characters. Ensure strings are the 
; same size to avoid writing garbage characters.
WELCOME_STRING:
.DB "Welcome!        " \
    "Please press PD7"
WAIT_STRING:
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
