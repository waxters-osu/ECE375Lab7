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
; WARNING: THIS REGISTER IS A GLOBAL VARIABLE ACCESSED IN INTERRUPT
;		   IT CANNOT BE USED IN SUBROUTINES EVEN WITH PUSH/POP
.def countdown_indicator_r = r23

; Holds the game state of both players.
.def remote_game_state_r = r24
.def local_game_state_r = r25
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
.equ countdown_indicator_equal_0 = 0b0000
.equ countdown_indicator_equal_1 = 0b0001
.equ countdown_indicator_equal_2 = 0b0011
.equ countdown_indicator_equal_3 = 0b0111
.equ countdown_indicator_equal_4 = 0b1111

.equ button_ddrx = DDRD
.equ button_portx = PORTD
.equ button_pinx = PIND
.equ button_ready_bit = 7
.equ button_move_bit = 4

.equ lcd_buffer_character_count = 15
.equ lcd_buffer_address_start_line_1 = 0x0100
.equ lcd_buffer_address_start_line_2 = 0x0110
.equ lcd_buffer_address_end_line_2 = 0x011F 

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
; Desc: updates the countdown indicator LEDs to match the 
;		countdown indicator register.
;----------------------------------------------------------------
.macro update_countdown_indicator
	cpi countdown_indicator_r, 4
	breq update_countdown_indicator_4
	cpi countdown_indicator_r, 3
	breq update_countdown_indicator_3
	cpi countdown_indicator_r, 2
	breq update_countdown_indicator_2
	cpi countdown_indicator_r, 1
	breq update_countdown_indicator_1
	cpi countdown_indicator_r, 0
	breq update_countdown_indicator_0

	update_countdown_indicator_4:
		set_countdown_indicator countdown_indicator_equal_4
		rjmp update_countdown_indicator_return
	update_countdown_indicator_3:
		set_countdown_indicator countdown_indicator_equal_3
		rjmp update_countdown_indicator_return
	update_countdown_indicator_2:
		set_countdown_indicator countdown_indicator_equal_2
		rjmp update_countdown_indicator_return
	update_countdown_indicator_1:
		set_countdown_indicator countdown_indicator_equal_1
		rjmp update_countdown_indicator_return
	update_countdown_indicator_0:
		set_countdown_indicator countdown_indicator_equal_0
		rjmp update_countdown_indicator_return

	update_countdown_indicator_return:
		nop
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
;*  Functions
;***********************************************************
;----------------------------------------------------------------
; Desc:  Application entrypoint. Initialize the peripherals and 
;		 applicataion data.
;----------------------------------------------------------------
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

	; Clear Countdown Indicator
	clr countdown_indicator_r

	; Enable Interrupts
	;-----
	sei

;----------------------------------------------------------------
; Desc:  Application main loop. This application is a state 
;		 machine where each state is function that continously
;		 executes until its state transition is met--then it 
;		 returns back to main which will call the next state.
;----------------------------------------------------------------
main:
	; Clear all game state for new game.
	clr local_game_state_r
	clr remote_game_state_r
	transmit_local_game_state

	rcall welcome_state
	transmit_local_game_state

	rcall wait_state
	transmit_local_game_state

	rcall start_state
	transmit_local_game_state
	; BUG-PATCH: This is super gross but transmitting is unreliable. After 
	; 100 transmitts, there is a high probability that the local game
	; state is stored correctly on the other device
	; BETTER SOLUTION: Consider changing the uart transmition/receive to implement
	; a reliable data transfer. Use error checking and an ACK/NACK scheme. Then 
	; refactor state transitions to block until remote has confirmed it correctly 
	; received the transmitted message
	ldi mpr, 100
	temp:
		transmit_local_game_state
		dec mpr
		brne temp

	rcall player_choice_state

	rcall outcome_state

	rjmp main

;----------------------------------------------------------------
; Desc:  The first state of the application displays a welcome
;		 message on the LCD and blocks until the ready button
;		 is pressed.
;
;		 Changes local game state to ready.
;----------------------------------------------------------------
welcome_state:
	push mpr

	; write welcome message to lcd
	const_copy_prog_to_data_16 32, WELCOME_STRING, lcd_buffer_address_start_line_1
	rcall LCDWrite

	; block until button is pressed
	welcome_state_await_button_press:
		sbic button_pinx, button_ready_bit
		rjmp welcome_state_await_button_press
	
	; update local game state
	sbr local_game_state_r, (1<<game_state_ready_bit)

	pop mpr
	ret

;----------------------------------------------------------------
; Desc:  This state displays the waiting message to the LCD and 
;		 blocks until the remote device signals that its ready.
;----------------------------------------------------------------
wait_state:
	; write wait message to lcd
	const_copy_prog_to_data_16 32, WAIT_STRING, lcd_buffer_address_start_line_1
	rcall LCDWrite

	wait_state_await_remote_ready:
		sbrs remote_game_state_r, game_state_ready_bit
		rjmp wait_state_await_remote_ready

	ret

;----------------------------------------------------------------
; Desc:  This state displays the game start message on the first
;		 line of the LCD, and displays the active move choice 
;		 which is "rock", "paper", or "scissors" on the second 
;		 line of the LCD. The state transitions after a 6 second
;		 countdown expires.
;
;		 Changes local game state to indicate move choice. The 
;		 ready state bit is preserved.
;----------------------------------------------------------------
start_state:
	push mpr
	push XL
	push XH

	; write wait message to lcd
	const_copy_prog_to_data_16 32, START_STRING, lcd_buffer_address_start_line_1
	rcall LCDWrite

	; initialize the 6 second timer
	ldi countdown_indicator_r, 4		; countdown_indicator_r * 1.5 seconds
	update_countdown_indicator

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
			display_game_state local_game_state_r, lcd_buffer_address_start_line_2

			cpi countdown_indicator_r, 0
			breq start_state_return

			rjmp start_state_await_timer_expire

	start_state_return:
		pop XH
		pop XL
		pop mpr
		ret

;----------------------------------------------------------------
; Desc:  This state displays the remote player's move on the 
;		 first line of the LCD and the local player's move on the
;		 second line of the LCD. The state transtitions after a 6 
;		 second countdown expires
;----------------------------------------------------------------
player_choice_state:
	; initialize the 6 second timer
	ldi countdown_indicator_r, 4		; countdown_indicator_r * 1.5 seconds
	update_countdown_indicator

	player_choice_state_await_timer_expire:
		; update display with selected values
		display_game_state local_game_state_r, lcd_buffer_address_start_line_2
		display_game_state remote_game_state_r, lcd_buffer_address_start_line_1

		cpi countdown_indicator_r, 0
		breq player_choice_state_return

		rjmp player_choice_state_await_timer_expire

	player_choice_state_return:
		ret

;----------------------------------------------------------------
; Desc:  This state determines and displays the game outcome,
;		 that is win, loose, or tie, on the first line of the
;		 LCD. The state transtitions after a 6 second countdown
;		 expires
;----------------------------------------------------------------
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
		rjmp outcome_state_timer
	outcome_state_win:
		const_copy_prog_to_data_16 16, WIN_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp outcome_state_timer
	outcome_state_loose:
		const_copy_prog_to_data_16 16, LOOSE_STRING, lcd_buffer_address_start_line_1
		rcall LCDWrite
		rjmp outcome_state_timer
	
	outcome_state_timer:
		; initialize the 6 second timer
		ldi countdown_indicator_r, 4		; countdown_indicator_r * 1.5 seconds
		update_countdown_indicator

		outcome_state_await_timer_expire:
			cpi countdown_indicator_r, 0
			breq outcome_state_return

			rjmp outcome_state_await_timer_expire

	outcome_state_return:
		pop r17
		pop mpr
		ret

;----------------------------------------------------------------
; Desc:  Transmits the data stored in mpr over uart1. Blocks
;		 until prior transmit is completed and transmit
;        buffer is empty.
; Param: mpr = data to transmit
;----------------------------------------------------------------
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
; Desc:  The isr for timer1 compare match A. If 
;		 countdown_indicator_r is not 0, decrement it and display
;		 the new value on countdown indicator LEDs. Zero Timer1
;		 before returning.
;----------------------------------------------------------------
timer1_compare_match_A_isr:
	push mpr

	cpi countdown_indicator_r, 0
	breq timer_compare_match_A_isr_return

	dec countdown_indicator_r
	update_countdown_indicator
	
	timer_compare_match_A_isr_return:
		update_countdown_indicator

		; Zero the counter
		ldi mpr, 0
		sts TCNT1H, mpr
		sts	TCNT1L, mpr

		pop mpr
		ret

;-----------------------------------------------------------
; Desc:		Copies an array of n-bytes specified by param #1
;			from program memory specified by param #2 & #3 to
;			data memory specified by param #4 & #5.
; Params:	These parameters should be on the stack the 
;			following order (in order of stack push):
;				1) length of array in bytes
;				2) lower-byte of 16-bit program memory addresss
;				3) upper-byte of 16-bit program memory addresss
;				4) lower-byte of 16-bit data memory addresss
;				5) upper-byte of 16-bit data memory addresss
; NOTE:     Destroys contents of registers X, Y, and Z
;-----------------------------------------------------------
copy_prog_to_data_16:
	; pop return address off stack temporarily to access
	; caller's pushed data
	pop XH
	pop XL

	; point Y at start of lcd buffer (data memory)
	pop YH
	pop YL
	; point Z at start of string (program memory)
	pop ZH
	pop ZL
	; left shift z because least-significant-bit toggles
	; upper/lower byte of program memory--not apart of 
	; program memory address.
	; perform `<< 1` treating Z as 16 continous bits.
	bclr 0		; clear carry-bit so that LSB will be 0 
				; which is pointing at first byte in prog. mem.
	rol ZL
	rol ZH			

	; pop number of bytes off stack
	pop mpr

	; push return address back onto the stack
	push XL
	push XH

	; copy each character from program memory to buffer
	copy_character_to_buffer:
		; 1) move character from program memory to register 0
		;    then point at next character in program memory.
		lpm r0, Z+

		; 2) move character from register 0 to buffer in data
		;	 memory then point at next character in data memory
		st Y+, r0

		dec mpr
		brne copy_character_to_buffer

	ret

;----------------------------------------------------------------
; Desc:		A wait loop that does nothing for approximately 
;			n*10ms where n is determined by the value stored in 
;			waitcnt_r.
;			The general equation for number of clock cycles 
;			consumed by this function is as follows:
;				(((((3*r18)-1+4)*r17)-1+4)*waitcnt)-1+16
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
.include "LCDDriver.asm"
