// =============================================================================
// File: tb_system_top.v
// Description: End-to-End Full System Integration Testbench
//              Injects realistic RMII 100Mbps Ethernet frames containing:
//              IPv4 -> UDP (10443) -> MoldUDP64 -> ITCH 5.0 (Add Orders)
//              Verifies complete chain through:
//              RMII MAC RX -> CRC32 FCS -> IP/UDP Parser -> MoldUDP64 ->
//              ITCH Decoder -> Async FIFO CDC -> LOB Accelerator ->
//              MMIO BBO Registers -> VGA Visualizer & UART Telemetry.
// Target: IEEE 1364-2001 Pure Verilog
// =============================================================================

`timescale 1ns / 1ps

`include "lob_defines.vh"

module tb_system_top;

    // -------------------------------------------------------------------------
    // Clocks and Board Controls
    // -------------------------------------------------------------------------
    reg        clk;
    reg        reset;
    reg  [1:0] sw;
    reg ps2_clk,ps2_data;
    wire [15:0] led;
    wire [7:0] an;
    wire [6:0] seg;
    wire       dp;

    // Ethernet RMII
    wire       eth_refclk;
    wire       eth_rstn;
    reg        eth_crsdv;
    reg        eth_rxerr;
    reg  [1:0] eth_rxd;

    // UART
    wire       uart_txd_out;
    reg        uart_rxd_in;

    // VGA
    wire       vga_hs;
    wire       vga_vs;
    wire [3:0] vga_r;
    wire [3:0] vga_g;
    wire [3:0] vga_b;

    // 100 MHz Master Board Clock (10.0 ns period)
    always #5.0 clk = ~clk;

    // -------------------------------------------------------------------------
    // Device Under Test (DUT)
    // -------------------------------------------------------------------------
    top_system #(
        .DEFAULT_PRICE_BASE(32'd900000), // $90.0000
        .DEFAULT_TICK      (32'd1000),   // $0.1000 per tick
        .DEFAULT_LOCATE    (16'd1)       // Stock Locate 1 (AAPL)
    ) dut (
        .clk         (clk),
        .reset       (reset),
        .sw          (sw),
        .ps2_clk     (ps2_clk),
        .ps2_data    (ps2_data),
        .led         (led),
        .an          (an),
        .seg         (seg),
        .dp          (dp),
        .eth_refclk  (eth_refclk),
        .eth_rstn    (eth_rstn),
        .eth_crsdv   (eth_crsdv),
        .eth_rxerr   (eth_rxerr),
        .eth_rxd     (eth_rxd),
        .uart_txd_out(uart_txd_out),
        .uart_rxd_in (uart_rxd_in),
        .vga_hs      (vga_hs),
        .vga_vs      (vga_vs),
        .vga_r       (vga_r),
        .vga_g       (vga_g),
        .vga_b       (vga_b)
    );

    // -------------------------------------------------------------------------
    // Packet Memory Buffers
    // -------------------------------------------------------------------------
    reg [7:0] pkt [0:511];
    reg [7:0] frame_bytes [0:511];
    integer   pkt_len;
    integer   test_errors;
    integer   timeout;

    // -------------------------------------------------------------------------
    // IEEE 802.3 CRC32 Calculation
    // -------------------------------------------------------------------------
    function [31:0] calc_crc32;
        input integer len;
        reg   [31:0] crc;
        reg   [7:0]  b;
        integer i, bit_idx;
        begin
            crc = 32'hFFFFFFFF;
            for (i = 0; i < len; i = i + 1) begin
                b = pkt[i];
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    if ((crc[0] ^ b[bit_idx]) == 1'b1)
                        crc = (crc >> 1) ^ 32'hEDB88320;
                    else
                        crc = (crc >> 1);
                end
            end
            calc_crc32 = ~crc;
        end
    endfunction

    // -------------------------------------------------------------------------
    // RMII Frame Transmission Task (at 50 MHz eth_refclk)
    // -------------------------------------------------------------------------
    task send_rmii_packet;
        input integer len;
        integer total_len;
        reg [31:0] fcs;
        integer i, p, d;
        reg [7:0] cur_b;
        begin
            total_len = len + 4;

            // Copy payload
            for (i = 0; i < len; i = i + 1) begin
                frame_bytes[i] = pkt[i];
            end

            // Calculate and append 32-bit FCS (CRC32 little-endian)
            fcs = calc_crc32(len);
            frame_bytes[len + 0] = fcs[7:0];
            frame_bytes[len + 1] = fcs[15:8];
            frame_bytes[len + 2] = fcs[23:16];
            frame_bytes[len + 3] = fcs[31:24];

            $display("[TB_RMII] Transmitting %0d-byte Ethernet frame (Payload: %0d, FCS: 0x%08X)...",
                     total_len, len, fcs);

            // Wait for eth_refclk edge
            @(posedge eth_refclk);
            eth_crsdv <= 1'b0;
            eth_rxerr <= 1'b0;
            eth_rxd   <= 2'b00;

            // Preamble: 7 bytes of 0x55 (28 dibits) + 1 byte SFD 0xD5 (4 dibits)
            for (p = 0; p < 7; p = p + 1) begin
                for (d = 0; d < 4; d = d + 1) begin
                    @(posedge eth_refclk);
                    eth_crsdv <= 1'b1;
                    eth_rxd   <= 2'b01; // 0x55 in dibits
                end
            end

            // SFD (0xD5: dibits 01, 01, 01, 11)
            @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= 2'b01;
            @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= 2'b01;
            @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= 2'b01;
            @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= 2'b11;

            // Frame Data Bytes (LSB dibit first)
            for (i = 0; i < total_len; i = i + 1) begin
                cur_b = frame_bytes[i];
                @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= cur_b[1:0];
                @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= cur_b[3:2];
                @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= cur_b[5:4];
                @(posedge eth_refclk); eth_crsdv <= 1'b1; eth_rxd <= cur_b[7:6];
            end

            // End of Frame
            @(posedge eth_refclk);
            eth_crsdv <= 1'b0;
            eth_rxd   <= 2'b00;
            repeat (24) @(posedge eth_refclk); // Inter-packet gap
        end
    endtask

    task ps2_bit(input bit_value);
        begin
            // Accelerated integration stimulus; timing/framing is also
            // tested at normal PS/2 speed in tb_ps2_keyboard.
            ps2_data=bit_value;#5000;
            ps2_clk=0;#5000;
            ps2_clk=1;#5000;
        end
    endtask
    task send_ps2(input [7:0] code);
        integer bit_no;
        begin
            ps2_bit(0);
            for(bit_no=0;bit_no<8;bit_no=bit_no+1) ps2_bit(code[bit_no]);
            ps2_bit(~^code);ps2_bit(1);
            ps2_data=1;#5000;
        end
    endtask
    task press_ps2(input [7:0] code);
        begin send_ps2(code);send_ps2(8'hf0);send_ps2(code);end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("==================================================================");
        $display("STARTING FULL-SYSTEM INTEGRATION TESTBENCH (tb_system_top)");
        $display("==================================================================");

        test_errors = 0;
        clk         = 1'b0;
        reset       = 1'b0; // Hold in reset
        sw          = 2'd0;
        ps2_clk=1;ps2_data=1;
        eth_crsdv   = 1'b0;
        eth_rxerr   = 1'b0;
        eth_rxd     = 2'b00;
        uart_rxd_in = 1'b1;

        // Deassert reset after 200 ns
        #200;
        reset = 1'b1;
        $display("[TB] System reset deasserted. Waiting for MMCM and LOB core initialization...");

        // Wait for MMCM lock
        wait (dut.mmcm_locked == 1'b1);
        $display("[TB] MMCM Clock Generator Locked!");

        // Wait for LOB Price RAM and table initialization (~16,400 cycles)
        wait (dut.lob_init_done == 1'b1 && dut.lob_book_valid == 1'b1);
        $display("[TB] LOB Core Initialized Successfully! (Book valid = 1)");

        // Allow system to settle
        repeat (100) @(posedge clk);

        // ---------------------------------------------------------------------
        // Construct Realistic Market Data Packet
        // Ethernet II + IPv4 + UDP (10443) + MoldUDP64 + ITCH 5.0
        // ---------------------------------------------------------------------
        // Total frame size:
        // Eth Header: 14 bytes
        // IP Header:  20 bytes
        // UDP Header:  8 bytes
        // Mold Header: 20 bytes (Session: 10B, Seq: 8B, MsgCount: 2B)
        // ITCH Msg 1:  2B len + 36B ITCH Add Buy  500 @ $150.0000 = 38B
        // ITCH Msg 2:  2B len + 36B ITCH Add Sell 300 @ $150.5000 = 38B
        // Total payload = 14 + 20 + 8 + 20 + 38 + 38 = 138 bytes.
        pkt_len = 138;

        // Ethernet II Header (14 bytes)
        pkt[0]  = 8'h00; pkt[1]  = 8'h0A; pkt[2]  = 8'h35; pkt[3]  = 8'h01; pkt[4]  = 8'h02; pkt[5]  = 8'h03; // Dest MAC
        pkt[6]  = 8'h00; pkt[7]  = 8'h50; pkt[8]  = 8'h56; pkt[9]  = 8'hC0; pkt[10] = 8'h00; pkt[11] = 8'h08; // Src MAC
        pkt[12] = 8'h08; pkt[13] = 8'h00; // EtherType = IPv4

        // IPv4 Header (20 bytes)
        pkt[14] = 8'h45; // Version 4, IHL 5
        pkt[15] = 8'h00; // DSCP / ECN
        pkt[16] = 8'h00; pkt[17] = 8'h7C; // Total Length = 124 bytes (20 IP + 8 UDP + 96 UDP Payload)
        pkt[18] = 8'h1C; pkt[19] = 8'h46; // Identification
        pkt[20] = 8'h40; pkt[21] = 8'h00; // Flags: Don't Fragment
        pkt[22] = 8'h40; // TTL: 64
        pkt[23] = 8'h11; // Protocol: 17 (UDP)
        pkt[24] = 8'h00; pkt[25] = 8'h00; // Checksum placeholder
        pkt[26] = 8'hC0; pkt[27] = 8'hA8; pkt[28] = 8'h01; pkt[29] = 8'h64; // Src IP: 192.168.1.100
        pkt[30] = 8'hC0; pkt[31] = 8'hA8; pkt[32] = 8'h01; pkt[33] = 8'hC8; // Dst IP: 192.168.1.200

        // Calculate IPv4 Checksum
        begin : calc_ip_csum
            reg [31:0] sum;
            integer csum_i;
            sum = 0;
            for (csum_i = 0; csum_i < 10; csum_i = csum_i + 1) begin
                if (csum_i != 5) sum = sum + {pkt[14 + csum_i*2], pkt[15 + csum_i*2]};
            end
            while (sum >> 16) sum = (sum & 32'hFFFF) + (sum >> 16);
            sum = ~sum;
            pkt[24] = sum[15:8];
            pkt[25] = sum[7:0];
        end

        // UDP Header (8 bytes)
        pkt[34] = 8'hC3; pkt[35] = 8'h50; // Src Port: 50000
        pkt[36] = 8'h28; pkt[37] = 8'hCB; // Dst Port: 10443 (TotalView ITCH default)
        pkt[38] = 8'h00; pkt[39] = 8'h68; // UDP Length: 104 bytes
        pkt[40] = 8'h00; pkt[41] = 8'h00; // UDP Checksum: 0

        // MoldUDP64 Header (20 bytes)
        // Session ID: "MOLDTEST01" (10 bytes)
        pkt[42] = "M"; pkt[43] = "O"; pkt[44] = "L"; pkt[45] = "D"; pkt[46] = "T";
        pkt[47] = "E"; pkt[48] = "S"; pkt[49] = "T"; pkt[50] = "0"; pkt[51] = "1";
        // Sequence Number: 64'd1 (8 bytes)
        pkt[52] = 8'h00; pkt[53] = 8'h00; pkt[54] = 8'h00; pkt[55] = 8'h00;
        pkt[56] = 8'h00; pkt[57] = 8'h00; pkt[58] = 8'h00; pkt[59] = 8'h01;
        // Message Count: 16'd2 (2 bytes)
        pkt[60] = 8'h00; pkt[61] = 8'h02;

        // Mold Block 1: ITCH Message 1 (Add Buy Order 500 @ $150.0000)
        pkt[62] = 8'h00; pkt[63] = 8'h24; // Message Length = 36 bytes
        pkt[64] = "A";                    // Message Type 'A'
        pkt[65] = 8'h00; pkt[66] = 8'h01; // Stock Locate = 1
        pkt[67] = 8'h00; pkt[68] = 8'h01; // Tracking = 1
        pkt[69] = 8'h00; pkt[70] = 8'h00; pkt[71] = 8'h00; pkt[72] = 8'h00; pkt[73] = 8'h01; pkt[74] = 8'h00; // Timestamp
        pkt[75] = 8'h00; pkt[76] = 8'h00; pkt[77] = 8'h00; pkt[78] = 8'h00;
        pkt[79] = 8'h00; pkt[80] = 8'h00; pkt[81] = 8'h10; pkt[82] = 8'h01; // Order Ref = 0x1001
        pkt[83] = "B";                    // Buy Side
        pkt[84] = 8'h00; pkt[85] = 8'h00; pkt[86] = 8'h01; pkt[87] = 8'hF4; // Shares = 500
        pkt[88] = "A"; pkt[89] = "A"; pkt[90] = "P"; pkt[91] = "L"; pkt[92] = " "; pkt[93] = " "; pkt[94] = " "; pkt[95] = " "; // Stock
        pkt[96] = 8'h00; pkt[97] = 8'h16; pkt[98] = 8'hE3; pkt[99] = 8'h60; // Price = 1500000 ($150.0000)

        // Mold Block 2: ITCH Message 2 (Add Sell Order 300 @ $150.5000)
        pkt[100] = 8'h00; pkt[101] = 8'h24; // Message Length = 36 bytes
        pkt[102] = "A";                     // Message Type 'A'
        pkt[103] = 8'h00; pkt[104] = 8'h01; // Stock Locate = 1
        pkt[105] = 8'h00; pkt[106] = 8'h02; // Tracking = 2
        pkt[107] = 8'h00; pkt[108] = 8'h00; pkt[109] = 8'h00; pkt[110] = 8'h00; pkt[111] = 8'h02; pkt[112] = 8'h00; // Timestamp
        pkt[113] = 8'h00; pkt[114] = 8'h00; pkt[115] = 8'h00; pkt[116] = 8'h00;
        pkt[117] = 8'h00; pkt[118] = 8'h00; pkt[119] = 8'h20; pkt[120] = 8'h01; // Order Ref = 0x2001
        pkt[121] = "S";                     // Sell Side
        pkt[122] = 8'h00; pkt[123] = 8'h00; pkt[124] = 8'h01; pkt[125] = 8'h2C; // Shares = 300
        pkt[126] = "A"; pkt[127] = "A"; pkt[128] = "P"; pkt[129] = "L"; pkt[130] = " "; pkt[131] = " "; pkt[132] = " "; pkt[133] = " "; // Stock
        pkt[134] = 8'h00; pkt[135] = 8'h16; pkt[136] = 8'hF6; pkt[137] = 8'hE8; // Price = 1505000 ($150.5000)

        $display("[TB] Injecting Ethernet frame into RMII PHY interface...");
        send_rmii_packet(pkt_len);

        // ---------------------------------------------------------------------
        // Wait for Hardware Processing Pipeline to Complete
        // ---------------------------------------------------------------------
        $display("[TB] Frame injected. Waiting for hardware pipeline processing...");

        // Wait until LOB processes both events (with timeout)
        timeout = 0;
        while (dut.core_event_count < 32'd2 && timeout < 5000) begin
            #10;
            timeout = timeout + 1;
        end

        if (dut.core_event_count == 32'd2) begin
            $display("[TB] Both market data events committed by LOB accelerator!");
        end else begin
            $display("[TB_TIMEOUT] LOB core did not commit 2 events within timeout! Count = %0d", dut.core_event_count);
            test_errors = test_errors + 1;
        end

        // Additional settling cycles for telemetry and MMIO registers
        repeat (50) @(posedge clk);
        // The second ITCH add must expose the storage writes that actually
        // reached the slot, hash, and price RAM ports.
        if (dut.lob_storage_trace[315] !== 1'b1 ||
            dut.lob_storage_trace[314:311] !== 4'h1 ||
            dut.lob_storage_trace[310:247] !== 64'h2001 ||
            dut.lob_storage_trace[182] !== 1'b1 ||
            dut.lob_storage_trace[170] !== 1'b1 ||
            dut.lob_storage_trace[169] !== 1'b1 ||
            dut.lob_storage_trace[155:124] !== 32'd300 ||
            dut.lob_storage_trace[108] !== 1'b1 ||
            dut.lob_storage_trace[93] !== 1'b1 ||
            dut.lob_storage_trace[78:47] !== 32'd300) begin
            $display("[FAIL] FPGA storage trace does not match committed second add");
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] FPGA slot/hash/price write trace matches second add");
        end
        repeat (100) @(posedge clk);
        if (dut.u_views.quote_count !== 8'd2 ||
            dut.u_views.event_count !== 9'd2 ||
            dut.u_views.u_display_journal.event_mem[1][393:362] !== 32'd2 ||
            dut.u_views.u_display_journal.event_mem[1][361:316] !== {1'b1, 32'd300, 13'd605}) begin
            $display("[FAIL] FPGA VGA journal disagrees with second add");
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] FPGA VGA journal contains the second add");
        end
        // Exercise the UART query's core->VGA->core readback bridge against
        // the actual second order slot, not only the raw VGA read port.
        force dut.u_uart.req_kind = "S";
        force dut.u_uart.req_addr = 14'd2046;
        force dut.u_uart.req_toggle = 1'b1;
        timeout = 0;
        while (!dut.u_uart.rsp_update && timeout < 100) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout == 100 || dut.u_uart.rsp_core[629:622] !== "S" ||
            dut.u_uart.rsp_core[621:608] !== 14'd2046 ||
            dut.u_uart.rsp_core[46] !== 1'b1 ||
            dut.u_uart.rsp_core[31:0] !== 32'd300) begin
            $display("[FAIL] UART readback bridge did not return actual slot RAM");
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] UART query bridge returned actual slot RAM");
        end
        repeat (4) @(posedge clk);
        force dut.u_uart.req_kind = "B";
        force dut.u_uart.req_addr = 14'd0;
        force dut.u_uart.req_toggle = 1'b0;
        timeout = 0;
        while (!dut.u_uart.rsp_update && timeout < 600) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout == 600 || dut.u_uart.rsp_core[629:622] !== "B" ||
            dut.u_uart.rsp_core[621:608] !== 14'd0 ||
            dut.u_uart.rsp_core[31:0] !== 32'h00000220) begin
            $display("[FAIL] UART occupied-hash bitmap: timeout=%0d kind=%h addr=%h bits=%h", timeout,
                     dut.u_uart.rsp_core[629:622], dut.u_uart.rsp_core[621:608], dut.u_uart.rsp_core[31:0]);
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] UART occupied-hash bitmap matches actual hash RAM");
        end
        release dut.u_uart.req_kind;
        release dut.u_uart.req_addr;
        release dut.u_uart.req_toggle;
        timeout = 0;
        while ((dut.u_cpu_system.u_dmem.DMEM.dmem[0] !== 32'd1500000 ||
                dut.u_cpu_system.u_dmem.DMEM.dmem[2] !== 32'd1505000) && timeout < 5000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (timeout == 5000 || dut.u_cpu_system.u_dmem.DMEM.dmem[6][1] !== 1'b1) begin
            $display("[FAIL] Monitor firmware did not publish a valid BBO snapshot");
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] Monitor firmware published BBO and status to DMEM");
        end

        // ---------------------------------------------------------------------
        // Verify Diagnostic and Telemetry Counters
        // ---------------------------------------------------------------------
        $display("\n==================================================================");
        $display("VERIFYING PIPELINE SUBSYSTEM STATUS:");
        $display("==================================================================");

        $display("1. RMII MAC RX:");
        $display("   - Total Valid Frames Received : %0d (Expected: 1)", dut.u_ingest.cnt_rx_frames);
        $display("   - CRC-32 Errors               : %0d (Expected: 0)", dut.u_ingest.cnt_crc_err);
        if (dut.u_ingest.cnt_rx_frames != 32'd1 || dut.u_ingest.cnt_crc_err != 32'd0) begin
            $display("[FAIL] RMII frame count or CRC error check failed!");
            test_errors = test_errors + 1;
        end else begin
            $display("   -> [PASS] RMII Ethernet Frame & CRC32 Verified.");
        end

        $display("1.5. Network Parser (net_parser):");
        $display("   - State                       : %0d", dut.u_ingest.u_net_parser.state);
        $display("   - IPv4 Frames                 : %0d", dut.u_ingest.u_net_parser.cnt_ipv4_frames);
        $display("   - UDP Packets                 : %0d", dut.u_ingest.u_net_parser.cnt_udp_packets);
        $display("   - Non-IPv4 Drop               : %0d", dut.u_ingest.u_net_parser.cnt_non_ipv4_drop);
        $display("   - IP Checksum Error           : %0d", dut.u_ingest.u_net_parser.cnt_ip_csum_err);
        $display("   - IP Frag Drop                : %0d", dut.u_ingest.u_net_parser.cnt_ip_frag_drop);
        $display("   - Non-UDP Drop                : %0d", dut.u_ingest.u_net_parser.cnt_non_udp_drop);
        $display("   - Port Mismatch Drop          : %0d", dut.u_ingest.u_net_parser.cnt_port_mismatch_drop);
        $display("   - Destination Port Detected   : %0d (Expected: %0d)", dut.u_ingest.u_net_parser.udp_dst_port, dut.u_ingest.u_net_parser.active_target_port);

        $display("2. Transport Layer (MoldUDP64):");
        $display("   - Mold State                  : %0d", dut.u_ingest.u_mold_decoder.state);
        $display("   - MoldUDP64 Packets Parsed    : %0d (Expected: 1)", dut.u_ingest.cnt_mold_pkts);
        $display("   - Messages Un-framed          : %0d (Expected: 2)", dut.u_ingest.cnt_mold_msgs);
        $display("   - Sequence Gap Detected       : %0d (Expected: 0)", dut.u_ingest.seq_gap_detected);
        if (dut.u_ingest.cnt_mold_msgs != 32'd2 || dut.u_ingest.seq_gap_detected != 1'b0) begin
            $display("[FAIL] MoldUDP64 message count or gap check failed!");
            test_errors = test_errors + 1;
        end else begin
            $display("   -> [PASS] MoldUDP64 Protocol Decoder Verified.");
        end

        $display("2.5. Exchange Feed Layer (ITCH 5.0):");
        $display("   - ITCH State                  : %0d", dut.u_ingest.u_itch_decoder.state);
        $display("   - ITCH Total Messages         : %0d", dut.u_ingest.u_itch_decoder.cnt_itch_total_msgs);
        $display("   - ITCH Order Events           : %0d", dut.u_ingest.u_itch_decoder.cnt_itch_order_events);
        $display("   - ITCH Filtered Messages      : %0d", dut.u_ingest.u_itch_decoder.cnt_itch_filtered_msgs);
        $display("   - ITCH OOW Events             : %0d", dut.u_ingest.u_itch_decoder.cnt_itch_oow_events);
        $display("   - ITCH Decode Error           : %0d (length=%0d bytes=%0d)",
                 dut.u_ingest.itch_decode_error, dut.u_ingest.u_itch_decoder.length, dut.u_ingest.u_itch_decoder.count);
        $display("   - ITCH Msg Type Latched       : %0c (0x%02X)", dut.u_ingest.u_itch_decoder.msg_type, dut.u_ingest.u_itch_decoder.msg_type);
        $display("   - ITCH Locate Latched         : %0d", dut.u_ingest.u_itch_decoder.msg_locate);
        $display("   - FIFO Count (wr/rd)          : %0d / %0d", dut.u_ingest.fifo_wr_cnt, dut.u_ingest.fifo_rd_cnt);
        $display("   - Book Valid                  : %0b (Expected: 1)", dut.lob_book_valid);
        $display("   - Active Order Count          : %0d (Expected: 2)", dut.lob_active_orders);
        $display("   - Best Bid Valid              : %0b (Expected: 1)", dut.lob_bid_valid);
        $display("   - Best Bid Price              : %0d ($%0d.%04d) (Expected: 1500000)",
                 dut.lob_bid_price, dut.lob_bid_price / 10000, dut.lob_bid_price % 10000);
        $display("   - Best Bid Quantity           : %0d (Expected: 500)", dut.lob_bid_qty);
        $display("   - Best Ask Valid              : %0b (Expected: 1)", dut.lob_ask_valid);
        $display("   - Best Ask Price              : %0d ($%0d.%04d) (Expected: 1505000)",
                 dut.lob_ask_price, dut.lob_ask_price / 10000, dut.lob_ask_price % 10000);
        $display("   - Best Ask Quantity           : %0d (Expected: 300)", dut.lob_ask_qty);

        if (dut.lob_bid_valid != 1'b1 || dut.lob_bid_price != 32'd1500000 || dut.lob_bid_qty != 32'd500) begin
            $display("[FAIL] Best Bid mismatch!");
            test_errors = test_errors + 1;
        end else if (dut.lob_ask_valid != 1'b1 || dut.lob_ask_price != 32'd1505000 || dut.lob_ask_qty != 32'd300) begin
            $display("[FAIL] Best Ask mismatch!");
            test_errors = test_errors + 1;
        end else if (dut.lob_active_orders != 12'd2) begin
            $display("[FAIL] Active order count mismatch!");
            test_errors = test_errors + 1;
        end else begin
            $display("   -> [PASS] LOB Core Execution & Book State Verified.");
        end

        $display("4. Peripherals & Visualizer Interfaces:");
        $display("   - VGA Sync (HS: %0b, VS: %0b, R: %0h, G: %0h, B: %0h)",
                 vga_hs, vga_vs, vga_r, vga_g, vga_b);
        $display("   - Board LEDs: 0x%04X (LD0=Locked, LD2=InitDone, LD3=BookValid, LD4=BidValid, LD5=AskValid)",
                 led);
        $display("   - 7-Segment Display: an=0x%02X, seg=0x%02X", an, seg);
        $display("   - UART Serial Line: %0b", uart_txd_out);

        if (!led[0] || !led[2] || !led[3] || !led[4] || !led[5]) begin
            $display("[FAIL] Status LED assertion failed!");
            test_errors = test_errors + 1;
        end else begin
            $display("   -> [PASS] Diagnostic Peripherals Verified.");
        end

        // Enter generates one local order from values typed through PS/2.
        press_ps2(8'h83); // F7
        press_ps2(8'h0d);press_ps2(8'h0d); // price
        press_ps2(8'h46);press_ps2(8'h45);press_ps2(8'h49);
        press_ps2(8'h2e);press_ps2(8'h45);press_ps2(8'h45);press_ps2(8'h45);
        press_ps2(8'h0d); // quantity
        press_ps2(8'h16);press_ps2(8'h45);press_ps2(8'h45);
        press_ps2(8'h0d); // order ID
        press_ps2(8'h32); // B
        repeat(7) press_ps2(8'h45);
        send_ps2(8'h5a); // Enter
        timeout=0;
        while(dut.core_event_count != 3 && timeout<100000) begin
            @(posedge clk);timeout=timeout+1;
        end
        send_ps2(8'h5a); // held Enter repeat
        repeat(30) @(posedge clk);
        if (dut.core_event_count !== 3 || dut.lob_active_orders !== 3 ||
            dut.lob_storage_trace[310:247] !== 64'hB0000000 ||
            dut.u_ingest.cnt_itch_events !== 2 || !dut.lob_book_valid ||
            dut.u_order_merge.local_done_count !== 1 || !dut.u_order_merge.local_done_valid) begin
            $display("[FAIL] Enter path duplicated/lost the keyboard order");
            test_errors = test_errors + 1;
        end else $display("[PASS] Enter submitted one keyboard order through the source arbiter");
        // The next network sequence remains 3 after the local event.
        pkt[59] = 3;
        pkt[82] = 8'h11;
        pkt[120] = 8'h11;
        send_rmii_packet(pkt_len);
        timeout=0;
        while(dut.core_event_count != 5 && timeout<5000) begin
            @(posedge clk); timeout=timeout+1;
        end
        repeat(30) @(posedge clk);
        if(dut.core_event_count !== 5 || dut.lob_active_orders !== 5 ||
           dut.u_ingest.cnt_itch_events !== 4 || !dut.lob_book_valid) begin
            $display("[FAIL] Network feed failed after a keyboard-generated order");
            test_errors=test_errors+1;
        end else $display("[PASS] Laptop and keyboard orders share a book without changing network sequencing");

        // A frame with a valid Ethernet FCS but bad IPv4 checksum must
        // invalidate the previously published book, even if no later
        // sequence number arrives to expose the lost market packet.
        pkt[24] = pkt[24] ^ 8'h01;
        send_rmii_packet(pkt_len);
        timeout = 0;
        while (dut.u_ingest.cnt_ip_csum_err == 0 && timeout < 5000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (20) @(posedge clk);
        if (timeout == 5000 || dut.lob_book_valid !== 1'b0 ||
            dut.lob_error_code !== 8'h0A || dut.core_event_count !== 32'd5) begin
            $display("[FAIL] Bad IPv4 checksum did not fail-stop the book");
            test_errors = test_errors + 1;
        end else begin
            $display("[PASS] Bad IPv4 checksum invalidated the book");
        end

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        $display("==================================================================");
        if (test_errors == 0) begin
            $display("[PASS] ALL END-TO-END SYSTEM INTEGRATION TESTS PASSED (0 ERRORS)");
            $display("==================================================================");
        end else begin
            $display("[FAIL] INTEGRATION TEST FAILED WITH %0d ERRORS", test_errors);
            $display("==================================================================");
            $fatal(1, "Full-system integration failed");
        end

        $finish;
    end

endmodule
