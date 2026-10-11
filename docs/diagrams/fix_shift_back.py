with open("fig3_timing.py") as f:
    code = f.read()

# Row 6 (lw):        {10: "id", 11: "ex", 12: "wb"}
# Row 7 (add x7):     {11: "id", 12: "stall", 13: "ex", 14: "wb"}  (1-cycle Load-ALU stall at T12!)
# Row 8 (beq):        {13: "id", 14: "ex", 15: "wb"}
# Row 9 (addi x8):    {14: "id", 15: "flush", 16: "flush"}
# Row 10 (addi x11):  {15: "id", 16: "flush", 17: "flush"}
# Row 11 (div x9):    {16: "id", **{t: "mex" for t in (17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"}
# Row 12 (addi x10):  {17: "id", **h(18, 19, 20, 21, 22, 23, 24, 53, 54), 55: "ex", 56: "wb"}

# Let's inspect R replacement:
old_R = """    6: {10: "id", 11: "ex", 12: "wb"},
    7: {11: "id", **{t: "stall" for t in (12, 13, 14, 15)}, 16: "ex", 17: "wb"}, # explicitly load-ALU stall
    8: {17: "id", 18: "ex", 19: "wb"},
    9: {18: "id", 19: "flush", 20: "flush"},
    10: {19: "id", 20: "flush", 21: "flush"},
    11: {20: "id", **{t: "mex" for t in (21, 22, 23, 24, 53, 54)}, 55: "wb"},
    12: {21: "id", **h(22, 23, 24, 53, 54), 55: "ex", 56: "wb"},"""

new_R = """    6: {10: "id", 11: "ex", 12: "wb"},
    7: {11: "id", 12: "stall", 13: "ex", 14: "wb"}, # 1-cycle Load-ALU stall
    8: {13: "id", 14: "ex", 15: "wb"},
    9: {14: "id", 15: "flush", 16: "flush"},
    10: {15: "id", 16: "flush", 17: "flush"},
    11: {16: "id", **{t: "mex" for t in (17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"},
    12: {17: "id", **h(18, 19, 20, 21, 22, 23, 24, 53, 54), 55: "ex", 56: "wb"},"""

code = code.replace(old_R, new_R)

# Update forwarding arrow for add x7:
# Producer is lw x6 (row 6) ending at T12, consumer is add x7 (row 7) EX at T13!
# draw_forward_arrow(13, 6, 7) drops at cx(13) right before row 7 EX!
code = code.replace("draw_forward_arrow(16, 6, 7)   # lw x6 (row 6) -> add x7 EX (row 7) at T16",
                    "draw_forward_arrow(13, 6, 7)   # lw x6 (row 6) -> add x7 EX (row 7) at T13")

# Update bottom description line
code = code.replace("T16 (lw x6 -> add x7)", "T13 (lw x6 -> add x7)")
code = code.replace("Load-ALU Stall at T12-T15", "Load-ALU Stall at T12")
code = code.replace("Branch taken at T18 squashes T19-T21", "Branch taken at T14 squashes T15-T17")

# In digital waveforms:
# Let us update the branch_taken pulse from 18 to 14, and fw1/fw2 at 13 instead of 16:
