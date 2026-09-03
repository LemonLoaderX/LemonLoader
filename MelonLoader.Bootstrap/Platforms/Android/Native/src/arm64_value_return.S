.text

.macro LEMON_RETURN_ADAPTER name, load_result
.p2align 3
.global \name
.global \name\()_target
.global \name\()_end
.hidden \name
.hidden \name\()_target
.hidden \name\()_end
.type \name, %function
\name:
    bti c
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x16, \name\()_target
    blr x16
    \load_result
    ldp x29, x30, [sp], #16
    ret
.p2align 3
\name\()_target:
    .xword 0
\name\()_end:
.size \name, .-\name
.endm

LEMON_RETURN_ADAPTER lemon_arm64_return_8, "ldr x0, [x0, #16]"
LEMON_RETURN_ADAPTER lemon_arm64_return_16, "ldp x0, x1, [x0, #16]"

.section .note.GNU-stack,"",%progbits
