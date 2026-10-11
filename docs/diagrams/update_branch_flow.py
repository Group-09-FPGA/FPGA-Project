with open("fig3_timing.py") as f:
    code = f.read()

# 1. Update PROG to 12 instructions (eliminate 0x28 addi x11, change beq target to 0x28)
old_prog = """PROG = [
    ("0x00", "addi x1, x0, 7",   "x1 = 7"),
    ("0x04", "addi x2, x1, 2",   "x2 = 9 (RAW on x1 -> EX-to-EX Forward)"),
    ("0x08", "lui  x5, 0x20000", "x5 = 0x20000000 (DMEM base)"),
    ("0x0c", "mul  x3, x1, x2",  "x3 = 63 (RV32M 3-stage mult: 4 cycles in EX)"),
    ("0x10", "add  x4, x3, x1",  "x4 = 70 (RAW stall on MUL, EX-to-EX fwd T8)"),
    ("0x14", "sw   x4, 0(x5)",   "Mem[x5] = 70 (Bus store request)"),
    ("0x18", "lw   x6, 0(x5)",   "x6 = Mem[x5] (Bus load: 4-cycle bus stall)"),
    ("0x1c", "add  x7, x6, x1",  "x7 = 77 (Load-ALU stall + EX-to-EX forward T16)"),
    ("0x20", "beq  x0, x0, +12", "Branch Taken -> target 0x2c (T18 branch_taken)"),
    ("0x24", "addi x8, x0, 1",   "Wrong-path fetch -> Flushed in EX/WB"),
    ("0x28", "addi x11, x0, 2",  "Wrong-path fetch -> Flushed in EX/WB"),
    ("0x2c", "div  x9, x4, x2",  "x9 = 7 (RV32M non-restoring divider: 34 cycles)"),
    ("0x30", "addi x10, x9, 1",  "x10 = 8 (RAW stall on DIV, EX-to-EX fwd T55)"),
]"""

new_prog = """PROG = [
    ("0x00", "addi x1, x0, 7",   "x1 = 7"),
    ("0x04", "addi x2, x1, 2",   "x2 = 9 (RAW on x1 -> EX-to-EX Forward)"),
    ("0x08", "lui  x5, 0x20000", "x5 = 0x20000000 (DMEM base)"),
    ("0x0c", "mul  x3, x1, x2",  "x3 = 63 (RV32M 3-stage mult: 4 cycles in EX)"),
    ("0x10", "add  x4, x3, x1",  "x4 = 70 (RAW stall on MUL, EX-to-EX fwd T8)"),
    ("0x14", "sw   x4, 0(x5)",   "Mem[x5] = 70 (Bus store request)"),
    ("0x18", "lw   x6, 0(x5)",   "x6 = Mem[x5] (Canonical 3-cycle load)"),
    ("0x1c", "add  x7, x6, x1",  "x7 = 77 (Load-ALU stall + EX-to-EX forward T13)"),
    ("0x20", "beq  x0, x0, +8",   "Branch Taken -> target 0x28 (T14 in EX, T15 in WB)"),
    ("0x24", "addi x8, x0, 1",   "Wrong +4 fetch (T14 IF/ID) -> Flushed at T15"),
    ("0x28", "div  x9, x4, x1",  "x9 = 7 (Branch target: IF/ID at T15 during beq WB)"),
    ("0x2c", "addi x10, x9, 1",  "x10 = 8 (RAW stall on DIV, EX-to-EX fwd T55)"),
]"""

code = code.replace(old_prog, new_prog)

# 2. Update R dictionary
old_R = """    6: {10: "id", 11: "ex", 12: "wb"},
    7: {11: "id", 12: "stall", 13: "ex", 14: "wb"}, # 1-cycle Load-ALU stall
    8: {13: "id", 14: "ex", 15: "wb"},
    9: {14: "id", 15: "flush", 16: "flush"},
    10: {15: "id", 16: "flush", 17: "flush"},
    11: {16: "id", **{t: "mex" for t in (17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"},
    12: {17: "id", **h(18, 19, 20, 21, 22, 23, 24, 53, 54), 55: "ex", 56: "wb"},"""

new_R = """    6: {10: "id", 11: "ex", 12: "wb"},
    7: {11: "id", 12: "stall", 13: "ex", 14: "wb"}, # 1-cycle Load-ALU stall
    8: {13: "id", 14: "ex", 15: "wb"},               # beq: EX at T14, WB at T15
    9: {14: "id", 15: "flush"},                      # addi x8: only 1 wrong instruction, flushed at T15
    10: {15: "id", **{t: "mex" for t in (16, 17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"}, # target div: IF/ID at T15 while beq is WB
    11: {16: "id", **h(17, 18, 19, 20, 21, 22, 23, 24, 53, 54), 55: "ex", 56: "wb"},"""

code = code.replace(old_R, new_R)

# 3. Update dashed continuation lines across break
code = code.replace("for r in (11, 12):", "for r in (10, 11):")

# 4. Update forwarding arrow for div -> addi x10:
code = code.replace("draw_forward_arrow(55, 11, 12)", "draw_forward_arrow(55, 10, 11)")

# 5. Update bottom description text:
code = code.replace("T55 (div x9 -> addi x10)", "T55 (div x9 -> addi x10)")
code = code.replace(
    "- Multi-Cycle & Stalls: MUL takes 4 cycles in EX (T4-T7, m_busy=1); DIV takes 34 cycles (T21-T54, radix-2). Load-ALU Stall at T12 (1 cycle). Branch taken at T14 squashes wrong path T15-T17.",
    "- Multi-Cycle & Control: MUL takes 4 cycles in EX (T4-T7). Load-ALU Stall at T12 (1 cycle). Branch taken at T14 squashes single wrong +4 fetch (0x24 at T15); target 0x28 is fetched in T15 while branch is in WB. DIV takes 34 cycles."
)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated branch flow in fig3_timing.py successfully")
