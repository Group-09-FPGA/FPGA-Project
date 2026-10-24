// =============================================================================
// File: top_system.v
// Description: Full End-to-End FPGA Market Data Processor & LOB Accelerator
// Target: AMD/Xilinx Artix-7 (Digilent Nexys A7-100T, XC7A100T-1CSG324C)
// Data Path:
//   RMII PHY -> RMII MAC RX -> CRC32 -> IPv4/UDP Parser -> MoldUDP64 Decoder ->
//   ITCH 5.0 Decoder -> 256-bit Async FIFO -> Hardware LOB Accelerator ->
//   BBO Registers -> MMIO -> RV32IM CPU -> VGA & UART Telemetry
// =============================================================================

`timescale 1ns / 1ps

`include "lob_defines.vh"

module top_system #(
    parameter [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter [31:0] DEFAULT_TICK       = 32'd1000,
    parameter [15:0] DEFAULT_LOCATE     = 16'd1,
    parameter [47:0] DEST_MAC           = 48'd0,
    parameter [31:0] DEST_IP            = 32'd0
) (
    // -------------------------------------------------------------------------
    // 100 MHz Master Board Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,             // Pin E3 (100.0 MHz board oscillator)
    input  wire        reset,           // Pin C12 (CPU_RESETN, active-low push button)

    // -------------------------------------------------------------------------
    // Interactive User Switches & Push Buttons
    // sw[0]: SW14 (Pin U11), sw[1]: SW15 (Pin V10), sw[2]: Pin M13, sw[3]: Pin R15
    // -------------------------------------------------------------------------
    input  wire [ 3:0] sw,

    // -------------------------------------------------------------------------
    // Diagnostic LEDs (LD0..LD15)
    // -------------------------------------------------------------------------
    output wire [15:0] led,

    // -------------------------------------------------------------------------
    // 8-Digit 7-Segment Multiplexed Display
    // -------------------------------------------------------------------------
    output wire [ 7:0] an,
    output wire [ 6:0] seg,
    output wire        dp,

    // -------------------------------------------------------------------------
    // Ethernet Physical Interface (LAN8720A RMII PHY)
    // -------------------------------------------------------------------------
    output wire        eth_refclk,      // Pin D5 (50.0 MHz reference clock to PHY)
    output wire        eth_rstn,        // Pin B3 (Active-low hardware reset to PHY)
    input  wire        eth_crsdv,       // Pin D9 (Carrier Sense / Data Valid)
    input  wire        eth_rxerr,       // Pin C10 (RX Error)
    input  wire [ 1:0] eth_rxd,         // Pins C11 (RXD0), D10 (RXD1)

    // -------------------------------------------------------------------------
    // USB-UART Serial Telemetry (115200 Baud)
    // -------------------------------------------------------------------------
    output wire        uart_txd_out,    // Pin D4 (FPGA TX -> PC)
    input  wire        uart_rxd_in,     // Pin C4 (PC TX -> FPGA RX)

    // -------------------------------------------------------------------------
    // VGA 640x480 @ 60Hz Visualizer
    // -------------------------------------------------------------------------
    output wire        vga_hs,          // Pin B11 (Horizontal Sync)
    output wire        vga_vs,          // Pin B12 (Vertical Sync)
    output wire [ 3:0] vga_r,           // Pins A4, C5, B4, A3
    output wire [ 3:0] vga_g,           // Pins A6, B6, A5, C6
    output wire [ 3:0] vga_b            // Pins D8, D7, C7, B7
);

    // =========================================================================
    // 1. Clock Generation and Reset Management
    // =========================================================================
    wire clk_core;
    wire clk_eth;
    wire clk_eth_phy;
    wire clk_vga;
    wire rst_core_n;
    wire rst_eth_n;
    wire rst_vga_n;
    wire mmcm_locked;

    clk_rst_mgr u_clk_mgr (
        .clk_100mhz_in (clk),
        .rst_btn_n     (reset),
        .clk_core      (clk_core),
        .clk_eth       (clk_eth),
        .clk_eth_phy   (clk_eth_phy),
        .clk_vga       (clk_vga),
        .rst_core_n    (rst_core_n),
        .rst_eth_n     (rst_eth_n),
        .rst_vga_n     (rst_vga_n),
        .phy_rst_n     (eth_rstn),
        .mmcm_locked   (mmcm_locked)
    );

`ifdef SIMULATION
    assign eth_refclk = clk_eth;
`else
    // Forward dedicated 50.0 MHz 45-degree phase shifted clock to external LAN8720A PHY via ODDR primitive
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) u_oddr_refclk (
        .Q (eth_refclk),
        .C (clk_eth_phy),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R (1'b0),
        .S (1'b0)
    );
`endif

    // =========================================================================
    // 2. Ethernet RMII Physical Receiver & Frame Buffer (50 MHz Domain)
    // =========================================================================
    wire        rmii_frame_valid;
    wire [11:0] rmii_frame_len;
    wire        rmii_frame_read_en;
    wire [ 7:0] rmii_frame_byte;
    wire        rmii_frame_last;
    wire        rmii_frame_ack;

    wire [31:0] cnt_rx_frames;
    wire [31:0] cnt_crc_err;
    wire [31:0] cnt_len_err;
    wire [31:0] cnt_phy_err;
    wire [31:0] cnt_overflow_err;

    rmii_rx u_rmii_rx (
        .clk_50           (clk_eth),
        .rst_n            (rst_eth_n),
        .rmii_crs_dv      (eth_crsdv),
        .rmii_rx_err      (eth_rxerr),
        .rmii_rxd         (eth_rxd),
        .frame_valid      (rmii_frame_valid),
        .frame_len        (rmii_frame_len),
        .frame_read_en    (rmii_frame_read_en),
        .frame_byte_out   (rmii_frame_byte),
        .frame_byte_last  (rmii_frame_last),
        .frame_done_ack   (rmii_frame_ack),
        .cnt_rx_frames    (cnt_rx_frames),
        .cnt_crc_err      (cnt_crc_err),
        .cnt_len_err      (cnt_len_err),
        .cnt_phy_err      (cnt_phy_err),
        .cnt_overflow_err (cnt_overflow_err)
    );

    // =========================================================================
    // 3. Ethernet II / IPv4 / UDP Parser (50 MHz Domain)
    // =========================================================================
    wire        udp_valid;
    wire [11:0] udp_len;
    wire [ 7:0] udp_byte;
    wire        udp_start;
    wire        udp_last;
    wire        udp_ready;

    wire [31:0] cnt_ipv4_frames;
    wire [31:0] cnt_udp_packets;
    wire [31:0] cnt_udp_len_err;
    wire [31:0] cnt_udp_csum_err;
    wire [31:0] cnt_ip_csum_err;

    net_parser u_net_parser (
        .clk                   (clk_eth),
        .rst_n                 (rst_eth_n),
        .frame_valid           (rmii_frame_valid),
        .frame_len             (rmii_frame_len),
        .frame_read_en         (rmii_frame_read_en),
        .frame_byte_in         (rmii_frame_byte),
        .frame_byte_last       (rmii_frame_last),
        .cfg_udp_port          (16'd10443),
        .cfg_dst_mac           (DEST_MAC),
        .cfg_dst_ip            (DEST_IP),
        .udp_payload_valid     (udp_valid),
        .udp_payload_len       (udp_len),
        .udp_payload_byte      (udp_byte),
        .udp_payload_start     (udp_start),
        .udp_payload_last      (udp_last),
        .udp_payload_ready     (udp_ready),
        .cnt_ipv4_frames       (cnt_ipv4_frames),
        .cnt_udp_packets       (cnt_udp_packets),
        .cnt_udp_len_err       (cnt_udp_len_err),
        .cnt_udp_csum_err      (cnt_udp_csum_err),
        .cnt_non_ipv4_drop     (),
        .cnt_ip_csum_err       (cnt_ip_csum_err),
        .cnt_ip_frag_drop      (),
        .cnt_non_udp_drop      (),
        .cnt_port_mismatch_drop()
    );

    // =========================================================================
    // 4. MoldUDP64 Transport Layer Decoder (50 MHz Domain)
    // =========================================================================
    wire        itch_msg_valid;
    wire [15:0] itch_msg_len;
    wire [ 7:0] itch_msg_byte;
    wire [63:0] itch_msg_seq;
    wire        itch_msg_start;
    wire        itch_msg_last;
    wire        itch_msg_ready;

    wire        seq_gap_detected;
    wire [63:0] gap_expected_seq;
    wire [63:0] gap_received_seq;

    wire [31:0] cnt_mold_pkts;
    wire [31:0] cnt_mold_msgs;
    wire [31:0] cnt_heartbeats;
    wire [31:0] cnt_seq_gaps;
    wire [31:0] cnt_mold_trunc;

    moldudp64_decoder u_mold_decoder (
        .clk                (clk_eth),
        .rst_n              (rst_eth_n),
        .udp_payload_valid  (udp_valid),
        .udp_payload_len    (udp_len),
        .udp_payload_byte   (udp_byte),
        .udp_payload_start  (udp_start),
        .udp_payload_last   (udp_last),
        .udp_payload_ready  (udp_ready),
        .cfg_seq_reset      (1'b0),
        .cfg_expected_seq   (64'd1),
        .cfg_seq_override   (1'b0),
        .seq_gap_detected   (seq_gap_detected),
        .gap_expected_seq   (gap_expected_seq),
        .gap_received_seq   (gap_received_seq),
        .itch_msg_valid     (itch_msg_valid),
        .itch_msg_len       (itch_msg_len),
        .itch_msg_byte      (itch_msg_byte),
        .itch_msg_seq       (itch_msg_seq),
        .itch_msg_start     (itch_msg_start),
        .itch_msg_last      (itch_msg_last),
        .itch_msg_ready     (itch_msg_ready),
        .cnt_mold_pkts      (cnt_mold_pkts),
        .cnt_mold_msgs      (cnt_mold_msgs),
        .cnt_heartbeats     (cnt_heartbeats),
        .cnt_end_of_session (),
        .cnt_seq_gaps       (cnt_seq_gaps),
        .cnt_duplicates     (),
        .cnt_trunc_errors   (cnt_mold_trunc)
    );

    // =========================================================================
    // 5. NASDAQ TotalView-ITCH 5.0 Exchange Decoder (50 MHz Domain)
    // =========================================================================
    wire         canon_evt_valid;
    wire [255:0] canon_evt_data;
    wire         canon_evt_ready;

    wire [31:0]  cnt_itch_total;
    wire [31:0]  cnt_itch_events;
    wire [31:0]  cnt_itch_filtered;
    wire         itch_decode_error;
    wire [31:0] mmio_cfg_price_base;
    wire [31:0] mmio_cfg_tick;
    wire [15:0] mmio_cfg_stock_locate;
    wire        mmio_accel_enable;
    wire        mmio_cfg_ready;
    wire [79:0] eth_cfg;
    wire eth_cfg_update;

    config_cdc #(
        .WIDTH(80),
        .RESET_VALUE({DEFAULT_LOCATE, DEFAULT_PRICE_BASE, DEFAULT_TICK})
    ) u_config_cdc (
        .src_clk(clk_core), .src_rst_n(rst_core_n),
        .src_data({mmio_cfg_stock_locate, mmio_cfg_price_base, mmio_cfg_tick}),
        .src_busy(), .src_ready(mmio_cfg_ready),
        .dst_clk(clk_eth), .dst_rst_n(rst_eth_n),
        .dst_data(eth_cfg), .dst_update(eth_cfg_update)
    );

    itch_decoder #(
        .DEFAULT_PRICE_BASE(DEFAULT_PRICE_BASE),
        .DEFAULT_TICK      (DEFAULT_TICK),
        .DEFAULT_LOCATE    (DEFAULT_LOCATE)
    ) u_itch_decoder (
        .clk                   (clk_eth),
        .rst_n                 (rst_eth_n),
        .itch_msg_valid        (itch_msg_valid),
        .itch_msg_len          (itch_msg_len),
        .itch_msg_byte         (itch_msg_byte),
        .itch_msg_seq          (itch_msg_seq),
        .itch_msg_start        (itch_msg_start),
        .itch_msg_last         (itch_msg_last),
        .itch_msg_ready        (itch_msg_ready),
        .cfg_stock_locate      (eth_cfg[79:64]),
        .cfg_price_base        (eth_cfg[63:32]),
        .cfg_tick              (eth_cfg[31:0]),
        .canon_event_valid     (canon_evt_valid),
        .canon_event_data      (canon_evt_data),
        .canon_event_ready     (canon_evt_ready),
        .decode_error          (itch_decode_error),
        .cnt_itch_total_msgs   (cnt_itch_total),
        .cnt_itch_order_events (cnt_itch_events),
        .cnt_itch_filtered_msgs(cnt_itch_filtered),
        .cnt_itch_admin_msgs   (),
        .cnt_itch_oow_events   ()
    );

    // =========================================================================
    // 6. Dual-Clock Asynchronous Event FIFO (separate 50 MHz clock domains)
    // =========================================================================
    wire         core_evt_valid;
    wire [255:0] core_evt_data;
    wire         core_evt_ready;
    wire         fifo_wr_overflow;
    wire         fifo_rd_underflow;
    wire [ 6:0]  fifo_wr_cnt;
    wire [ 6:0]  fifo_rd_cnt;
    reg          feed_loss_eth;
    (* ASYNC_REG = "TRUE" *) reg feed_loss_sync1, feed_loss_sync2;

    // Latch short loss indications in their source domain before crossing to
    // the core. Once a message is lost the book needs a complete reset/replay.
    always @(posedge clk_eth or negedge rst_eth_n) begin
        if (!rst_eth_n)
            feed_loss_eth <= 1'b0;
        else if (seq_gap_detected || itch_decode_error || fifo_wr_overflow ||
                 (eth_cfg_update && cnt_mold_msgs != 32'd0) ||
                 (cnt_crc_err != 32'd0) || (cnt_len_err != 32'd0) ||
                 (cnt_phy_err != 32'd0) || (cnt_overflow_err != 32'd0) ||
                 (cnt_mold_trunc != 32'd0) ||
                 (cnt_udp_len_err != 32'd0) || (cnt_udp_csum_err != 32'd0) ||
                 (cnt_ip_csum_err != 32'd0))
            feed_loss_eth <= 1'b1;
    end

    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            feed_loss_sync1 <= 1'b0;
            feed_loss_sync2 <= 1'b0;
        end else begin
            feed_loss_sync1 <= feed_loss_eth;
            feed_loss_sync2 <= feed_loss_sync1;
        end
    end

    async_event_fifo #(
        .DATA_WIDTH(256),
        .ADDR_WIDTH(6)
    ) u_async_fifo (
        .wr_clk       (clk_eth),
        .wr_rst_n     (rst_eth_n),
        .wr_valid     (canon_evt_valid),
        .wr_data      (canon_evt_data),
        .wr_ready     (canon_evt_ready),
        .wr_full      (),
        .wr_overflow  (fifo_wr_overflow),

        .rd_clk       (clk_core),
        .rd_rst_n     (rst_core_n),
        .rd_ready     (core_evt_ready),
        .rd_valid     (core_evt_valid),
        .rd_data      (core_evt_data),
        .rd_empty     (),
        .rd_underflow (fifo_rd_underflow),

        .wr_count     (fifo_wr_cnt),
        .rd_count     (fifo_rd_cnt)
    );

    // =========================================================================
    // 7. Hardware Limit Order Book Accelerator Core (50 MHz Domain)
    // =========================================================================
    wire        lob_book_valid;
    wire        lob_init_done;
    wire        lob_busy;
    wire        lob_error_valid;
    wire [ 7:0] lob_error_code;
    wire [11:0] lob_active_orders;
    wire        lob_event_done;

    wire        lob_bid_valid;
    wire [31:0] lob_bid_price;
    wire [31:0] lob_bid_qty;

    wire        lob_ask_valid;
    wire [31:0] lob_ask_price;
    wire [31:0] lob_ask_qty;


    lob_core #(
        .DEFAULT_PRICE_BASE  (DEFAULT_PRICE_BASE),
        .DEFAULT_TICK        (DEFAULT_TICK),
        .DEFAULT_FAIL_STOP_EN(1'b1)
    ) u_lob_core (
        .clk                (clk_core),
        .rst_n              (rst_core_n),
        .event_valid        (core_evt_valid),
        .event_ready        (core_evt_ready),
        .event_data         (core_evt_data),
        .cfg_clear          (1'b0),
        .cfg_fail_stop_en   (1'b1),
        .run_enable         (mmio_accel_enable),
        .feed_fault        (feed_loss_sync2),
        .cfg_price_base     (mmio_cfg_price_base),
        .cfg_tick           (mmio_cfg_tick),
        .book_valid         (lob_book_valid),
        .init_done          (lob_init_done),
        .busy               (lob_busy),
        .error_valid        (lob_error_valid),
        .error_code         (lob_error_code),
        .active_order_count (lob_active_orders),
        .event_done         (lob_event_done),
        .best_bid_valid     (lob_bid_valid),
        .best_bid_price     (lob_bid_price),
        .best_bid_qty       (lob_bid_qty),
        .best_ask_valid     (lob_ask_valid),
        .best_ask_price     (lob_ask_price),
        .best_ask_qty       (lob_ask_qty)
    );

    // Event counter
    reg [31:0] core_event_count;
    reg [31:0] fifo_event_count;
    wire [159:0] pipe_eth_snapshot;
    config_cdc #(.WIDTH(160), .RESET_VALUE(160'd0)) u_pipe_trace_cdc (
        .src_clk(clk_eth), .src_rst_n(rst_eth_n),
        .src_data({cnt_rx_frames, cnt_udp_packets, cnt_mold_msgs,
                   cnt_itch_events, fifo_event_count}), .src_busy(),
        .dst_clk(clk_core), .dst_rst_n(rst_core_n),
        .dst_data(pipe_eth_snapshot), .dst_update()
    );
    always @(posedge clk_eth or negedge rst_eth_n) begin
        if (!rst_eth_n)
            fifo_event_count <= 32'd0;
        else if (canon_evt_valid && canon_evt_ready)
            fifo_event_count <= fifo_event_count + 32'd1;
    end
    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n)
            core_event_count <= 32'd0;
        else if (lob_event_done)
            core_event_count <= core_event_count + 32'd1;
    end

    // =========================================================================
    // 8. System Bus Interconnect & CPU Subsystem (50 MHz Domain)
    // =========================================================================
    wire        bus_req_valid;
    wire        bus_req_write;
    wire [31:0] bus_req_addr;
    wire [31:0] bus_req_wdata;
    wire [ 3:0] bus_req_wstrb;
    wire        bus_rsp_valid;
    wire [31:0] bus_rsp_rdata;
    wire        bus_rsp_error;

    wire [31:0] cpu_pc;
    wire        cpu_exception;

    // Bus Slave Connections
    wire        imem_req_valid, imem_req_write;
    wire [31:0] imem_req_addr, imem_req_wdata;
    wire [ 3:0] imem_req_wstrb;
    wire        imem_rsp_valid;
    wire [31:0] imem_rsp_rdata;

    wire        dmem_req_valid, dmem_req_write;
    wire [31:0] dmem_req_addr, dmem_req_wdata;
    wire [ 3:0] dmem_req_wstrb;
    wire        dmem_rsp_valid;
    wire [31:0] dmem_rsp_rdata;

    wire        lob_bus_req_valid, lob_bus_req_write;
    wire [31:0] lob_bus_req_addr, lob_bus_req_wdata;
    wire [ 3:0] lob_bus_req_wstrb;
    wire        lob_bus_rsp_valid;
    wire [31:0] lob_bus_rsp_rdata;

    wire        uart_bus_req_valid, uart_bus_req_write;
    wire [31:0] uart_bus_req_addr, uart_bus_req_wdata;
    wire [ 3:0] uart_bus_req_wstrb;
    wire        uart_bus_rsp_valid;
    wire [31:0] uart_bus_rsp_rdata;

    wire        net_bus_req_valid, net_bus_req_write;
    wire [31:0] net_bus_req_addr, net_bus_req_wdata;
    wire [ 3:0] net_bus_req_wstrb;
    wire        net_bus_rsp_valid;
    wire [31:0] net_bus_rsp_rdata;
    wire [351:0] net_diag_snapshot;
    wire [31:0] ip_checksum_errors_core;
    config_cdc #(.WIDTH(352), .RESET_VALUE(352'd0)) u_net_diag_cdc (
        .src_clk(clk_eth), .src_rst_n(rst_eth_n),
        .src_data({cnt_rx_frames, cnt_crc_err, cnt_mold_msgs, cnt_seq_gaps,
                   cnt_len_err, cnt_phy_err, cnt_overflow_err, cnt_mold_trunc,
                   cnt_udp_len_err, cnt_udp_csum_err,
                   29'd0, itch_decode_error, seq_gap_detected, feed_loss_eth}),
        .src_busy(), .dst_clk(clk_core), .dst_rst_n(rst_core_n),
        .dst_data(net_diag_snapshot), .dst_update()
    );
    config_cdc #(.WIDTH(32), .RESET_VALUE(32'd0)) u_ip_checksum_cdc (
        .src_clk(clk_eth), .src_rst_n(rst_eth_n),
        .src_data(cnt_ip_csum_err), .src_busy(),
        .dst_clk(clk_core), .dst_rst_n(rst_core_n),
        .dst_data(ip_checksum_errors_core), .dst_update()
    );

    wire        sys_bus_req_valid, sys_bus_req_write;
    wire [31:0] sys_bus_req_addr, sys_bus_req_wdata;
    wire [ 3:0] sys_bus_req_wstrb;
    reg         sys_bus_rsp_valid;
    reg  [31:0] sys_bus_rsp_rdata;

    // CPU Core Instance
    cpu_core u_cpu (
        .clk           (clk_core),
        .reset         (rst_core_n),
        .stall         (1'b0),
        .exception     (cpu_exception),
        .pc_out        (cpu_pc),
        .bus_req_valid (bus_req_valid),
        .bus_req_write (bus_req_write),
        .bus_req_addr  (bus_req_addr),
        .bus_req_wdata (bus_req_wdata),
        .bus_req_wstrb (bus_req_wstrb),
        .bus_rsp_valid (bus_rsp_valid),
        .bus_rsp_rdata (bus_rsp_rdata),
        .bus_rsp_error (bus_rsp_error)
    );

    // Crossbar / System Bus Interconnect
    sys_bus_interconnect u_interconnect (
        .clk           (clk_core),
        .reset         (rst_core_n),
        .cpu_req_valid (bus_req_valid),
        .cpu_req_write (bus_req_write),
        .cpu_req_addr  (bus_req_addr),
        .cpu_req_wdata (bus_req_wdata),
        .cpu_req_wstrb (bus_req_wstrb),
        .cpu_rsp_valid (bus_rsp_valid),
        .cpu_rsp_rdata (bus_rsp_rdata),
        .cpu_rsp_error (bus_rsp_error),

        .imem_req_valid(imem_req_valid),
        .imem_req_write(imem_req_write),
        .imem_req_addr (imem_req_addr),
        .imem_req_wdata(imem_req_wdata),
        .imem_req_wstrb(imem_req_wstrb),
        .imem_rsp_valid(imem_rsp_valid),
        .imem_rsp_rdata(imem_rsp_rdata),

        .dmem_req_valid(dmem_req_valid),
        .dmem_req_write(dmem_req_write),
        .dmem_req_addr (dmem_req_addr),
        .dmem_req_wdata(dmem_req_wdata),
        .dmem_req_wstrb(dmem_req_wstrb),
        .dmem_rsp_valid(dmem_rsp_valid),
        .dmem_rsp_rdata(dmem_rsp_rdata),

        .lob_req_valid (lob_bus_req_valid),
        .lob_req_write (lob_bus_req_write),
        .lob_req_addr  (lob_bus_req_addr),
        .lob_req_wdata (lob_bus_req_wdata),
        .lob_req_wstrb (lob_bus_req_wstrb),
        .lob_rsp_valid (lob_bus_rsp_valid),
        .lob_rsp_rdata (lob_bus_rsp_rdata),

        .net_req_valid (net_bus_req_valid),
        .net_req_write (net_bus_req_write),
        .net_req_addr  (net_bus_req_addr),
        .net_req_wdata (net_bus_req_wdata),
        .net_req_wstrb (net_bus_req_wstrb),
        .net_rsp_valid (net_bus_rsp_valid),
        .net_rsp_rdata (net_bus_rsp_rdata),

        .uart_req_valid(uart_bus_req_valid),
        .uart_req_write(uart_bus_req_write),
        .uart_req_addr (uart_bus_req_addr),
        .uart_req_wdata(uart_bus_req_wdata),
        .uart_req_wstrb(uart_bus_req_wstrb),
        .uart_rsp_valid(uart_bus_rsp_valid),
        .uart_rsp_rdata(uart_bus_rsp_rdata),

        .sys_req_valid (sys_bus_req_valid),
        .sys_req_write (sys_bus_req_write),
        .sys_req_addr  (sys_bus_req_addr),
        .sys_req_wdata (sys_bus_req_wdata),
        .sys_req_wstrb (sys_bus_req_wstrb),
        .sys_rsp_valid (sys_bus_rsp_valid),
        .sys_rsp_rdata (sys_bus_rsp_rdata)
    );

    // Instruction Memory Slave
    imem_slave u_imem (
        .clk      (clk_core),
        .reset    (rst_core_n),
        .req_valid(imem_req_valid),
        .req_write(imem_req_write),
        .req_addr (imem_req_addr),
        .req_wdata(imem_req_wdata),
        .req_wstrb(imem_req_wstrb),
        .rsp_valid(imem_rsp_valid),
        .rsp_rdata(imem_rsp_rdata)
    );

    // Data Memory Slave
    dmem_slave #(
        .DELAY_CYCLES(0)
    ) u_dmem (
        .clk      (clk_core),
        .reset    (rst_core_n),
        .req_valid(dmem_req_valid),
        .req_write(dmem_req_write),
        .req_addr (dmem_req_addr),
        .req_wdata(dmem_req_wdata),
        .req_wstrb(dmem_req_wstrb),
        .rsp_valid(dmem_rsp_valid),
        .rsp_rdata(dmem_rsp_rdata)
    );

    // LOB MMIO Slave with Coherent Snapshot Engine (0x4000_0000)
    lob_mmio_slave u_lob_mmio (
        .clk                (clk_core),
        .reset              (rst_core_n),
        .bus_req_valid      (lob_bus_req_valid),
        .bus_req_write      (lob_bus_req_write),
        .bus_req_addr       (lob_bus_req_addr),
        .bus_req_wdata      (lob_bus_req_wdata),
        .bus_req_wstrb      (lob_bus_req_wstrb),
        .bus_rsp_valid      (lob_bus_rsp_valid),
        .bus_rsp_rdata      (lob_bus_rsp_rdata),
        .cfg_price_base     (mmio_cfg_price_base),
        .cfg_tick           (mmio_cfg_tick),
        .cfg_stock_locate   (mmio_cfg_stock_locate),
        .accel_enable       (mmio_accel_enable),
        .config_ready       (mmio_cfg_ready),
        .book_valid         (lob_book_valid),
        .init_done          (lob_init_done),
        .busy               (lob_busy),
        .error_valid        (lob_error_valid),
        .error_code         (lob_error_code),
        .active_order_count (lob_active_orders),
        .event_done         (lob_event_done),
        .event_ready        (core_evt_ready),
        .best_bid_valid     (lob_bid_valid),
        .best_bid_price     (lob_bid_price),
        .best_bid_qty       (lob_bid_qty),
        .best_ask_valid     (lob_ask_valid),
        .best_ask_price     (lob_ask_price),
        .best_ask_qty       (lob_ask_qty)
    );

    // Network Telemetry MMIO Slave (0x5000_0000)
    // Implemented as a dedicated module to isolate the net_diag_snapshot mux
    // from the CPU pipeline timing arc (see rtl/bus/net_mmio_slave.v).
    net_mmio_slave u_net_mmio (
        .clk             (clk_core),
        .reset           (rst_core_n),
        .bus_req_valid   (net_bus_req_valid),
        .bus_req_addr    (net_bus_req_addr[7:0]),
        .bus_rsp_valid   (net_bus_rsp_valid),
        .bus_rsp_rdata   (net_bus_rsp_rdata),
        .net_diag_snapshot(net_diag_snapshot)
    );

    // System Control / Switches MMIO Slave (0x7000_0000)
    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            sys_bus_rsp_valid <= 1'b0;
            sys_bus_rsp_rdata <= 32'd0;
        end else begin
            sys_bus_rsp_valid <= sys_bus_req_valid;
            if (sys_bus_req_valid) begin
                case (sys_bus_req_addr[7:0])
                    8'h00: sys_bus_rsp_rdata <= {28'd0, sw};
                    8'h04: sys_bus_rsp_rdata <= {31'd0, mmcm_locked};
                    default: sys_bus_rsp_rdata <= 32'd0;
                endcase
            end
        end
    end

    // =========================================================================
    // 9. UART Serial Telemetry Engine (0x6000_0000)
    // =========================================================================
    uart_telemetry #(
        .CLK_FREQ (50_000_000),
        .BAUD_RATE(115_200)
    ) u_uart (
        .clk              (clk_core),
        .rst_n            (rst_core_n),
        .bus_req_valid    (uart_bus_req_valid),
        .bus_req_write    (uart_bus_req_write),
        .bus_req_addr     (uart_bus_req_addr),
        .bus_req_wdata    (uart_bus_req_wdata),
        .bus_rsp_valid    (uart_bus_rsp_valid),
        .bus_rsp_rdata    (uart_bus_rsp_rdata),
        .hw_telem_trigger (lob_event_done),
        .best_bid_price   (lob_bid_price),
        .best_bid_qty     (lob_bid_qty),
        .best_ask_price   (lob_ask_price),
        .best_ask_qty     (lob_ask_qty),
        .active_orders    (lob_active_orders),
        .book_valid       (lob_book_valid),
        .error_code       (lob_error_code),
        .crc_errors       (net_diag_snapshot[319:288]),
        .udp_checksum_errors(net_diag_snapshot[63:32]),
        .ip_checksum_errors(ip_checksum_errors_core),
        .pipe_rx_frames   (pipe_eth_snapshot[159:128]),
        .pipe_udp_packets (pipe_eth_snapshot[127:96]),
        .pipe_mold_msgs   (pipe_eth_snapshot[95:64]),
        .pipe_itch_events (pipe_eth_snapshot[63:32]),
        .pipe_fifo_events (pipe_eth_snapshot[31:0]),
        .pipe_done_events (core_event_count),
        .uart_txd         (uart_txd_out)
    );

    // =========================================================================
    // 10. VGA Market Data & LOB Visualizer (25 MHz Domain)
    // =========================================================================
    wire [174:0] vga_core_snapshot;
    wire [127:0] vga_net_snapshot;
    config_cdc #(.WIDTH(175), .RESET_VALUE(175'd0)) u_vga_core_cdc (
        .src_clk(clk_core), .src_rst_n(rst_core_n),
        .src_data({lob_book_valid, lob_bid_valid, lob_bid_price, lob_bid_qty,
                   lob_ask_valid, lob_ask_price, lob_ask_qty,
                   lob_active_orders, core_event_count}),
        .src_busy(), .dst_clk(clk_vga), .dst_rst_n(rst_vga_n),
        .dst_data(vga_core_snapshot), .dst_update()
    );
    config_cdc #(.WIDTH(128), .RESET_VALUE(128'd0)) u_vga_net_cdc (
        .src_clk(clk_eth), .src_rst_n(rst_eth_n),
        .src_data({cnt_rx_frames, cnt_crc_err, cnt_mold_msgs, cnt_seq_gaps}),
        .src_busy(), .dst_clk(clk_vga), .dst_rst_n(rst_vga_n),
        .dst_data(vga_net_snapshot), .dst_update()
    );
    vga_top u_vga (
        .clk_vga        (clk_vga),
        .rst_n          (rst_vga_n),
        .book_valid     (vga_core_snapshot[174]),
        .best_bid_valid (vga_core_snapshot[173]),
        .best_bid_price (vga_core_snapshot[172:141]),
        .best_bid_qty   (vga_core_snapshot[140:109]),
        .best_ask_valid (vga_core_snapshot[108]),
        .best_ask_price (vga_core_snapshot[107:76]),
        .best_ask_qty   (vga_core_snapshot[75:44]),
        .active_orders  (vga_core_snapshot[43:32]),
        .event_count    (vga_core_snapshot[31:0]),
        .cnt_rx_frames  (vga_net_snapshot[127:96]),
        .cnt_crc_err    (vga_net_snapshot[95:64]),
        .cnt_mold_msgs  (vga_net_snapshot[63:32]),
        .cnt_seq_gaps   (vga_net_snapshot[31:0]),
        .vga_hs         (vga_hs),
        .vga_vs         (vga_vs),
        .vga_r          (vga_r),
        .vga_g          (vga_g),
        .vga_b          (vga_b)
    );

    // =========================================================================
    // 11. Board Diagnostic LEDs & 7-Segment Multiplexed Display
    // =========================================================================
    assign led[0]     = mmcm_locked;
    assign led[1]     = eth_rstn;
    assign led[2]     = lob_init_done;
    assign led[3]     = lob_book_valid;
    assign led[4]     = lob_bid_valid;
    assign led[5]     = lob_ask_valid;
    assign led[6]     = lob_busy;
    assign led[7]     = lob_error_valid;
    assign led[8]     = eth_crsdv;
    assign led[9]     = core_evt_valid; // Event waiting in FIFO
    assign led[10]    = seq_gap_detected;
    assign led[11]    = (cnt_crc_err != 32'd0);
    assign led[15:12] = lob_error_valid ? lob_error_code[3:0] : lob_active_orders[3:0];

    // Interactive 7-Segment Value Selection via Slide Switches sw[1:0]
    // Default (sw=00): Best Bid Price ($XXXX.XXXX)
    // sw=01:          Best Ask Price ($XXXX.XXXX)
    // sw=10:          Active Orders (4 decimal digits) & Events (4 digits)
    // sw=11:          RX Frames (4 decimal digits) & CPU PC (4 digits)
    reg [31:0] display_val;
    always @(*) begin
        case (sw[1:0])
            2'b00: display_val = lob_bid_price;                                     // Best Bid Price
            2'b01: display_val = lob_ask_price;                                     // Best Ask Price
            2'b10: display_val = {4'h0, lob_active_orders, core_event_count[15:0]}; // Orders & Events
            2'b11: display_val = {net_diag_snapshot[351:336], cpu_pc[15:0]};      // Net Frames & CPU PC
        endcase
    end

    seven_seg_driver #(.CLK_FREQ_HZ(50_000_000)) u_seven_seg (
        .clk   (clk_core),
        .reset (rst_core_n),
        .value (display_val),
        .format((sw[1:0] == 2'b00 || sw[1:0] == 2'b01) ? 2'b01 : 2'b10),
        .point_mask((sw[1:0] == 2'b00 || sw[1:0] == 2'b01) ? 8'b0001_0000 : 8'b0),
        .an    (an),
        .seg   (seg),
        .dp    (dp)
    );

endmodule
