with open("fig3_timing.py") as f:
    code = f.read()

# Update R dictionary:
# Row 3 (mul): stays as "mex" (or "m") so it displays "M"
# Row 10 (div): change to "dex" so it displays "D"
old_r10 = """    10: {15: "id", **{t: "mex" for t in (16, 17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"}, # target div: IF/ID at T15 while beq is WB"""
new_r10 = """    10: {15: "id", **{t: "dex" for t in (16, 17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"}, # target div: IF/ID at T15 while beq is WB"""

code = code.replace(old_r10, new_r10)

# In label checking:
old_mex = """        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M" """

new_mex = """        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M"
        elif st == "dex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "D" """

code = code.replace(old_mex, new_mex)

# In stages legend:
# Update ("M (RV32M Multi-cycle EX)", "#004870", "#ffffff")
# to ("M / D (Multiply / Divide Multi-cycle EX)", "#004870", "#ffffff")
code = code.replace('"M (RV32M Multi-cycle EX)"', '"M / D (Multiply / Divide Multi-Cycle EX)"')

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated div instruction stages from M to D")
