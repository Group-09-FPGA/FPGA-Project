.globl main
.text
main:
    # Set up DMEM base pointer: 0x20000000
    lui  x15, 0x20000

    # -------------------------------------------------------------
    # 1. MULTIPLICATION (MUL): 6 * 7 = 42 (0x002A)
    # -------------------------------------------------------------
    addi x1, x0, 6
    addi x2, x0, 7
    mul  x3, x1, x2
    sw   x3, 0(x15)         # DMEM[0] = 42, LED = 0x002A

    # -------------------------------------------------------------
    # 2. SIGNED UPPER MULTIPLICATION (MULH): -5 * 2 = -10
    #    Product: 0xFFFFFFFF_FFFFFFF6, Upper 32: 0xFFFFFFFF (-1)
    # -------------------------------------------------------------
    addi x4, x0, -5
    addi x5, x0, 2
    mulh x6, x4, x5
    sw   x6, 4(x15)         # DMEM[1] = 0xFFFFFFFF, LED = 0xFFFF

    # -------------------------------------------------------------
    # 3. UNSIGNED UPPER MULTIPLICATION (MULHU): 0xFFFFFFFB * 2
    #    Product: 0x00000001_FFFFFFF6, Upper 32: 0x00000001 (1)
    # -------------------------------------------------------------
    mulhu x7, x4, x5
    sw   x7, 8(x15)         # DMEM[2] = 0x00000001, LED = 0x0001

    # -------------------------------------------------------------
    # 4. SIGNED x UNSIGNED UPPER MULTIPLICATION (MULHSU): -5 * 2
    #    Product: 0xFFFFFFFF_FFFFFFF6, Upper 32: 0xFFFFFFFF (-1)
    # -------------------------------------------------------------
    mulhsu x8, x4, x5
    sw   x8, 12(x15)        # DMEM[3] = 0xFFFFFFFF, LED = 0xFFFF

    # -------------------------------------------------------------
    # 5. SIGNED DIVISION (DIV): 100 / 7 = 14 (0x000E)
    # -------------------------------------------------------------
    addi x9, x0, 100
    addi x10, x0, 7
    div  x11, x9, x10
    sw   x11, 16(x15)       # DMEM[4] = 14, LED = 0x000E

    # -------------------------------------------------------------
    # 6. UNSIGNED DIVISION (DIVU): 0xFFFFFFFB / 2 = 2147483645 (0x7FFFFFFD)
    # -------------------------------------------------------------
    divu x12, x4, x5
    sw   x12, 20(x15)       # DMEM[5] = 0x7FFFFFFD, LED = 0xFFFD

    # -------------------------------------------------------------
    # 7. SIGNED REMAINDER (REM): 100 % 7 = 2 (0x0002)
    # -------------------------------------------------------------
    rem  x13, x9, x10
    sw   x13, 24(x15)       # DMEM[6] = 2, LED = 0x0002

    # -------------------------------------------------------------
    # 8. UNSIGNED REMAINDER (REMU): 0xFFFFFFFB % 2 = 1 (0x0001)
    # -------------------------------------------------------------
    remu x14, x4, x5
    sw   x14, 28(x15)       # DMEM[7] = 1, LED = 0x0001

    # -------------------------------------------------------------
    # 9. DIVISION BY ZERO (RISC-V spec compliant)
    # -------------------------------------------------------------
    # 9a. Signed DIV by zero: 100 / 0 = -1 (0xFFFFFFFF)
    div  x16, x9, x0
    sw   x16, 32(x15)       # DMEM[8] = 0xFFFFFFFF, LED = 0xFFFF

    # 9b. Unsigned DIV by zero: 100 / 0 = 0xFFFFFFFF
    divu x17, x9, x0
    sw   x17, 36(x15)       # DMEM[9] = 0xFFFFFFFF, LED = 0xFFFF

    # 9c. Signed REM by zero: 100 % 0 = dividend (100 = 0x00000064)
    rem  x18, x9, x0
    sw   x18, 40(x15)       # DMEM[10] = 100, LED = 0x0064

    # 9d. Unsigned REM by zero: 100 % 0 = dividend (100 = 0x00000064)
    remu x19, x9, x0
    sw   x19, 44(x15)       # DMEM[11] = 100, LED = 0x0064

    # -------------------------------------------------------------
    # 10. SIGNED OVERFLOW (RISC-V spec compliant)
    # -------------------------------------------------------------
    # 10a. Signed DIV overflow: 0x80000000 / 0xFFFFFFFF = 0x80000000
    lui  x25, 0x80000
    addi x26, x0, -1
    div  x20, x25, x26
    sw   x20, 48(x15)       # DMEM[12] = 0x80000000, LED = 0x0000

    # 10b. Signed REM overflow: 0x80000000 % 0xFFFFFFFF = 0x00000000
    rem  x21, x25, x26
    sw   x21, 52(x15)       # DMEM[13] = 0, LED = 0x0000

    # -------------------------------------------------------------
    # 11. SELF-CHECKING VERIFICATION ASSERTIONS
    # -------------------------------------------------------------
    li   x27, 42
    bne  x3, x27, fail_mul

    li   x27, -1
    bne  x6, x27, fail_mulh

    li   x27, 1
    bne  x7, x27, fail_mulhu

    li   x27, -1
    bne  x8, x27, fail_mulhsu

    li   x27, 14
    bne  x11, x27, fail_div

    li   x27, 2147483645
    bne  x12, x27, fail_divu

    li   x27, 2
    bne  x13, x27, fail_rem

    li   x27, 1
    bne  x14, x27, fail_remu

    li   x27, -1
    bne  x16, x27, fail_divzero

    li   x27, -1
    bne  x17, x27, fail_divuzero

    li   x27, 100
    bne  x18, x27, fail_remzero

    li   x27, 100
    bne  x19, x27, fail_remuzero

    lui  x27, 0x80000
    bne  x20, x27, fail_divovf

    bne  x21, x0, fail_removf

    # -------------------------------------------------------------
    # 12. FINAL PASS SENTINEL & STABLE HALT LOOP
    # -------------------------------------------------------------
    li   x22, 0xCAFE
    sw   x22, 56(x15)       # DMEM[14] = 0xCAFE, LED = 0xCAFE

pass_loop:
    j    pass_loop

# -----------------------------------------------------------------
# ERROR HANDLERS (Unique error codes on LEDs and distinct halt loops)
# -----------------------------------------------------------------
fail_mul:
    li   x23, 0xEE01
    sw   x23, 60(x15)
fail_loop1:
    j    fail_loop1

fail_mulh:
    li   x23, 0xEE02
    sw   x23, 60(x15)
fail_loop2:
    j    fail_loop2

fail_mulhu:
    li   x23, 0xEE03
    sw   x23, 60(x15)
fail_loop3:
    j    fail_loop3

fail_mulhsu:
    li   x23, 0xEE04
    sw   x23, 60(x15)
fail_loop4:
    j    fail_loop4

fail_div:
    li   x23, 0xEE05
    sw   x23, 60(x15)
fail_loop5:
    j    fail_loop5

fail_divu:
    li   x23, 0xEE06
    sw   x23, 60(x15)
fail_loop6:
    j    fail_loop6

fail_rem:
    li   x23, 0xEE07
    sw   x23, 60(x15)
fail_loop7:
    j    fail_loop7

fail_remu:
    li   x23, 0xEE08
    sw   x23, 60(x15)
fail_loop8:
    j    fail_loop8

fail_divzero:
    li   x23, 0xEE09
    sw   x23, 60(x15)
fail_loop9:
    j    fail_loop9

fail_divuzero:
    li   x23, 0xEE0A
    sw   x23, 60(x15)
fail_loop10:
    j    fail_loop10

fail_remzero:
    li   x23, 0xEE0B
    sw   x23, 60(x15)
fail_loop11:
    j    fail_loop11

fail_remuzero:
    li   x23, 0xEE0C
    sw   x23, 60(x15)
fail_loop12:
    j    fail_loop12

fail_divovf:
    li   x23, 0xEE0D
    sw   x23, 60(x15)
fail_loop13:
    j    fail_loop13

fail_removf:
    li   x23, 0xEE0E
    sw   x23, 60(x15)
fail_loop14:
    j    fail_loop14
