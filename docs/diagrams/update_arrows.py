with open("fig3_timing.py") as f:
    code = f.read()

# Let's inspect how RH is defined: RH = 27
# In a row r: y = ry(r) = GY + r * RH
# Cell rect: x+1, y+2, width CW-2, height RH-4 (i.e. y+2 to y+25).
# Row r bottom is y+27. Next row r+1 top is y+27.
# Producing stage is at row r_prod, cycle t_prod.
# Consuming stage is at row r_cons, cycle t_cons.
# In EX-to-EX:
# Producer EX is in cycle T(p), consumer EX is in cycle T(c) = T(p+1).
# Boundary between cycle T(p) and T(c) is exactly cx(t_cons)!
# Producer EX cell ends at cx(t_cons)-1, y_prod+2 to y_prod+25.
# Consumer EX cell starts at cx(t_cons)+1, y_cons+2 to y_cons+25.
# So a drop straight down along cx(t_cons) is exactly between the columns, perfectly outside any cells!
# From the bottom-right corner of Producer EX: (cx(t_cons)-1, ry(r_prod)+RH-2)
# Or from the right edge of Producer EX: (cx(t_cons)-1, ry(r_prod)+RH/2)
# Move right 2px to cx(t_cons)+1, drop down to ry(r_cons)+RH/2, enter Consumer EX at cx(t_cons)+1!
# And the badge can be placed cleanly above the arrow or at the label!

new_draw = """def draw_forward_arrow(t_cons, r_prod, r_cons, label):
    # Consumer EX is at cx(t_cons), ry(r_cons). Producer is at row r_prod.
    x_line = cx(t_cons)
    y_start = ry(r_prod) + RH/2
    y_end = ry(r_cons) + RH/2
    
    # Path: from right edge of producer EX -> boundary line -> straight down -> enter consumer EX
    pts = f"M{x_line-1},{y_start} L{x_line+3},{y_start} L{x_line+3},{y_end} L{x_line+6},{y_end}"
    f.raw(f'<path d="{pts}" fill="none" stroke="#2e7d32" stroke-width="2" marker-end="url(#ah)"/>')
    
    # Clean pill badge placed directly above consumer EX cell, or neatly aligned
    # We can place it floating right at the boundary corner or right above:
    bw = len(label) * 5.4 + 10
    bh = 13
    bx = x_line + 8
    by = ry(r_cons) - 3
    f.raw(f'<rect x="{bx}" y="{by-9}" width="{bw}" height="{bh}" rx="2" fill="#e8f5e9" stroke="#2e7d32" stroke-width="0.8"/>')
    f.text(bx + bw/2, by, label, 7.0, True, "middle", fill="#1b5e20")
"""

# Replace in code
old_section = """def draw_forward_arrow(fx, fy, tx, ty, label, offset_x=14, badge_x=None, badge_y=None, badge_side="right"):
    # fx, fy: source center point
    # tx, ty: destination center point (left border of consuming EX cell)
    mid_x = tx - offset_x
    pts = f"M{fx},{fy} L{mid_x},{fy+3} L{mid_x},{ty} L{tx},{ty}"
    f.raw(f'<path d="{pts}" fill="none" stroke="#2e7d32" stroke-width="1.8" marker-end="url(#ah)"/>')
    # Draw a clean pill badge for the label to the right of the EX stage
    bx = badge_x if badge_x is not None else tx + CW + 4
    by = badge_y if badge_y is not None else ty
    bw = len(label) * 5.6 + 10
    bh = 14
    f.raw(f'<rect x="{bx}" y="{by-10}" width="{bw}" height="{bh}" rx="3" fill="#e8f5e9" stroke="#2e7d32" stroke-width="0.8"/>')
    f.text(bx + bw/2, by, label, 7.2, True, "middle", fill="#1b5e20")

# 1. Forwarding from addi x1 EX (T1) -> addi x2 EX (T2) : EX-to-EX Forwarding
# Source: T1 EX right/bottom (cx(1)+CW, ry(0)+RH/2) or T2 start
draw_forward_arrow(cx(1)+CW, ry(0)+RH/2, cx(2)+1, ry(1)+RH/2, "EX to EX (x1)", offset_x=8, badge_x=cx(2)+CW+4, badge_y=ry(1)+RH/2)

# 2. MUL multi-cycle label (placed safely inside the instruction row 3 text column or above row 3)
f.raw(f'<rect x="85" y="{ry(3)+16}" width="182" height="13" rx="2" fill="#e1f5fe" stroke="#0288d1" stroke-width="0.8"/>')
f.text(85 + 91, ry(3)+25, "MUL 4-cyc Multi-Cycle EX (m_busy=1)", 7.2, True, "middle", fill="#01579b")

# 3. Forwarding from MUL x3 EX (T7) -> add x4 EX (T8) : EX-to-EX Forwarding
draw_forward_arrow(cx(7)+CW, ry(3)+RH/2, cx(8)+1, ry(4)+RH/2, "EX to EX (x3)", offset_x=8, badge_x=cx(8)+CW+4, badge_y=ry(4)+RH/2)

# 4. Bus stall during load badge (placed cleanly in instruction note or above row 6)
f.raw(f'<rect x="85" y="{ry(6)+16}" width="182" height="13" rx="2" fill="#fff3e0" stroke="#f57c00" stroke-width="0.8"/>')
f.text(85 + 91, ry(6)+25, "DMEM Load Stall: 4-cycle bus latency", 7.2, True, "middle", fill="#e65100")

# 5. Load-ALU Hazard & Forwarding from LW x6 EX/MEM (T15) -> add x7 EX (T16) : MEM-to-EX / EX-to-EX Forwarding
draw_forward_arrow(cx(15)+CW, ry(6)+RH/2, cx(16)+1, ry(7)+RH/2, "EX to EX (x6)", offset_x=8, badge_x=cx(16)+CW+4, badge_y=ry(7)+RH/2)
# Load-ALU Stall callout badge (positioned cleanly below the STALL cells in row 7 without clipping row 8)
f.raw(f'<rect x="{cx(12)}" y="{ry(7)+RH+1}" width="168" height="13" rx="2" fill="#fbe9e7" stroke="#d84315" stroke-width="0.8"/>')
f.text(cx(12)+84, ry(7)+RH+10, "LOAD-ALU STALL (Wait for data)", 7.2, True, "middle", fill="#bf360c")

# 6. Branch Taken callout (placed in note column for row 8)
f.raw(f'<rect x="85" y="{ry(8)+16}" width="160" height="13" rx="2" fill="#ffebee" stroke="#c62828" stroke-width="0.8"/>')
f.text(85 + 80, ry(8)+25, "Branch Taken (Target 0x2c)", 7.2, True, "middle", fill="#b71c1c")

# 7. DIV stall & forward to addi x10 at T55 : EX-to-EX Forwarding
draw_forward_arrow(cx(54)+CW, ry(11)+RH/2, cx(55)+1, ry(12)+RH/2, "EX to EX (x9)", offset_x=8, badge_x=cx(55)+CW+4, badge_y=ry(12)+RH/2)"""

new_section = """def draw_forward_arrow(t_cons, r_prod, r_cons, label):
    x_line = cx(t_cons)
    y_start = ry(r_prod) + RH/2
    y_end = ry(r_cons) + RH/2
    pts = f"M{x_line-1},{y_start} L{x_line+3},{y_start} L{x_line+3},{y_end} L{x_line+6},{y_end}"
    f.raw(f'<path d="{pts}" fill="none" stroke="#2e7d32" stroke-width="1.8" marker-end="url(#ah)"/>')
    bw = len(label) * 5.4 + 10
    bh = 13
    bx = x_line + 8
    by = ry(r_cons) - 2
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

code = code.replace(old_section, new_section)
with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Replacement done successfully")
