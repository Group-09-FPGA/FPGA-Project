with open("fig3_timing.py") as f:
    code = f.read()

# Replace the MUL callout badge
old_mul = """# 2. MUL multi-cycle badge
f.raw(f'<rect x="{cx(4)+2}" y="{ry(2)+RH+1}" width="168" height="15" rx="3" fill="#e1f5fe" stroke="#0288d1" stroke-width="0.8"/>')
f.text(cx(4)+86, ry(2)+RH+11, "MUL 4-cyc Multi-Cycle EX (m_busy=1)", 7.5, True, "middle", fill="#01579b")"""

new_mul = """# 2. MUL multi-cycle label (placed safely inside the instruction row 3 text column or above row 3)
f.raw(f'<rect x="85" y="{ry(3)+16}" width="182" height="13" rx="2" fill="#e1f5fe" stroke="#0288d1" stroke-width="0.8"/>')
f.text(85 + 91, ry(3)+25, "MUL 4-cyc Multi-Cycle EX (m_busy=1)", 7.2, True, "middle", fill="#01579b")"""

code = code.replace(old_mul, new_mul)

# Replace the Bus stall during load badge (T11..T15)
old_bus = """# 4. Bus stall during load badge (T11..T15)
f.raw(f'<rect x="{cx(11)+2}" y="{ry(5)+RH+1}" width="206" height="15" rx="3" fill="#fff3e0" stroke="#f57c00" stroke-width="0.8"/>')
f.text(cx(11)+105, ry(5)+RH+11, "DMEM Load Stall: 4 cycles bus latency", 7.5, True, "middle", fill="#e65100")"""

new_bus = """# 4. Bus stall during load badge (placed cleanly in instruction note or above row 6)
f.raw(f'<rect x="85" y="{ry(6)+16}" width="182" height="13" rx="2" fill="#fff3e0" stroke="#f57c00" stroke-width="0.8"/>')
f.text(85 + 91, ry(6)+25, "DMEM Load Stall: 4-cycle bus latency", 7.2, True, "middle", fill="#e65100")"""

code = code.replace(old_bus, new_bus)

# Replace Load-ALU Stall callout badge
old_load_alu = """# Load-ALU Stall callout badge
f.raw(f'<rect x="{cx(12)+4}" y="{ry(7)+RH+2}" width="155" height="16" rx="3" fill="#fbe9e7" stroke="#d84315" stroke-width="0.9"/>')
f.text(cx(12)+81, ry(7)+RH+13, "LOAD-ALU STALL (Hold until data ready)", 7.2, True, "middle", fill="#bf360c")"""

new_load_alu = """# Load-ALU Stall callout badge (positioned cleanly below the STALL cells in row 7 without clipping row 8)
f.raw(f'<rect x="{cx(12)}" y="{ry(7)+RH+1}" width="168" height="13" rx="2" fill="#fbe9e7" stroke="#d84315" stroke-width="0.8"/>')
f.text(cx(12)+84, ry(7)+RH+10, "LOAD-ALU STALL (Wait for data)", 7.2, True, "middle", fill="#bf360c")"""

code = code.replace(old_load_alu, new_load_alu)

# Replace Branch Taken callout
old_branch = """# 6. Branch Taken callout (T18) & Squashed instructions
f.raw(f'<rect x="{cx(18)+2}" y="{ry(7)+RH+2}" width="145" height="15" rx="3" fill="#ffebee" stroke="#c62828" stroke-width="0.8"/>')
f.text(cx(18)+74, ry(7)+RH+12, "Branch Taken (Target 0x2c)", 7.5, True, "middle", fill="#b71c1c")"""

new_branch = """# 6. Branch Taken callout (placed in note column for row 8)
f.raw(f'<rect x="85" y="{ry(8)+16}" width="160" height="13" rx="2" fill="#ffebee" stroke="#c62828" stroke-width="0.8"/>')
f.text(85 + 80, ry(8)+25, "Branch Taken (Target 0x2c)", 7.2, True, "middle", fill="#b71c1c")"""

code = code.replace(old_branch, new_branch)

# Also check draw_forward_arrow arrowhead so it doesn't overlap cell border
old_fn = """def draw_forward_arrow(fx, fy, tx, ty, label, offset_x=14, badge_x=None, badge_y=None, badge_side="right"):
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
    f.text(bx + bw/2, by + 1, label, 7.5, True, "middle", fill="#1b5e20")"""

new_fn = """def draw_forward_arrow(fx, fy, tx, ty, label, offset_x=14, badge_x=None, badge_y=None, badge_side="right"):
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
    f.text(bx + bw/2, by, label, 7.2, True, "middle", fill="#1b5e20")"""

code = code.replace(old_fn, new_fn)

# Change arrow connections to enter EX cell cleanly at left side mid-height (y + RH/2)
code = code.replace(
    'draw_forward_arrow(cx(1)+CW-4, ry(0)+RH, cx(2)+8, ry(1)+2, "EX to EX (x1)", offset_x=12, badge_x=cx(2)+CW+4, badge_y=ry(1)+6)',
    'draw_forward_arrow(cx(1)+CW, ry(0)+RH/2, cx(2)+1, ry(1)+RH/2, "EX to EX (x1)", offset_x=8, badge_x=cx(2)+CW+4, badge_y=ry(1)+RH/2)'
)
code = code.replace(
    'draw_forward_arrow(cx(7)+CW-4, ry(3)+RH, cx(8)+8, ry(4)+2, "EX to EX (x3)", offset_x=12, badge_x=cx(8)+CW+4, badge_y=ry(4)+6)',
    'draw_forward_arrow(cx(7)+CW, ry(3)+RH/2, cx(8)+1, ry(4)+RH/2, "EX to EX (x3)", offset_x=8, badge_x=cx(8)+CW+4, badge_y=ry(4)+RH/2)'
)
code = code.replace(
    'draw_forward_arrow(cx(15)+CW-4, ry(6)+RH, cx(16)+8, ry(7)+2, "EX to EX (x6)", offset_x=12, badge_x=cx(16)+CW+4, badge_y=ry(7)+6)',
    'draw_forward_arrow(cx(15)+CW, ry(6)+RH/2, cx(16)+1, ry(7)+RH/2, "EX to EX (x6)", offset_x=8, badge_x=cx(16)+CW+4, badge_y=ry(7)+RH/2)'
)
code = code.replace(
    'draw_forward_arrow(cx(54)+CW-4, ry(11)+RH, cx(55)+8, ry(12)+2, "EX to EX (x9)", offset_x=12, badge_x=cx(55)+CW+4, badge_y=ry(12)+6)',
    'draw_forward_arrow(cx(54)+CW, ry(11)+RH/2, cx(55)+1, ry(12)+RH/2, "EX to EX (x9)", offset_x=8, badge_x=cx(55)+CW+4, badge_y=ry(12)+RH/2)'
)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated fig3_timing.py successfully")
