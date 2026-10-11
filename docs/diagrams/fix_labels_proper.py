with open("fig3_timing.py") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if 'lbl = "ID"' in line:
        line = line.replace('lbl = "ID"', 'lbl = "IF/ID"')
    elif 'lbl = "WB"' in line:
        line = line.replace('lbl = "WB"', 'lbl = "MEM/WB"')
    elif 'lbl = "IF"' in line:
        line = line.replace('lbl = "IF"', 'lbl = "IF/ID"')
    elif 'lbl, 8.5' in line:
        line = '        f.text(x + CW / 2, y + 16.5, lbl, 8.0 if len(lbl)<=2 else 6.8, True, "middle", fill=text_col)\n'
    new_lines.append(line)

with open("fig3_timing.py", "w") as f:
    f.writelines(new_lines)

print("Updated labels to IF/ID and MEM/WB cleanly")
