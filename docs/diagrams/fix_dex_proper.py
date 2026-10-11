with open("fig3_timing.py") as f:
    code = f.read()

old_block = """        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M"
        elif st == "wb":"""

new_block = """        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M"
        elif st == "dex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "D"
        elif st == "wb":"""

assert old_block in code, "old_block not found!"
code = code.replace(old_block, new_block)

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Added dex block cleanly!")
