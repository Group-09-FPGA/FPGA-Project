with open("fig3_timing.py") as f:
    code = f.read()

# 1. Update R so that fetch is removed and everything starts at IF/ID:
# Row 5 was: 5: {8: "fetch", 9: "id", 10: "ex", 11: "wb", **h(12, 13, 14, 15)},
# In 3-stage pipeline (IF/ID -> EX -> MEM/WB): row 5 executes IF/ID at T9, EX at T10, MEM/WB at T11!
# Row 8 was: 8: {16: "fetch", 17: "id", 18: "ex", 19: "wb"},
# It executes IF/ID at T17, EX at T18, MEM/WB at T19!
old_r5 = """    5: {8: "fetch", 9: "id", 10: "ex", 11: "wb", **h(12, 13, 14, 15)},"""
new_r5 = """    5: {9: "id", 10: "ex", 11: "wb", **h(12, 13, 14, 15)},"""

old_r8 = """    8: {16: "fetch", 17: "id", 18: "ex", 19: "wb"},"""
new_r8 = """    8: {17: "id", 18: "ex", 19: "wb"},"""

code = code.replace(old_r5, new_r5)
code = code.replace(old_r8, new_r8)

# 2. Update cell label mapping:
# "id" -> "IF/ID"
# "ex" -> "EX"
# "mex" -> "M"
# "wb" -> "MEM/WB"
old_labels = """        if st == "id":
            fill_col = "#e8eaf6"
            lbl = "ID"
        elif st == "ex":
            fill_col = "#c8e6c9"
            lbl = "EX"
        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M"
        elif st == "wb":
            fill_col = "#ffe0b2"
            lbl = "WB"
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
            lbl = "IF" """

new_labels = """        if st == "id":
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
            text_col = "#c62828" """

code = code.replace(old_labels, new_labels)

# 3. Update font size for text inside the cell:
# For "MEM/WB" (6 chars) and "IF/ID" (5 chars), font size 7.2 or 7.0 is very legible inside CW=43!
old_fsize = """f.text(x + CW / 2, y + 17, lbl, 8.5 if len(lbl)<=2 else 6.5, True, "middle", fill=text_col)"""
new_fsize = """f.text(x + CW / 2, y + 16.5, lbl, 8.5 if len(lbl)<=2 else (7.2 if len(lbl)<=5 else 6.8), True, "middle", fill=text_col)"""
code = code.replace(old_fsize, new_fsize)

# 4. In stages legend:
# Change ("MEM/WB (Writeback)", ...) to ("MEM/WB (Memory / Writeback)", ...)
code = code.replace('"MEM/WB (Writeback)"', '"MEM/WB (Memory/Writeback)"')

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Updated stage labels in fig3_timing.py")
