`timescale 1ns / 1ps
// Trace testbench for the report timing diagram. Same wiring as
// sim/unit/core/tb_rv32m_pipeline.v; dumps one CSV row per clock cycle.
module tb_timing_trace;
    reg clk = 0;
    reg reset = 0;
    always #5 clk = ~clk;

    wire        bus_req_valid, bus_req_write, bus_rsp_valid, bus_rsp_error;
    wire [31:0] bus_req_addr, bus_req_wdata, bus_rsp_rdata;
    wire [ 3:0] bus_req_wstrb;
    wire        imem_req_valid, imem_req_write, imem_rsp_valid;
    wire [31:0] imem_req_addr, imem_req_wdata, imem_rsp_rdata;
    wire [ 3:0] imem_req_wstrb;
    wire        dmem_req_valid, dmem_req_write, dmem_rsp_valid;
    wire [31:0] dmem_req_addr, dmem_req_wdata, dmem_rsp_rdata;
    wire [ 3:0] dmem_req_wstrb;
    wire        exception;
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

    integer i, cyc, fd;
    initial begin
        for (i = 0; i < 1024; i = i + 1) imem_u.IMEM.imem[i] = 32'h00000013;
        imem_u.IMEM.imem[0]  = 32'h00700093; // 00 addi x1,x0,7
        imem_u.IMEM.imem[1]  = 32'h00900113; // 04 addi x2,x0,9
        imem_u.IMEM.imem[2]  = 32'h022081b3; // 08 mul  x3,x1,x2
        imem_u.IMEM.imem[3]  = 32'h00118233; // 0c add  x4,x3,x1   RAW on MUL
        imem_u.IMEM.imem[4]  = 32'h200002b7; // 10 lui  x5,0x20000
        imem_u.IMEM.imem[5]  = 32'h0042a023; // 14 sw   x4,0(x5)
        imem_u.IMEM.imem[6]  = 32'h0002a303; // 18 lw   x6,0(x5)
        imem_u.IMEM.imem[7]  = 32'h001303b3; // 1c add  x7,x6,x1   load-use
        imem_u.IMEM.imem[8]  = 32'h00000463; // 20 beq  x0,x0,+8   taken
        imem_u.IMEM.imem[9]  = 32'h00100413; // 24 addi x8,x0,1    must be flushed
        imem_u.IMEM.imem[10] = 32'h021244b3; // 28 div  x9,x4,x1
        imem_u.IMEM.imem[11] = 32'h00148513; // 2c addi x10,x9,1   RAW on DIV
        fd = $fopen("trace.csv", "w");
        $fwrite(fd, "cyc,fetch_pc,id_pc,ex_pc,stall,bstate,m_busy,m_done,m_stalling,branch_taken,wb_stall,wb_rd,wb_we,req_v,req_w,rsp_v,ex_m,ex_mem_to_reg,wb_mem_write,fwd_a,fwd_b,wb_stalling,ex_stalling,if_stalling,branch_stall,m_start,ex_rs1,ex_rs2\n");
        #22 reset = 1;
        for (cyc = 0; cyc < 110; cyc = cyc + 1) begin
            @(negedge clk);
            $fwrite(fd, "%0d,%h,%h,%h,%b,%0d,%b,%b,%b,%b,%b,%0d,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%0d,%0d\n", cyc,
                DUT.fetch_pc, DUT.id_pc, DUT.ex_pc, DUT.stall_pipeline, DUT.bus_state,
                DUT.m_busy, DUT.m_done, DUT.m_stalling, DUT.branch_taken, DUT.wb_stall,
                DUT.wb_dest_reg_sel, DUT.wb_reg_write_en, bus_req_valid, bus_req_write,
                bus_rsp_valid, DUT.ex_m, DUT.ex_mem_to_reg, DUT.wb_mem_write,
                (DUT.ex_rs1!=0 && !DUT.wb_stall && DUT.wb_reg_write_en && DUT.wb_dest_reg_sel==DUT.ex_rs1),
                (DUT.ex_rs2!=0 && !DUT.wb_stall && DUT.wb_reg_write_en && DUT.wb_dest_reg_sel==DUT.ex_rs2),
                DUT.wb_stalling, DUT.ex_stalling, DUT.if_stalling, DUT.branch_stall, DUT.m_start, DUT.ex_rs1, DUT.ex_rs2);
        end
        $fclose(fd);
        $display("x1=%0d x3=%0d x4=%0d x6=%0d x7=%0d x8=%0d x9=%0d x10=%0d",
            DUT.u_reg_file.regs[1], DUT.u_reg_file.regs[3], DUT.u_reg_file.regs[4],
            DUT.u_reg_file.regs[6], DUT.u_reg_file.regs[7], DUT.u_reg_file.regs[8],
            DUT.u_reg_file.regs[9], DUT.u_reg_file.regs[10]);
        $finish;
    end
endmodule
