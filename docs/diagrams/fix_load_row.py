with open("fig3_timing.py") as f:
    code = f.read()

# Replace row 6 in R
old_r6 = """    6: {10: "id", 11: "ex", **h(12, 13, 14, 15), 16: "wb"},"""
new_r6 = """    6: {10: "id", 11: "ex", 16: "wb"},"""

code = code.replace(old_r6, new_r6)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated row 6 in fig3_timing.py")
