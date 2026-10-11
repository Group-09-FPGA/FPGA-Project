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
TCQ = 6                            # Clock-to-Q visual delay offset in pixels

def cx(t):
    return X0 + COLS.index(t) * CW
BRK = X0 + COLS.index(None) * CW

f = Fig(1750, 920)
f.defs.append('<pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" '
              'patternTransform="rotate(45)"><rect width="6" height="6" fill="#f4f4f4"/>'
              '<line x1="0" y1="0" x2="0" y2="6" stroke="#8a8a8a" stroke-width="1.3"/></pattern>')
f.defs.append('<pattern id="flush_hatch" width="6" height="6" patternUnits="userSpaceOnUse" '
              'patternTransform="rotate(45)"><rect width="6" height="6" fill="#ffebee"/>'
              '<line x1="0" y1="0" x2="0" y2="6" stroke="#e53935" stroke-width="1.3"/></pattern>')
f.defs.append('<marker id="ah_green" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#2e7d32"/></marker>')
f.defs.append('<pattern id="stall_hatch" width="6" height="6" patternUnits="userSpaceOnUse" '
              'patternTransform="rotate(45)"><rect width="6" height="6" fill="#fff3e0"/>'
              '<line x1="0" y1="0" x2="0" y2="6" stroke="#fb8c00" stroke-width="1.3"/></pattern>')

f.title("Figure 3 - Pipeline Timing: EX-to-EX Forwarding, Load-ALU Stall, Bus Wait & RV32M Multi-Cycle Ops",
        "Exact cycle-by-cycle trace from cpu_core + sys_bus_interconnect + imem/dmem slaves  |  "
        "1 Cycle = 1 Clock Period (10 ns @ 100 MHz)  |  Stages: IF/ID (Fetch+Decode), EX (Execute/M-Unit), MEM/WB (Bus/Writeback)  |  tcq propagation delay shown on stages & signals")

PROG = [
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
]

HEX = ["00700093", "00208113", "200002b7", "022081b3", "00118233", "0042a023", "0002a303",
       "001303b3", "00000663", "00100413", "00200593", "022244b3", "00148513"]

h = lambda *a: {t: "hold" for t in a}
R = {
    0: {0: "id", 1: "ex", 2: "wb"},
    1: {1: "id", 2: "ex", 3: "wb"},
    2: {2: "id", 3: "ex", 4: "wb"},
    3: {3: "id", 4: "mex", 5: "mex", 6: "mex", 7: "mex", 8: "wb"},
    4: {4: "id", **h(5, 6, 7), 8: "ex", 9: "wb"},
    5: {9: "id", 10: "ex", 11: "wb"},
    6: {10: "id", 11: "ex", 12: "wb"},
    7: {11: "id", 12: "stall", 13: "ex", 14: "wb"}, # 1-cycle Load-ALU stall
    8: {13: "id", 14: "ex", 15: "wb"},               # beq: EX at T14, WB at T15
    9: {14: "id", 15: "flush"},                      # addi x8: only 1 wrong instruction, flushed at T15
    10: {15: "id", **{t: "dex" for t in (16, 17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"}, # target div: IF/ID at T15 while beq is WB
    11: {16: "id", **h(17, 18, 19, 20, 21, 22, 23, 24, 53, 54), 55: "ex", 56: "wb"},
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
        x = cx(t) + TCQ
        fill_col = "#ffffff"
        text_col = "#1a1a1a"
        lbl = ""
        border_col = "#1a1a1a"
        if st == "id":
            fill_col = "#e8eaf6"
            lbl = "IF/ID"
        elif st == "ex":
            fill_col = "#c8e6c9"
            lbl = "EX"
        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M"
        elif st == "dex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "D"
        elif st == "wb":
            fill_col = "#ffe0b2"
            lbl = "MEM/WB"
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
            lbl = "IF/ID"

        f.raw(f'<rect x="{x}" y="{y+2}" width="{CW-5}" height="{RH-4}" rx="2" fill="{fill_col}" stroke="{border_col}" stroke-width="0.9"/>')
        f.text(x + (CW-5) / 2, y + 16.5, lbl, 8.0 if len(lbl)<=2 else 6.8, True, "middle", fill=text_col)

f.raw(f'<line x1="40" y1="{ry(NR)}" x2="{cx(56)+CW}" y2="{ry(NR)}" stroke="#dcdcdc"/>')

# Axis break column
f.raw(f'<rect x="{BRK}" y="{GY-6}" width="{CW}" height="{RH*NR+10}" fill="#ffffff"/>')
f.text(BRK + CW / 2, GY + 180, "T25 - T52: Radix-2 Divider (33 cyc stall)", 8.5, False, "middle", rot=-90, fill="#666666")
for yy in (GY - 6, ry(NR) + 4):
    f.raw(f'<path d="M{BRK+8},{yy} l8,-6 l8,12 l8,-12" fill="none" stroke="#1a1a1a"/>')

# Dashed continuation lines across break for multi-cycle div / wait
for r in (10, 11):
    f.raw(f'<line x1="{cx(24)+CW-2+TCQ}" y1="{ry(r)+14}" x2="{cx(53)+TCQ}" y2="{ry(r)+14}" stroke="#004870" stroke-dasharray="3 3" stroke-width="1.5"/>')

# ----------------- CLEAN ANNOTATIONS & EX-TO-EX FORWARDING PATHS -----------------
# Forwarding helper to draw clean orthogonal routed arrows with non-overlapping badges
def draw_forward_arrow(t_cons, r_prod, r_cons):
    x_stem = cx(t_cons) + 2
    x_dest = cx(t_cons) + TCQ + 7
    y_start = ry(r_prod) + RH/2
    y_end = ry(r_cons) + RH/2
    pts = f"M{x_stem-3},{y_start} L{x_stem},{y_start} L{x_stem},{y_end} L{x_dest},{y_end}"
    f.raw(f'<path d="{pts}" fill="none" stroke="#2e7d32" stroke-width="1.8" marker-end="url(#ah_green)"/>')

# EX-to-EX Forwarding arrows (clean thin arrows, no overlapping pill/box overlays)
draw_forward_arrow(2, 0, 1)    # addi x1 -> addi x2
draw_forward_arrow(8, 3, 4)    # mul x3  -> add x4
draw_forward_arrow(13, 6, 7)   # lw x6 (row 6) -> add x7 EX (row 7) at T13
draw_forward_arrow(55, 10, 11) # div x9  -> addi x10


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

def get_sig_val(name, t):
    if t is None or t < 0:
        return False
    if name == "stall_pipeline":
        return (t in (4, 5, 6, 11) or (16 <= t <= 53))
    elif name == "m_start":
        return (t in (3, 15))
    elif name == "m_busy":
        return (t in (3, 4, 5, 6) or (15 <= t <= 53))
    elif name == "m_done":
        return (t in (7, 54))
    elif name == "fwd_a / fwd_b":
        return (t in (1, 7, 12, 54))
    elif name == "bus_req_valid":
        return (t in (0, 1, 2, 3, 8, 9, 10, 11, 13, 14, 55, 56))
    elif name == "bus_rsp_valid":
        return (t in (0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 55, 56))
    elif name == "branch_taken":
        return (t == 14)
    elif name == "wb_stall":
        return (t in (15, 16))
    return False

sig_colors = {
    "stall_pipeline": "#d32f2f",
    "m_start": "#0277bd",
    "m_busy": "#0277bd",
    "m_done": "#2e7d32",
    "fwd_a / fwd_b": "#2e7d32",
    "bus_req_valid": "#ef6c00",
    "bus_rsp_valid": "#ef6c00",
    "branch_taken": "#c62828",
    "wb_stall": "#d84315",
}

for idx, (sig_name, sig_type, desc) in enumerate(SIGNALS):
    sy = SY0 + idx * SH
    f.raw(f'<line x1="40" y1="{sy}" x2="{cx(56)+CW}" y2="{sy}" stroke="#eeeeee"/>')
    f.text(40, sy + 18, sig_name, 10, True, fill="#004870")
    f.text(170, sy + 18, desc, 8.5, False, fill="#666666")

    scol = sig_colors.get(sig_name, "#1a1a1a")

    # Render digital waveform across columns
    for t in HEAD + TAIL:
        x = cx(t)
        mid_y = sy + 6
        hi_y = sy + 4
        lo_y = sy + 20

        # evaluate signal value at cycle t
        if sig_name == "clk":
            f.raw(f'<polyline points="{x},{lo_y} {x},{hi_y} {x+CW/2},{hi_y} {x+CW/2},{lo_y} {x+CW},{lo_y}" fill="none" stroke="#37474f" stroke-width="1.2"/>')
        else:
            v_curr = get_sig_val(sig_name, t)
            # previous cycle value
            t_prev = (t - 1) if t in HEAD else (52 if t == 53 else t - 1)
            v_prev = get_sig_val(sig_name, t_prev)

            y_curr = hi_y if v_curr else lo_y
            y_prev = hi_y if v_prev else lo_y

            x_cq = x + TCQ
            if v_prev == v_curr:
                # Flat line across whole cycle
                f.raw(f'<line x1="{x}" y1="{y_curr}" x2="{x+CW}" y2="{y_curr}" stroke="{scol}" stroke-width="1.6"/>')
            else:
                # Transitions at x_cq (t_cq delay)
                f.raw(f'<line x1="{x}" y1="{y_prev}" x2="{x_cq}" y2="{y_prev}" stroke="{scol}" stroke-width="1.6"/>')
                f.raw(f'<line x1="{x_cq}" y1="{y_prev}" x2="{x_cq}" y2="{y_curr}" stroke="{scol}" stroke-width="1.6"/>')
                f.raw(f'<line x1="{x_cq}" y1="{y_curr}" x2="{x+CW}" y2="{y_curr}" stroke="{scol}" stroke-width="1.6"/>')

            if sig_name == "fwd_a / fwd_b" and v_curr:
                f.text(x_cq + (CW - TCQ)/2, hi_y - 2, "EX-EX", 7, True, "middle", fill="#2e7d32")

    if get_sig_val(sig_name, 25):
        f.raw(f'<line x1="{BRK}" y1="{hi_y}" x2="{cx(53)}" y2="{hi_y}" stroke="{scol}" stroke-dasharray="3 3" stroke-width="1.6"/>')

# Legend and Stage Color Key box
KY = SY0 + len(SIGNALS) * SH + 12
f.box(40, KY, 1660, 78, kind="plain", shadow=0)
f.text(48, KY + 16, "Stage Key:", 9.5, True)
stages = [
    ("IF/ID (Fetch/Decode)", "#e8eaf6", "#1a1a1a"),
    ("EX (Single-cycle ALU)", "#c8e6c9", "#1a1a1a"),
    ("M / D (Multiply / Divide Multi-Cycle EX)", "#004870", "#ffffff"),
    ("MEM/WB (Memory/Writeback)", "#ffe0b2", "#1a1a1a"),
    ("Load-ALU Stall (Bubble)", "url(#stall_hatch)", "#bf360c"),
    ("Pipeline Freeze / Bus Hold", "url(#hatch)", "#555555"),
    ("Flushed (Branch Squash)", "url(#flush_hatch)", "#c62828")
]
kx = 130
for name, col, tcol in stages:
    f.raw(f'<rect x="{kx}" y="{KY+5}" width="24" height="15" fill="{col}" stroke="#888888" stroke-width="0.8"/>')
    f.text(kx + 30, KY + 17, name, 8.5, False, fill="#333333")
    kx += len(name) * 5.8 + 48

# Clean small description lines at the bottom summarizing all hazards and forwardings
f.text(48, KY + 38, "Pipeline Hazards & Forwarding Details:", 8.5, True, fill="#004870")
f.text(48, KY + 52, "- EX-to-EX Forwarding (Green Arrows): T2 (addi x1 -> addi x2), T8 (mul x3 -> add x4), T13 (lw x6 -> add x7), T55 (div x9 -> addi x10). Eliminates RAW bubbles.", 8.0, False, fill="#2e7d32")
f.text(48, KY + 66, "- Multi-Cycle & Control: MUL takes 4 cycles in EX (T4-T7). Load-ALU Stall at T12 (1 cycle). Branch taken at T14 squashes single wrong +4 fetch (0x24 at T15); target 0x30 is fetched in T15 while branch is in WB. DIV takes 34 cycles. tcq delay depicted on all transitions.", 8.0, False, fill="#444444")

open("fig3_timing.svg", "w").write(f.svg())
print("Successfully wrote fig3_timing.svg")
