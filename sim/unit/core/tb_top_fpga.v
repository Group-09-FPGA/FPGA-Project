`timescale 1ns / 1ps

module tb_top_fpga;

    reg clk;
    reg reset; // active-low reset (CPU_RESETN, pin C12)

    wire [15:0] led;
    wire [7:0]  an;
    wire [6:0]  seg;
    wire        dp;

    // Fast 100 MHz board clock (10 ns period)
    always #5 clk = ~clk;

    // DUT instantiation with fast divider count for simulation
    top_fpga #(
        .CLK_DIV_COUNT(26'd1) // Toggles slow_clk every 2 fast cycles (20 ns period)
    ) dut (
        .clk(clk),
        .reset(reset),
        .led(led),
        .an(an),
        .seg(seg),
        .dp(dp)
    );

    integer num_stores = 0;
    reg [15:0] last_led;
    integer led_drop_errors = 0;
    integer test_errors = 0;
    integer halt_cycles = 0;
    reg reset_rearm_done = 0;

    initial begin
        clk = 0;
        reset = 0; // Asserted (active-low)
        last_led = 16'h0000;

        // 1. Verify reset assertion state
        #50;
        if (led !== 16'h0000) begin
            $display("[FAIL] Initial reset: led is not 0x0000! got 0x%04x", led);
            test_errors = test_errors + 1;
        end
        if (dut.pc_out !== 32'h0) begin
            $display("[FAIL] Initial reset: pc_out is not 0! got %08x", dut.pc_out);
            test_errors = test_errors + 1;
        end
        if (dut.clk_cnt !== 26'd0 || dut.slow_clk !== 1'b0) begin
            $display("[FAIL] Initial reset: clock divider not held in reset!");
            test_errors = test_errors + 1;
        end
        $display("[PASS] Reset assertion verified: CPU held at PC=0, LED=0x0000, clk_div=0");

        // 2. Release reset
        #50;
        reset = 1;
        $display("[INFO] Released reset (reset=1). Processor beginning execution...");

        // Wait until first store occurs and latches into LEDs
        wait(num_stores >= 1);
        @(posedge dut.slow_clk);
        #5;
        $display("[INFO] First store completed: LED = 0x%04x (expected 0x002a)", led);
        if (led !== 16'h002a) begin
            $display("[FAIL] LED mismatch after store #1! Expected 0x002a, got 0x%04x", led);
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] Store #1 verified: LED correctly latched 0x002a!");
        end

        // 3. Test Reset Re-assertion while running with non-zero LED value
        $display("[INFO] Testing reset re-assertion while running...");
        reset = 0; // Assert active-low reset
        #20;       // Asynchronous reset propagation check
        if (led !== 16'h0000) begin
            $display("[FAIL] Re-asserted reset: LED failed to asynchronously clear to 0x0000! got 0x%04x", led);
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] Re-asserted reset: LED asynchronously cleared to 0x0000!");
        end

        if (dut.pc_out !== 32'h0) begin
            $display("[FAIL] Re-asserted reset: pc_out failed to clear to 0! got %08x", dut.pc_out);
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] Re-asserted reset: CPU returned to PC=0!");
        end

        // 4. Release reset again and let full test run through completion
        #80;
        num_stores = 0;
        halt_cycles = 0;
        last_led = 16'h0000;
        reset_rearm_done = 1;
        reset = 1;
        $display("[INFO] Released reset again. Running full RV32M validation program to completion...");

        // Safety timeout
        #35000;
        $display("[ERROR] Simulation timed out in tb_top_fpga!");
        $finish;
    end

    // Monitor LED transitions and check for spurious zero-drops
    always @(posedge dut.slow_clk) begin
        if (reset && !reset_rearm_done) begin
            // Pre-rearm store counting
            if (dut.bus_rsp_valid && !dut.bus_rsp_error && dut.bus_req_write && (dut.bus_req_addr[31:28] == 4'h2)) begin
                num_stores <= num_stores + 1;
            end
        end else if (reset && reset_rearm_done) begin
            // Post-rearm: full sequence verification
            if (dut.bus_rsp_valid && !dut.bus_rsp_error && dut.bus_req_write && (dut.bus_req_addr[31:28] == 4'h2)) begin
                num_stores <= num_stores + 1;
                $display("time: %10t [TOP_FPGA STORE #%02d] Latching LED = 0x%04x (addr=%08x)",
                         $time, num_stores + 1, dut.bus_req_wdata[15:0], dut.bus_req_addr);
            end

            // Check that LEDs do NOT drop to zero while running between stores
            if (num_stores > 0 && led == 16'h0000 && last_led != 16'h0000) begin
                // Check if 0x0000 was the legitimately written value (e.g. for overflow stores)
                if (dut.bus_req_wdata[15:0] !== 16'h0000) begin
                    $display("time: %10t [FAIL] LED dropped unexpectedly to 0x0000! (previous=0x%04x)",
                             $time, last_led);
                    led_drop_errors <= led_drop_errors + 1;
                end
            end
            last_led <= led;

            // Check terminal halt loop
            if (dut.pipe_u.instruction == 32'h0000006f) begin
                halt_cycles <= halt_cycles + 1;
                if (halt_cycles == 10) begin
                    $display("\n=======================================================");
                    $display("    TOP_FPGA BOARD-LEVEL OBSERVABILITY VERIFICATION");
                    $display("=======================================================");
                    $display("[INFO] Processor settled in stable halt loop at PC = %08x", dut.pc_out);
                    $display("[INFO] Total DMEM Stores Accepted: %0d", num_stores);
                    $display("[INFO] Final Latched LED Value: 0x%04x (expected 0xcafe)", led);

                    if (led !== 16'hcafe) begin
                        $display("[FAIL] Final LED value mismatch! Expected 0xcafe, got 0x%04x", led);
                        test_errors = test_errors + 1;
                    end else begin
                        $display("[PASS] Final LED latch correctly holds 0xCAFE pass sentinel!");
                    end

                    if (led_drop_errors > 0) begin
                        $display("[FAIL] Detected %0d unexpected LED drop-to-zero glitches!", led_drop_errors);
                        test_errors = test_errors + 1;
                    end else begin
                        $display("[PASS] LEDs stably retained values across all execution cycles without drop-to-zero glitches!");
                    end

                    if (test_errors == 0) begin
                        $display("\n>>> TOP_FPGA BOARD OBSERVABILITY & RESET VERIFICATION PASSED <<<\n");
                    end else begin
                        $display("\n>>> TOP_FPGA VERIFICATION FAILED: %0d ERRORS <<<\n", test_errors);
                    end
                    $display("=======================================================\n");
                    #50 $finish;
                end
            end
        end
    end

endmodule
