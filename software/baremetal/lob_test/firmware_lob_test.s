.section .text
.globl _start

_start:
    li sp, 0x20000FF0

    li s0, 0x40000000
    li s1, 0x20000000

wait_init:
    lw t0, 0x04(s0)
    andi t1, t0, 0x03
    li t2, 0x03
    bne t1, t2, wait_init

    li t0, 900000
    sw t0, 0x24(s0)
    li t0, 1000
    sw t0, 0x28(s0)
    li t0, 1
    sw t0, 0x2C(s0)

wait_bbo:
    lw t0, 0x04(s0)
    andi t1, t0, 0x30
    li t2, 0x30
    bne t1, t2, wait_bbo

    lw t2, 0x10(s0)
    lw t3, 0x14(s0)
    lw t4, 0x18(s0)
    lw t5, 0x1C(s0)
    lw t6, 0x0C(s0)

    sw t2, 0x00(s1)
    sw t3, 0x04(s1)
    sw t4, 0x08(s1)
    sw t5, 0x0C(s1)
    sw t6, 0x10(s1)

    li a0, 0xCAFEBEEF
    sw a0, 0x14(s1)

halt_loop:
    j halt_loop
