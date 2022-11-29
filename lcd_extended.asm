; This file declares extended functionality for the LCD Driver.
.equ	lcd_buffer_character_count = 15
.equ	lcd_buffer_address_start_line_1 = 0x0100
.equ	lcd_buffer_address_start_line_2 = 0x0110
.equ	lcd_buffer_address_end_line_2 = 0x011F 

;-----------------------------------------------------------
; Params:	These parameters should be on the stack the 
;			following order (in order of stack push):
;				1) length of array in bytes
;				2) lower-byte of 16-bit program memory addresss
;				3) upper-byte of 16-bit program memory addresss
;				4) lower-byte of 16-bit data memory addresss
;				5) upper-byte of 16-bit data memory addresss
; Desc:		Copies an array of n-bytes specified by param #1
;			from program memory specified by param #2 & #3 to
;			data memory specified by param #4 & #5.
; NOTE:     Destroys contents of registers X, Y, and Z
;-----------------------------------------------------------
copy_prog_to_data_16:
	; pop return address off stack temporarily to access
	; caller pushed data
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
	bclr 0		; clear the carry flag in status register
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