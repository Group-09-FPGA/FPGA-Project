with open("fig3_timing.py") as f:
    code = f.read()

# Replace row 5 (sw) in R: remove the trailing grey boxes (**h(12, 13, 14, 15))
old_r5 = """    5: {9: "id", 10: "ex", 11: "wb", **h(12, 13, 14, 15)},"""
new_r5 = """    5: {9: "id", 10: "ex", 11: "wb"},"""

code = code.replace(old_r5, new_r5)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated sw row in fig3_timing.py")
