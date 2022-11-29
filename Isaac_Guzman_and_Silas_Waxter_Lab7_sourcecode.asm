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
.def local_game_state_r = r24
.equ game_state_ready_bit = 4
; NOTE: outcome of game is based on this specific bit order of moves
.equ game_state_rock_bit = 1
.equ game_state_paper_bit = 2
.equ game_state_scissors_bit = 3

; Describe the LEDs used for the countdown indicator. 
.equ countdown_indicator_ddrx = DDRB
.equ countdown_indicator_portx = PORTB
.equ countdown_indicator_lowest_bit = 4
.equ countdown_indicator_mask = 0xF0
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

;----------------------------------------------------------------
; Desc: debounce button wait method
;----------------------------------------------------------------
.macro debounce_button
	ldi wait_count_r, 15	;150ms delay
	rcall wait
.endmacro

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

;----------------------------------------------------------------
; Desc: call copy_prog_to_data_16 with the const parameters. Makes
;		subroutine call denser and easier to read.
; Ex:	`const_copy_prog_to_data_16 32 ROCK_STRING lcd_buffer_address_start_line_1`
; Param:
;		@0 = const. number of bits to copy (corresponds to param #1)
;		@1 = const. first data memory address (corresponds to params #2 & #3)
;		@2 = const. first prog memory address (corresponds to params #4 & #5)
;----------------------------------------------------------------
.macro const_copy_prog_to_data_16
	push mpr

	ldi mpr, @0
	push mpr
	ldi mpr, low(@1)
	push mpr
	ldi mpr, high(@1)
	push mpr
	ldi mpr, low(@2)
	push mpr
	ldi mpr, high(@2)
	push mpr
	rcall copy_prog_to_data_16

	pop mpr
.endmacro
;***********************************************************
;*  Start of Code Segment
;***********************************************************
.cseg

;***********************************************************
;*  Interrupt Vectors
;***********************************************************
.org $0000
	rjmp init
.org $0056						; End of Interrupt Vectors


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

	; <<< DELETE ME ONCE TESTING IS COMPLETE
	ldi remote_game_state_r, (1<<game_state_paper_bit)
	; <<< DELETE ME ONCE TESTING IS COMPLETE

	; Initialize USART1
	;-----

	; Initialize Timer1
	;-----

main:
	set_countdown_indicator countdown_indicator_equal_4

	rcall welcome_state

	rcall wait_state

	rcall start_state

	rcall player_choice_state

	rcall outcome_state

	rcall LCDClr
	rjmp main

; displays welcome message and blocks until button is pressed
welcome_state:
	push mpr

	; copy welcome message to lcd buffer
	const_copy_prog_to_data_16 32, WELCOME_STRING, lcd_buffer_address_start_line_1

	; synchronize LCD with its buffer
	rcall LCDWrite

	welcome_state_await_button_press:
		sbic button_pinx, button_ready_bit
		rjmp welcome_state_await_button_press
	
	ldi local_game_state_r, (1<<game_state_ready_bit)
	pop mpr
	ret

wait_state:
	push mpr

	; copy wait message to lcd buffer
	const_copy_prog_to_data_16 32, WAIT_STRING, lcd_buffer_address_start_line_1

	; synchronize LCD with its buffer
	rcall LCDWrite

	; block until receive opponenet ready message
	wait_state_await_remote_ready:
		cpi remote_game_state_r, game_state_ready_bit
		; TODO: send ready message to remote using UART Transmitt
		; <<< DELETE ME ONCE UART ISR IMPLEMENTED
		sbic button_pinx, button_test1_bit
		; <<< DELETE ME ONCE UART ISR IMPLEMENTED
		brne wait_state_await_remote_ready
	
	pop mpr
	ret

start_state:
	push mpr
	push XL
	push XH

	; copy wait message to lcd buffer
	const_copy_prog_to_data_16 32, START_STRING, lcd_buffer_address_start_line_1

	; synchronize LCD with its buffer
	rcall LCDWrite

	; block until timer expires
	start_state_await_timer_expire:
		; continously poll button. once pressed change move state to next
		in mpr, button_pinx
		sbic button_pinx, button_move_bit
		rjmp start_state_finished_move_change

		debounce_button

		; if game state doesn't have a move set, set it to rock
		mov mpr, local_game_state_r
		andi mpr, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)
		breq start_state_set_rock
		; branch to set next move based on currently set move
		cpi local_game_state_r, 1<<game_state_rock_bit
		breq start_state_set_paper
		cpi local_game_state_r, 1<<game_state_paper_bit
		breq start_state_set_scissors
		cpi local_game_state_r, 1<<game_state_scissors_bit
		breq start_state_set_rock  
			
		start_state_set_rock:
			ldi local_game_state_r, 1<<game_state_rock_bit
			const_copy_prog_to_data_16 16, ROCK_STRING, lcd_buffer_address_start_line_2
			rcall LCDWrite
			rjmp start_state_finished_move_change

		start_state_set_paper:
			ldi local_game_state_r, 1<<game_state_paper_bit
			const_copy_prog_to_data_16 16, PAPER_STRING, lcd_buffer_address_start_line_2
			rcall LCDWrite
			rjmp start_state_finished_move_change

		start_state_set_scissors:
			ldi local_game_state_r, 1<<game_state_scissors_bit
			const_copy_prog_to_data_16 16, SCISSORS_STRING, lcd_buffer_address_start_line_2
			rcall LCDWrite
			rjmp start_state_finished_move_change

		start_state_finished_move_change:
			; TODO: transmit chosen move over UART
			; <<< DELETE ME ONCE TIMER IMPLEMENTED
			sbic button_pinx, button_test2_bit
			; <<< DELETE ME ONCE TIMER IMPLEMENTED
			rjmp start_state_await_timer_expire

	pop XH
	pop XL
	pop mpr
	ret

player_choice_state:
	; conditional display of move based on remote's move choice
	cpi remote_game_state_r, 1<<game_state_rock_bit
	breq player_choice_state_display_remote_rock
	cpi remote_game_state_r, 1<<game_state_paper_bit
	breq player_choice_state_display_remote_paper
	cpi remote_game_state_r, 1<<game_state_scissors_bit
	breq player_choice_state_display_remote_scissors

	;if execution reaches here, remote's move choice does not match move options: ERROR
	const_copy_prog_to_data_16 16, ERROR_NO_MOVE_STRING, lcd_buffer_address_start_line_1
	rcall LCDWrite
	rjmp player_choice_state_await_timer_expire

	player_choice_state_display_remote_rock:
		const_copy_prog_to_data_16 16, ROCK_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp player_choice_state_await_timer_expire
	player_choice_state_display_remote_paper:
		const_copy_prog_to_data_16 16, PAPER_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp player_choice_state_await_timer_expire
	player_choice_state_display_remote_scissors:
		const_copy_prog_to_data_16 16, SCISSORS_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp player_choice_state_await_timer_expire

	player_choice_state_await_timer_expire:
		; <<< DELETE ME ONCE TIMER IMPLEMENTED
		sbic button_pinx, button_test1_bit
		; <<< DELETE ME ONCE TIMER IMPLEMENTED
		rjmp player_choice_state_await_timer_expire

	ret

outcome_state:
	push r16
	push r17

	; Copy the game state to working registers
	mov r16, local_game_state_r
	mov r17, remote_game_state_r

	; Mask out all state except move choices
	andi r16, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)
	andi r17, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)

	; Check for tie
	cp r16, r17
	breq outcome_state_tie

	; Check for win/loose
	; This implementation is dependent on the specific bit pattern
	; defined: Local won if the right shifted bits (with LSB within mask
	; to MSB within mask) of local game state bits is equal to remote.
	ror r16							; since this is a copy of the actual game state, it doesn't
									; matter if the carry bit gets propogated to register's MSB
	brcc outcome_state_tie_clear_msb_mask
	outcome_state_tie_set_msb_mask:
		sbr r16, game_state_scissors_bit
		rjmp outcome_state_win_or_loose
	outcome_state_tie_clear_msb_mask:
		cbr r16, game_state_scissors_bit
		rjmp outcome_state_win_or_loose
	outcome_state_win_or_loose:
		cp r16, r17
		breq outcome_state_win
		brne outcome_state_loose

	outcome_state_tie:
		const_copy_prog_to_data_16 16, TIE_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp outcome_state_await_timer_expire
	outcome_state_win:
		const_copy_prog_to_data_16 16, WIN_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp outcome_state_await_timer_expire
	outcome_state_loose:
		const_copy_prog_to_data_16 16, LOOSE_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp outcome_state_await_timer_expire
	
	outcome_state_await_timer_expire:
		; <<< DELETE ME ONCE TIMER IMPLEMENTED
		sbic button_pinx, button_test2_bit
		; <<< DELETE ME ONCE TIMER IMPLEMENTED
		rjmp outcome_state_await_timer_expire

pop r17
pop r16
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
		ldi wait_outter_loop_r, 224				; load outter loop regisster
		outter_loop:  
			ldi wait_inner_loop_r, 237			; load inner loop register
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
TIE_STRING:
.DB "You tied.       "
WIN_STRING:
.DB "You won!        "
LOOSE_STRING:
.DB "You lost!       "
ERROR_NO_MOVE_STRING:
.DB "ERROR NO MOVE   "

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "lcd_extended.asm"
.include "LCDDriver.asm"
