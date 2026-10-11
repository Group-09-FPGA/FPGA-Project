with open("fig3_timing.py") as f:
    code = f.read()

# Replace draw_forward_arrow and all overlay boxes
old_block = """def draw_forward_arrow(t_cons, r_prod, r_cons, label):
    x_line = cx(t_cons)
    y_start = ry(r_prod) + RH/2
    y_end = ry(r_cons) + RH/2
    pts = f"M{x_line-1},{y_start} L{x_line+3},{y_start} L{x_line+3},{y_end} L{x_line+6},{y_end}"
    f.raw(f'<path d="{pts}" fill="none" stroke="#2e7d32" stroke-width="1.8" marker-end="url(#ah)"/>')
    bw = len(label) * 5.4 + 10
    bh = 13
    bx = x_line + CW + 4
    by = ry(r_cons) + RH/2
    f.raw(f'<rect x="{bx}" y="{by-9}" width="{bw}" height="{bh}" rx="2" fill="#e8f5e9" stroke="#2e7d32" stroke-width="0.8"/>')
    f.text(bx + bw/2, by, label, 7.0, True, "middle", fill="#1b5e20")

# 1. Forwarding from addi x1 EX (T1) -> addi x2 EX (T2) : EX-to-EX Forwarding
draw_forward_arrow(2, 0, 1, "EX to EX (x1)")

# 2. MUL multi-cycle label (placed cleanly in instruction column)
f.raw(f'<rect x="85" y="{ry(3)+15}" width="186" height="13" rx="2" fill="#e1f5fe" stroke="#0288d1" stroke-width="0.8"/>')
f.text(85 + 93, ry(3)+24, "MUL 4-cyc Multi-Cycle EX (m_busy=1)", 7.2, True, "middle", fill="#01579b")

# 3. Forwarding from MUL x3 EX (T7) -> add x4 EX (T8) : EX-to-EX Forwarding
draw_forward_arrow(8, 3, 4, "EX to EX (x3)")

# 4. Bus stall during load badge (placed cleanly in instruction column)
f.raw(f'<rect x="85" y="{ry(6)+15}" width="186" height="13" rx="2" fill="#fff3e0" stroke="#f57c00" stroke-width="0.8"/>')
f.text(85 + 93, ry(6)+24, "DMEM Load Stall: 4-cycle bus latency", 7.2, True, "middle", fill="#e65100")

# 5. Load-ALU Hazard & Forwarding from LW x6 EX/MEM (T15) -> add x7 EX (T16) : EX-to-EX Forwarding
draw_forward_arrow(16, 6, 7, "EX to EX (x6)")
# Load-ALU Stall callout badge
f.raw(f'<rect x="{cx(12)}" y="{ry(7)+RH+1}" width="168" height="13" rx="2" fill="#fbe9e7" stroke="#d84315" stroke-width="0.8"/>')
f.text(cx(12)+84, ry(7)+RH+10, "LOAD-ALU STALL (Wait for data)", 7.2, True, "middle", fill="#bf360c")

# 6. Branch Taken callout
f.raw(f'<rect x="85" y="{ry(8)+15}" width="160" height="13" rx="2" fill="#ffebee" stroke="#c62828" stroke-width="0.8"/>')
f.text(85 + 80, ry(8)+24, "Branch Taken (Target 0x2c)", 7.2, True, "middle", fill="#b71c1c")

# 7. DIV stall & forward to addi x10 at T55 : EX-to-EX Forwarding
draw_forward_arrow(55, 11, 12, "EX to EX (x9)")"""

new_block = """def draw_forward_arrow(t_cons, r_prod, r_cons):
    x_line = cx(t_cons)
    y_start = ry(r_prod) + RH/2
    y_end = ry(r_cons) + RH/2
    pts = f"M{x_line-1},{y_start} L{x_line+3},{y_start} L{x_line+3},{y_end} L{x_line+6},{y_end}"
    f.raw(f'<path d="{pts}" fill="none" stroke="#2e7d32" stroke-width="2" marker-end="url(#ah)"/>')

# EX-to-EX Forwarding arrows (clean thin arrows, no overlapping pill/box overlays)
draw_forward_arrow(2, 0, 1)    # addi x1 -> addi x2
draw_forward_arrow(8, 3, 4)    # mul x3  -> add x4
draw_forward_arrow(16, 6, 7)   # lw x6   -> add x7
draw_forward_arrow(55, 11, 12) # div x9  -> addi x10"""

code = code.replace(old_block, new_block)

# Expand the bottom description card to cleanly list all hazard details
old_footer = """KY = SY0 + len(SIGNALS) * SH + 15
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

f.text(48, KY + 40, "Key Architectural Features: (1) EX-to-EX Forwarding bypasses calculated results directly from end-of-EX into the dependent EX stage without bubble. (2) Load-ALU Hazard inserts a hardware stall until memory load returns. (3) RV32M pipelined multiplier executes in 4 cycles; divider executes in 34 cycles. (4) Taken branches squash speculatively fetched wrong-path instructions.", 8, italic=True, fill="#444444")"""

new_footer = """KY = SY0 + len(SIGNALS) * SH + 12
f.box(40, KY, 1660, 78, kind="plain", shadow=0)
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

# Clean small description lines at the bottom summarizing all hazards and forwardings
f.text(48, KY + 38, "Pipeline Hazards & Forwarding Details:", 8.5, True, fill="#004870")
f.text(48, KY + 52, "- EX-to-EX Forwarding (Green Arrows): T2 (addi x1 -> addi x2), T8 (mul x3 -> add x4), T16 (lw x6 -> add x7), T55 (div x9 -> addi x10). Eliminates RAW bubbles.", 8.0, False, fill="#2e7d32")
f.text(48, KY + 66, "- Multi-Cycle & Stalls: MUL takes 4 cycles in EX (T4-T7, m_busy=1); DIV takes 34 cycles (T21-T54, radix-2). Load-ALU Stall at T12-T15 waits for DMEM bus response. Branch taken at T18 squashes T19-T21.", 8.0, False, fill="#444444")"""

code = code.replace(old_footer, new_footer)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("fig3_timing.py updated with clean layout and bottom description lines")
