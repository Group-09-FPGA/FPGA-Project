with open("fig3_timing.py") as f:
    code = f.read()

# Replace the custom arrow with clean boundary drop at cx(16):
old_fwd = """# lw x6 (row 6) produces x6 at T12, forwarded to add x7 EX (row 7) at T16:
x_fwd_src = cx(12) + CW
x_fwd_dst = cx(16)
y_fwd_src = ry(6) + RH/2
y_fwd_dst = ry(7) + RH/2
f.raw(f'<path d="M{x_fwd_src},{y_fwd_src} L{x_fwd_src+10},{y_fwd_src} L{x_fwd_src+10},{y_fwd_dst} L{x_fwd_dst+6},{y_fwd_dst}" fill="none" stroke="#2e7d32" stroke-width="2" marker-end="url(#ah)"/>')"""

# Use draw_forward_arrow(16, 6, 7) which drops at cx(16) right before the EX box without crossing any cells:
new_fwd = """draw_forward_arrow(16, 6, 7)   # lw x6 (row 6) -> add x7 EX (row 7) at T16"""

code = code.replace(old_fwd, new_fwd)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated arrow cleanly")
