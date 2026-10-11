import re
from dg import Fig, NAVY, GREY

# parse the simulation log
T = {}
for ln in open("trace/trace.log"):
    m = re.match(r"T (\d+) ", ln)
    if not m:
        continue
    d = dict(kv.split("=") for kv in ln.split()[2:])
    T[int(m.group(1))] = d

HEAD = list(range(0, 25))          # shown in full (T0 to T24 = 25 cycles)
TAIL = [53, 54, 55, 56]            # after the divider has iterated (4 cycles)
COLS = HEAD + [None] + TAIL        # None = axis break
CW = 43
X0 = 340
def cx(t):
    return X0 + COLS.index(t) * CW
BRK = X0 + COLS.index(None) * CW

f = Fig(1750, 1180)
f.defs.append('<pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" '
              'patternTransform="rotate(45)"><rect width="6" height="6" fill="#f4f4f4"/>'
              '<line x1="0" y1="0" x2="0" y2="6" stroke="#8a8a8a" stroke-width="1.3"/></pattern>')
f.defs.append('<pattern id="flush_hatch" width="6" height="6" patternUnits="userSpaceOnUse" '
              'patternTransform="rotate(45)"><rect width="6" height="6" fill="#ffebee"/>'
              '<line x1="0" y1="0" x2="0" y2="6" stroke="#e53935" stroke-width="1.3"/></pattern>')
f.defs.append('<pattern id="stall_hatch" width="6" height="6" patternUnits="userSpaceOnUse" '
              'patternTransform="rotate(45)"><rect width="6" height="6" fill="#fff3e0"/>'
              '<line x1="0" y1="0" x2="0" y2="6" stroke="#fb8c00" stroke-width="1.3"/></pattern>')

f.title("Figure 3 - Pipeline Timing: EX-to-EX Forwarding, Load-ALU Stall, Bus Wait & RV32M Multi-Cycle Ops",
        "Exact cycle-by-cycle trace from cpu_core + sys_bus_interconnect + imem/dmem slaves  |  "
        "1 Cycle = 1 Clock Period (10 ns @ 100 MHz)  |  Stages: IF/ID (Fetch+Decode), EX (Execute/M-Unit), MEM/WB (Bus/Writeback)")

PROG = [
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
]

HEX = ["00700093", "00208113", "200002b7", "022081b3", "00118233", "0042a023", "0002a303",
       "001303b3", "00000663", "00100413", "00200593", "022244b3", "00148513"]

h = lambda *a: {t: "hold" for t in a}
R = {
    0: {0: "id", 1: "ex", 2: "wb"},
    1: {1: "id", 2: "ex", 3: "wb"},
    2: {2: "id", 3: "ex", 4: "wb", **h(5, 6, 7)},
    3: {3: "id", 4: "mex", 5: "mex", 6: "mex", 7: "mex", 8: "wb"},
    4: {4: "id", **h(5, 6, 7), 8: "ex", 9: "wb"},
    5: {8: "fetch", 9: "id", 10: "ex", 11: "wb", **h(12, 13, 14, 15)},
    6: {10: "id", 11: "ex", **h(12, 13, 14, 15), 16: "wb"},
    7: {11: "id", **{t: "stall" for t in (12, 13, 14, 15)}, 16: "ex", 17: "wb"}, # explicitly load-ALU stall
    8: {16: "fetch", 17: "id", 18: "ex", 19: "wb"},
    9: {18: "id", 19: "flush", 20: "flush"},
    10: {19: "id", 20: "flush", 21: "flush"},
    11: {20: "id", **{t: "mex" for t in (21, 22, 23, 24, 53, 54)}, 55: "wb"},
    12: {21: "id", **h(22, 23, 24, 53, 54), 55: "ex", 56: "wb"},
}

GY, RH = 125, 27
NR = len(PROG)
WY0 = GY + NR * RH + 48
ry = lambda r: GY + r * RH

# Header columns
f.text(40, GY - 14, "PC", 10.5, True)
f.text(85, GY - 14, "Instruction & Operations", 10.5, True)

for t in HEAD + TAIL:
    f.text(cx(t) + CW / 2, GY - 14, f"T{t}", 9, True, "middle")

# Vertical grid lines
for t in HEAD + TAIL + [None]:
    xx = cx(t) if t is not None else BRK
    f.raw(f'<line x1="{xx}" y1="{GY-6}" x2="{xx}" y2="{WY0+10*26}" stroke="#e0e0e0"/>')
f.raw(f'<line x1="{cx(56)+CW}" y1="{GY-6}" x2="{cx(56)+CW}" y2="{WY0+10*26}" stroke="#e0e0e0"/>')

# Draw Program Rows
for r, (pc, ins, note) in enumerate(PROG):
    y = ry(r)
    f.raw(f'<line x1="40" y1="{y}" x2="{cx(56)+CW}" y2="{y}" stroke="#dcdcdc"/>')
    f.text(40, y + 18, pc, 9.5, True, fill="#333333")
    f.text(85, y + 18, ins, 10, True, fill="#111111")
    # Draw gantt cells
    cells = R.get(r, {})
    for t in HEAD + TAIL:
        if t not in cells:
            continue
        st = cells[t]
        x = cx(t)
        fill_col = "#ffffff"
        text_col = "#1a1a1a"
        lbl = ""
        border_col = "#1a1a1a"
        if st == "id":
            fill_col = "#e8eaf6"
            lbl = "ID"
        elif st == "ex":
            fill_col = "#c8e6c9"
            lbl = "EX"
        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M"
        elif st == "wb":
            fill_col = "#ffe0b2"
            lbl = "WB"
        elif st == "hold":
            fill_col = "url(#hatch)"
            border_col = "#888888"
            lbl = "-"
            text_col = "#777777"
        elif st == "stall":
            fill_col = "url(#stall_hatch)"
            border_col = "#e65100"
            lbl = "STALL"
            text_col = "#bf360c"
        elif st == "flush":
            fill_col = "url(#flush_hatch)"
            border_col = "#e53935"
            lbl = "FLUSH"
            text_col = "#c62828"
        elif st == "fetch":
            fill_col = "#f3e5f5"
            lbl = "IF"

        f.raw(f'<rect x="{x+1}" y="{y+2}" width="{CW-2}" height="{RH-4}" rx="2" fill="{fill_col}" stroke="{border_col}" stroke-width="0.9"/>')
        f.text(x + CW / 2, y + 17, lbl, 8.5 if len(lbl)<=2 else 6.5, True, "middle", fill=text_col)

f.raw(f'<line x1="40" y1="{ry(NR)}" x2="{cx(56)+CW}" y2="{ry(NR)}" stroke="#dcdcdc"/>')

# Axis break column
f.raw(f'<rect x="{BRK}" y="{GY-6}" width="{CW}" height="{RH*NR+10}" fill="#ffffff"/>')
f.text(BRK + CW / 2, GY + 180, "T25 - T52: Radix-2 Divider (33 cyc stall)", 8.5, False, "middle", rot=-90, fill="#666666")
for yy in (GY - 6, ry(NR) + 4):
    f.raw(f'<path d="M{BRK+8},{yy} l8,-6 l8,12 l8,-12" fill="none" stroke="#1a1a1a"/>')

# Dashed continuation lines across break for multi-cycle div / wait
for r in (11, 12):
    f.raw(f'<line x1="{cx(24)+CW}" y1="{ry(r)+14}" x2="{cx(53)}" y2="{ry(r)+14}" stroke="#004870" stroke-dasharray="3 3" stroke-width="1.5"/>')

# ----------------- CLEAN ANNOTATIONS & EX-TO-EX FORWARDING PATHS -----------------
# Forwarding helper to draw clean orthogonal routed arrows with non-overlapping badges
def draw_forward_arrow(fx, fy, tx, ty, label, offset_x=14, badge_x=None, badge_y=None, badge_side="right"):
    # fx, fy: source center point (bottom of producing stage)
    # tx, ty: destination center point (top of consuming stage)
    mid_x = tx - offset_x
    pts = f"M{fx},{fy} L{mid_x},{fy+4} L{mid_x},{ty-4} L{tx-2},{ty}"
    f.raw(f'<path d="{pts}" fill="none" stroke="#2e7d32" stroke-width="1.8" marker-end="url(#ah)"/>')
    # Draw a clean pill badge for the label
    bx = badge_x if badge_x is not None else (mid_x - 35 if badge_side=="left" else tx + 4)
    by = badge_y if badge_y is not None else ty - 8
    bw = len(label) * 5.8 + 12
    bh = 15
    f.raw(f'<rect x="{bx}" y="{by-10}" width="{bw}" height="{bh}" rx="3" fill="#e8f5e9" stroke="#2e7d32" stroke-width="0.8"/>')
    f.text(bx + bw/2, by + 1, label, 7.5, True, "middle", fill="#1b5e20")

# 1. Forwarding from addi x1 EX (T1) -> addi x2 EX (T2) : EX-to-EX Forwarding
# Source: T1 EX right/bottom (cx(1)+CW, ry(0)+RH/2) or T2 start
draw_forward_arrow(cx(1)+CW-4, ry(0)+RH, cx(2)+8, ry(1)+2, "EX to EX (x1)", offset_x=12, badge_x=cx(2)+CW+4, badge_y=ry(1)+6)

# 2. MUL multi-cycle badge
f.raw(f'<rect x="{cx(4)+2}" y="{ry(2)+RH+1}" width="168" height="15" rx="3" fill="#e1f5fe" stroke="#0288d1" stroke-width="0.8"/>')
f.text(cx(4)+86, ry(2)+RH+11, "MUL 4-cyc Multi-Cycle EX (m_busy=1)", 7.5, True, "middle", fill="#01579b")

# 3. Forwarding from MUL x3 EX (T7) -> add x4 EX (T8) : EX-to-EX Forwarding
draw_forward_arrow(cx(7)+CW-4, ry(3)+RH, cx(8)+8, ry(4)+2, "EX to EX (x3)", offset_x=12, badge_x=cx(8)+CW+4, badge_y=ry(4)+6)

# 4. Bus stall during load badge (T11..T15)
f.raw(f'<rect x="{cx(11)+2}" y="{ry(5)+RH+1}" width="206" height="15" rx="3" fill="#fff3e0" stroke="#f57c00" stroke-width="0.8"/>')
f.text(cx(11)+105, ry(5)+RH+11, "DMEM Load Stall: 4 cycles bus latency", 7.5, True, "middle", fill="#e65100")

# 5. Load-ALU Hazard & Forwarding from LW x6 EX/MEM (T15) -> add x7 EX (T16) : MEM-to-EX / EX-to-EX Forwarding
draw_forward_arrow(cx(15)+CW-4, ry(6)+RH, cx(16)+8, ry(7)+2, "EX to EX (x6)", offset_x=12, badge_x=cx(16)+CW+4, badge_y=ry(7)+6)
# Load-ALU Stall callout badge
f.raw(f'<rect x="{cx(12)+4}" y="{ry(7)+RH+2}" width="155" height="16" rx="3" fill="#fbe9e7" stroke="#d84315" stroke-width="0.9"/>')
f.text(cx(12)+81, ry(7)+RH+13, "LOAD-ALU STALL (Hold until data ready)", 7.2, True, "middle", fill="#bf360c")

# 6. Branch Taken callout (T18) & Squashed instructions
f.raw(f'<rect x="{cx(18)+2}" y="{ry(7)+RH+2}" width="145" height="15" rx="3" fill="#ffebee" stroke="#c62828" stroke-width="0.8"/>')
f.text(cx(18)+74, ry(7)+RH+12, "Branch Taken (Target 0x2c)", 7.5, True, "middle", fill="#b71c1c")

# 7. DIV stall & forward to addi x10 at T55 : EX-to-EX Forwarding
draw_forward_arrow(cx(54)+CW-4, ry(11)+RH, cx(55)+8, ry(12)+2, "EX to EX (x9)", offset_x=12, badge_x=cx(55)+CW+4, badge_y=ry(12)+6)


# ----------------- Bottom: Hardware Signal Waveforms -----------------
f.raw(f'<rect x="40" y="{WY0-30}" width="1660" height="22" fill="#eceff1" rx="3"/>')
f.text(48, WY0 - 15, "HARDWARE CONTROL SIGNALS & BUS PROTOCOL (RTL cycle-accurate waveforms from sim)", 10.5, True, fill="#263238")

SIGNALS = [
    ("clk",             "1-bit", "System Clock (100 MHz)"),
    ("stall_pipeline",  "1-bit", "Global pipeline freeze"),
    ("m_start",         "1-bit", "RV32M unit trigger pulse"),
    ("m_busy",          "1-bit", "RV32M internal compute active"),
    ("m_done",          "1-bit", "RV32M operation complete"),
    ("fwd_a / fwd_b",   "bits",  "EX-to-EX forwarding multiplexer selects"),
    ("bus_req_valid",   "1-bit", "Interconnect bus request"),
    ("bus_rsp_valid",   "1-bit", "Interconnect slave response"),
    ("branch_taken",    "1-bit", "Branch evaluate true (EX)"),
    ("wb_stall",        "1-bit", "Bus load/store wait in WB stage"),
]

SY0 = WY0 + 10
SH = 26

for idx, (sig_name, sig_type, desc) in enumerate(SIGNALS):
    sy = SY0 + idx * SH
    f.raw(f'<line x1="40" y1="{sy}" x2="{cx(56)+CW}" y2="{sy}" stroke="#eeeeee"/>')
    f.text(40, sy + 18, sig_name, 10, True, fill="#004870")
    f.text(170, sy + 18, desc, 8.5, False, fill="#666666")

    # Render digital waveform across columns
    for t in HEAD + TAIL:
        x = cx(t)
        mid_y = sy + 6
        hi_y = sy + 4
        lo_y = sy + 20

        # evaluate signal value at cycle t
        if sig_name == "clk":
            f.raw(f'<polyline points="{x},{lo_y} {x},{hi_y} {x+CW/2},{hi_y} {x+CW/2},{lo_y} {x+CW},{lo_y}" fill="none" stroke="#37474f" stroke-width="1.2"/>')
        elif sig_name == "stall_pipeline":
            v = T[t]["stall"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#d32f2f" stroke-width="1.6"/>')
        elif sig_name == "m_start":
            v = T[t]["mst"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#0277bd" stroke-width="1.6"/>')
        elif sig_name == "m_busy":
            v = T[t]["mbusy"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#0277bd" stroke-width="1.6"/>')
        elif sig_name == "m_done":
            v = T[t]["mdone"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#2e7d32" stroke-width="1.6"/>')
        elif sig_name == "fwd_a / fwd_b":
            v1 = T[t]["fw1"] == "1"
            v2 = T[t]["fw2"] == "1"
            v = v1 or v2
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#2e7d32" stroke-width="1.6"/>')
            if v:
                f.text(x + CW/2, hi_y - 2, "EX-EX", 7, True, "middle", fill="#2e7d32")
        elif sig_name == "bus_req_valid":
            v = T[t]["rv"] == "1" and T[t]["bst"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#ef6c00" stroke-width="1.6"/>')
        elif sig_name == "bus_rsp_valid":
            v = T[t]["rv"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#ef6c00" stroke-width="1.6"/>')
        elif sig_name == "branch_taken":
            v = T[t]["bt"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#c62828" stroke-width="1.6"/>')
        elif sig_name == "wb_stall":
            v = T[t]["wbst"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#d84315" stroke-width="1.6"/>')

# Legend and Stage Color Key box
KY = SY0 + len(SIGNALS) * SH + 15
f.box(40, KY, 1660, 56, kind="plain", shadow=0)
f.text(48, KY + 16, "Stage Key:", 9.5, True)
stages = [
    ("IF/ID (Fetch/Decode)", "#e8eaf6", "#1a1a1a"),
    ("EX (Single-cycle ALU)", "#c8e6c9", "#1a1a1a"),
    ("M (RV32M Multi-cycle EX)", "#004870", "#ffffff"),
    ("MEM/WB (Writeback)", "#ffe0b2", "#1a1a1a"),
    ("Load-ALU Stall (Bubble)", "url(#stall_hatch)", "#bf360c"),
    ("Pipeline Freeze / Bus Hold", "url(#hatch)", "#555555"),
    ("Flushed (Branch Squash)", "url(#flush_hatch)", "#c62828")
]
kx = 130
for name, col, tcol in stages:
    f.raw(f'<rect x="{kx}" y="{KY+5}" width="24" height="15" fill="{col}" stroke="#888888" stroke-width="0.8"/>')
    f.text(kx + 30, KY + 17, name, 8.5, False, fill="#333333")
    kx += len(name) * 5.8 + 48

f.text(48, KY + 40, "Key Architectural Features: (1) EX-to-EX Forwarding bypasses calculated results directly from end-of-EX into the dependent EX stage without bubble. (2) Load-ALU Hazard inserts a hardware stall until memory load returns. (3) RV32M pipelined multiplier executes in 4 cycles; divider executes in 34 cycles. (4) Taken branches squash speculatively fetched wrong-path instructions.", 8, italic=True, fill="#444444")

open("fig3_timing.svg", "w").write(f.svg())
print("Successfully wrote cleaned fig3_timing.svg")
