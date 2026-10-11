# Option A: row 6 has 3 contiguous boxes: 10: IF/ID, 11: EX, 12: MEM/WB.
# If row 6 has {10: "id", 11: "ex", 12: "wb"}, then:
# row 7 is add x7: IF/ID at 11, then Load-ALU STALL at 12, EX at 13, MEM/WB at 14.
# Then forwarding goes from row 6 (at T12) -> row 7 (at T13 EX).
# But what about the downstream instructions?
# In the original trace, branch was at T17/T18, div was at T20/T21..T54.
# If row 6 is {10: "id", 11: "ex", 12: "wb"} without shifting downstream:
# row 6 has 3 boxes: T10 (IF/ID), T11 (EX), T12 (MEM/WB).
# row 7 has: T11 (IF/ID), T12..T15 (STALL), T16 (EX), T17 (MEM/WB).
# OR: does row 6 just have {10: "id", 11: "ex", 12: "wb"}?
# Wait! Let's check: why did row 6 have 4 grey boxes?
# Because in row 6: {10: "id", 11: "ex", **h(12, 13, 14, 15), 16: "wb"}.
# That had 6 boxes total: ID(10), EX(11), hold(12), hold(13), hold(14), hold(15), WB(16) -> 7 boxes total!
# And earlier when I removed the grey boxes from row 6, it had: ID(10), EX(11), [gap 12..15], WB(16).
# The user said: "noo not the second load , i meant the first load , second load should be like before only" -> referring to lui vs lw.
# And now the user said:
# "in 0x18 why is load word taking 4 cycles , it should be 3 cycle only"
# "i meant only IF/ID EX Mem/WB should be there for the 0x18"
# User is saying: For 0x18, there should NOT be any extra cycles or gap; it should ONLY have IF/ID, EX, MEM/WB (3 cycles total: 10, 11, 12)!
