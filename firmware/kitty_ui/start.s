    .section .text.start
    .globl _start
_start:
    li sp, 65536
    call main
1:  j 1b
