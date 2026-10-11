with open("fig3_timing.py") as f:
    code = f.read()

old_prog = """PROG = [
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

new_prog = """PROG = [
    ("0x00", "addi x1, x0, 7",   "x1 = 7"),
    ("0x04", "addi x2, x1, 2",   "x2 = 9 (RAW on x1 -> EX-to-EX Forward)"),
    ("0x08", "lui  x5, 0x20000", "x5 = 0x20000000 (DMEM base)"),
    ("0x0c", "mul  x3, x1, x2",  "x3 = 63 (RV32M 3-stage mult: 4 cycles in EX)"),
    ("0x10", "add  x4, x3, x1",  "x4 = 70 (RAW stall on MUL, EX-to-EX fwd T8)"),
    ("0x14", "sw   x4, 0(x5)",   "Mem[x5] = 70 (Bus store request)"),
    ("0x18", "lw   x6, 0(x5)",   "x6 = Mem[x5] (Canonical 3-cycle load)"),
    ("0x1c", "add  x7, x6, x1",  "x7 = 77 (Load-ALU stall + EX-to-EX forward T13)"),
    ("0x20", "beq  x0, x0, +16",  "Branch Taken -> target 0x30 (T14 in EX, T15 in WB)"),
    ("0x24", "addi x8, x0, 1",   "Wrong +4 fetch (T14 IF/ID) -> Flushed at T15"),
    ("0x30", "div  x9, x4, x1",  "x9 = 7 (Branch target 0x20+16: IF/ID at T15 during beq WB)"),
    ("0x34", "addi x10, x9, 1",  "x10 = 8 (RAW stall on DIV, EX-to-EX fwd T55)"),
]"""

code = code.replace(old_prog, new_prog)

# Update bottom description line
code = code.replace("target 0x28 is fetched", "target 0x30 is fetched")

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated to +16 offset (0x30, 0x34)")
