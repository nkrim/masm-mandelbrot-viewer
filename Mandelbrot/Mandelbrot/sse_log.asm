.data

align 16
.code
; ------------------------------------------------
fln_pd PROC
;  Computes the natural log on the FPU stack
; IN: 
;	XMM0 - packed double inputs
;	rdx	- offset of destination memory
; OUT:
;	[rdx] - results stored as 16 bytes at rdx, 
;			with the lower QWORD of XMM appearing first
; USES:
;	- rax
; ------------------------------------------------
	movapd	[rdx],	xmm0
	fld		[rdx]
	fldln2		; load ln(2)
	fyl2x		; perform ln(2) * log_2(x) = ln(x)
	f
	ret
fln_pd ENDP
END