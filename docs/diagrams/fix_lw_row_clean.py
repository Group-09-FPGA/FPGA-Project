with open("fig3_timing.py") as f:
    code = f.read()

# Replace row 6 in R with strictly 3 stages: IF/ID (10), EX (11), MEM/WB (12)
# And row 7 has load-ALU stall at T12, and then EX or wait until ready:
# If row 6 finishes MEM/WB at T12, then load data is produced by MEM/WB at T12!
# So add x7 stalls for 1 cycle (T12) due to Load-ALU hazard, or if memory had delay:
# Wait, if row 7 was stalled at 12, 13, 14, 15:
# Does user want row 7 to stall at 12 and then execute EX at 13, or keep row 7 stall at 12..15?
# Let's check row 6:
# If row 6 is strictly: {10: "id", 11: "ex", 12: "wb"}
# If row 6 is {10: "id", 11: "ex", 12: "wb"}, it only has IF/ID, EX, MEM/WB! Exactly 3 boxes!
