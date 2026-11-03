`timescale 1ns / 1ps

// Ethernet frame -> canonical order event, with statistics.
// Runs in the eth clock domain; every output is delivered in the core domain.
module net_ingest #(
    parameter [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter [31:0] DEFAULT_TICK       = 32'd1000,
    parameter [15:0] DEFAULT_LOCATE     = 16'd1,
    parameter [47:0] DEST_MAC           = 48'd0,
    parameter [31:0] DEST_IP            = 32'd0
) (
    input  wire         clk_eth,
    input  wire         rst_eth_n,
    input  wire         clk_core,
    input  wire         rst_core_n,

    input  wire         eth_crsdv,
    input  wire         eth_rxerr,
    input  wire [1:0]   eth_rxd,

    input  wire [79:0]  cfg_core,        // {stock locate, price base, tick}
    output wire         cfg_ready,

    output wire         evt_valid,
    output wire [255:0] evt_data,
    input  wire         evt_ready,

    output wire         feed_loss,
    output wire [351:0] diag,            // see net_mmio_slave for the field order
    output wire [31:0]  ip_csum_errors,
    output wire [159:0] pipe_stats       // rx frames, udp packets, mold msgs, itch events, fifo events
);
    wire        frame_valid, frame_read_en, frame_last, frame_ack;
    wire [11:0] frame_len;
    wire [7:0]  frame_byte;
    wire [31:0] cnt_rx_frames, cnt_crc_err, cnt_len_err, cnt_phy_err, cnt_overflow_err;

    rmii_rx u_rmii_rx (
        .clk_50(clk_eth), .rst_n(rst_eth_n),
        .rmii_crs_dv(eth_crsdv), .rmii_rx_err(eth_rxerr), .rmii_rxd(eth_rxd),
        .frame_valid(frame_valid), .frame_len(frame_len),
        .frame_read_en(frame_read_en), .frame_byte_out(frame_byte),
        .frame_byte_last(frame_last), .frame_done_ack(frame_ack),
        .cnt_rx_frames(cnt_rx_frames), .cnt_crc_err(cnt_crc_err),
        .cnt_len_err(cnt_len_err), .cnt_phy_err(cnt_phy_err),
        .cnt_overflow_err(cnt_overflow_err)
    );

    wire        udp_valid, udp_start, udp_last, udp_ready;
    wire [11:0] udp_len;
    wire [7:0]  udp_byte;
    wire [31:0] cnt_udp_packets, cnt_udp_len_err, cnt_udp_csum_err, cnt_ip_csum_err;

    net_parser u_net_parser (
        .clk(clk_eth), .rst_n(rst_eth_n),
        .frame_valid(frame_valid), .frame_len(frame_len),
        .frame_read_en(frame_read_en), .frame_byte_in(frame_byte),
        .frame_byte_last(frame_last),
        .cfg_udp_port(16'd10443), .cfg_dst_mac(DEST_MAC), .cfg_dst_ip(DEST_IP),
        .udp_payload_valid(udp_valid), .udp_payload_len(udp_len),
        .udp_payload_byte(udp_byte), .udp_payload_start(udp_start),
        .udp_payload_last(udp_last), .udp_payload_ready(udp_ready),
        .cnt_ipv4_frames(), .cnt_udp_packets(cnt_udp_packets),
        .cnt_udp_len_err(cnt_udp_len_err), .cnt_udp_csum_err(cnt_udp_csum_err),
        .cnt_non_ipv4_drop(), .cnt_ip_csum_err(cnt_ip_csum_err),
        .cnt_ip_frag_drop(), .cnt_non_udp_drop(), .cnt_port_mismatch_drop()
    );

    wire        msg_valid, msg_start, msg_last, msg_ready;
    wire [15:0] msg_len;
    wire [7:0]  msg_byte;
    wire [63:0] msg_seq;
    wire        seq_gap_detected;
    wire [31:0] cnt_mold_pkts, cnt_mold_msgs, cnt_seq_gaps, cnt_mold_trunc;

    moldudp64_decoder u_mold_decoder (
        .clk(clk_eth), .rst_n(rst_eth_n),
        .udp_payload_valid(udp_valid), .udp_payload_len(udp_len),
        .udp_payload_byte(udp_byte), .udp_payload_start(udp_start),
        .udp_payload_last(udp_last), .udp_payload_ready(udp_ready),
        .cfg_seq_reset(1'b0), .cfg_expected_seq(64'd1), .cfg_seq_override(1'b0),
        .seq_gap_detected(seq_gap_detected), .gap_expected_seq(), .gap_received_seq(),
        .itch_msg_valid(msg_valid), .itch_msg_len(msg_len), .itch_msg_byte(msg_byte),
        .itch_msg_seq(msg_seq), .itch_msg_start(msg_start), .itch_msg_last(msg_last),
        .itch_msg_ready(msg_ready),
        .cnt_mold_pkts(cnt_mold_pkts), .cnt_mold_msgs(cnt_mold_msgs), .cnt_heartbeats(),
        .cnt_end_of_session(), .cnt_seq_gaps(cnt_seq_gaps), .cnt_duplicates(),
        .cnt_trunc_errors(cnt_mold_trunc)
    );

    wire [79:0] eth_cfg;
    wire        eth_cfg_update;
    config_cdc #(
        .WIDTH(80), .RESET_VALUE({DEFAULT_LOCATE, DEFAULT_PRICE_BASE, DEFAULT_TICK})
    ) u_cfg_cdc (
        .src_clk(clk_core), .src_rst_n(rst_core_n), .src_data(cfg_core),
        .src_busy(), .src_ready(cfg_ready),
        .dst_clk(clk_eth), .dst_rst_n(rst_eth_n),
        .dst_data(eth_cfg), .dst_update(eth_cfg_update)
    );

    wire         canon_valid, canon_ready, itch_decode_error;
    wire [255:0] canon_data;
    wire [31:0]  cnt_itch_events;

    itch_decoder #(
        .DEFAULT_PRICE_BASE(DEFAULT_PRICE_BASE), .DEFAULT_TICK(DEFAULT_TICK),
        .DEFAULT_LOCATE(DEFAULT_LOCATE)
    ) u_itch_decoder (
        .clk(clk_eth), .rst_n(rst_eth_n),
        .itch_msg_valid(msg_valid), .itch_msg_len(msg_len), .itch_msg_byte(msg_byte),
        .itch_msg_seq(msg_seq), .itch_msg_start(msg_start), .itch_msg_last(msg_last),
        .itch_msg_ready(msg_ready),
        .cfg_stock_locate(eth_cfg[79:64]), .cfg_price_base(eth_cfg[63:32]),
        .cfg_tick(eth_cfg[31:0]),
        .canon_event_valid(canon_valid), .canon_event_data(canon_data),
        .canon_event_ready(canon_ready), .decode_error(itch_decode_error),
        .cnt_itch_total_msgs(), .cnt_itch_order_events(cnt_itch_events),
        .cnt_itch_filtered_msgs(), .cnt_itch_admin_msgs(), .cnt_itch_oow_events()
    );

    wire fifo_wr_overflow;
    wire [6:0] fifo_wr_cnt, fifo_rd_cnt;
    async_event_fifo #(.DATA_WIDTH(256), .ADDR_WIDTH(6)) u_event_fifo (
        .wr_clk(clk_eth), .wr_rst_n(rst_eth_n),
        .wr_valid(canon_valid), .wr_data(canon_data), .wr_ready(canon_ready),
        .wr_full(), .wr_overflow(fifo_wr_overflow),
        .rd_clk(clk_core), .rd_rst_n(rst_core_n),
        .rd_ready(evt_ready), .rd_valid(evt_valid), .rd_data(evt_data),
        .rd_empty(), .rd_underflow(), .wr_count(fifo_wr_cnt), .rd_count(fifo_rd_cnt)
    );

    wire [31:0] fifo_event_count;
    event_counter u_fifo_events (
        .clk(clk_eth), .rst_n(rst_eth_n),
        .inc(canon_valid && canon_ready), .count(fifo_event_count)
    );

    // Once any message may have been lost the book needs a full reset and replay,
    // so the loss flag is sticky.
    reg feed_loss_eth;
    always @(posedge clk_eth or negedge rst_eth_n) begin
        if (!rst_eth_n)
            feed_loss_eth <= 1'b0;
        else if (seq_gap_detected || itch_decode_error || fifo_wr_overflow ||
                 (eth_cfg_update && cnt_mold_msgs != 32'd0) ||
                 cnt_crc_err != 32'd0 || cnt_len_err != 32'd0 ||
                 cnt_phy_err != 32'd0 || cnt_overflow_err != 32'd0 ||
                 cnt_mold_trunc != 32'd0 || cnt_udp_len_err != 32'd0 ||
                 cnt_udp_csum_err != 32'd0 || cnt_ip_csum_err != 32'd0)
            feed_loss_eth <= 1'b1;
    end

    (* ASYNC_REG = "TRUE" *) reg loss_sync1, loss_sync2;
    always @(posedge clk_core or negedge rst_core_n) begin
        if (!rst_core_n) begin
            loss_sync1 <= 1'b0;
            loss_sync2 <= 1'b0;
        end else begin
            loss_sync1 <= feed_loss_eth;
            loss_sync2 <= loss_sync1;
        end
    end
    assign feed_loss = loss_sync2;

    config_cdc #(.WIDTH(352), .RESET_VALUE(352'd0)) u_diag_cdc (
        .src_clk(clk_eth), .src_rst_n(rst_eth_n),
        .src_data({cnt_rx_frames, cnt_crc_err, cnt_mold_msgs, cnt_seq_gaps,
                   cnt_len_err, cnt_phy_err, cnt_overflow_err, cnt_mold_trunc,
                   cnt_udp_len_err, cnt_udp_csum_err,
                   29'd0, itch_decode_error, seq_gap_detected, feed_loss_eth}),
        .src_busy(), .dst_clk(clk_core), .dst_rst_n(rst_core_n),
        .dst_data(diag), .dst_update()
    );

    config_cdc #(.WIDTH(32), .RESET_VALUE(32'd0)) u_ip_csum_cdc (
        .src_clk(clk_eth), .src_rst_n(rst_eth_n), .src_data(cnt_ip_csum_err),
        .src_busy(), .dst_clk(clk_core), .dst_rst_n(rst_core_n),
        .dst_data(ip_csum_errors), .dst_update()
    );

    config_cdc #(.WIDTH(160), .RESET_VALUE(160'd0)) u_pipe_cdc (
        .src_clk(clk_eth), .src_rst_n(rst_eth_n),
        .src_data({cnt_rx_frames, cnt_udp_packets, cnt_mold_msgs,
                   cnt_itch_events, fifo_event_count}),
        .src_busy(), .dst_clk(clk_core), .dst_rst_n(rst_core_n),
        .dst_data(pipe_stats), .dst_update()
    );
endmodule
