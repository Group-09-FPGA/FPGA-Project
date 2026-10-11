`timescale 1ns / 1ps

module tb_cpu_core;

////////////////////////////////////////////////////////////
// CLOCK & RESET
////////////////////////////////////////////////////////////
reg clk;
reg reset;

// 100 MHz clock
initial begin
	clk = 0;
	forever #5 clk = ~clk;
end

// reset (active low in our CPU)
initial begin
	reset = 0;
	#100;
	reset = 1;
end


////////////////////////////////////////////////////////////
// BUS SIGNALS
////////////////////////////////////////////////////////////
    wire        bus_req_valid;
    wire        bus_req_write;
    wire [31:0] bus_req_addr;
    wire [31:0] bus_req_wdata;
    wire [ 3:0] bus_req_wstrb;
    wire        bus_rsp_valid;
    wire [31:0] bus_rsp_rdata;
    wire        bus_rsp_error;
    
    wire        imem_req_valid;
    wire        imem_req_write;
    wire [31:0] imem_req_addr;
    wire [31:0] imem_req_wdata;
    wire [ 3:0] imem_req_wstrb;
    wire        imem_rsp_valid;
    wire [31:0] imem_rsp_rdata;

    wire        dmem_req_valid;
    wire        dmem_req_write;
    wire [31:0] dmem_req_addr;
    wire [31:0] dmem_req_wdata;
    wire [ 3:0] dmem_req_wstrb;
    wire        dmem_rsp_valid;
    wire [31:0] dmem_rsp_rdata;

    wire exception;
    wire [31:0] pc_out;
    
    // Optional delay for DMEM (can be changed to test delayed slave)
    parameter DMEM_DELAY_CYCLES = 0;


////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
////////////////////////////////////////////////////////////
// DUT : PIPELINE CPU
cpu_core DUT (
	.clk(clk),
	.reset(reset),
	.stall(1'b0),
	.exception(exception),
	.pc_out(pc_out),

    .bus_req_valid(bus_req_valid),
    .bus_req_write(bus_req_write),
    .bus_req_addr(bus_req_addr),
    .bus_req_wdata(bus_req_wdata),
    .bus_req_wstrb(bus_req_wstrb),
    .bus_rsp_valid(bus_rsp_valid),
    .bus_rsp_rdata(bus_rsp_rdata),
    .bus_rsp_error(bus_rsp_error)
);

sys_bus_interconnect interconnect_u (
    .clk(clk),
    .reset(reset),
    .cpu_req_valid(bus_req_valid),
    .cpu_req_write(bus_req_write),
    .cpu_req_addr(bus_req_addr),
    .cpu_req_wdata(bus_req_wdata),
    .cpu_req_wstrb(bus_req_wstrb),
    .cpu_rsp_valid(bus_rsp_valid),
    .cpu_rsp_rdata(bus_rsp_rdata),
    .cpu_rsp_error(bus_rsp_error),
    
    .imem_req_valid(imem_req_valid),
    .imem_req_write(imem_req_write),
    .imem_req_addr(imem_req_addr),
    .imem_req_wdata(imem_req_wdata),
    .imem_req_wstrb(imem_req_wstrb),
    .imem_rsp_valid(imem_rsp_valid),
    .imem_rsp_rdata(imem_rsp_rdata),
    
    .dmem_req_valid(dmem_req_valid),
    .dmem_req_write(dmem_req_write),
    .dmem_req_addr(dmem_req_addr),
    .dmem_req_wdata(dmem_req_wdata),
    .dmem_req_wstrb(dmem_req_wstrb),
    .dmem_rsp_valid(dmem_rsp_valid),
    .dmem_rsp_rdata(dmem_rsp_rdata)
);


////////////////////////////////////////////////////////////
// INSTRUCTION MEMORY SLAVE
////////////////////////////////////////////////////////////
imem_slave imem_u (
    .clk(clk),
    .reset(reset),
    .req_valid(imem_req_valid),
    .req_write(imem_req_write),
    .req_addr(imem_req_addr),
    .req_wdata(imem_req_wdata),
    .req_wstrb(imem_req_wstrb),
    .rsp_valid(imem_rsp_valid),
    .rsp_rdata(imem_rsp_rdata)
);

////////////////////////////////////////////////////////////
// DATA MEMORY SLAVE
////////////////////////////////////////////////////////////
dmem_slave #(
    .DELAY_CYCLES(DMEM_DELAY_CYCLES)
) dmem_u (
    .clk(clk),
    .reset(reset),
    .req_valid(dmem_req_valid),
    .req_write(dmem_req_write),
    .req_addr(dmem_req_addr),
    .req_wdata(dmem_req_wdata),
    .req_wstrb(dmem_req_wstrb),
    .rsp_valid(dmem_rsp_valid),
    .rsp_rdata(dmem_rsp_rdata)
);


////////////////////////////////////////////////////////////
// SIMULATION TIME & LOGGING
////////////////////////////////////////////////////////////
initial begin
	$dumpfile("pipeline.vcd");
	$dumpvars(0, tb_cpu_core);
	#20000;   // run long enough to see program execute
	$finish;
end










    integer test_errors = 0;
    task check_result(input [199:0] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual !== expected) begin
                $display("[FAIL] %0s: expected %08x (%0d), got %08x (%0d)", name, expected, $signed(expected), actual, $signed(actual));
                test_errors = test_errors + 1;
            end else begin
                $display("[PASS] %0s: %08x (%0d)", name, actual, $signed(actual));
            end
        end
    endtask

always @(posedge clk) begin
    if (reset) begin
        $display("next_pc = %08x", DUT.fetch_pc);

        if (DUT.wb_reg_write_en && DUT.wb_dest_reg_sel == 15 && !DUT.wb_stall && !DUT.stall_pipeline && !DUT.wb_mem_to_reg) begin
            $display("time:\t%10t ,result =\t%10d", $time, $signed(DUT.wb_result));
        end

        // Dynamic stop condition for baseline C workloads
        if (DUT.instruction == 32'h00008067) begin
            $display("All instructions are Fetched");
            $display("next_pc = 00000000");
            #10 $finish;
        end

        // Terminal halt loop check (pass_loop / fail_loop: j .)
        if (DUT.instruction == 32'h0000006f) begin
            $display("[INFO] Terminal halt loop reached at PC = %08x", DUT.fetch_pc);
            repeat (10) @(posedge clk);

            if (DUT.u_reg_file.regs[22] == 32'hcafe || DUT.u_reg_file.regs[23] != 32'h0) begin
                $display("\n=======================================================");
                $display("       RV32M HARDWARE TEST PROGRAM VERIFICATION");
                $display("=======================================================");

                check_result("x3  (MUL 6*7)",           DUT.u_reg_file.regs[3],  32'd42);
                check_result("x6  (MULH -5*2)",          DUT.u_reg_file.regs[6],  32'hffffffff);
                check_result("x7  (MULHU 0xfffffffb*2)", DUT.u_reg_file.regs[7],  32'd1);
                check_result("x8  (MULHSU -5*2)",        DUT.u_reg_file.regs[8],  32'hffffffff);
                check_result("x11 (DIV 100/7)",          DUT.u_reg_file.regs[11], 32'd14);
                check_result("x12 (DIVU unsigned)",      DUT.u_reg_file.regs[12], 32'd2147483645);
                check_result("x13 (REM 100%7)",          DUT.u_reg_file.regs[13], 32'd2);
                check_result("x14 (REMU unsigned)",      DUT.u_reg_file.regs[14], 32'd1);
                check_result("x16 (DIV by zero)",        DUT.u_reg_file.regs[16], 32'hffffffff);
                check_result("x17 (DIVU by zero)",       DUT.u_reg_file.regs[17], 32'hffffffff);
                check_result("x18 (REM by zero)",        DUT.u_reg_file.regs[18], 32'd100);
                check_result("x19 (REMU by zero)",       DUT.u_reg_file.regs[19], 32'd100);
                check_result("x20 (DIV overflow)",       DUT.u_reg_file.regs[20], 32'h80000000);
                check_result("x21 (REM overflow)",       DUT.u_reg_file.regs[21], 32'd0);
                check_result("x22 (PASS sentinel)",      DUT.u_reg_file.regs[22], 32'hcafe);

                // Memory checks
                check_result("DMEM[0]  (MUL store)",    dmem_u.DMEM.dmem[0],  32'd42);
                check_result("DMEM[1]  (MULH store)",   dmem_u.DMEM.dmem[1],  32'hffffffff);
                check_result("DMEM[2]  (MULHU store)",  dmem_u.DMEM.dmem[2],  32'd1);
                check_result("DMEM[3]  (MULHSU store)", dmem_u.DMEM.dmem[3],  32'hffffffff);
                check_result("DMEM[4]  (DIV store)",    dmem_u.DMEM.dmem[4],  32'd14);
                check_result("DMEM[5]  (DIVU store)",   dmem_u.DMEM.dmem[5],  32'd2147483645);
                check_result("DMEM[6]  (REM store)",    dmem_u.DMEM.dmem[6],  32'd2);
                check_result("DMEM[7]  (REMU store)",   dmem_u.DMEM.dmem[7],  32'd1);
                check_result("DMEM[8]  (DIV/0 store)",  dmem_u.DMEM.dmem[8],  32'hffffffff);
                check_result("DMEM[9]  (DIVU/0 store)", dmem_u.DMEM.dmem[9],  32'hffffffff);
                check_result("DMEM[10] (REM/0 store)",  dmem_u.DMEM.dmem[10], 32'd100);
                check_result("DMEM[11] (REMU/0 store)", dmem_u.DMEM.dmem[11], 32'd100);
                check_result("DMEM[12] (DIVovf store)", dmem_u.DMEM.dmem[12], 32'h80000000);
                check_result("DMEM[13] (REMovf store)", dmem_u.DMEM.dmem[13], 32'd0);
                check_result("DMEM[14] (PASS store)",   dmem_u.DMEM.dmem[14], 32'hcafe);

                if (test_errors == 0) begin
                    $display("\n>>> ALL RV32M TEST CHECKS PASSED (0 ERRORS) <<<\n");
                end else begin
                    $display("\n>>> RV32M TEST FAILED: %0d ERRORS <<<\n", test_errors);
                end
                $display("=======================================================\n");
            end
            #10 $finish;
        end
    end
end

endmodule
