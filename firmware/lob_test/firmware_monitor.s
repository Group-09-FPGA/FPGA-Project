.section .text
.globl _start

# Memory map is in docs/rtl_reference.md. The CPU continuously records
# coherent book snapshots and the diagnostic state for host-side inspection.
_start:
    li sp, 0x20000FF0
    li s0, 0x40000000       # LOB MMIO
    li s1, 0x20000000       # 4-KiB data memory
    li s2, 0x50000000       # Network diagnostics MMIO

wait_init:
    lw t0, 0x04(s0)
    andi t1, t0, 1
    beqz t1, wait_init

wait_config:
    lw t0, 0x04(s0)
    andi t1, t0, 0x80      # bundled configuration has reached ETH clock domain
    beqz t1, wait_config
    li t0, 1
    sw t0, 0x00(s0)        # enable feed consumption after configuration settles

monitor:
    lw t0, 0x04(s0)        # status and validity
    sw t0, 0x18(s1)
    lw t0, 0x08(s0)        # latched LOB error
    sw t0, 0x1C(s1)
    lw t0, 0x20(s2)        # feed loss/decode flags
    sw t0, 0x20(s1)
    lw t0, 0x00(s2)        # received frames
    sw t0, 0x24(s1)
    lw t0, 0x0C(s2)        # sequence gaps
    sw t0, 0x28(s1)
    lw t0, 0x18(s2)        # RMII overflow
    sw t0, 0x2C(s1)

    lw t0, 0x04(s0)
    andi t1, t0, 2         # do not publish an invalid book
    beqz t1, monitor

    lw t2, 0x10(s0)        # reading BID_P latches a coherent snapshot
    lw t3, 0x14(s0)
    lw t4, 0x18(s0)
    lw t5, 0x1C(s0)
    lw t6, 0x20(s0)        # snapshot flags and generation
    sw t2, 0x00(s1)
    sw t3, 0x04(s1)
    sw t4, 0x08(s1)
    sw t5, 0x0C(s1)
    sw t6, 0x10(s1)
    lw t0, 0x0C(s0)        # active orders
    sw t0, 0x14(s1)
    j monitor
