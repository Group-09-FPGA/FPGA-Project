with open("fig3_timing.py") as f:
    code = f.read()

# Replace row 6 in R
old_r6 = """    6: {10: "id", 11: "ex", **h(12, 13, 14, 15), 16: "wb"},"""
new_r6 = """    6: {10: "id", 11: "ex", 12: "wb"},"""

code = code.replace(old_r6, new_r6)

# Update forwarding arrow for x6:
# Producer is row 6 (lw), Consumer is row 7 (add x7).
# Consumer EX is at cx(16). Producer WB is at cx(12).
# If we draw forwarding arrow from row 6 to row 7:
# Producer is at row 6, consumer is row 7.
# Let's adjust draw_forward_arrow for row 7:
old_fwd = "draw_forward_arrow(16, 6, 7)   # lw x6   -> add x7"
new_fwd = """# lw x6 (row 6) produces x6 at T12, forwarded to add x7 EX (row 7) at T16:
x_fwd_src = cx(12) + CW
x_fwd_dst = cx(16)
y_fwd_src = ry(6) + RH/2
y_fwd_dst = ry(7) + RH/2
f.raw(f'<path d="M{x_fwd_src},{y_fwd_src} L{x_fwd_src+10},{y_fwd_src} L{x_fwd_src+10},{y_fwd_dst} L{x_fwd_dst+6},{y_fwd_dst}" fill="none" stroke="#2e7d32" stroke-width="2" marker-end="url(#ah)"/>')"""

code = code.replace(old_fwd, new_fwd)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated fig3_timing.py successfully")
