with open("fig3_timing.py") as f:
    code = f.read()

# Since lw is 3 cycles (10: IF/ID, 11: EX, 12: MEM/WB):
# The Load-ALU hazard stall on add x7 is just 1 cycle stall at T12!
# add x7 (row 7) has: IF/ID at T11, STALL at T12, EX at T13, MEM/WB at T14!
# beq (row 8) has: IF/ID at T13, EX at T14, MEM/WB at T15!
# addi x8 (row 9): IF/ID at T14, FLUSH at T15, FLUSH at T16!
# addi x11 (row 10): IF/ID at T15, FLUSH at T16, FLUSH at T17!
# div x9 (row 11): IF/ID at T16, M from T17 to T50, MEM/WB at T51!
# Wait! In the digital waveforms at the bottom:
# Notice the digital waveform tracks were sampled from the log where bus stall happened at T11-T15, branch at T18, div at T21.
# If row 7 has: {11: "id", 12: "stall", 16: "ex", 17: "wb"} or {11: "id", **{t: "stall" for t in (12, 13, 14, 15)}, 16: "ex", 17: "wb"}?
# In crop_check_lw_only3.png, look at row 7:
# Row 7 has STALL at 12, 13, 14, 15, and the green arrow currently cuts right through the STALL boxes!
# If the arrow goes from row 6 MEM/WB (at T12) -> enters row 7 EX (at T16):
# The arrow can either:
# Drop down along the vertical line at cx(16), starting from ry(6)+RH/2, just like the other arrows!
# Let us check:
# If arrow drops at cx(16), it does NOT cross the STALL boxes at all!
# pts = f"M{cx(16)-1},{ry(6)+RH/2} L{cx(16)+3},{ry(6)+RH/2} L{cx(16)+3},{ry(7)+RH/2} L{cx(16)+6},{ry(7)+RH/2}"
# That drops cleanly right at the boundary between T15 and T16, perfectly entering the EX cell of add x7!
