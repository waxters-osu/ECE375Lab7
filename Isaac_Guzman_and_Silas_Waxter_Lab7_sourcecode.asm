;----------------------------------------------------------------
;
; The lab 7 final project. A two-player rock-paper-scissors game
; between two AVR boards which communicate over UART.
;
;	 Author: Silas Waxter and Isaac Guzman
;	   Date: 11/16/2022
;
;----------------------------------------------------------------
;***********************************************************
;*	Internal Register Definitions and Constants
;***********************************************************
.include "m32U4def.inc"

.def mpr = r16

.def wait_count_r = r17
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
; NOTE: outcome of game is based on this specific bit order of moves
.equ game_state_rock_bit = 0
.equ game_state_paper_bit = 1
.equ game_state_scissors_bit = 2
.equ game_state_ready_bit = 3

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

;----------------------------------------------------------------
; Desc: Transmit the local game state to remote player. The purpose 
;		is a label for this repeated behavior that does not need a
;		unique subroutine.
;----------------------------------------------------------------
.macro transmit_local_game_state
	push mpr

	mov mpr, local_game_state_r
	rcall uart1_transmit

	pop mpr
.endmacro

;----------------------------------------------------------------
; Desc: Display the game state on the lcd based based on its setting
; Ex:	`display_game_state local_game_state_r lcd_buffer_address_start_line_1`
; Param:
;		@0 = register containing game state
;		@1 = lcd buffer start address for line
;----------------------------------------------------------------
.macro display_game_state
	sbrc @0, game_state_rock_bit
	rjmp display_game_state_rock

	sbrc @0, game_state_paper_bit
	rjmp display_game_state_paper

	sbrc @0, game_state_scissors_bit
	rjmp display_game_state_scissors

	; if execution reaches this point, invalid game state for move
	const_copy_prog_to_data_16 16, EMPTY_STRING, @1
	rjmp display_game_state_display

	display_game_state_rock:	
		const_copy_prog_to_data_16 16, ROCK_STRING, @1	
		rjmp display_game_state_display

	display_game_state_paper:
		const_copy_prog_to_data_16 16, PAPER_STRING, @1	
		rjmp display_game_state_display

	display_game_state_scissors:
		const_copy_prog_to_data_16 16, SCISSORS_STRING, @1	
		rjmp display_game_state_display

	display_game_state_display:
		rcall LCDWrite
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
.org $0032
	rcall uart1_receive_isr
	reti
.org $0022
	rcall timer1_compare_match_A_isr
	reti
.org $0056			; End of Interrupt Vectors


;***********************************************************
;*  Program Initialization
;***********************************************************
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
	;-----
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

	; Initialize UART1
	;-----
	; Set baudrate
	ldi	mpr, high(207)
	sts	UBRR1H,mpr
	ldi	mpr, low(207)
	sts	UBRR1L,mpr

	; Enable receiver and transmitter
	ldi	mpr, (1<<RXEN1)|(1<<TXEN1)|(1<<RXCIE1)|(0<<UCSZ12)
	sts	UCSR1B, mpr

	; Set frame format: 8 data bits, 2 stop bits
	ldi	mpr, (0<<UMSEL11)|(0<<UMSEL10)|(0<<UPM11)|(0<<UPM10)|(1<<USBS1)|(1<<UCSZ11)|(1<<UCSZ10)|(0<<UCPOL1)
	sts	UCSR1C, mpr

	; Initialize Timer1
	;-----
	;Set Timer1 normal mode
	ldi mpr, 0
	sts	TCCR1A, mpr

	; Set Timer1 prescaler to 1024
	ldi mpr, (1 << CS12)| (1<< CS10)		
	sts TCCR1B, mpr

	; Enable interupt for Compare-Match-A
	ldi	mpr, (1<< OCIE1A)
	sts TIMSK1, mpr
	
	; Initialize Compare-Register-A
	ldi	mpr, high(11718)
	sts	OCR1AH, mpr
	ldi	mpr, low(11718)
	sts	OCR1AL, mpr

	; Zero Timer1
	ldi	mpr, 0
	sts	TCNT1H, mpr
	sts	TCNT1L, mpr

	; Enable Interrupts
	;-----
	sei

main:
	; set default game state for local and remote
	clr local_game_state_r
	clr remote_game_state_r

	rcall welcome_state

	rcall wait_state

	rcall start_state

	rcall player_choice_state

	rcall outcome_state

	rjmp main

; displays welcome message and blocks until button is pressed
welcome_state:
	push mpr

	; write welcome message to lcd
	const_copy_prog_to_data_16 32, WELCOME_STRING, lcd_buffer_address_start_line_1
	rcall LCDWrite

	welcome_state_await_button_press:
		transmit_local_game_state
		sbic button_pinx, button_ready_bit
		rjmp welcome_state_await_button_press
	
	; update local game state
	sbr local_game_state_r, (1<<game_state_ready_bit)
	pop mpr
	ret

wait_state:
	; write wait message to lcd
	const_copy_prog_to_data_16 32, WAIT_STRING, lcd_buffer_address_start_line_1
	rcall LCDWrite

	wait_state_await_remote_ready:
		transmit_local_game_state
		sbrs remote_game_state_r, game_state_ready_bit
		rjmp wait_state_await_remote_ready

	ret

start_state:
	push mpr
	push XL
	push XH

	; write wait message to lcd
	const_copy_prog_to_data_16 32, START_STRING, lcd_buffer_address_start_line_1
	rcall LCDWrite

	start_state_await_timer_expire:
		; on button press, change local game state
		sbic button_pinx, button_move_bit
		rjmp start_state_finished_move_change
		debounce_button

		; goto next move if currently set to rock or paper.
		; when not set or set to scissors, set to rock
		sbrc local_game_state_r, game_state_rock_bit
		rjmp start_state_set_paper

		sbrc local_game_state_r, game_state_paper_bit
		rjmp start_state_set_scissors
			
		start_state_set_rock:
			; clear rock-paper-scissors bits
			cbr local_game_state_r, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)
			; set rock bit
			sbr local_game_state_r, 1<<game_state_rock_bit
			rjmp start_state_finished_move_change

		start_state_set_paper:
			; clear rock-paper-scissors bits
			cbr local_game_state_r, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)
			; set paper bit
			sbr local_game_state_r, 1<<game_state_paper_bit
			rjmp start_state_finished_move_change

		start_state_set_scissors:
			; clear rock-paper-scissors bits
			cbr local_game_state_r, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)
			; set scissors bit
			sbr local_game_state_r, 1<<game_state_scissors_bit
			rjmp start_state_finished_move_change

		start_state_finished_move_change:
			transmit_local_game_state

			display_game_state local_game_state_r, lcd_buffer_address_start_line_2

			; <<< DELETE ME ONCE TIMER IMPLEMENTED
			sbic button_pinx, button_test2_bit
			; <<< DELETE ME ONCE TIMER IMPLEMENTED
			rjmp start_state_await_timer_expire

	; transmit move again after its finaly selected
	transmit_local_game_state

	pop XH
	pop XL
	pop mpr
	ret

player_choice_state:
	player_choice_state_await_timer_expire:
		; ensure that remote has correct game state
		transmit_local_game_state

		; update display with selected values
		display_game_state local_game_state_r, lcd_buffer_address_start_line_2
		display_game_state remote_game_state_r, lcd_buffer_address_start_line_1

		; <<< DELETE ME ONCE TIMER IMPLEMENTED
		sbic button_pinx, button_test1_bit
		; <<< DELETE ME ONCE TIMER IMPLEMENTED
		rjmp player_choice_state_await_timer_expire

	ret

outcome_state:
	push mpr
	push r17

	; Copy the game state to working registers (game state register must not be mpr-r17
	mov mpr, local_game_state_r
	mov r17, remote_game_state_r

	; Mask out all state except move choices
	andi mpr, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)
	andi r17, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)

	; Check for tie
	cp mpr, r17
	breq outcome_state_tie

	; Check for win/loose
	; This implementation is dependent on the specific bit pattern defined:
	; The local player won if the move state bits rolled to the right such that all bits are 
	; shifted one place to the right and LSB of the move state replaces the MSB of the move state.
	; If the local player neither tied nor won, it loss
	;-----
	ror mpr
	brcs outcome_state_set_msb_move_bit
	brcc outcome_state_clear_lsb_move_bit
	outcome_state_set_msb_move_bit:
		sbr mpr, 1<<game_state_scissors_bit
		rjmp outcome_state_determine_win
	outcome_state_clear_lsb_move_bit:
		cbr mpr, 1<<game_state_scissors_bit
		rjmp outcome_state_determine_win

	outcome_state_determine_win:
		; Mask out all state except move choices
		andi mpr, (1<<game_state_rock_bit | 1<<game_state_paper_bit | 1<<game_state_scissors_bit)

		cp mpr, r17
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
pop mpr
ret

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

;----------------------------------------------------------------
; Desc:  The isr for receive on uart1. Updates 
;		 remote_game_state_r with data sent.
;----------------------------------------------------------------
uart1_receive_isr:
	push mpr
	push r17
			
	lds	remote_game_state_r, UDR1

	pop r17
	pop mpr
	ret

;----------------------------------------------------------------
; Desc:  The isr for timer1 compare match A.
;----------------------------------------------------------------
timer1_compare_match_A_isr:
	push mpr

	set_countdown_indicator countdown_indicator_equal_4
	
	; Zero the counter
	ldi mpr, 0
	sts TCNT1H, mpr
	sts	TCNT1L, mpr

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
EMPTY_STRING:
.DB "                "

;***********************************************************
;*	Additional Program Includes
;***********************************************************
.include "lcd_extended.asm"
.include "LCDDriver.asm"
