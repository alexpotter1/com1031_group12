
;;; Group 12 Coursework
;;; Alex Potter, Alfin Jose, Adrien Royer, Nick Sweeting

;;; just including the standard symbol definitions of all ports:
#define __SFR_OFFSET 0
#include <avr/io.h>

#include "decode.S"
#include "displayCharacterCodes.S"


;;; user code starts from here, as init.S ends with jmp main:

BUTTON = 0		; Button on Arduino pin 8 (PORTB pin 0)

.global main 		; declaring main global, so it can be used in other files

main:
	;;; Runs a function to test all lights in the 7-segment are working 
	call test_display

	;;; Switch on button as input (not pressed = 1, pressed = 0)
	cbi DDRB, BUTTON
	sbi PORTB, BUTTON
	sbi DDRC, 5

	;;; Set output of 7 segment
	ldi r16, DISP_ALL
	out DDRD, r16

	ldi r16, DISP_DOT
	out DDRC, r16

	;;; Initialise timer1 control register
	;;; Also enable input capture, overflow interrupts for timer1
	clr r18
	sts TCCR1A, r18
	ldi r18, _BV(OCIE1A) | _BV(ICIE1)
	sts TIMSK1, r18

	call setup_timer1	;setting the timer reset limit, and resetting

	;;; Enable noise-cancelling and set prescaler properly
	ldi r18, _BV(ICNC1) | _BV(CS12) | _BV(WGM12) | _BV(CS10)
	sts TCCR1B, r18

	; Clear timer1 overflow register, just in case
	clr r22
	clr r27
	clr r28
	clr r29

	; Global Interrupt Enable
	sei

;;; Wait for interrupts
interrupt_loop:
	rjmp interrupt_loop

.global timer1_compa_isr

;;; Timer1 has reached OCR1AH
timer1_compa_isr:

	push r16
	in r16, SREG
	push r16
	push r27
	
	ldi r16, TCCR1B
	tst r29
	sbrs r16, ICES1
	brne checkSequence
	; Otherwise just reset display to ready state
	rcall ready_display

	;;; Cleanup and end timer1_compa_isr
	rjmp endOverflowInterrupt

checkSequence:
;;; Check the amount of presses stored in r29 and branch to appropriate function
	
	cpi r29, 0x01
	breq onePress

	cpi r29, 0x02
	breq twoPress

	cpi r29, 0x03
	breq threePress

	cpi r29, 0x04
	breq fourPress

	cpi r29, 0x05
	breq fivePress
	
; checkSequence falls through to this if nothing matches
.global checkSequenceNotMatched
checkSequenceNotMatched:
	rcall error_display
	rjmp endOverflowInterruptStartNewLetter

.global endOverflowInterruptStartNewLetter
endOverflowInterruptStartNewLetter:

	;;; Reset r28, r29 because we want a new letter now
	
	clr r28
	clr r29

;;; Fall through to this
endOverflowInterrupt:
	pop r27
	pop r16
	out SREG, r16
	pop r16
	
	;;; Set timer overflow register (r22)
	ser r22
	reti

;;; Functions branched to depending on the button press count in a single letter.
;;; Each jumps to a function in decode.S to reduce the amount of code in group12.S.
onePress:
	jmp one_press 
	
twoPress:
	jmp two_press

threePress:
	jmp three_press

fourPress:
	jmp four_press

fivePress:
	jmp five_press
	
.global timer1_cpt_isr
; Handle button input event
timer1_cpt_isr:
	; Save SREG
	push r8
	in r8, SREG
	push r8

	; Save input capture timer to r8
	lds r8, ICR1L
	lds r8, ICR1H

	;; Debounce Button

	push r17

	mov r17, r23
	or r17, r8

	breq debounce

	pop r17

	; Check for rising or falling edge
	push r17
	lds r17, TCCR1B
	; skip next if rising edge (ICES=1 for rising, ICES=0 for falling)
	sbrs r17, ICES1
	; skip pressed if button is released
	rjmp pressed
	sbrc r17, ICES1
	rcall released


	andi r17, ~(_BV(ICES1))

	rjmp invertEdgeDetection

pressed:
;;; occurrs when the button is first depressed (falling edge)
	
	ori r17, _BV(ICES1)	; expects next button change to be rising edge
	rcall reset_timer1
	
invertEdgeDetection:
	sts TCCR1B, r17

end_timer1_cpt_isr:
	pop r17
	pop r8
	out SREG, r8
	pop r8
	reti

debounce:

	pop r17
	pop r8
	out SREG, r8
	pop r8

	reti

released:
;;; occurs when the button is released (rising edge)
	
	push r16
	push r27

	inc r29			; increment the button press counter

	ldi r16, MORSE_SIGNAL_BOUNDARY ; testing whether dot or dash
	cp r8,r16
	brcs short_press		; if dot (short press) jump to short_press
	brcc long_press

long_press:
;;; loads r28 with a dash (0) when button is depressed for more than 200ms
	
	lsl r28

	; display T for now
	; Set pins, reset the timer and return to ISR
	rcall reset_timer1
	rjmp returnFromPressed


short_press:
;;; loads r28 with a dot (1) when button is depressed for less than 200ms
	;; here store that the press was a dot
	lsl r28
	inc r28

	rcall reset_timer1
	rjmp returnFromPressed

returnFromPressed:
	pop r27
	pop r16
	; reset timer overflow, set timer to zero
	clr r22
	; Going back to ISR
	ret

;;; Call this when a morse signal is received, to reset the timeout
setup_timer1:
	push r19

	;;; Set the timer1 high byte to the inter-signal timeout (400ms)
	;;; So load it with 400/16 ~= 25 (in hex)
	ldi r19, 0x19
	sts OCR1AH, r19

	;;; Store zero in timer1 low byte
	clr r19
	sts OCR1AL, r19
	pop r19
	ret

test_display:
;;; Tests the display by turning on all segments
	
	push r21

	ldi r21, ~(DISP_ALL)
	out PORTD, r21
	ldi r21, ~(DISP_DOT)
	out PORTC, r21

	pop r21
	ret
	
error_display:
;;; Occurrs when there is a wrong sequence of dots or dashes, or when there are
;;; too many presses in one letter
	
	; Set top, middle and bottom segment of display to ON (segments A G D)
	cbi PORTD, DISP_A
	cbi PORTD, DISP_G
	cbi PORTD, DISP_D
	ret

ready_display:
;;; readies the display by turning off all segements and showing DP2 to indicate
;;; that the display is still working
	
	push r21

	;;; Inverse logic
	;;; Turn everything off except dot
	ldi r21, DISP_ALL
	out PORTD, r21
	ldi r21, ~(DISP_DOT)
	out PORTC, r21

	pop r21
	ret

reset_timer1:
;;; resets the overflow timer

	push r17

	clr r17			; setting timer back to 0
	sts TCNT1H, r17		; high bit
	sts TCNT1L, r17		; low bit

	pop r17
	ret
