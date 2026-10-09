`timescale 1ns / 1ps

module tb_rv32m_pipeline;

    reg clk;
    reg reset;

    always #5 clk = ~clk;

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

    parameter DMEM_DELAY_CYCLES = 0;

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

    integer i;
    integer errors = 0;
    integer passed_checks = 0;
    integer div_stall_counter = 0;
    integer skid_div_stalls_verified = 0;
    reg     skid_check_failed = 0;

    initial begin
        clk = 0;
        reset = 0;

        // Initialize imem with NOPs
        for (i = 0; i < 1024; i = i + 1) begin
            imem_u.IMEM.imem[i] = 32'h00000013; // nop (addi x0, x0, 0)
        end

        // Program sequence:
        imem_u.IMEM.imem[0]  = 32'h00700093; // 00: addi x1, x0, 7
        imem_u.IMEM.imem[1]  = 32'h00900113; // 04: addi x2, x0, 9
        imem_u.IMEM.imem[2]  = 32'h022081b3; // 08: mul  x3, x1, x2       (x3 = 63)
        imem_u.IMEM.imem[3]  = 32'h00118233; // 0c: add  x4, x3, x1       (x4 = 70) [RAW forwarding from MUL]
        imem_u.IMEM.imem[4]  = 32'h024182b3; // 10: mul  x5, x3, x4       (x5 = 4410)
        imem_u.IMEM.imem[5]  = 32'h02128333; // 14: mul  x6, x5, x1       (x6 = 30870) [back-to-back MUL]
        imem_u.IMEM.imem[6]  = 32'h022343b3; // 18: div  x7, x6, x2       (x7 = 3430) [DIV after MUL]
        imem_u.IMEM.imem[7]  = 32'h02238433; // 1c: mul  x8, x7, x2       (x8 = 30870) [MUL after DIV]
        imem_u.IMEM.imem[8]  = 32'h021344b3; // 20: div  x9, x6, x1       (x9 = 4410)
        imem_u.IMEM.imem[9]  = 32'h02136533; // 24: rem  x10, x6, x1      (x10 = 0)
        imem_u.IMEM.imem[10] = 32'h020345b3; // 28: div  x11, x6, x0      (x11 = -1) [DIV by zero]
        imem_u.IMEM.imem[11] = 32'h02036633; // 2c: rem  x12, x6, x0      (x12 = 30870) [REM by zero]
        imem_u.IMEM.imem[12] = 32'h00000693; // 30: addi x13, x0, 0      (x13 = 0)
        imem_u.IMEM.imem[13] = 32'h00000463; // 34: beqz x0, 8            (branches to 3c)
        imem_u.IMEM.imem[14] = 32'h022086b3; // 38: mul  x13, x1, x2      (FLUSHED! MUST NOT WRITE x13)
        imem_u.IMEM.imem[15] = 32'h06300713; // 3c: addi x14, x0, 99      (x14 = 99)
        imem_u.IMEM.imem[16] = 32'h200007b7; // 40: lui  x15, 0x20000     (DMEM base 0x20000000)
        imem_u.IMEM.imem[17] = 32'h0067a023; // 44: sw   x6, 0(x15)       (DMEM[0] = 30870)
        imem_u.IMEM.imem[18] = 32'h02208833; // 48: mul  x16, x1, x2      (x16 = 63) [MUL after store]
        imem_u.IMEM.imem[19] = 32'h0007a883; // 4c: lw   x17, 0(x15)      (x17 = 30870) [DMEM load]
        imem_u.IMEM.imem[20] = 32'h0218c933; // 50: div  x18, x17, x1     (x18 = 4410) [DIV after load, load forwarding]
        imem_u.IMEM.imem[21] = 32'hffb00a13; // 54: addi x20, x0, -5      (x20 = -5 = 0xfffffffb)
        imem_u.IMEM.imem[22] = 32'h00200a93; // 58: addi x21, x0, 2       (x21 = 2)
        imem_u.IMEM.imem[23] = 32'h035a1b33; // 5c: mulh x22, x20, x21    (x22 = -1 = 0xffffffff)
        imem_u.IMEM.imem[24] = 32'h035a2bb3; // 60: mulhsu x23, x20, x21  (x23 = -1 = 0xffffffff)
        imem_u.IMEM.imem[25] = 32'h035a3c33; // 64: mulhu x24, x20, x21   (x24 = 1)
        imem_u.IMEM.imem[26] = 32'h035a5cb3; // 68: divu x25, x20, x21    (x25 = 0x7ffffffd)
        imem_u.IMEM.imem[27] = 32'h035a7d33; // 6c: remu x26, x20, x21    (x26 = 1)
        imem_u.IMEM.imem[28] = 32'h00100d93; // 70: addi x27, x0, 1       (x27 = 1) [COMPLETION FLAG]
        imem_u.IMEM.imem[29] = 32'h0000006f; // 74: jal  x0, 0            (halt loop)

        #100;
        reset = 1;

        // Wait until completion flag x27 is set
        wait (DUT.u_reg_file.regs[27] == 32'd1);
        @(posedge clk);
        #1; // Settled

        $display("\n=======================================================");
        $display("   RV32M PIPELINE INTEGRATION VERIFICATION");
        $display("=======================================================\n");

        check_reg(1,  32'd7,          "x1  = addi 7");
        check_reg(2,  32'd9,          "x2  = addi 9");
        check_reg(3,  32'd63,         "x3  = mul 7*9");
        check_reg(4,  32'd70,         "x4  = add 63+7 (RAW forwarding)");
        check_reg(5,  32'd4410,       "x5  = mul 63*70");
        check_reg(6,  32'd30870,      "x6  = mul 4410*7 (back-to-back mul)");
        check_reg(7,  32'd3430,       "x7  = div 30870/9 (div after mul)");
        check_reg(8,  32'd30870,      "x8  = mul 3430*9 (mul after div)");
        check_reg(9,  32'd4410,       "x9  = div 30870/7");
        check_reg(10, 32'd0,          "x10 = rem 30870%7");
        check_reg(11, 32'hffffffff,   "x11 = div by zero (signed -1)");
        check_reg(12, 32'd30870,      "x12 = rem by zero (returns dividend)");
        check_reg(13, 32'd0,          "x13 = branch flushed MUL (must remain 0)");
        check_reg(14, 32'd99,         "x14 = target branch reached");
        check_reg(15, 32'h20000000,   "x15 = lui dmem base");
        check_reg(16, 32'd63,         "x16 = mul after store");
        check_reg(17, 32'd30870,      "x17 = lw from dmem");
        check_reg(18, 32'd4410,       "x18 = div after lw (load forwarding)");
        check_reg(20, 32'hfffffffb,   "x20 = addi -5");
        check_reg(21, 32'd2,          "x21 = addi 2");
        check_reg(22, 32'hffffffff,   "x22 = mulh (-5 * 2) >> 32");
        check_reg(23, 32'hffffffff,   "x23 = mulhsu (-5 * 2) >> 32");
        check_reg(24, 32'd1,          "x24 = mulhu (0xfffffffb * 2) >> 32");
        check_reg(25, 32'h7ffffffd,   "x25 = divu 0xfffffffb / 2");
        check_reg(26, 32'd1,          "x26 = remu 0xfffffffb % 2");
        check_reg(27, 32'd1,          "x27 = completion flag");

        // Verify dmem stored value
        if (dmem_u.DMEM.dmem[0] !== 32'd30870) begin
            $display("[FAIL] DMEM[0] expected 30870, got %d", dmem_u.DMEM.dmem[0]);
            errors = errors + 1;
        end else begin
            $display("[PASS] DMEM[0] store verified = 30870");
            passed_checks = passed_checks + 1;
        end

        // Verify skid-buffer retention during DIV stalls
        if (skid_check_failed || skid_div_stalls_verified < 4) begin
            $display("[FAIL] Skid-buffer retention check failed (stalls_verified=%0d, failed=%b)",
                     skid_div_stalls_verified, skid_check_failed);
            errors = errors + 1;
        end else begin
            $display("[PASS] Skid-buffer retention and bus arbitration verified across %0d DIV stalls",
                     skid_div_stalls_verified);
            passed_checks = passed_checks + 1;
        end

        $display("\n=======================================================");
        if (errors == 0) begin
            $display("   *** ALL %0d RV32M PIPELINE TESTS PASSED (0 ERRORS) ***", passed_checks);
        end else begin
            $display("   *** PIPELINE TESTS FAILED: %0d ERRORS (PASSED %0d) ***", errors, passed_checks);
        end
        $display("=======================================================\n");

        if (errors > 0) $fatal(1, "RV32M pipeline verification failed");
        $finish;
    end

    // Concurrent skid-buffer and bus arbiter monitor during long DIV stalls
    reg prev_if_buf_valid = 0;
    always @(posedge clk) begin
        if (reset) begin
            if (DUT.ex_m && DUT.ex_alu_op[2] && DUT.m_stalling) begin
                div_stall_counter <= div_stall_counter + 1;
                // If a buffer became valid during the stall, it must remain valid until pipeline advances
                if (div_stall_counter > 1 && prev_if_buf_valid && !DUT.if_buf_valid) begin
                    $display("[FAIL] if_buf_valid dropped during active DIV stall at T=%0t!", $time);
                    skid_check_failed <= 1;
                end
                // Bus must never launch a spurious IF fetch during an active M stall
                if (DUT.bus_state == 2'b01 && div_stall_counter > 2) begin // ST_WAIT_IF
                    $display("[FAIL] Spurious instruction fetch launched during DIV stall at T=%0t!", $time);
                    skid_check_failed <= 1;
                end
            end else begin
                if (div_stall_counter >= 30) begin
                    skid_div_stalls_verified <= skid_div_stalls_verified + 1;
                end
                div_stall_counter <= 0;
            end
            prev_if_buf_valid <= DUT.if_buf_valid;
        end
    end

    // Timeout guard
    initial begin
        #10000;
        $display("[ERROR] TIMEOUT reached in tb_rv32m_pipeline!");
        $fatal(1, "Simulation timed out");
    end

    task check_reg;
        input integer r;
        input [31:0] expected;
        input [383:0] test_name;
        reg [31:0] actual;
        begin
            actual = DUT.u_reg_file.regs[r];
            if (actual !== expected) begin
                $display("[FAIL] %0s: Reg x%0d expected %08x (%0d), got %08x (%0d)",
                         test_name, r, expected, $signed(expected), actual, $signed(actual));
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s: Reg x%0d = %08x (%0d)",
                         test_name, r, actual, $signed(actual));
                passed_checks = passed_checks + 1;
            end
        end
    endtask

endmodule
