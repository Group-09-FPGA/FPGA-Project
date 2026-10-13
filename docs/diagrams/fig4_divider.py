"""Figure 4 - RV32M 32-Iteration Restoring Divider RTL Datapath.
Exact graphical rendition of the verified ASCII architecture.
Every signal, register, multiplexer, and corner-case rule is derived 1-to-1 from:
  rtl/cpu/core/rv32m_unit.v and rtl/cpu/core/cpu_core.v
"""
import os
import sys

# Ensure docs/diagrams directory is in python path
sys.path.insert(0, os.path.dirname(__file__))
from dg import Fig, NAVY, GREY, INK

f = Fig(1760, 960)

# =========================================================================
# TITLE HEADER
# =========================================================================
f.title(
    "Figure 4 - RV32M 32-Iteration Restoring Divider: RTL Hardware Datapath",
    "rv32m_unit.v  |  32-iteration serial restoring recurrence  |  33 compute clocks / 34 pipeline clocks  |  "
    "RISC-V M-Extension (DIV, DIVU, REM, REMU) 1-to-1 Verilog correspondence"
)

# Helper for 2:1 Trapezoid MUX
def draw_mux(x, y, w, h, label="MUX", sel_text=None, p0_text="0", p1_text="1"):
    # Points: top-left, top-right, bottom-right, bottom-left
    # Trapezoid narrowing from left to right
    pts = f"{x},{y} {x+w},{y+10} {x+w},{y+h-10} {x},{y+h}"
    f.raw(f'<polygon points="{pts}" fill="white" stroke="{INK}" stroke-width="1.3"/>')
    f.text(x + w / 2, y + h / 2 + 4, label, 9.5, bold=True, anchor="middle", fill="#444")
    if sel_text:
        f.text(x + w / 2, y - 6, sel_text, 9.5, bold=True, anchor="middle", fill=NAVY, halo=True)
    if p0_text:
        f.text(x + 5, y + h - 14, p0_text, 8, anchor="start", fill="#666")
    if p1_text:
        f.text(x + 5, y + 16, p1_text, 8, anchor="start", fill="#666")

# =========================================================================
# STAGE 1 REGION: INPUT CONDITIONING & CORNER-CASE LATCH (CYCLE 1)
# =========================================================================
f.region(35, 86, 440, 844, "STAGE 1: INPUT CONDITIONING & CORNER-CASE LATCH (CYCLE 1)", color=NAVY)
f.text(45, 118, "Absolute Value MUXes · Div-by-Zero & Overflow Detectors · Init Latches", 9.5, italic=True, fill="#555")

# Inputs
f.box(55, 136, 140, 48, ["rs1 · Dividend", "Signed / Unsigned"], title="op1[31:0]", size=9)
f.box(55, 218, 140, 48, ["rs2 · Divisor", "Signed / Unsigned"], title="op2[31:0]", size=9)
f.box(55, 300, 140, 48, ["DIV / DIVU / REM / REMU", "funct3[2] == 1'b1"], title="funct3[2:0]", size=9)

# 2's Complement Negators
f.box(230, 136, 85, 48, ["~op1 + 1", "32-bit negator"], title="- op1", size=9)
f.box(230, 218, 85, 48, ["~op2 + 1", "32-bit negator"], title="- op2", size=9)

# Absolute Value 2:1 MUXes
draw_mux(345, 132, 28, 56, sel_text="op1_neg", p1_text="1: -op1", p0_text="0: op1")
draw_mux(345, 214, 28, 56, sel_text="op2_neg", p1_text="1: -op2", p0_text="0: op2")

# Wires from Inputs to Negators & MUXes
# op1
f.arrow([(195, 160), (230, 160)])
f.arrow([(210, 160), (210, 178), (345, 178)], dot=[(210, 160)])
f.arrow([(315, 160), (345, 160)])

# op2
f.arrow([(195, 242), (230, 242)])
f.arrow([(210, 242), (210, 260), (345, 260)], dot=[(210, 242)])
f.arrow([(315, 242), (345, 242)])

# Corner-Case & Predicate Detectors
pred_lines = [
    "div_zero = (op2 == 32'd0)",
    "overflow = op1_is_signed && (op1 == 0x80000000) && (op2 == 0xFFFFFFFF)",
    "neg_quo  = op1_is_signed && (op1[31] ^ op2[31]) && (op2 != 32'd0)",
    "neg_rem  = op1_is_signed && op1[31] && (op2 != 32'd0)",
    "orig_op1 = op1 (Preserved for Remainder-by-Zero rule)",
]
f.box(55, 375, 330, 160, pred_lines, title="Corner-Case & Predicate Detectors (Combinational)", size=9, align="left")

# Wires from inputs down to Predicate box
f.arrow([(125, 348), (125, 375)])

# Cycle 1 Init Registers
init_lines = [
    "rem_reg[31:0]  <= 32'd0 (Initial remainder cleared)",
    "quo_reg[31:0]  <= abs_op1 (Dividend loaded into quotient)",
    "div_reg[31:0]  <= abs_op2 (Divisor held constant)",
    "orig_op1[31:0] <= op1 (Preserved for div-by-zero remainder)",
    "div_cnt[4:0]   <= 5'd0 (5-bit counter: resets 32-iteration loop)",
    "div_op_r[2:0]  <= funct3 (Latched instruction encoding)",
    "Latches: div_zero, overflow, neg_quo, neg_rem",
    "busy <= 1'b1 · asserts m_stalling to freeze CPU pipeline",
    "state <= STATE_DIV (Advances to iterative recurrence)",
]
f.box(55, 560, 400, 230, init_lines, kind="new", title="Cycle 1 Init Registers (▲ posedge clk on start)", size=9, align="left")

# Vertical bypass wires from Abs MUXes down to Init Registers
f.arrow([(373, 160), (410, 160), (410, 560)], label="abs_op1[31:0]", lp=(410, 200), lsize=8.5)
f.arrow([(373, 242), (430, 242), (430, 560)], label="abs_op2[31:0]", lp=(430, 280), lsize=8.5)

# Predicates into Init Registers
f.arrow([(220, 535), (220, 560)])

# =========================================================================
# STAGE 2 REGION: 32-ITERATION RESTORING RECURRENCE LOOP (CYCLES 2–32)
# =========================================================================
f.region(495, 86, 725, 844, "STAGE 2: 32-ITERATION RESTORING RECURRENCE LOOP (CYCLES 2–32)", color=NAVY)
f.text(505, 118, "1-Bit Left Shift · 34-Bit Trial Subtraction · Remainder Restoration MUX · div_cnt[4:0]", 9.5, italic=True, fill="#555")

# Top 3 Recurrence Registers
f.box(515, 136, 210, 68, ["32-bit Remainder Accumulator", "Init: 32'd0  |  Loop: next_rem"], kind="new", title="rem_reg[31:0] (DFF)", size=9)
f.box(750, 136, 210, 68, ["32-bit Quotient Shift Register", "Init: abs_op1  |  Loop: next_quo"], kind="new", title="quo_reg[31:0] (DFF)", size=9)
f.box(985, 136, 210, 68, ["32-bit Divisor Constant", "Init: abs_op2  |  Held constant"], kind="new", title="div_reg[31:0] (DFF)", size=9)

# 1-Bit Left Shifter & Concat
f.box(535, 238, 330, 64, [
    "shifted_rem[32:0] = {rem_reg[31:0], quo_reg[31]}",
    "Shifts remainder left by 1 bit; inserts MSB of quotient"
], title="1-Bit Left Shifter & Concat", size=9)

# Divisor Zero-Extension
f.box(930, 238, 245, 64, [
    "{2'b00, div_reg[31:0]}  [33:0]",
    "Zero-extends 32-bit divisor to 34-bit subtrahend"
], title="Divisor Zero-Extension", size=9)

# Wires from top registers down to Shifter and Divisor Extension
f.arrow([(620, 204), (620, 238)], label="rem_reg[31:0]", lp=(620, 222), lsize=8)
f.arrow([(820, 204), (820, 220), (770, 220), (770, 238)], label="quo_reg[31] (MSB)", lp=(800, 213), lsize=8)
f.arrow([(1090, 204), (1090, 238)], label="div_reg[31:0]", lp=(1090, 222), lsize=8)

# 34-Bit Trial Subtractor
f.box(555, 336, 445, 68, [
    "trial_sub[33:0] = {1'b0, shifted_rem[32:0]} - {2'b00, div_reg[31:0]}",
    "Tentative subtraction for current quotient bit position"
], kind="new", title="34-Bit Trial Subtractor", size=9)

# Borrow Flag Detector
f.box(1035, 336, 150, 68, [
    "borrow = trial_sub[33]",
    "1 = Underflow (Subtract failed)",
    "0 = Success (Subtract passed)"
], title="Borrow Flag", size=9)

# Wires into Subtractor & Borrow Flag
f.arrow([(700, 302), (700, 336)], label="{1'b0, shifted_rem}", lp=(700, 320), lsize=8)
f.arrow([(1050, 302), (1050, 320), (890, 320), (890, 336)], label="{2'b00, div_reg}", lp=(970, 313), lsize=8)
f.arrow([(1000, 370), (1035, 370)], label="trial[33]", lp=(1018, 362), lsize=8.5)

# Restoring Multiplexer
draw_mux(615, 438, 35, 76, label="RESTORE", sel_text="borrow", p0_text="0: trial_sub", p1_text="1: shifted_rem")
f.text(665, 460, "0: trial_sub[31:0] (Subtracted)", 8.5, bold=True, fill="#1f7a4d")
f.text(665, 495, "1: shifted_rem[31:0] (RESTORED)", 8.5, bold=True, fill="#b4451f")

# Quotient Shift & Bit Insert Unit
f.box(820, 438, 310, 76, [
    "next_quo[31:0] = {quo_reg[30:0], ~borrow}",
    "Shifts quotient register left by 1 bit and",
    "inserts inverted borrow bit (~borrow) at LSB"
], kind="new", title="Quotient Shift & Bit Insert", size=9)

# Wires into Restoring MUX and Quotient Shift Unit
f.arrow([(680, 404), (680, 420), (615, 455)], label="trial_sub[31:0]", lp=(660, 412), lsize=8)
f.arrow([(540, 302), (540, 500), (615, 500)], label="shifted_rem[31:0]", lp=(540, 410), lsize=8)

# Borrow wire routing to MUX select and Inverter
f.arrow([(1110, 404), (1110, 430), (632, 430)], dot=[(1110, 430)])
f.text(910, 423, "borrow select", 8.5, halo=True)
f.arrow([(1110, 430), (1110, 475), (1130, 475)], label="borrow", lp=(1120, 450), lsize=8)
f.box(1130, 460, 28, 30, ["~"], kind="plain", shadow=0, size=11)
f.arrow([(1158, 475), (1175, 475), (1175, 525), (975, 525), (975, 514)], label="~borrow (quotient bit)", lp=(1075, 535), lsize=8)

# Recurrence Loop State Update
loop_lines = [
    "rem_reg <= next_rem (Restored remainder or trial subtraction)",
    "quo_reg <= next_quo (Quotient shifts left, appends ~borrow at bit 0)",
    "Feedback loop iterates exactly once per cycle across 32 clocks",
    "Generates exactly 1 quotient bit per cycle (bits 31 downto 0)",
]
f.box(515, 555, 425, 95, loop_lines, title="Recurrence Loop State Update (Cycles 2–32 ▲)", size=9, align="left")

# Iteration Counter
f.box(960, 555, 235, 95, [
    "Counts 32 iterations (div_cnt: 0 → 31)",
    "while (div_cnt < 5'd31): loop continues",
    "div_cnt == 5'd31: evaluates final 32nd step,",
    "latches result_reg and moves to STATE_DONE"
], title="Iteration Counter (div_cnt[4:0])", size=9, align="left")

# Wires from MUX & Shift Unit into State Update
f.arrow([(650, 476), (700, 476), (700, 555)], label="next_rem[31:0]", lp=(700, 520), lsize=8)
f.arrow([(920, 514), (920, 555)], label="next_quo[31:0]", lp=(920, 535), lsize=8)

# Recurrence Feedback Loops back to top registers (Dashed animated style)
f.arrow([(515, 600), (498, 600), (498, 170), (515, 170)], dashed=True, width=1.5, color=NAVY, label="32-Cycle Loop Remainder Feedback", lp=(498, 380), lsize=8.5, lrot=-90)
f.arrow([(735, 600), (735, 170), (750, 170)], dashed=True, width=1.5, color=NAVY, label="32-Cycle Loop Quotient Feedback", lp=(735, 380), lsize=8.5, lrot=-90)

# Bottom Timing Breakdown Banner
timing_lines = [
    "Cycle 1: STATE_IDLE -> STATE_DIV operand conditioning, abs(op1), abs(op2), predicate latches, reg init (div_cnt <= 0)",
    "Cycles 2–32: 31 clocked restoring iterations (div_cnt: 0 -> 30) generating bits 31 downto 1 while pipeline stalls (m_stalling=1)",
    "Cycle 33: div_cnt == 31 evaluates combinational 32nd step (bit 0) + RISC-V exception MUX -> result_reg <= final_div_result; state <= STATE_DONE",
    "Cycle 34: STATE_DONE asserts done=1, busy=0 -> releases m_stalling -> CPU captures result into EX/WB register on posedge clk"
]
f.box(515, 680, 680, 110, timing_lines, kind="plain", title="Hardware Timing Breakdown: 32 Restoring Iterations · 33 Compute Clocks · 34 Pipeline Clocks", size=8.5, align="left")

# =========================================================================
# STAGE 3 REGION: POST-PROCESS, SIGN CORRECTION & EXCEPTIONS (CYCLES 33–34)
# =========================================================================
f.region(1245, 86, 480, 844, "STAGE 3: POST-PROCESS, SIGN CORRECTION & EXCEPTIONS (CYCLES 33–34)", color=NAVY)
f.text(1255, 118, "Two's Complement Correction · RISC-V Exception Priority MUX · Output Handshake", 9.5, italic=True, fill="#555")

# Sign Negators
f.box(1265, 136, 120, 50, ["~final_quo_u + 1", "32-bit negator"], title="- final_quo_u", size=9)
f.box(1265, 218, 120, 50, ["~final_rem_u + 1", "32-bit negator"], title="- final_rem_u", size=9)

# Sign Correction 2:1 MUXes
draw_mux(1420, 132, 28, 56, sel_text="neg_quo", p1_text="1: -quo_u", p0_text="0: quo_u")
draw_mux(1420, 214, 28, 56, sel_text="neg_rem", p1_text="1: -rem_u", p0_text="0: rem_u")

# Wires from Stage 2 into Stage 3
f.arrow([(1130, 455), (1225, 455), (1225, 160), (1265, 160)], label="final_quo_u = next_quo", lp=(1225, 300), lsize=8, lrot=-90)
f.arrow([(1225, 160), (1245, 160), (1245, 178), (1420, 178)], dot=[(1225, 160)])
f.arrow([(1385, 160), (1420, 160)])

f.arrow([(700, 476), (700, 485), (1235, 485), (1235, 242), (1265, 242)], label="final_rem_u = next_rem", lp=(1235, 360), lsize=8, lrot=-90)
f.arrow([(1235, 242), (1245, 242), (1245, 260), (1420, 260)], dot=[(1235, 242)])
f.arrow([(1385, 242), (1420, 242)])

# Sign Summary Box
f.box(1480, 136, 225, 132, [
    "DIV / REM: Uses 2's complement",
    "negated values (final_quo / final_rem)",
    "DIVU / REMU: Bypasses negation directly",
    "(final_quo_u / final_rem_u)",
    "Strict IEEE & RISC-V signed quotient rule:",
    "sign(Q) = sign(op1) XOR sign(op2)",
    "sign(R) = sign(op1)"
], title="Signed / Unsigned Select", size=8.5, align="left")

# RISC-V Priority Exception Multiplexer
mux_lines = [
    "1. if (div_zero): [Division by zero rule]",
    "     DIV / DIVU → 32'hFFFF_FFFF (-1 signed / 2^32 - 1 unsigned)",
    "     REM / REMU → orig_op1 (Preserves dividend unaltered)",
    "",
    "2. else if (overflow): [Signed overflow rule: INT_MIN / -1]",
    "     DIV        → 32'h8000_0000 (INT_MIN unaltered)",
    "     REM        → 32'h0000_0000 (Zero remainder)",
    "",
    "3. else: [Normal Arithmetic]",
    "     DIV  → final_quo   |  DIVU → final_quo_u",
    "     REM  → final_rem   |  REMU → final_rem_u"
]
f.box(1265, 305, 440, 250, mux_lines, kind="new", title="RISC-V Priority Exception Multiplexer (final_div_result)", size=9, align="left")

# Wires from Sign MUXes into Priority Exception MUX
f.arrow([(1448, 160), (1465, 160), (1465, 305)], label="final_quo", lp=(1465, 230), lsize=8)
f.arrow([(1448, 242), (1475, 242), (1475, 305)], label="final_rem", lp=(1475, 275), lsize=8)

# Architectural Result Register (Cycle 33)
res_lines = [
    "result_reg <= final_div_result",
    "Latched on posedge clk at div_cnt == 5'd31 when transitioning to STATE_DONE",
    "Held stable throughout pipeline handshake while state == STATE_DONE",
    "Directly drives architectural output: assign result = result_reg"
]
f.box(1265, 585, 440, 95, res_lines, kind="new", title="Architectural Result Register (Cycle 33 ▲)", size=9, align="left")

f.arrow([(1485, 555), (1485, 585)], label="final_div_result[31:0]", lp=(1485, 570), lsize=8.5)

# Pipeline Handshake (Cycle 34)
handshake_lines = [
    "done = (state == STATE_DONE) [Asserted on Cycle 34]",
    "busy = (state == STATE_MULT) || (state == STATE_DIV) [Deasserted 1'b0]",
    "Deasserts m_stalling in cpu_core.v -> stall_pipeline deasserts (0)",
    "CPU pipeline captures result_reg into EX/WB register on posedge clk",
    "Unit returns to STATE_IDLE when !stall_pipeline"
]
f.box(1265, 710, 440, 100, handshake_lines, title="Pipeline Handshake & Stall Release (Cycle 34)", size=9, align="left")

f.arrow([(1485, 680), (1485, 710)], label="Moves to STATE_DONE", lp=(1485, 695), lsize=8.5)

# Architectural Ports exiting Stage 3
f.arrow([(1705, 632), (1735, 632)], label="result[31:0] (to EX Stage ex_result MUX)", lp=(1720, 620), lsize=8, anchor="end")
f.arrow([(1705, 745), (1735, 745)], label="done (to Hazard Unit)", lp=(1720, 735), lsize=8, anchor="end")
f.arrow([(1705, 775), (1735, 775)], label="busy (to Stall Logic)", lp=(1720, 765), lsize=8, anchor="end")

# Write out SVG
out_path = os.path.join(os.path.dirname(__file__), "fig4_divider.svg")
with open(out_path, "w") as fp:
    fp.write(f.svg())

print(f"Generated clean SVG: {out_path}")
