.data
; static constants
ESCAPE_VALUE		EQU		32.0;
MAX_ITERATIONS		EQU		256;
FRAME_WIDTH			EQU		512;
FRAME_HEIGHT		EQU		512;

; floating point values
align 16
defaultCenterVals	QWORD	-0.765, 0	; packed x, y values
align 16
defaultHalfSizeVals	QWORD	1.235, 1.12	; packed x, y values
align 16
escapeValue			QWORD	ESCAPE_VALUE, ESCAPE_VALUE
align 16
scale				QWORD	1.0
align 16
twoFP				QWORD	2.0
align 16
blueConstFP			QWORD	255.0, 1.5, 3.4		
align 16
xmmStorage			QWORD	32 DUP (?)
align 16
ymmIntermediary		QWORD	4 DUP (?)
; packed integer constants
align 16
maxIterations		QWORD	MAX_ITERATIONS, MAX_ITERATIONS
align 16
iterIncrement		QWORD	1, 1

; local data
align 16
frameDimensions DWORD	FRAME_HEIGHT, FRAME_WIDTH
align 16
packedDataTemp	QWORD	4 DUP (?)
align 16
pixelArray		DWORD	(FRAME_WIDTH*FRAME_HEIGHT) DUP (?)

; external function prototypes
extern malloc: proc
extern free: proc


.code
; ------------------------------------------------
mandelbrot_frame_generator PROC uses rbx
;  Generates the frame of pixel data from a set of 
;  input parameters that determine the center position 
;  and scaleof the mandelbrot frame.
; IN:
; - XMM0 - double - x-position of center
; - XMM1 - double - y-position of center
; - XMM2 - double - scale
; - r9	 - __int32 - max_iterations
; OUT:
; - __int32* - reference to an array of __int32 pixels
; ------------------------------------------------
	; initialize fpu
	finit

	; store xmm registers as per calling convention
	call	store_xmm

	; save MAX_ITERATIONS
	mov		[maxIterations],	r9
	mov		[maxIterations+8],	r9
	; gets log_2(max_iterations)-2 by decrementing, then counting set bits 
	; - assuming max_iterations is apower of 2
	; - used as shift value for bw to ensure there's always a smooth gradient
	dec		r9
	popcnt	rcx,	r9

	; calculate top-left point and width-height
	movapd	xmm8,	defaultCenterVals
	movapd	xmm9,	defaultHalfSizeVals
	movlhps	xmm0,	xmm0
	movlhps xmm1,	xmm1	; copy y value into higher qword of xmm1
	movhlps	xmm1,	xmm0	; move x value into lower qword of xmm1
	movlhps xmm2,	xmm2	; copy scale to upper qword of its register
	mulpd	xmm2,	xmm9	; scale half-size offsets for center
	subpd	xmm8,	xmm2	; offset default center values
	addpd	xmm1,	xmm8	; set top-left position, packed xy, in xmm1
	cvtpi2pd	xmm8,	QWORD PTR frameDimensions		; convert frame dimensions to floats
	divpd	xmm2,	xmm8	; divide complex dims by frame dims to get half-pixel dims
	addpd	xmm1,	xmm2	; offset top-left position by half-pixel to get to center of pixel
	addpd	xmm2,	xmm2	; double to get full pixel dims
	; call pixel array filling function
	mov		rdi,	OFFSET pixelArray
	call mandelbrot_pixel_array

	; load xmm registers as per calling convention
	call	load_xmm

	ret
mandelbrot_frame_generator ENDP 



; ------------------------------------------------
mandelbrot_pixel_array PROC uses rdi
;  Builds the array of pixel data given an augmented
;  set of parameters that prepare this function to 
;  easily iterate over the mandelbrot set within the
;  defined frame.
; IN:
; - rdi  - pointer - reference to pixel array memory to fill
; - XMM1 - double - x & y-position of top left point, packed
; - XMM2 - double - width/height of pixel in complex coords, packed
; OUT:
; - __int32* - reference to the array of __int32 pixels passed in r8
; ------------------------------------------------
	
	; separate packed pixel dimensions
	movapd	xmm3,	xmm2	; copy pixel width to xmm3
	movlhps xmm3,   xmm3
	movapd  xmm4,	xmm2	; copy pixel height to xmm4
	movhlps	xmm4,	xmm4

	; prepare some xmm loads for mandelbrot_value call
	movdqa	xmm2,	OWORD PTR iterIncrement
	movapd	xmm14,	escapeValue
	movdqa	xmm15,	OWORD PTR maxIterations

	; store some repeated computations in fpu
	fld		[blueConstFP]	; 255.0 at ST(+4)
	fld		[blueConstFP+8]	; 1.5 at ST(+3)
	fld		[blueConstFP+16]; 3.4 at ST(+2)
	fld		twoFP			; 2.0 at ST(+1)
	fldln2					; ln(2.0) at ST(+0)

	; cache maxIterations in a register
	mov		rdx,	[maxIterations]

	xor		r10,	r10		; row var, set to 0
	movhlps	xmm6,	xmm1	; copy y0 to xmm6
	movlhps	xmm6,	xmm6
mpa_row_loop:
	xor		r11,	r11		; col var, set to 0
	movlhps	xmm5,	xmm1	; copy x0 to xmm5
	movhlps	xmm5,	xmm5
	addpd	xmm5,	xmm3	; increment x by 1 pixel width
	subsd	xmm5,	xmm3	; revert lower double back to x0
mpa_col_loop:
	call	mandelbrot_value
	
	; black and white color generator
	call	mandelbrot_pixel_color_bw
	mov	[rdi],	rax
	add	rdi,	8
	; blue-white-orange color generator
	; - performed on only 1 pixel at a time
	;call	mandelbrot_pixel_color_blue

	addpd	xmm5,	xmm3	; increment x value of positions
	addpd	xmm5,	xmm3	; increment x value of positions
	add		r11,	2
	cmp		r11,	FRAME_WIDTH
	jl		mpa_col_loop

	addpd	xmm6,	xmm4	; increment y value of positions
	inc		r10
	cmp		r10,	FRAME_HEIGHT
	jl		mpa_row_loop

	mov		rax,	[rsp]
	ret
mandelbrot_pixel_array ENDP



; ------------------------------------------------
mandelbrot_value PROC
;  Caclualtes the mandelbrot value of the coordinate,
;  which is equal to the number of iterations for escape,
;  or 0 if within the mandelbrot set.
; IN:
; - XMM5 - double - x position of 2 points, packed
; - XMM6 - double - y position of 2 points, packed
; - cl - QWORD - log_2(max_iterations) as integer
; OUT:
; - XMM0 - 2 QWORDS that represent number of iterations, packed
; - XMM9 - Squared X values of the 2 pixels
; - XMM10 - Squared Y values of the 2 pixels
; ------------------------------------------------
	movapd	xmm7,	xmm5	; volatile x
	movapd	xmm9,	xmm5	; squared x
	movapd	xmm8,	xmm6	; volatile y
	movapd	xmm10,	xmm6	; squared y
	mulpd	xmm9,	xmm9	; (squaring done here)
	mulpd	xmm10,	xmm10	; (squaring done here)
	pxor	xmm11,	xmm11	; iteration count
mv_loop:
	; x_sqr + y_sqr <= escapeValue
	movapd	xmm12,	xmm9
	addpd	xmm12,	xmm10
	cmppd	xmm12,	xmm14, 10b
	; iter_count < MAX_ITERATIONS
	movapd	xmm13,	xmm15
	pcmpgtq	xmm13,	xmm11
	ptest	xmm12,	xmm13
	jz		mv_loop_end
	; x_temp = x_sqr - y_sqr + x_base
	movapd	xmm13,	xmm9
	subpd	xmm13,	xmm10
	addpd	xmm13,	xmm5
	; y = y*x*2 + y_base
	movapd	xmm0,	xmm8
	mulpd	xmm0,	xmm7
	addpd	xmm0,	xmm0
	addpd	xmm0,	xmm6
	; conditionally adjust xmm8 (volatile y)
	subpd	xmm0,	xmm8
	andpd	xmm0,	xmm12
	addpd	xmm8,	xmm0
	; conditionally adjust xmm7 (volatile x)
	subpd	xmm13,	xmm7
	andpd	xmm13,	xmm12
	addpd	xmm7,	xmm13
	; square x and y
	movapd	xmm9,	xmm7
	mulpd	xmm9,	xmm9
	movapd	xmm10,	xmm8
	mulpd	xmm10,	xmm10
	; iter_count++
	pand	xmm12,	xmm2
	paddq	xmm11,	xmm12
	jmp		mv_loop
mv_loop_end:
	
	movdqa	xmm0,	xmm11
	ret
mandelbrot_value ENDP



; ------------------------------------------------
mandelbrot_pixel_color_bw PROC
;  Determines the color of a pixel given coordinates in
;  the mandelbrot set.
;  Uses black and white based off the integer iteration count
; IN:
; - XMM0 - 2 packed QWORDS that represent number of iterations for each pixel
; - cl - QWORD - log_2(max_iterations) as integer
; OUT:
; - rax - QWORD - color data for both given coordinates
; USES:
; - rbx
; ------------------------------------------------
	mov		ch,		cl
	movd	ebx,	xmm0
	movhlps	xmm0,	xmm0
	movd	eax,	xmm0
	sub		cl,		8
	js		mpcbw_shift_left
mpcbw_shift_right:
	shr		eax,	cl
	shr		ebx,	cl
	jmp		mpcbw_shift_end
mpcbw_shift_left:
	neg		cl
	shl		eax,	cl
	shl		ebx,	cl
mpcbw_shift_end:
	; reduce eax to it's lowest byte
	and		eax,	0ffh
	; put eax in higher dword of rax, and put bl in lowest byte
	shl		rax,	32
	or		al,		bl
	; copy first byte of each packed dword into 2nd and 3rd bytes
	mov		rbx,	rax
	shl		rbx,	8
	or		rax,	rbx
	shl		rbx,	8
	or		rax,	rbx
	mov		rbx,	0ff000000ff000000h
	or		rax,	rbx
	mov		cl,		ch
	ret		
mandelbrot_pixel_color_bw ENDP



; ------------------------------------------------
mandelbrot_pixel_color_blue PROC
;  Determines the color of a pixel given coordinates in
;  the mandelbrot set.
;  Uses a fancy log equation to form a gradient 
;  from blue to white to orange.
; IN:
; - rdx - QWORD - max_iteration count
; - XMM0 - QWORD - iter_count, packed for 2 pixels
; - XMM9 - double - x_sqr, packed for 2 pixels
; - XMM10 - double - y_sqr, packed for 2 pixels
; - rdi  - [DWORD] - destination in memory to use as temporary storage (since it will be cached already)
; OUT:
; - rax - QWORD - color data for both given coordinates
; ------------------------------------------------
	; performed once above - store some repeated computations in fpu
	;fld		[blueConstFP]	; 255.0 at ST(+3)
	;fld		[blueConstFP+8]	; 1.5 at ST(+3)
	;fld		[blueConstFP+16]; 3.4 at ST(+2)
	;fld		twoFP			; 2.0 at ST(+1)
	;fldln2						; ln(2.0) at ST(+0)

	; if iter_count == max_iterations, shortcut and do a black pixel
	movq	rax,	xmm0
	cmp		rax,	rdx
	jge		mpcb_1_black_pixel

	; store some values that will be consumed by mpcbp proc
	mov		[rdi],	rax	; load iter_count into ST(+1)
	fld		QWORD PTR [rdi]
	fwait
	movlpd	QWORD PTR [rdi],	xmm9	; compute ST(+0) = x_sqr + y_sqr
	fld		QWORD PTR [rdi]
	fwait
	movlpd	QWORD PTR [rdi],	xmm10
	fadd	QWORD PTR [rdi]
	call	mandelbrot_pixel_color_blue_pixel
	jmp		mpcb_1_end
mpcb_1_black_pixel:
	mov		QWORD PTR [rdi],	0ff000000h
	add		rdi,	4
mpcb_1_end:
	
	; REPEAT FOR SECOND PIXEL
	; if iter_count == max_iterations, shortcut and do a black pixel
	movhlps	xmm0,	xmm0
	movq	rax,	xmm0
	cmp		rax,	rdx
	jge		mpcb_2_black_pixel

	; store some values that will be consumed by mpcbp proc
	mov		QWORD PTR [rdi],	rax	; load iter_count into ST(+1)
	fld		QWORD PTR [rdi]
	movhlps	xmm9,	xmm9
	fwait
	movlpd	QWORD PTR [rdi],	xmm9	; compute ST(+0) = x_sqr + y_sqr
	fld		QWORD PTR [rdi]
	movhlps	xmm10,	xmm10
	fwait
	movlpd	QWORD PTR [rdi],	xmm10
	fadd	QWORD PTR [rdi]
	call	mandelbrot_pixel_color_blue_pixel
	jmp		mpcb_2_end
mpcb_2_black_pixel:
	mov		QWORD PTR [rdi],	0ff000000h
	add		rdi,	4
mpcb_2_end:

	ret
mandelbrot_pixel_color_blue ENDP

; ------------------------------------------------
mandelbrot_pixel_color_blue_pixel PROC
;  Determines the color of a pixel given coordinates in
;  the mandelbrot set.
;  Uses a fancy log equation to form a gradient 
;  from blue to white to orange.
; IN:
; - rdi  - [DWORD] - destination in memory to use as temporary storage (since it will be cached already)
; OUT:
; - [rdi] - places color data at destination and increments by 4 bytes
; USES:
; - rax, 
; ------------------------------------------------
	; performed once above - store some repeated computations in fpu
	;fld		[blueConstFP]	; 255.0 at ST(+6)
	;fld		[blueConstFP+8]	; 1.5 at ST(+5)
	;fld		[blueConstFP+16]; 3.4 at ST(+4)
	;fld		twoFP			; 2.0 at ST(+3)
	;fldln2						; ln(2.0) at ST(+2)
								; load iter_count into ST(+1)
								; compute ST(+0) = x_sqr + y_sqr

	; calculate interpolated color value v
	; -> v = ln(1.5 + iter_count - log_2(ln(sqrt(x_sqr+y_sqr)))) / 3.4
	fsqrt						; sqrt(x_sqr+y_sqr)
	fld		ST(2)				; - load ln(2) for ln(sqrt(x_sqr+y_sqr))
	fxch						; - swap operands for ln(sqrt(x_sqr+y_sq))
	fyl2x						; ln(sqrt(x_sqr+y_sqr))
	fld1						; - load 1 for log_2(ln(sqrt(x_sqr+y_sqr)))
	fxch						; - swap operands for log_2(ln(sqrt(x_sqr+y_sqr)))
	fyl2x						; log_2(ln(sqrt(x_sqr+y_sqr)))
	fsubp						; iter_count - log_2(ln(sqrt(x_sqr+y_sqr))), pop stack to ST(-1) from function start
	fadd	ST(0),	ST(-1+5)	; 1.5 + iter_count - log_2(ln(sqrt(x_sqr+y_sqr)))
	fld		ST(-1+2)			; - load ln(2) for ln(1.5 + iter_count - log_2(ln(sqrt(x_sqr+y_sqr))))
	fxch						; - swap operands for ln(1.5 + iter_count - log_2(ln(sqrt(x_sqr+y_sqr))))
	fyl2x						; ln(1.5 + iter_count - log_2(ln(sqrt(x_sqr+y_sqr))))
	fdiv	ST(0),	ST(-1+4)	; v = ln(1.5 + iter_count - log_2(ln(sqrt(x_sqr+y_sqr)))) / 3.4

	; determine color
	mov		QWORD PTR [rdi],	0
	fld1		
	fcomip	ST(0),	ST(1)	; 1 <= v, pop 1 off stack
	jle		mpcbp_orange
mpcbp_blue:
	; v = fmaxl(0.0, 2.0 - v)
	fld		QWORD PTR [rdi]	; load 0, stored here earlier in proc
	fxch					; push 0 below v
	fld		ST(0+3)
	fsubrp					; calc 2.0 - v
	ftst					; test ST(0) & 0
	fstsw	ax				; store FPU status in ax
	sahf					; load ax in eflags
	fcmovb	ST(0),	ST(1)	; store 0 at top if 2.0-v < 0
	fxch
	fstp	ST(0)			; pop 0 from stack

mpcbp_blue_nonzero:
	; pixel_array[pa_index+0] = (sf::Uint8)(v*255)
	fld		ST(0)
	fmul	ST(0),	ST(0+6)
	fistp	WORD PTR [rdi]
	; pixel_array[pa_index+1] = (sf::Uint8)(powl(v,1.5)*255)
	fld		ST(0)
	fsqrt
	fmulp
	fld		ST(0)
	fmul	ST(0),	ST(0+6)
	fistp	WORD PTR [rdi+1]
	; pixel_array[pa_index+2] = (sf::Uint8)(powl(v,3)*255)
	fmul	ST(0),	ST(0)
	fmul	ST(0),	ST(-1+6)
	fistp	WORD PTR [rdi+2]
	jmp		mpcbp_end
mpcbp_orange:
mpcbp_end:
	; pixel_array[pa_index+3] = 0xFF;
	fwait
	mov		BYTE PTR [rdi+3],	0ffh
	add		rdi,		4
	ret
mandelbrot_pixel_color_blue_pixel ENDP


;; potentially useful for smooth coloring from array of colors
;;; -> ln_zn = ln(x_sqr + y_sqr) / 2
;;fld		ST(0+2)				; load ln(2.0) ; pre-load for "nu" calc
;;fld		ST(1+2)				; load ln(2.0)
;;fld		ST(2+0)				; load x_sqr + y_sqr
;;fyl2x						; ln(2)*log_2(x_sqr+y_sqr) = ln(s_sqr+y_sqr) at ST(1), pops stack
;;fdiv	ST(0),	ST(2+3)		; ln(s_sqr+y_sqr)/2.0 at ST(0)
;;; -> nu = ln(ln_zn / ln(2)) / ln(2), consumes and overwrites ln_zn
;;fdiv	ST(0),	ST(2+2)		; ln_zn / ln(2)
;;fyl2x						; ln(ln_zn / ln(2)) at ST(1), pops stack, uses extra ln(2.0) stored at start of block
;;fdiv	ST(0),	ST(1+2)		; ln(ln_zn / ln(2)) / ln(2)



; ------------------------------------------------
store_xmm PROC uses rdi
;  Stores the XMM registers in memory
; ------------------------------------------------
	lea		rdi,	xmmStorage
	mov		QWORD PTR [rdi+8],	0fffffffh
	movapd	OWORD PTR [rdi],	xmm0
	add		rdi,	16
	movapd	[rdi],	xmm1
	add		rdi,	16
	movapd	[rdi],	xmm2
	add		rdi,	16
	movapd	[rdi],	xmm3
	add		rdi,	16
	movapd	[rdi],	xmm4
	add		rdi,	16
	movapd	[rdi],	xmm5
	add		rdi,	16
	movapd	[rdi],	xmm6
	add		rdi,	16
	movapd	[rdi],	xmm7
	add		rdi,	16
	movapd	[rdi],	xmm8
	add		rdi,	16
	movapd	[rdi],	xmm9
	add		rdi,	16
	movapd	[rdi],	xmm10
	add		rdi,	16
	movapd	[rdi],	xmm11
	add		rdi,	16
	movapd	[rdi],	xmm12
	add		rdi,	16
	movapd	[rdi],	xmm13
	add		rdi,	16
	movapd	[rdi],	xmm14
	add		rdi,	16
	movapd	[rdi],	xmm15
	ret
store_xmm ENDP

; ------------------------------------------------
load_xmm PROC uses rdi
;  Loads data back into the XMM registers from memory
; ------------------------------------------------
	mov		rdi,	OFFSET xmmStorage
	movapd	xmm0,	[rdi]
	add		rdi,	16
	movapd	xmm1,	[rdi]
	add		rdi,	16
	movapd	xmm2,	[rdi]
	add		rdi,	16
	movapd	xmm3,	[rdi]
	add		rdi,	16
	movapd	xmm4,	[rdi]
	add		rdi,	16
	movapd	xmm5,	[rdi]
	add		rdi,	16
	movapd	xmm6,	[rdi]
	add		rdi,	16
	movapd	xmm7,	[rdi]
	add		rdi,	16
	movapd	xmm8,	[rdi]
	add		rdi,	16
	movapd	xmm9,	[rdi]
	add		rdi,	16
	movapd	xmm10,	[rdi]
	add		rdi,	16
	movapd	xmm11,	[rdi]
	add		rdi,	16
	movapd	xmm12,	[rdi]
	add		rdi,	16
	movapd	xmm13,	[rdi]
	add		rdi,	16
	movapd	xmm14,	[rdi]
	add		rdi,	16
	movapd	xmm15,	[rdi]
	ret
load_xmm ENDP
end