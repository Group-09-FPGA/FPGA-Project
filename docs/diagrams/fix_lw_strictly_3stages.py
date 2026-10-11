with open("fig3_timing.py") as f:
    code = f.read()

# 0x18 lw: only IF/ID, EX, MEM/WB (3 cycles: 10, 11, 12)
# Row 6: {10: "id", 11: "ex", 12: "wb"}
# Row 7: add x7 has Load-ALU Stall at T12, EX at T13, MEM/WB at T14!
# Let's adjust subsequent rows so the entire pipeline flows consistently:
# Row 7 (add x7):  {11: "id", 12: "stall", 13: "ex", 14: "wb"}
# Row 8 (beq):     {13: "id", 14: "ex", 15: "wb"}
# Row 9 (addi x8): {14: "id", 15: "flush", 16: "flush"}
# Row 10 (addi 11):{15: "id", 16: "flush", 17: "flush"}
# Row 11 (div x9): {16: "id", **{t: "mex" for t in (17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"}  # or similar
# Wait, let's check what row 6 should have:
# If user says: "i meant only IF/ID EX Mem/WB should be there for the 0x18"
# In row 6, there were:
# 6: {10: "id", 11: "ex", **h(12, 13, 14, 15), 16: "wb"}
# If only IF/ID, EX, MEM/WB are there, row 6 is strictly:
# 6: {10: "id", 11: "ex", 12: "wb"}
# What about row 7?
# If row 7 has load-ALU stall:
# If row 7 was: 7: {11: "id", 12: "stall", 13: "ex", 14: "wb"}
# Then forwarding from lw (row 6) MEM/WB (or EX) goes to row 7 EX!
# Wait, what if the user wants row 6 to just be {10: "id", 11: "ex", 12: "wb"}, or does row 7 stay at 16?
# Wait! If row 6 has EX at 11, and WB at 16, without the hold boxes, that was: {10: "id", 11: "ex", 16: "wb"}. But earlier user asked:
# "in 0x18 why is load word taking 4 cycles , it should be 3 cycle only"
# Then user clarified:
# "i meant only IF/ID EX Mem/WB should be there for the 0x18"
# Exactly! The user literally wants only the 3 boxes: IF/ID, EX, MEM/WB for 0x18!
