with open("fig3_timing.py") as f:
    code = f.read()

target = """        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M" """

replacement = """        elif st == "mex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "M"
        elif st == "dex":
            fill_col = "#004870"
            text_col = "#ffffff"
            border_col = "#002840"
            lbl = "D" """

# Let's inspect if target exists in code:
print("target in code:", target in code)
# If not, let's look for "mex"
if "mex" in code:
    idx = code.find('lbl = "M"')
    print("context:", repr(code[idx-50:idx+30]))
