`timescale 1ns / 1ps
// Scratch testbench for Figure 3: runs a fixed program on the unmodified RTL and
// logs per-cycle pipeline state. Not part of the regression suite.
module tb_trace;
    reg clk = 0, reset = 0;
    always #5 clk = ~clk;

    wire        bus_req_valid, bus_req_write, bus_rsp_valid, bus_rsp_error;
    wire [31:0] bus_req_addr, bus_req_wdata, bus_rsp_rdata;
    wire [3:0]  bus_req_wstrb;
    wire        imem_req_valid, imem_req_write, imem_rsp_valid;
    wire [31:0] imem_req_addr, imem_req_wdata, imem_rsp_rdata;
    wire [3:0]  imem_req_wstrb;
    wire        dmem_req_valid, dmem_req_write, dmem_rsp_valid;
    wire [31:0] dmem_req_addr, dmem_req_wdata, dmem_rsp_rdata;
    wire [3:0]  dmem_req_wstrb;
    wire exception;
    wire [31:0] pc_out;

    cpu_core DUT (.clk(clk), .reset(reset), .stall(1'b0), .exception(exception), .pc_out(pc_out),
        .bus_req_valid(bus_req_valid), .bus_req_write(bus_req_write), .bus_req_addr(bus_req_addr),
        .bus_req_wdata(bus_req_wdata), .bus_req_wstrb(bus_req_wstrb),
        .bus_rsp_valid(bus_rsp_valid), .bus_rsp_rdata(bus_rsp_rdata), .bus_rsp_error(bus_rsp_error));

    sys_bus_interconnect ic (.clk(clk), .reset(reset),
        .cpu_req_valid(bus_req_valid), .cpu_req_write(bus_req_write), .cpu_req_addr(bus_req_addr),
        .cpu_req_wdata(bus_req_wdata), .cpu_req_wstrb(bus_req_wstrb),
        .cpu_rsp_valid(bus_rsp_valid), .cpu_rsp_rdata(bus_rsp_rdata), .cpu_rsp_error(bus_rsp_error),
        .imem_req_valid(imem_req_valid), .imem_req_write(imem_req_write), .imem_req_addr(imem_req_addr),
        .imem_req_wdata(imem_req_wdata), .imem_req_wstrb(imem_req_wstrb),
        .imem_rsp_valid(imem_rsp_valid), .imem_rsp_rdata(imem_rsp_rdata),
        .dmem_req_valid(dmem_req_valid), .dmem_req_write(dmem_req_write), .dmem_req_addr(dmem_req_addr),
        .dmem_req_wdata(dmem_req_wdata), .dmem_req_wstrb(dmem_req_wstrb),
        .dmem_rsp_valid(dmem_rsp_valid), .dmem_rsp_rdata(dmem_rsp_rdata));

    imem_slave imem_u (.clk(clk), .reset(reset), .req_valid(imem_req_valid), .req_write(imem_req_write),
        .req_addr(imem_req_addr), .req_wdata(imem_req_wdata), .req_wstrb(imem_req_wstrb),
        .rsp_valid(imem_rsp_valid), .rsp_rdata(imem_rsp_rdata));

    dmem_slave #(.DELAY_CYCLES(0)) dmem_u (.clk(clk), .reset(reset), .req_valid(dmem_req_valid),
        .req_write(dmem_req_write), .req_addr(dmem_req_addr), .req_wdata(dmem_req_wdata),
        .req_wstrb(dmem_req_wstrb), .rsp_valid(dmem_rsp_valid), .rsp_rdata(dmem_rsp_rdata));

    integer i, cyc;
    wire fw1 = (DUT.ex_rs1!=0) && !DUT.wb_stall && DUT.wb_reg_write_en && (DUT.wb_dest_reg_sel==DUT.ex_rs1);
    wire fw2 = (DUT.ex_rs2!=0) && !DUT.wb_stall && DUT.wb_reg_write_en && (DUT.wb_dest_reg_sel==DUT.ex_rs2);
    reg [31:0] ex_i, wb_i;
    always @(posedge clk or negedge reset) begin
        if (!reset) begin ex_i <= 32'h13; wb_i <= 32'h13; end
        else if (!DUT.stall_pipeline) begin ex_i <= DUT.instruction; wb_i <= ex_i; end
    end
    initial begin
        for (i = 0; i < 1024; i = i + 1) imem_u.IMEM.imem[i] = 32'h00000013;
        imem_u.IMEM.imem[0]  = 32'h00700093; // 00 addi x1,x0,7
        imem_u.IMEM.imem[1]  = 32'h00208113; // 04 addi x2,x1,2   (RAW on x1)
        imem_u.IMEM.imem[2]  = 32'h200002b7; // 08 lui  x5,0x20000
        imem_u.IMEM.imem[3]  = 32'h022081b3; // 0c mul  x3,x1,x2
        imem_u.IMEM.imem[4]  = 32'h00118233; // 10 add  x4,x3,x1   (RAW on MUL)
        imem_u.IMEM.imem[5]  = 32'h0042a023; // 14 sw   x4,0(x5)
        imem_u.IMEM.imem[6]  = 32'h0002a303; // 18 lw   x6,0(x5)
        imem_u.IMEM.imem[7]  = 32'h001303b3; // 1c add  x7,x6,x1   (load-use)
        imem_u.IMEM.imem[8]  = 32'h00000663; // 20 beq  x0,x0,+12  (taken)
        imem_u.IMEM.imem[9]  = 32'h00100413; // 24 addi x8,x0,1    (wrong path)
        imem_u.IMEM.imem[10] = 32'h00200593; // 28 addi x11,x0,2   (wrong path)
        imem_u.IMEM.imem[11] = 32'h022244b3; // 2c div  x9,x4,x2
        imem_u.IMEM.imem[12] = 32'h00148513; // 30 addi x10,x9,1   (RAW on DIV)
        cyc = 0;
        #22 reset = 1;
        #1800;
        $display("FINAL x4=%0d x7=%0d x9=%0d x10=%0d x8=%0d",
            DUT.u_reg_file.regs[4], DUT.u_reg_file.regs[7], DUT.u_reg_file.regs[9],
            DUT.u_reg_file.regs[10], DUT.u_reg_file.regs[8]);
        $display("FINAL2 x2=%0d x3=%0d x6=%0d x11=%0d", DUT.u_reg_file.regs[2], DUT.u_reg_file.regs[3], DUT.u_reg_file.regs[6], DUT.u_reg_file.regs[11]);
        $finish;
    end

    // sample just before each rising edge = state visible during that cycle
    always @(negedge clk) if (reset) begin
        $display("T %0d id=%h ex=%h wb=%h stall=%b fw1=%b fw2=%b wbst=%b bst=%0d mst=%b mbusy=%b mdone=%b bs=%b bt=%b rv=%b ra=%h",
            cyc, DUT.instruction, ex_i, wb_i, DUT.stall_pipeline, fw1, fw2, DUT.wb_stall, DUT.bus_state, DUT.m_start, DUT.m_busy, DUT.m_done,
            DUT.branch_stall, DUT.branch_taken, bus_rsp_valid, bus_req_addr);
        cyc = cyc + 1;
    end
endmodule
