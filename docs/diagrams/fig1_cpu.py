"""Figure 1 - RV32IM core datapath. Every label is taken from
rtl/cpu/core/cpu_core.v, rv32m_unit.v, hazard_unit.v, forwarding_unit.v."""
from dg import Fig

f = Fig(1700, 1150)
f.title("Figure 1 - RV32IM core: datapath, control and bus master",
        "cpu_core.v  |  3-stage pipeline: IF+ID | EX | MEM+WB  |  single clk (100 MHz target), "
        "async active-low reset on every register")

# ---------------- stage header strip ----------------
f.box(40, 84, 560, 26, kind="plain", shadow=0)
f.box(660, 84, 520, 26, kind="plain", shadow=0)
f.box(1240, 84, 420, 26, kind="plain", shadow=0)
for x, s in ((170, "IF"), (460, "ID"), (920, "EX"), (1345, "MEM"), (1560, "WB")):
    f.text(x, 102, s, 13, True, "middle")
f.raw('<line x1="320" y1="84" x2="320" y2="110" stroke="#1a1a1a"/>')
f.raw('<line x1="1457" y1="84" x2="1457" y2="110" stroke="#1a1a1a"/>')

# ---------------- pipeline register bars ----------------
BY, BH = 136, 364
f.bar(300, BY, 40, BH, "IF/ID", "id_pc[31:0]")
f.bar(606, BY, 46, BH, "ID/EX", "pc, imm[31:0], rd rs1 rs2[4:0], funct3[2:0], ctrl")
f.bar(1176, BY, 46, BH, "EX/WB", "result, mem_addr, rs2 [31:0], rd[4:0], ctrl")

# ---------------- IF column ----------------
f.box(60, 172, 210, 52, ["next_pc[31:0] select", "+4 | jal | jalr | branch"], size=10)
f.box(60, 252, 210, 40, ["fetch_pc[31:0]"])
f.box(60, 332, 210, 44, ["instruction mux", "if_buf_valid ? if_buf : rsp_rdata"], size=10)
f.box(60, 420, 210, 44, ["if_buf[31:0] + valid", "skid buffer, holds fetch on stall"], size=10)
f.arrow([(165, 224), (165, 252)])
f.arrow([(165, 420), (165, 376)])
f.arrow([(270, 272), (300, 272)])
f.arrow([(285, 272), (285, 790)], dot=[(285, 272)])
f.text(279, 600, "fetch_pc -> req_addr", 9, anchor="end", halo=True)

# ---------------- ID column ----------------
dec = ["rs1 rs2 rd[4:0]", "funct3[2:0]", "immediate[31:0]  immediate_sel",
       "alu lui jal jalr branch", "mem_write mem_to_reg", "arithsubtype m_op"]
f.box(400, 172, 190, 236, dec, title="decoder", size=10)
f.arrow([(270, 354), (400, 354)])
f.text(344, 347, "instr[31:0]", 9, halo=True)
f.arrow([(340, 146), (606, 146)], label="id_pc[31:0]", lp=(473, 140))
f.arrow([(590, 290), (606, 290)])
f.box(400, 436, 190, 40, ["exception = illegal_inst", "| pc[1:0]!=0 | bus_rsp_error"], size=9)
f.arrow([(495, 408), (495, 436)])

# ---------------- EX column ----------------
f.box(690, 190, 170, 80, ["32 x 32b, 2R / 1W", "read in EX via ex_rs1/2"], title="reg_file")
f.box(690, 326, 170, 62, ["WB -> EX bypass", "rd==rs & RegWrite; x0 -> 0"], title="forwarding_unit", size=10)
f.arrow([(652, 215), (690, 215)], label="rs1/2[4:0]", lp=(671, 208), lsize=8)
f.arrow([(775, 270), (775, 326)], label="raw[31:0]", lp=(782, 303), lsize=9, anchor="start")
# WB feedback lane -> forwarding unit
f.arrow([(662, 548), (662, 370), (690, 370)], dot=[(662, 240)])
f.arrow([(662, 240), (690, 240)])
f.text(700, 542, "wb_data[31:0], wb_rd[4:0], wb_reg_write_en  (bypass + regfile write)", 9, halo=True)

# operand bus
f.arrow([(860, 357), (884, 357)])
f.raw('<line x1="884" y1="196" x2="884" y2="446" stroke="#1a1a1a" stroke-width="1.6"/>')
f.text(876, 320, "alu_operand1/2[31:0]", 9, anchor="middle", halo=True, rot=-90)
for y in (198, 264, 322, 436):
    f.arrow([(884, y), (910, y)])

# parallel EX units (as on the H&P slide: fan out from ID/EX, merge at the result mux)
f.box(910, 170, 170, 56, ["branch_unit + target adders", "condition_met, next_pc[31:0]"], size=10)
f.box(910, 236, 170, 46, ["rs1 + imm adder", "ex_mem_address[31:0]"], size=10)
f.box(910, 292, 170, 56, ["alu", "ADD SUB AND OR XOR SLT SH*", "1 cycle"], size=10)
rm = ["MUL MULH MULHSU MULHU", "33x33 -> 66b, 3 stages (DSP48E1)",
      "DIV DIVU REM REMU", "32-iteration restoring divider",
      "start, funct3[2:0] -> busy, done"]
f.box(910, 358, 170, 142, rm, kind="new", title="rv32m_unit", size=9.5)
# unpipelined iterate loop (H&P slide notation)
f.arrow([(1040, 500), (1040, 514), (950, 514), (950, 500)], width=1.1)
f.text(995, 527, "iterate x32 (div) / 3 stages (mul)", 8.5, anchor="middle")

# result mux
f.box(1105, 292, 46, 208, [])
f.text(1132, 396, "ex_result mux (store|PC+4|imm|alu|m)", 9, False,
       "middle", rot=-90)
f.arrow([(1080, 320), (1105, 320)])
f.arrow([(1080, 430), (1105, 430)])
f.arrow([(1151, 396), (1176, 396)])
f.arrow([(1080, 259), (1176, 259)], label="ex_mem_address[31:0]", lp=(1128, 253), lsize=9)
f.arrow([(995, 170), (995, 128), (165, 128), (165, 172)],
        label="branch_taken, next_pc[31:0]", lp=(640, 124), lsize=10)
# EX load address -> bus arbiter
f.arrow([(1095, 259), (1095, 790)], dot=[(1095, 259)])
f.text(1101, 760, "ex_mem_address[31:0]", 9, anchor="start", halo=True)


# ---------------- MEM | WB ----------------
f.box(1245, 172, 200, 96, ["SB / SH / SW", "wb_write_data[31:0]", "wb_write_byte[3:0]"], title="store align", size=10)
f.arrow([(1222, 220), (1245, 220)])
f.arrow([(1270, 268), (1270, 790)])
f.text(1264, 730, "wb_mem_address, wb_write_data, wb_write_byte", 9, anchor="end", halo=True)

f.box(1300, 330, 145, 48, ["bus_rdata_reg[31:0]", "!stall_pipeline"], size=10)
f.box(1475, 330, 185, 70, ["LB LH LW LBU LHU", "sign / zero extend", "wb_read_data[31:0]"], title="load align", size=10)
f.arrow([(1445, 354), (1475, 354)])
f.box(1475, 440, 185, 46, ["wb_mem_to_reg ? read : result"], title="writeback mux", size=10)
f.arrow([(1567, 400), (1567, 440)])
f.arrow([(1222, 463), (1475, 463)], label="wb_result[31:0]", lp=(1348, 457), lsize=9)
f.arrow([(1567, 486), (1567, 548), (662, 548)], head=False)
f.text(1250, 542, "write_data[31:0]", 9, halo=True)

f.box(1475, 172, 185, 96, ["clk : 100 MHz core clock", "reset : active-low, async", "stall : external freeze", "regs: posedge clk / negedge reset"],
      title="clock and reset", size=9)

# ---------------- hazard / stall ----------------
f.box(690, 570, 200, 76, ["wb_branch -> wb_stall_first/second", "branch_stall = first | wb_branch", "2-cycle redirect bubble"], title="hazard_unit", size=9)
f.box(920, 570, 170, 76, ["stall | wb_stalling | ex_stalling", "| if_stalling | m_stalling"], title="stall_pipeline", size=9)
f.arrow([(890, 608), (920, 608)])
f.arrow([(1070, 500), (1070, 570)], label="m_done / m_busy", lp=(1078, 566), anchor="start", lsize=9)
f.text(700, 678, "stall_pipeline freezes fetch_pc, id_pc, ID/EX, EX/WB", 9, anchor="start", halo=True)
f.arrow([(1005, 646), (1005, 662), (629, 662), (629, 500)], dashed=True, dot=[(1005, 662)])
f.arrow([(1005, 662), (1199, 662), (1199, 500)], dashed=True)


# ---------------- bus master arbiter ----------------
f.box(270, 790, 1075, 60, ["FSM ST_IDLE / WAIT_IF / WAIT_EX / WAIT_WB  |  priority WB-store > EX-load > IF-fetch  |  one outstanding request"],
      title="bus master arbiter", size=10)
f.box(270, 898, 1075, 48, ["OUT  bus_req_valid, req_write, req_addr[31:0], req_wdata[31:0], req_wstrb[3:0]   ->   sys_bus_interconnect (Fig. 2)",
                           "IN   bus_rsp_valid, rsp_rdata[31:0], rsp_error   <-   sys_bus_interconnect"],
      kind="plain", size=10, shadow=0)
f.arrow([(800, 850), (800, 898)])
f.arrow([(1345, 922), (1400, 922), (1400, 378)])
f.text(1408, 700, "bus_rsp_rdata[31:0]", 9, anchor="start", halo=True)
f.arrow([(270, 922), (50, 922), (50, 354), (60, 354)], dot=[(50, 442)])
f.arrow([(50, 442), (60, 442)])
f.text(44, 700, "bus_rsp_rdata[31:0], rsp_valid, rsp_error", 9, anchor="middle", halo=True, rot=-90)

# ---------------- key control signals ----------------
f.box(40, 975, 800, 140, [], kind="plain", shadow=0)
f.text(52, 995, "Key control signals (assignment name -> RTL name)", 11, True)
rows = [("RegWrite", "wb_reg_write_en = alu|lui|jal|jalr|load|m"), ("MemRead", "ex_mem_to_reg"),
        ("MemWrite", "ex_mem_write -> wb_mem_write"), ("ALUSrc", "ex_imm_sel"),
        ("ALUOp", "ex_alu_op[2:0] + ex_arithsubtype"), ("Branch/Jump", "ex_branch, ex_jal, ex_jalr -> branch_taken"),
        ("M select", "ex_m -> m_start; m_stalling = ex_m & !m_done"), ("Stall", "stall_pipeline")]
for i, (a, b) in enumerate(rows):
    cx, cy = 52 + (i // 4) * 400, 1022 + (i % 4) * 22
    f.text(cx, cy, a, 10, True)
    f.text(cx + 85, cy, b, 9.5)

# ---------------- legend ----------------
f.box(880, 975, 780, 140, [], kind="plain", shadow=0)
f.text(892, 995, "Legend", 11, True)
f.box(892, 1008, 30, 16, kind="old", shadow=3)
f.text(932, 1021, "existing RTL in rtl/cpu/core", 10)
f.box(892, 1034, 30, 16, kind="new", shadow=3)
f.text(932, 1047, "new in this project", 10)
f.text(892, 1075, "Honest stage mapping: IF+ID fetch and decode in one cycle (no instruction register);", 10)
f.text(892, 1089, "EX reads regfile, executes, issues loads; MEM+WB stores from EX/WB regs, aligns loads,", 10)
f.text(892, 1103, "writes regfile. Dashed = stall_pipeline hold.", 10)

open("fig1_cpu.svg", "w").write(f.svg())
print("ok")

