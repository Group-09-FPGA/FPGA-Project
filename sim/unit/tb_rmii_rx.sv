// =============================================================================
// File: tb_rmii_rx.sv
// Description: Unit testbench for RMII Ethernet receiver and CRC32 engine
// =============================================================================

`timescale 1ns / 1ps

module tb_rmii_rx;

    logic        clk_50;
    logic        rst_n;
    logic        rmii_crs_dv;
    logic        rmii_rx_err;
    logic [1:0]  rmii_rxd;

    wire         frame_valid;
    wire [11:0]  frame_len;
    logic        frame_read_en;
    wire [7:0]   frame_byte_out;
    wire         frame_byte_last;
    wire         frame_done_ack;

    wire [31:0]  cnt_rx_frames;
    wire [31:0]  cnt_crc_err;
    wire [31:0]  cnt_len_err;
    wire [31:0]  cnt_phy_err;
    wire [31:0]  cnt_overflow_err;

    rmii_rx dut (
        .clk_50(clk_50),
        .rst_n(rst_n),
        .rmii_crs_dv(rmii_crs_dv),
        .rmii_rx_err(rmii_rx_err),
        .rmii_rxd(rmii_rxd),
        .frame_valid(frame_valid),
        .frame_len(frame_len),
        .frame_read_en(frame_read_en),
        .frame_byte_out(frame_byte_out),
        .frame_byte_last(frame_byte_last),
        .frame_done_ack(frame_done_ack),
        .cnt_rx_frames(cnt_rx_frames),
        .cnt_crc_err(cnt_crc_err),
        .cnt_len_err(cnt_len_err),
        .cnt_phy_err(cnt_phy_err),
        .cnt_overflow_err(cnt_overflow_err)
    );

    // 50 MHz clock (20 ns period)
    always #10 clk_50 = ~clk_50;

    // CRC32 calculation helper for testbench
    function automatic [31:0] tb_calc_crc32(input logic [7:0] data[], input int len);
        logic [31:0] crc = 32'hFFFF_FFFF;
        for (int i = 0; i < len; i++) begin
            logic [7:0] d = data[i];
            for (int b = 0; b < 8; b++) begin
                if ((crc[0] ^ d[b]) == 1'b1)
                    crc = (crc >> 1) ^ 32'hEDB88320;
                else
                    crc = (crc >> 1);
            end
        end
        return ~crc; // Final XOR
    endfunction

    // Task to transmit a full RMII frame (preamble, SFD, payload, FCS)
    task automatic transmit_rmii_frame(
        input logic [7:0] payload[],
        input int payload_len,
        input bit corrupt_crc,
        input bit inject_phy_err
    );
        logic [7:0] full_frame[];
        logic [31:0] fcs;
        int frame_size = payload_len + 4;
        full_frame = new[frame_size];

        for (int i = 0; i < payload_len; i++) begin
            full_frame[i] = payload[i];
        end

        // Calculate CRC32 over payload
        fcs = tb_calc_crc32(payload, payload_len);
        if (corrupt_crc) fcs = fcs ^ 32'hDEADBEEF;

        // FCS is appended in little-endian order (least significant byte first on wire)
        full_frame[payload_len + 0] = fcs[7:0];
        full_frame[payload_len + 1] = fcs[15:8];
        full_frame[payload_len + 2] = fcs[23:16];
        full_frame[payload_len + 3] = fcs[31:24];

        @(posedge clk_50);
        rmii_crs_dv = 1'b1;
        rmii_rx_err = 1'b0;

        // 1. Send Preamble (7 bytes of 0x55 = 28 dibits of 2'b01)
        for (int i = 0; i < 28; i++) begin
            rmii_rxd = 2'b01;
            @(posedge clk_50);
        end

        // 2. Send SFD (0xD5: 1101_0101 -> dibits 01, 01, 01, 11)
        rmii_rxd = 2'b01; @(posedge clk_50);
        rmii_rxd = 2'b01; @(posedge clk_50);
        rmii_rxd = 2'b01; @(posedge clk_50);
        rmii_rxd = 2'b11; @(posedge clk_50);

        // 3. Send Frame Data + FCS
        for (int b = 0; b < frame_size; b++) begin
            logic [7:0] byte_val = full_frame[b];
            if (inject_phy_err && b == 10) rmii_rx_err = 1'b1;
            else rmii_rx_err = 1'b0;

            rmii_rxd = byte_val[1:0]; @(posedge clk_50);
            rmii_rxd = byte_val[3:2]; @(posedge clk_50);
            rmii_rxd = byte_val[5:4]; @(posedge clk_50);
            rmii_rxd = byte_val[7:6]; @(posedge clk_50);
        end

        // End of frame (drop crs_dv)
        rmii_crs_dv = 1'b0;
        rmii_rx_err = 1'b0;
        rmii_rxd = 2'b00;

        // Inter-frame gap (at least 96 bit times = 48 clocks)
        repeat (10) @(posedge clk_50);
    endtask

    logic [7:0] test_pkt[];
    int pass_count = 0;
    int test_count = 0;

    task automatic verify(input string name, input bit cond);
        test_count++;
        if (cond) begin
            pass_count++;
            $display("[PASS] %s", name);
        end else begin
            $display("[FAIL] %s", name);
        end
    endtask

    initial begin
        clk_50 = 0;
        rst_n = 0;
        rmii_crs_dv = 0;
        rmii_rx_err = 0;
        rmii_rxd = 0;
        frame_read_en = 0;

        $display("=================================================");
        $display("   STARTING RMII ETHERNET RECEIVER UNIT TEST     ");
        $display("=================================================");

        #40 rst_n = 1;
        #40;

        // ---------------------------------------------------------------------
        // Test 1: Valid 60-byte payload (64 bytes total with FCS)
        // ---------------------------------------------------------------------
        test_pkt = new[60];
        for (int i = 0; i < 60; i++) test_pkt[i] = 8'(i + 1);

        transmit_rmii_frame(test_pkt, 60, 0, 0);

        #100;
        verify("Test 1: Valid frame accepted (cnt_rx_frames == 1)", cnt_rx_frames == 1);
        verify("Test 1: Frame length reported correctly (frame_len == 60)", frame_len == 60);
        verify("Test 1: frame_valid asserted", frame_valid == 1);

        // Read out frame from buffer and verify content
        frame_read_en = 1'b1;
        for (int i = 0; i < 60; i++) begin
            @(posedge clk_50);
            #1;
            if (frame_byte_out != test_pkt[i]) begin
                $display("[MISMATCH] Byte %0d: Expected %02x, Got %02x", i, test_pkt[i], frame_byte_out);
            end
        end
        frame_read_en = 1'b0;
        @(posedge clk_50);
        verify("Test 1: Frame consumed and cleared (frame_valid == 0)", frame_valid == 0);

        // ---------------------------------------------------------------------
        // Test 2: Frame with Corrupt CRC
        // ---------------------------------------------------------------------
        transmit_rmii_frame(test_pkt, 60, 1, 0);
        #100;
        verify("Test 2: Corrupted CRC rejected (cnt_crc_err == 1)", cnt_crc_err == 1);
        verify("Test 2: frame_valid not asserted", frame_valid == 0);

        // ---------------------------------------------------------------------
        // Test 3: Runt Frame (< 64 bytes total, e.g. 30 bytes payload)
        // ---------------------------------------------------------------------
        test_pkt = new[30];
        for (int i = 0; i < 30; i++) test_pkt[i] = 8'(i);
        transmit_rmii_frame(test_pkt, 30, 0, 0);
        #100;
        verify("Test 3: Runt frame rejected (cnt_len_err == 1)", cnt_len_err == 1);
        verify("Test 3: frame_valid not asserted", frame_valid == 0);

        // ---------------------------------------------------------------------
        // Test 4: PHY Receive Error (rmii_rx_err asserted)
        // ---------------------------------------------------------------------
        test_pkt = new[60];
        for (int i = 0; i < 60; i++) test_pkt[i] = 8'(i);
        transmit_rmii_frame(test_pkt, 60, 0, 1);
        #100;
        verify("Test 4: PHY error frame rejected (cnt_phy_err == 1)", cnt_phy_err == 1);
        verify("Test 4: frame_valid not asserted", frame_valid == 0);

        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
        $display("\n=================================================");
        $display("   RMII RECEIVER TEST RESULTS: %0d / %0d PASSED", pass_count, test_count);
        $display("=================================================");
        if (pass_count == test_count) begin
            $display(">>> ALL RMII RX TESTS PASSED (0 ERRORS) <<<\n");
            $finish(0);
        end else begin
            $display(">>> ERRORS ENCOUNTERED IN RMII RX TEST <<<\n");
            $finish(1);
        end
    end

endmodule
