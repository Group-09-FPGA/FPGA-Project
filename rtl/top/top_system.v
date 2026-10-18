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
    parameter [15:0] DEFAULT_LOCATE     = 16'd1
) (
    // -------------------------------------------------------------------------
    // 100 MHz Master Board Clock & Reset
    // -------------------------------------------------------------------------
    input  wire        clk,             // Pin E3 (100.0 MHz board oscillator)
    input  wire        reset,           // Pin C12 (CPU_RESETN, active-low push button)

    // -------------------------------------------------------------------------
    // Interactive User Switches & Push Buttons
    // -------------------------------------------------------------------------
    input  wire [ 3:0] sw,              // Pins J15, L16, M13, R15

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
        .clk_vga       (clk_vga),
        .rst_core_n    (rst_core_n),
        .rst_eth_n     (rst_eth_n),
        .rst_vga_n     (rst_vga_n),
        .phy_rst_n     (eth_rstn),
        .mmcm_locked   (mmcm_locked)
    );

    // Forward 50.0 MHz clock to external LAN8720A PHY
    assign eth_refclk = clk_eth;

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

    net_parser u_net_parser (
        .clk                   (clk_eth),
        .rst_n                 (rst_eth_n),
        .frame_valid           (rmii_frame_valid),
        .frame_len             (rmii_frame_len),
        .frame_read_en         (rmii_frame_read_en),
        .frame_byte_in         (rmii_frame_byte),
        .frame_byte_last       (rmii_frame_last),
        .cfg_udp_port          (16'd10443),
        .udp_payload_valid     (udp_valid),
        .udp_payload_len       (udp_len),
        .udp_payload_byte      (udp_byte),
        .udp_payload_start     (udp_start),
        .udp_payload_last      (udp_last),
        .udp_payload_ready     (udp_ready),
        .cnt_ipv4_frames       (cnt_ipv4_frames),
        .cnt_udp_packets       (cnt_udp_packets),
        .cnt_non_ipv4_drop     (),
        .cnt_ip_csum_err       (),
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
        .cnt_trunc_errors   ()
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
        .cfg_stock_locate      (DEFAULT_LOCATE),
        .cfg_price_base        (DEFAULT_PRICE_BASE),
        .cfg_tick              (DEFAULT_TICK),
        .canon_event_valid     (canon_evt_valid),
        .canon_event_data      (canon_evt_data),
        .canon_event_ready     (canon_evt_ready),
        .cnt_itch_total_msgs   (cnt_itch_total),
        .cnt_itch_order_events (cnt_itch_events),
        .cnt_itch_filtered_msgs(cnt_itch_filtered),
        .cnt_itch_admin_msgs   (),
        .cnt_itch_oow_events   ()
    );

    // =========================================================================
    // 6. Dual-Clock Asynchronous Event FIFO (50 MHz -> 100 MHz CDC)
    // =========================================================================
    wire         core_evt_valid;
    wire [255:0] core_evt_data;
    wire         core_evt_ready;
    wire         fifo_wr_overflow;
    wire         fifo_rd_underflow;
    wire [ 6:0]  fifo_wr_cnt;
    wire [ 6:0]  fifo_rd_cnt;

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
    // 7. Hardware Limit Order Book Accelerator Core (100 MHz Domain)
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

    wire        mmio_cfg_clear;
    wire        mmio_cfg_fail_stop;
    wire [31:0] mmio_cfg_price_base;
    wire [31:0] mmio_cfg_tick;

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
        .cfg_clear          (mmio_cfg_clear),
        .cfg_fail_stop_en   (mmio_cfg_fail_stop),
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
    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n)
            core_event_count <= 32'd0;
        else if (lob_event_done)
            core_event_count <= core_event_count + 32'd1;
    end

    // =========================================================================
    // 8. System Bus Interconnect & CPU Subsystem (100 MHz Domain)
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
    reg         net_bus_rsp_valid;
    reg  [31:0] net_bus_rsp_rdata;

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
        .cfg_clear_strobe   (mmio_cfg_clear),
        .cfg_fail_stop_en   (mmio_cfg_fail_stop),
        .cfg_price_base     (mmio_cfg_price_base),
        .cfg_tick           (mmio_cfg_tick),
        .cfg_stock_locate   (),
        .accel_enable       (),
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
        .best_ask_qty       (lob_ask_qty),
        .inject_valid       (),
        .inject_event_data  (),
        .inject_ready       (1'b0)
    );

    // Network Telemetry MMIO Slave (0x5000_0000)
    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            net_bus_rsp_valid <= 1'b0;
            net_bus_rsp_rdata <= 32'd0;
        end else begin
            net_bus_rsp_valid <= net_bus_req_valid;
            if (net_bus_req_valid) begin
                case (net_bus_req_addr[7:0])
                    8'h00: net_bus_rsp_rdata <= cnt_rx_frames;
                    8'h04: net_bus_rsp_rdata <= cnt_crc_err;
                    8'h08: net_bus_rsp_rdata <= cnt_mold_msgs;
                    8'h0C: net_bus_rsp_rdata <= cnt_seq_gaps;
                    default: net_bus_rsp_rdata <= 32'd0;
                endcase
            end
        end
    end

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
        .CLK_FREQ (100_000_000),
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
        .uart_txd         (uart_txd_out)
    );

    // =========================================================================
    // 10. VGA Market Data & LOB Visualizer (25 MHz Domain)
    // =========================================================================
    vga_top u_vga (
        .clk_vga        (clk_vga),
        .rst_n          (rst_vga_n),
        .book_valid     (lob_book_valid),
        .best_bid_valid (lob_bid_valid),
        .best_bid_price (lob_bid_price),
        .best_bid_qty   (lob_bid_qty),
        .best_ask_valid (lob_ask_valid),
        .best_ask_price (lob_ask_price),
        .best_ask_qty   (lob_ask_qty),
        .active_orders  (lob_active_orders),
        .event_count    (core_event_count),
        .cnt_rx_frames  (cnt_rx_frames),
        .cnt_crc_err    (cnt_crc_err),
        .cnt_mold_msgs  (cnt_mold_msgs),
        .cnt_seq_gaps   (cnt_seq_gaps),
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
    reg [31:0] display_val;
    always @(*) begin
        case (sw[1:0])
            2'b00: display_val = cpu_pc;                                    // CPU PC
            2'b01: display_val = lob_bid_price;                            // Best Bid Price
            2'b10: display_val = lob_ask_price;                            // Best Ask Price
            2'b11: display_val = {4'h0, lob_active_orders, core_event_count[15:0]}; // Orders & Events
        endcase
    end

    seven_seg_driver u_seven_seg (
        .clk   (clk_core),
        .reset (rst_core_n),
        .value (display_val),
        .an    (an),
        .seg   (seg),
        .dp    (dp)
    );

endmodule
