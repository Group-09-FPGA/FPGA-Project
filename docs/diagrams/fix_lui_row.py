with open("fig3_timing.py") as f:
    code = f.read()

# Row 2 (lui): remove the 3 grey boxes (cycles 5, 6, 7) so they are white
# Row 6 (lw): restore the grey hold boxes across 12, 13, 14, 15 like before
old_r2 = """    2: {2: "id", 3: "ex", 4: "wb", **h(5, 6, 7)},"""
new_r2 = """    2: {2: "id", 3: "ex", 4: "wb"},"""

old_r6 = """    6: {10: "id", 11: "ex", 16: "wb"},"""
new_r6 = """    6: {10: "id", 11: "ex", **h(12, 13, 14, 15), 16: "wb"},"""

code = code.replace(old_r2, new_r2)
code = code.replace(old_r6, new_r6)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated rows in fig3_timing.py")
