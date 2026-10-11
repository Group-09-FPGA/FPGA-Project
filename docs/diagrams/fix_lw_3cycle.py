with open("fig3_timing.py") as f:
    code = f.read()

# Row 6: lw takes 3 cycles in total: IF/ID at T10, EX at T11, MEM/WB at T12! (or IF/ID @ 10, EX @ 11, WB @ 12)
# With load-ALU stall on add x7: IF/ID at T11, STALL at T12, EX at T13, MEM/WB at T14!
# Let's inspect the entire program schedule if lw is a standard 3-cycle load instruction:
# row 6: lw x6:    {10: "id", 11: "ex", 12: "wb"}
# row 7: add x7:   {11: "id", 12: "stall", 13: "ex", 14: "wb"} (1 cycle load-use stall)
# row 8: beq:      {13: "id", 14: "ex", 15: "wb"}
# row 9: addi x8:  {14: "id", 15: "flush", 16: "flush"}
# row 10: addi x11:{15: "id", 16: "flush", 17: "flush"}
# row 11: div x9:  {16: "id", **{t: "mex" for t in range(17, 51)}, 51: "wb"}
# Wait, let's check what the user wants:
# "in 0x18 why is load word taking 4 cycles , it should be 3 cycle only"
# Does user mean:
# lw stage progression: IF/ID (1 cycle), EX (1 cycle), MEM/WB (1 cycle) = 3 cycles total!
# Currently row 6 has: {10: "id", 11: "ex", **h(12, 13, 14, 15), 16: "wb"} which was 7 cycles total with 4 hold cycles!
# Or does the user mean the wait/latency was 4 cycles and should be 3 cycles (e.g. hold for 2 cycles so EX+hold+hold = 3)?
# Look closely at user's words: "in 0x18 why is load word taking 4 cycles , it should be 3 cycle only"
# In row 6, there were 4 grey hold boxes (12, 13, 14, 15), which was taking 4 cycles of wait!
# If load word takes 3 cycles total in the pipeline:
# Stage 1: IF/ID (T10)
# Stage 2: EX (T11)
# Stage 3: MEM/WB (T12)
# That's a classic 3-stage load instruction (3 cycles total: IF/ID -> EX -> MEM/WB)!
