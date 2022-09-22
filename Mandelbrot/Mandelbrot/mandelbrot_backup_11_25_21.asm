.data
; static constants
ESCAPE_VALUE		EQU		32.0;
MAX_ITERATIONS		EQU		63;
FRAME_WIDTH			EQU		512;
FRAME_HEIGHT		EQU		512;

; floating point values
align 16
defaultCenterVals	QWORD	-0.765, 0	; packed x, y values
defaultHalfSizeVals	QWORD	1.235, 1.12	; packed x, y values
escapeValue			QWORD	ESCAPE_VALUE, ESCAPE_VALUE
; packed integer constants
maxIterations		QWORD	MAX_ITERATIONS, MAX_ITERATIONS
iterIncrement		QWORD	1, 1

; local data
frameDimensions DWORD	FRAME_HEIGHT, FRAME_WIDTH
packedDataTemp	QWORD	4 DUP (?)
pixelArray		DWORD	(FRAME_WIDTH*FRAME_HEIGHT) DUP (?)

; external function prototypes
extern malloc: proc
extern free: proc


.code
; ------------------------------------------------
mandelbrot_frame_generator PROC 
;  Generates the frame of pixel data from a set of 
;  input parameters that determine the center position 
;  and scaleof the mandelbrot frame.
; IN:
; - XMM0 - double - x-position of center
; - XMM1 - double - y-position of center
; - XMM2 - double - scale factor
; OUT:
; - __int32* - reference to an array of __int32 pixels
; ------------------------------------------------
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

	; debug
	call mandelbrot_pixel_array

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

	xor		r10,	r10		; row var, set to 0
	movapd	xmm6,	xmm1	; copy y0 to xmm6
	movhlps	xmm6,	xmm6
	addsd	xmm6,	xmm4	; offset lower double by 1 pixel height
mpa_row_loop:
	xor		r11,	r11		; col var, set to 0
	movapd	xmm5,	xmm1	; copy x0 to xmm5
	movlhps	xmm5,	xmm5
	addsd	xmm5,	xmm3	; offset lower double by 1 pixel width
mpa_col_loop:
	call	mandelbrot_pixel_color
	mov		[rdi],	rax
	add		rdi,	8
	addpd	xmm5,	xmm3	; increment x value of positions
	addpd	xmm5,	xmm3	; increment x value of positions
	add		r11,	2
	cmp		r11,	FRAME_WIDTH
	jl		mpa_col_loop

	addpd	xmm3,	xmm4	; increment y value of positions
	addpd	xmm3,	xmm4	; increment y value of positions
	add		r10,	2
	cmp		r10,	FRAME_HEIGHT
	jl		mpa_row_loop

	mov		rax,	[rsp]
	ret
mandelbrot_pixel_array ENDP



; ------------------------------------------------
mandelbrot_pixel_color PROC
;  Determines the color of a pixel given coordinates in
;  the mandelbrot set.
; IN:
; - XMM5 - double - x position of 2 points, packed (expects later pixel in lower qword)
; - XMM6 - double - y position of 2 points, packed (expects later pixel in lower qword)
; OUT:
; - __int64 - color data for both given coordinate (reverses pixel order from input)
; ------------------------------------------------
	call	mandelbrot_value
	movd	ebx,	xmm11

	shl		ebx,	2;

	mov		al,		0FFh;
	shl		rax,	8;

	mov		al,		bl
	shl		rax,	8;
	mov		al,		bl;
	shl		rax,	8;
	mov		al,		bl;
	shl		rax,	8;

	movhlps	xmm11,	xmm11
	movd	ebx,	xmm11

	shl		ebx,	2;

	mov		al,		0FFh;
	shl		rax,	8;

	mov		al,		bl
	shl		rax,	8;
	mov		al,		bl;
	shl		rax,	8;
	mov		al,		bl;
	ret		
mandelbrot_pixel_color ENDP



; ------------------------------------------------
mandelbrot_value PROC
;  Caclualtes the mandelbrot value of the coordinate,
;  which is equal to the number of iterations for escape,
;  or 0 if within the mandelbrot set.
; IN:
; - XMM5 - double - x position of 2 points, packed
; - XMM6 - double - y position of 2 points, packed
; OUT:
; - XMM0 - 2 QWORDS that represent number of iterations, packed
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
	mulpd	xmm8,	xmm7
	addpd	xmm8,	xmm8
	addpd	xmm8,	xmm6
	; x = x_temp
	movapd	xmm7,	xmm13
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
end