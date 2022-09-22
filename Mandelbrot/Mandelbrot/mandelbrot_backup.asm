.data
; static constants
defaultXMin		EQU		-2.0
defaultXMax		EQU		0.47
defaultYMin		EQU		-1.12
defaultYMax		EQU		1.12

; local data
numPixels		DWORD	0
pixelArrayPTR	QWORD	0

; external function prototypes
extern malloc: proc
extern free: proc


.code
; ------------------------------------------------
mandelbrot_frame_generator PROC 
;  Generates the frame of pixel data from a set of 
;  input parameters that determine the center position, 
;  scale, and dimensions of the mandelbrot frame.
;  Handles the allocation of the pixel array,
;  which will only be freed if the pixel count
;  changes in a subsequent call.
; IN:
; - ecx - __int32 - width of the frame in pixels
; - edx - __int32 - height of the frame in pixels
; - XMM0 - double - x-position of center
; - XMM1 - double - y-position of center
; - XMM2 - double - scale factor
; OUT:
; - __int32* - reference to an array of __int32 pixels
; ------------------------------------------------
	mov		eax,	ecx
	imul	eax,	edx
	
	; free and re-allocate pixelArrayPTR if numPixels changed
	cmp		eax,	numPixels
	je		mfg_no_malloc
	push	rdx
	push	rcx
	push	rax

	mov		rcx,	pixelArrayPTR
	sub		rsp,	16
	call	free
	add		rsp,	16

	pop		rcx				; rcx <- rax
	shl		rcx,	2
	sub		rsp,	16
	call	malloc
	add		rsp,	16
	mov		pixelArrayPTR,	rax
	pop		rcx
	pop		rdx
mfg_no_malloc:
	mov		rax,	pixelArrayPTR

	; prepare arguments and call mandelbrot_pixel_array
	mov		r8,		rax
	call mandelbrot_pixel_array

	ret
mandelbrot_frame_generator ENDP 



; ------------------------------------------------
mandelbrot_pixel_array PROC uses r10 r11 r8 ; r8 must be last
;  Builds the array of pixel data given an augmented
;  set of parameters that prepare this function to 
;  easily iterate over the mandelbrot set within the
;  defined frame.
; IN:
; - rcx - __int32 - width of the frame in pixels
; - rdx - __int32 - height of the frame in pixels
; - r8  - pointer - reference to pixel array memory to fill
; - XMM0 - double - x-position of top left bound
; - XMM1 - double - y-position of top left bound
; - XMM2 - double - width of pixel in Mandelbrot coords
; - XMM3 - double - height of pixel in Mandelbrot coords
; OUT:
; - __int32* - reference to the array of __int32 pixels passed in r8
; ------------------------------------------------

	mov		r12,	0FFFFFFFFh
	xor		r10,	r10
mpa_row_loop:
	xor		r11,	r11
mpa_col_loop:
	mov		eax,	r10d
	add		eax,	r11d
	and		eax,	11h
	cmp		eax,	10h
	jnz		mpa_write_pixel
mpa_toggle_color:
	xor		r12,	0FFFFFF00h
mpa_write_pixel:
	mov		[r8],	r12d
	add		r8,		4
	inc		r11d
	cmp		r11d,	ecx
	jl		mpa_col_loop
	inc		r10d
	cmp		r10d,	edx
	jl		mpa_row_loop

	mov		rax,	[rsp]
	ret
mandelbrot_pixel_array ENDP



; ------------------------------------------------
mandelbrot_pixel_color PROC
;  Determines the color of a pixel given coordinates in
;  the mandelbrot set.
; IN:
; - XMM0 - double - x-position in set
; - XMM1 - double - y-position in set
; OUT:
; - __int32 - color data for given coordinate
; ------------------------------------------------
	ret
mandelbrot_pixel_color ENDP



; ------------------------------------------------
mandelbrot_value PROC
;  Caclualtes the mandelbrot value of the coordinate,
;  which is equal to the number of iterations for escape,
;  or 0 if within the mandelbrot set.
; IN:
; - XMM0 - double - x-position in set
; - XMM1 - double - y-position in set
; OUT:
; - __int32 - number of iterations 
; ------------------------------------------------
	ret
mandelbrot_value ENDP
end