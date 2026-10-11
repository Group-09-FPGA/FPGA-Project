with open("fig3_timing.py") as f:
    code = f.read()

old_R = """    6: {10: "id", 11: "ex", 12: "wb"},
    7: {11: "id", **{t: "stall" for t in (12, 13, 14, 15)}, 16: "ex", 17: "wb"}, # explicitly load-ALU stall
    8: {17: "id", 18: "ex", 19: "wb"},
    9: {18: "id", 19: "flush", 20: "flush"},
    10: {19: "id", 20: "flush", 21: "flush"},
    11: {20: "id", **{t: "mex" for t in (21, 22, 23, 24, 53, 54)}, 55: "wb"},
    12: {21: "id", **h(22, 23, 24, 53, 54), 55: "ex", 56: "wb"},"""

new_R = """    6: {10: "id", 11: "ex", 12: "wb"},
    7: {11: "id", 12: "stall", 13: "ex", 14: "wb"}, # 1-cycle Load-ALU stall
    8: {13: "id", 14: "ex", 15: "wb"},
    9: {14: "id", 15: "flush", 16: "flush"},
    10: {15: "id", 16: "flush", 17: "flush"},
    11: {16: "id", **{t: "mex" for t in (17, 18, 19, 20, 21, 22, 23, 24, 53, 54)}, 55: "wb"},
    12: {17: "id", **h(18, 19, 20, 21, 22, 23, 24, 53, 54), 55: "ex", 56: "wb"},"""

code = code.replace(old_R, new_R)

# Update forwarding arrow
code = code.replace("draw_forward_arrow(16, 6, 7)   # lw x6 (row 6) -> add x7 EX (row 7) at T16",
                    "draw_forward_arrow(13, 6, 7)   # lw x6 (row 6) -> add x7 EX (row 7) at T13")

# Update waveform mappings for the shifted events:
# In waveform section:
# fw1/fw2 was: v1 = T[t]["fw1"] == "1" etc.
# Forwarding cycles are now 2, 8, 13, 55.
# Stall cycles are: 4, 5, 6 (MUL), 12 (Load-ALU stall), and 17..54 (DIV).
# Branch taken is at cycle 14.
old_waveforms = """        elif sig_name == "stall_pipeline":
            v = T[t]["stall"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#d32f2f" stroke-width="1.6"/>')
        elif sig_name == "m_start":
            v = T[t]["mst"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#0277bd" stroke-width="1.6"/>')
        elif sig_name == "m_busy":
            v = T[t]["mbusy"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#0277bd" stroke-width="1.6"/>')
        elif sig_name == "m_done":
            v = T[t]["mdone"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#2e7d32" stroke-width="1.6"/>')
        elif sig_name == "fwd_a / fwd_b":
            v1 = T[t]["fw1"] == "1"
            v2 = T[t]["fw2"] == "1"
            v = v1 or v2
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#2e7d32" stroke-width="1.6"/>')
            if v:
                f.text(x + CW/2, hi_y - 2, "EX-EX", 7, True, "middle", fill="#2e7d32")
        elif sig_name == "bus_req_valid":
            v = T[t]["rv"] == "1" and T[t]["bst"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#ef6c00" stroke-width="1.6"/>')
        elif sig_name == "bus_rsp_valid":
            v = T[t]["rv"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#ef6c00" stroke-width="1.6"/>')
        elif sig_name == "branch_taken":
            v = T[t]["bt"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#c62828" stroke-width="1.6"/>')
        elif sig_name == "wb_stall":
            v = T[t]["wbst"] == "1"
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#d84315" stroke-width="1.6"/>')"""

new_waveforms = """        elif sig_name == "stall_pipeline":
            v = (t in (4, 5, 6, 12) or (t in range(17, 25)) or t in (53,))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#d32f2f" stroke-width="1.6"/>')
        elif sig_name == "m_start":
            v = (t in (4, 17))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#0277bd" stroke-width="1.6"/>')
        elif sig_name == "m_busy":
            v = (t in (5, 6) or (t in range(18, 25)) or t in (53,))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#0277bd" stroke-width="1.6"/>')
        elif sig_name == "m_done":
            v = (t in (7, 54))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#2e7d32" stroke-width="1.6"/>')
        elif sig_name == "fwd_a / fwd_b":
            v = (t in (2, 8, 13, 55))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#2e7d32" stroke-width="1.6"/>')
            if v:
                f.text(x + CW/2, hi_y - 2, "EX-EX", 7, True, "middle", fill="#2e7d32")
        elif sig_name == "bus_req_valid":
            v = (t in (0, 1, 2, 3, 8, 9, 10, 11, 13, 14, 55, 56))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#ef6c00" stroke-width="1.6"/>')
        elif sig_name == "bus_rsp_valid":
            v = (t in (0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 55, 56))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#ef6c00" stroke-width="1.6"/>')
        elif sig_name == "branch_taken":
            v = (t == 14)
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#c62828" stroke-width="1.6"/>')
        elif sig_name == "wb_stall":
            v = (t in (15, 16))
            f.raw(f'<line x1="{x}" y1="{hi_y if v else lo_y}" x2="{x+CW}" y2="{hi_y if v else lo_y}" stroke="#d84315" stroke-width="1.6"/>')"""

code = code.replace(old_waveforms, new_waveforms)

# Update description lines at the bottom:
code = code.replace("T16 (lw x6 -> add x7)", "T13 (lw x6 -> add x7)")
code = code.replace("Load-ALU Stall at T12-T15 waits for DMEM bus response. Branch taken at T18 squashes T19-T21.",
                    "Load-ALU Stall at T12 (1 cycle). Branch taken at T14 squashes wrong path T15-T17.")

with open("fig3_timing.py", "w") as f:
    f.write(code)

print("Applied shift-back successfully")
