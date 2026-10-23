`timescale 1ns/1ps

module tb_rv32m_unit;

    reg         clk;
    reg         reset;
    reg         start;
    reg  [2:0]  funct3;
    reg  [31:0] op1;
    reg  [31:0] op2;
    reg         stall_pipeline;
    wire        busy;
    wire        done;
    wire [31:0] result;

    // Clock generator: 10ns period (100MHz)
    always #5 clk = ~clk;

    rv32m_unit u_dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .funct3(funct3),
        .op1(op1),
        .op2(op2),
        .stall_pipeline(stall_pipeline),
        .busy(busy),
        .done(done),
        .result(result)
    );

    // Encodings
    localparam F3_MUL    = 3'b000;
    localparam F3_MULH   = 3'b001;
    localparam F3_MULHSU = 3'b010;
    localparam F3_MULHU  = 3'b011;
    localparam F3_DIV    = 3'b100;
    localparam F3_DIVU   = 3'b101;
    localparam F3_REM    = 3'b110;
    localparam F3_REMU   = 3'b111;

    integer pass_count = 0;
    integer fail_count = 0;

    // Task to run an operation and check result and latency
    task run_op(
        input [2:0]  f3,
        input [31:0] a,
        input [31:0] b,
        input [31:0] expected,
        input [31:0] exp_cycles,
        input [127:0] test_name
    );
        integer active_edges;
        integer elapsed_periods;
        time    t_start, t_done;
        integer exp_periods;
        begin
            exp_periods = (exp_cycles == 3) ? 2 : 32;

            @(posedge clk);
            #1;
            funct3 = f3;
            op1    = a;
            op2    = b;
            start  = 1'b1;

            @(posedge clk);
            #1;
            t_start = $time - 1; // accepted start posedge clk
            start   = 1'b0;
            active_edges = 1;

            while (!done) begin
                @(posedge clk);
                #1;
                active_edges = active_edges + 1;
                if (active_edges > 50) begin
                    $display("[FAIL] Timeout waiting for done on %0s", test_name);
                    fail_count = fail_count + 1;
                    $finish;
                end
            end
            t_done = $time - 1; // done posedge clk
            elapsed_periods = (t_done - t_start) / 10;

            // Check latency under both conventions
            if (active_edges != exp_cycles || elapsed_periods != exp_periods) begin
                $display("[FAIL] %0s: Latency mismatch: active_edges=%0d (exp %0d), elapsed_periods=%0d (exp %0d)",
                         test_name, active_edges, exp_cycles, elapsed_periods, exp_periods);
                fail_count = fail_count + 1;
            end

            // Check result
            if (result !== expected) begin
                $display("[FAIL] %0s: Result mismatch! a=%08x, b=%08x, got=%08x, expected=%08x", test_name, a, b, result, expected);
                fail_count = fail_count + 1;
            end else begin
                $display("[PASS] %0s: a=%08x, b=%08x -> res=%08x (edges=%0d, elapsed_periods=%0d)",
                         test_name, a, b, result, active_edges, elapsed_periods);
                pass_count = pass_count + 1;
            end

            // Advance pipeline to accept result
            stall_pipeline = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    // Independent architectural reference model task
    task check_ref(
        input [2:0]   f3,
        input [31:0]  a,
        input [31:0]  b,
        input [127:0] tname
    );
        reg [31:0] exp_val;
        reg signed [63:0] prod_signed;
        reg signed [63:0] prod_su;
        reg [63:0] prod_unsigned;
        integer exp_cyc;
        begin
            case (f3)
                F3_MUL: begin
                    prod_unsigned = {32'b0, a} * {32'b0, b};
                    exp_val = prod_unsigned[31:0];
                    exp_cyc = 3;
                end
                F3_MULH: begin
                    prod_signed = $signed({{32{a[31]}}, a}) * $signed({{32{b[31]}}, b});
                    exp_val = prod_signed[63:32];
                    exp_cyc = 3;
                end
                F3_MULHSU: begin
                    prod_su = $signed({{32{a[31]}}, a}) * $signed({32'b0, b});
                    exp_val = prod_su[63:32];
                    exp_cyc = 3;
                end
                F3_MULHU: begin
                    prod_unsigned = {32'b0, a} * {32'b0, b};
                    exp_val = prod_unsigned[63:32];
                    exp_cyc = 3;
                end
                F3_DIV: begin
                    exp_cyc = 33;
                    if (b == 32'd0) begin
                        exp_val = 32'hFFFFFFFF;
                    end else if (a == 32'h80000000 && b == 32'hFFFFFFFF) begin
                        exp_val = 32'h80000000;
                    end else begin
                        exp_val = $signed(a) / $signed(b);
                    end
                end
                F3_DIVU: begin
                    exp_cyc = 33;
                    if (b == 32'd0) begin
                        exp_val = 32'hFFFFFFFF;
                    end else begin
                        exp_val = a / b;
                    end
                end
                F3_REM: begin
                    exp_cyc = 33;
                    if (b == 32'd0) begin
                        exp_val = a;
                    end else if (a == 32'h80000000 && b == 32'hFFFFFFFF) begin
                        exp_val = 32'h0;
                    end else begin
                        exp_val = $signed(a) % $signed(b);
                    end
                end
                F3_REMU: begin
                    exp_cyc = 33;
                    if (b == 32'd0) begin
                        exp_val = a;
                    end else begin
                        exp_val = a % b;
                    end
                end
            endcase
            run_op(f3, a, b, exp_val, exp_cyc, tname);
        end
    endtask

    initial begin
        clk = 0;
        reset = 0;
        start = 0;
        funct3 = 0;
        op1 = 0;
        op2 = 0;
        stall_pipeline = 0;

        #25;
        reset = 1;
        @(posedge clk);
        #1;

        $display("=== STARTING RV32M UNIT-LEVEL TESTS ===");

        // --- 7.2 Specification Multiplication Reference Vectors ---
        // MULHU FFFFFFFF, FFFFFFFF -> FFFFFFFE (3 cycles)
        run_op(F3_MULHU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE, 3, "MULHU_ref1");

        // MULH FFFFFFFF, FFFFFFFF -> 00000000 (3 cycles)
        run_op(F3_MULH, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'h00000000, 3, "MULH_ref2");

        // MULHSU FFFFFFFF, FFFFFFFF -> FFFFFFFF (3 cycles)
        run_op(F3_MULHSU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, 3, "MULHSU_ref3");

        // MUL FFFFFFFF, 00000002 -> FFFFFFFE (3 cycles)
        run_op(F3_MUL, 32'hFFFFFFFF, 32'h00000002, 32'hFFFFFFFE, 3, "MUL_ref4");

        // MULH 7FFFFFFF, 7FFFFFFF -> 3FFFFFFF (3 cycles)
        run_op(F3_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h3FFFFFFF, 3, "MULH_ref5");

        // MULH 80000000, 80000000 -> 40000000 (3 cycles)
        run_op(F3_MULH, 32'h80000000, 32'h80000000, 32'h40000000, 3, "MULH_ref6");

        // MULHSU 80000000, 80000000 -> C0000000 (3 cycles)
        run_op(F3_MULHSU, 32'h80000000, 32'h80000000, 32'hC0000000, 3, "MULHSU_ref7");

        // MULHU 80000000, 80000000 -> 40000000 (3 cycles)
        run_op(F3_MULHU, 32'h80000000, 32'h80000000, 32'h40000000, 3, "MULHU_ref8");

        // --- Additional Multiplier Corner Cases ---
        run_op(F3_MUL, 32'd0, 32'd12345, 32'd0, 3, "MUL_zero_a");
        run_op(F3_MUL, 32'd12345, 32'd0, 32'd0, 3, "MUL_zero_b");
        run_op(F3_MUL, 32'd7, 32'd9, 32'd63, 3, "MUL_pos_pos");
        run_op(F3_MUL, -32'd7, 32'd9, -32'd63, 3, "MUL_neg_pos");
        run_op(F3_MUL, -32'd7, -32'd9, 32'd63, 3, "MUL_neg_neg");

        // --- 5.6 RISC-V Division & Remainder Edge Cases (33 cycles) ---
        // Divide by zero:
        // DIV x / 0 -> -1 (FFFFFFFF)
        run_op(F3_DIV, 32'd1234, 32'd0, 32'hFFFFFFFF, 33, "DIV_by_zero_pos");
        run_op(F3_DIV, -32'd1234, 32'd0, 32'hFFFFFFFF, 33, "DIV_by_zero_neg");
        // DIVU x / 0 -> 2^32 - 1 (FFFFFFFF)
        run_op(F3_DIVU, 32'd1234, 32'd0, 32'hFFFFFFFF, 33, "DIVU_by_zero");
        // REM x % 0 -> x
        run_op(F3_REM, 32'd1234, 32'd0, 32'd1234, 33, "REM_by_zero_pos");
        run_op(F3_REM, -32'd1234, 32'd0, -32'd1234, 33, "REM_by_zero_neg");
        // REMU x % 0 -> x
        run_op(F3_REMU, 32'd1234, 32'd0, 32'd1234, 33, "REMU_by_zero");

        // Signed overflow:
        // 0x80000000 / 0xFFFFFFFF -> 0x80000000
        run_op(F3_DIV, 32'h80000000, 32'hFFFFFFFF, 32'h80000000, 33, "DIV_overflow");
        // 0x80000000 % 0xFFFFFFFF -> 0
        run_op(F3_REM, 32'h80000000, 32'hFFFFFFFF, 32'h00000000, 33, "REM_overflow");

        // Truncation towards zero & sign rules:
        // 7 / 2 = 3, 7 % 2 = 1
        run_op(F3_DIV, 32'd7, 32'd2, 32'd3, 33, "DIV_7_2");
        run_op(F3_REM, 32'd7, 32'd2, 32'd1, 33, "REM_7_2");
        // -7 / 2 = -3, -7 % 2 = -1
        run_op(F3_DIV, -32'd7, 32'd2, -32'd3, 33, "DIV_neg7_2");
        run_op(F3_REM, -32'd7, 32'd2, -32'd1, 33, "REM_neg7_2");
        // 7 / -2 = -3, 7 % -2 = 1
        run_op(F3_DIV, 32'd7, -32'd2, -32'd3, 33, "DIV_7_neg2");
        run_op(F3_REM, 32'd7, -32'd2, 32'd1, 33, "REM_7_neg2");
        // -7 / -2 = 3, -7 % -2 = -1
        run_op(F3_DIV, -32'd7, -32'd2, 32'd3, 33, "DIV_neg7_neg2");
        run_op(F3_REM, -32'd7, -32'd2, -32'd1, 33, "REM_neg7_neg2");

        // Equal operands:
        run_op(F3_DIV, 32'd42, 32'd42, 32'd1, 33, "DIV_equal");
        run_op(F3_REM, 32'd42, 32'd42, 32'd0, 33, "REM_equal");
        run_op(F3_DIVU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd1, 33, "DIVU_max_equal");
        run_op(F3_REMU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0, 33, "REMU_max_equal");

        // Dividend smaller than divisor:
        run_op(F3_DIV, 32'd3, 32'd10, 32'd0, 33, "DIV_smaller");
        run_op(F3_REM, 32'd3, 32'd10, 32'd3, 33, "REM_smaller");
        run_op(F3_DIV, -32'd3, 32'd10, 32'd0, 33, "DIV_neg_smaller");
        run_op(F3_REM, -32'd3, 32'd10, -32'd3, 33, "REM_neg_smaller");

        // Divisor 1 and -1:
        run_op(F3_DIV, 32'd12345, 32'd1, 32'd12345, 33, "DIV_div1");
        run_op(F3_REM, 32'd12345, 32'd1, 32'd0, 33, "REM_div1");
        run_op(F3_DIV, 32'd12345, -32'd1, -32'd12345, 33, "DIV_div_neg1");
        run_op(F3_REM, 32'd12345, -32'd1, 32'd0, 33, "REM_div_neg1");

        // Zero dividend:
        run_op(F3_DIV, 32'd0, 32'd12345, 32'd0, 33, "DIV_zero_dividend");
        run_op(F3_REM, 32'd0, 32'd12345, 32'd0, 33, "REM_zero_dividend");

        // Large unsigned division:
        run_op(F3_DIVU, 32'hFFFFFFFF, 32'd2, 32'h7FFFFFFF, 33, "DIVU_max_half");
        run_op(F3_REMU, 32'hFFFFFFFF, 32'd2, 32'd1, 33, "REMU_max_half");

        // --- Section 4.2 Comprehensive Directed Multiplier Tests ---
        // Zero and One
        run_op(F3_MUL,    32'd1,        32'd1,        32'd1,        3, "MUL_1_1");
        run_op(F3_MUL,    32'd1,       -32'd1,       -32'd1,        3, "MUL_1_neg1");
        run_op(F3_MUL,   -32'd1,        32'd1,       -32'd1,        3, "MUL_neg1_1");
        run_op(F3_MUL,   -32'd1,       -32'd1,        32'd1,        3, "MUL_neg1_neg1");
        run_op(F3_MULH,   32'd1,        32'd1,        32'd0,        3, "MULH_1_1");
        run_op(F3_MULH,   32'd1,       -32'd1,        32'hFFFFFFFF, 3, "MULH_1_neg1");
        run_op(F3_MULH,  -32'd1,        32'd1,        32'hFFFFFFFF, 3, "MULH_neg1_1");
        run_op(F3_MULH,  -32'd1,       -32'd1,        32'd0,        3, "MULH_neg1_neg1");
        run_op(F3_MULHSU, 32'd1,        32'd1,        32'd0,        3, "MULHSU_1_1");
        run_op(F3_MULHSU,-32'd1,        32'd1,        32'hFFFFFFFF, 3, "MULHSU_neg1_1");
        run_op(F3_MULHSU, 32'd1,        32'hFFFFFFFF, 32'd0,        3, "MULHSU_1_uFFFFFFFF");
        run_op(F3_MULHU,  32'd1,        32'd1,        32'd0,        3, "MULHU_1_1");
        run_op(F3_MULHU,  32'd1,        32'hFFFFFFFF, 32'd0,        3, "MULHU_1_FFFFFFFF");
        run_op(F3_MULHU,  32'hFFFFFFFF, 32'd1,        32'd0,        3, "MULHU_FFFFFFFF_1");

        // Upper products with significant bits above bit 31
        run_op(F3_MUL,    32'h10000000, 32'h10,       32'h00000000, 3, "MUL_overflow_bits");
        run_op(F3_MULHU,  32'h10000000, 32'h10,       32'h00000001, 3, "MULHU_high_bit");
        run_op(F3_MULH,   32'h40000000, 32'd2,        32'h00000000, 3, "MULH_pos_near_overflow");
        run_op(F3_MULH,   32'h40000000, 32'd4,        32'h00000001, 3, "MULH_high_bit");
        run_op(F3_MULH,  -32'h40000000, 32'd4,        32'hFFFFFFFF, 3, "MULH_neg_high");

        // Extreme values: 0x80000000, 0x7FFFFFFF, 0xFFFFFFFF
        run_op(F3_MUL,    32'h80000000, 32'h80000000, 32'h00000000, 3, "MUL_min_min");
        run_op(F3_MUL,    32'h7FFFFFFF, 32'h7FFFFFFF, 32'h00000001, 3, "MUL_max_max");
        run_op(F3_MUL,    32'h80000000, 32'h7FFFFFFF, 32'h80000000, 3, "MUL_min_max");
        run_op(F3_MULH,   32'h80000000, 32'h7FFFFFFF, 32'hC0000000, 3, "MULH_min_max");
        run_op(F3_MULHSU, 32'h7FFFFFFF, 32'h80000000, 32'h3FFFFFFF, 3, "MULHSU_max_min");
        run_op(F3_MULHSU,-32'd1,        32'h80000000, 32'hFFFFFFFF, 3, "MULHSU_neg1_min");

        // --- Randomized Testing Against Independent Reference Model ---
        $display("Testing 160 randomized vectors against independent mathematical model...");
        begin : rand_block
            integer r_i;
            reg [31:0] rand_a, rand_b;
            reg [2:0]  rand_op;
            for (r_i = 0; r_i < 160; r_i = r_i + 1) begin
                rand_op = r_i % 8;
                rand_a = $random;
                rand_b = $random;
                check_ref(rand_op, rand_a, rand_b, "RANDOM_TEST");
            end
        end

        // --- Back-to-Back Sequences & Transitions ---
        $display("Testing Back-to-back Multiplier -> Divider...");
        run_op(F3_MUL, 32'd10, 32'd20, 32'd200, 3, "B2B_MUL");
        run_op(F3_DIV, 32'd200, 32'd10, 32'd20, 33, "B2B_DIV");
        run_op(F3_REM, 32'd205, 32'd10, 32'd5, 33, "B2B_REM");
        run_op(F3_MULH, 32'd100000, 32'd100000, 32'd2, 3, "B2B_MULH");

        // --- Stall During Completion Verification ---
        $display("Testing external pipeline stall holding completed result...");
        @(posedge clk);
        #1;
        funct3 = F3_MUL;
        op1    = 32'd123;
        op2    = 32'd456;
        start  = 1'b1;
        stall_pipeline = 1'b1; // Stall active while completing
        @(posedge clk);
        #1;
        start = 1'b0;

        // Wait until done
        while (!done) @(posedge clk);
        #1;

        // Hold external stall for 5 cycles
        repeat (5) begin
            if (done !== 1'b1 || result !== 32'd56088) begin
                $display("[FAIL] Result changed or done dropped during external stall! done=%b, result=%d", done, result);
                fail_count = fail_count + 1;
            end
            @(posedge clk);
            #1;
        end
        // Release stall
        stall_pipeline = 1'b0;
        @(posedge clk);
        #1;
        if (done !== 1'b0) begin
            $display("[FAIL] Unit failed to return to IDLE after stall release!");
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Result and done correctly held stable during external stall!");
            pass_count = pass_count + 1;
        end

        // --- Reset While Busy Verification ---
        $display("Testing asynchronous reset while busy...");
        @(posedge clk);
        #1;
        funct3 = F3_DIV;
        op1 = 32'd1000;
        op2 = 32'd3;
        start = 1'b1;
        @(posedge clk);
        #1;
        start = 1'b0;
        repeat (5) @(posedge clk);
        #1;
        if (busy !== 1'b1) begin
            $display("[FAIL] Unit not busy during division!");
            fail_count = fail_count + 1;
        end
        // Trigger reset
        reset = 0;
        #12;
        reset = 1;
        @(posedge clk);
        #1;
        if (busy !== 1'b0 || done !== 1'b0) begin
            $display("[FAIL] Reset did not return unit to IDLE! busy=%b, done=%b", busy, done);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] Reset successfully aborted in-flight division!");
            pass_count = pass_count + 1;
        end

        $display("========================================");
        $display("TEST RESULTS: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");

        if (fail_count == 0) begin
            $display("ALL RV32M UNIT TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        $finish;
    end

endmodule
