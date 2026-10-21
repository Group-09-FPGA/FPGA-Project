// =============================================================================
// File: moldudp64_decoder.v
// Description: Hardware MoldUDP64 protocol downstream framing and sequence tracker
//              Maintains authoritative 64-bit sequence, detects gaps/duplicates,
//              and un-frames length-prefixed ITCH 5.0 messages
// Target: AMD/Xilinx Artix-7 (Digilent Nexys A7-100T)
// =============================================================================

`timescale 1ns / 1ps

module moldudp64_decoder (
    input  wire        clk,
    input  wire        rst_n,

    // Ingress interface from net_parser
    input  wire        udp_payload_valid,
    input  wire [11:0] udp_payload_len,
    input  wire [ 7:0] udp_payload_byte,
    input  wire        udp_payload_start,
    input  wire        udp_payload_last,
    output wire        udp_payload_ready,

    // Control & Recovery interface from MMIO / Host
    input  wire        cfg_seq_reset,      // Reset sequence tracking
    input  wire [63:0] cfg_expected_seq,   // Initialize expected sequence from host snapshot
    input  wire        cfg_seq_override,   // Force set expected sequence
    output reg         seq_gap_detected,   // Latched fail-stop flag on sequence gap
    output reg  [63:0] gap_expected_seq,   // Latched expected sequence on gap
    output reg  [63:0] gap_received_seq,   // Latched received sequence on gap

    // Egress interface to NASDAQ ITCH 5.0 Decoder
    output reg         itch_msg_valid,     // Streaming message byte valid
    output reg  [15:0] itch_msg_len,       // Length of current ITCH message
    output reg  [ 7:0] itch_msg_byte,      // Message payload byte
    output reg  [63:0] itch_msg_seq,       // 64-bit sequence assigned to this message
    output reg         itch_msg_start,     // Pulses on first byte of ITCH message
    output reg         itch_msg_last,      // Pulses on last byte of ITCH message
    input  wire        itch_msg_ready,     // Downstream ITCH parser ready

    // Telemetry & Diagnostic Counters
    output reg  [31:0] cnt_mold_pkts,
    output reg  [31:0] cnt_mold_msgs,
    output reg  [31:0] cnt_heartbeats,
    output reg  [31:0] cnt_end_of_session,
    output reg  [31:0] cnt_seq_gaps,
    output reg  [31:0] cnt_duplicates,
    output reg  [31:0] cnt_trunc_errors
);

    localparam [2:0]
        MOLD_IDLE        = 3'd0,
        MOLD_HEADER      = 3'd1,
        MOLD_MSG_LEN     = 3'd2,
        MOLD_STREAM_MSG  = 3'd3,
        MOLD_DRAIN       = 3'd4;

    reg [2:0] state;

    reg [ 4:0] hdr_byte_cnt;
    reg [79:0] session_id;
    reg [63:0] pkt_seq;
    reg [15:0] msg_count;
    reg [15:0] cur_msg_idx;
    reg [15:0] cur_msg_len;
    reg [15:0] cur_msg_byte_cnt;

    reg [63:0] expected_seq;
    reg        seq_initialized;

    assign udp_payload_ready = (state == MOLD_IDLE) ||
                               (state == MOLD_HEADER) ||
                               (state == MOLD_DRAIN) ||
                               itch_msg_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= MOLD_IDLE;
            hdr_byte_cnt       <= 5'd0;
            session_id         <= 80'd0;
            pkt_seq            <= 64'd0;
            msg_count          <= 16'd0;
            cur_msg_idx        <= 16'd0;
            cur_msg_len        <= 16'd0;
            cur_msg_byte_cnt   <= 16'd0;
            expected_seq       <= 64'd0;
            seq_initialized    <= 1'b0;
            seq_gap_detected   <= 1'b0;
            gap_expected_seq   <= 64'd0;
            gap_received_seq   <= 64'd0;
            itch_msg_valid     <= 1'b0;
            itch_msg_len       <= 16'd0;
            itch_msg_byte      <= 8'd0;
            itch_msg_seq       <= 64'd0;
            itch_msg_start     <= 1'b0;
            itch_msg_last      <= 1'b0;
            cnt_mold_pkts      <= 32'd0;
            cnt_mold_msgs      <= 32'd0;
            cnt_heartbeats     <= 32'd0;
            cnt_end_of_session <= 32'd0;
            cnt_seq_gaps       <= 32'd0;
            cnt_duplicates     <= 32'd0;
            cnt_trunc_errors   <= 32'd0;
        end else begin
            itch_msg_valid <= 1'b0;
            itch_msg_start <= 1'b0;
            itch_msg_last  <= 1'b0;

            // Host override / recovery sequence reset
            if (cfg_seq_override) begin
                expected_seq     <= cfg_expected_seq;
                seq_initialized  <= 1'b1;
                seq_gap_detected <= 1'b0;
            end else if (cfg_seq_reset) begin
                seq_initialized  <= 1'b0;
                seq_gap_detected <= 1'b0;
            end

            case (state)
                MOLD_IDLE: begin
                    hdr_byte_cnt     <= 5'd0;
                    cur_msg_idx      <= 16'd0;
                    cur_msg_byte_cnt <= 16'd0;

                    if (udp_payload_valid && udp_payload_start) begin
                        state        <= MOLD_HEADER;
                        session_id   <= {session_id[71:0], udp_payload_byte};
                        hdr_byte_cnt <= 5'd1;
                    end
                end

                MOLD_HEADER: begin
                    if (udp_payload_valid) begin
                        hdr_byte_cnt <= hdr_byte_cnt + 5'd1;

                        // Bytes 0..9: Session ID (10 bytes)
                        if (hdr_byte_cnt < 5'd10) begin
                            session_id <= {session_id[71:0], udp_payload_byte};
                        end
                        // Bytes 10..17: Sequence Number (64-bit big-endian)
                        else if (hdr_byte_cnt < 5'd18) begin
                            pkt_seq <= {pkt_seq[55:0], udp_payload_byte};
                        end
                        // Bytes 18..19: Message Count (16-bit big-endian)
                        else if (hdr_byte_cnt == 5'd18) begin
                            msg_count[15:8] <= udp_payload_byte;
                        end else if (hdr_byte_cnt == 5'd19) begin
                            msg_count[7:0] <= udp_payload_byte;
                            cnt_mold_pkts  <= cnt_mold_pkts + 32'd1;

                            // 1. Check for Heartbeat (Message Count == 0)
                            if ({msg_count[15:8], udp_payload_byte} == 16'h0000) begin
                                cnt_heartbeats <= cnt_heartbeats + 32'd1;
                                state <= MOLD_DRAIN;
                            end
                            // 2. Check for End of Session (Message Count == 0xFFFF)
                            else if ({msg_count[15:8], udp_payload_byte} == 16'hFFFF) begin
                                cnt_end_of_session <= cnt_end_of_session + 32'd1;
                                state <= MOLD_DRAIN;
                            end
                            // 3. Normal Data Packet: Check Sequence Number
                            else begin
                                if (!seq_initialized) begin
                                    // First packet after reset: lock onto stream sequence
                                    expected_seq     <= pkt_seq;
                                    seq_initialized  <= 1'b1;
                                    state            <= MOLD_MSG_LEN;
                                    cur_msg_idx      <= 16'd0;
                                    cur_msg_byte_cnt <= 16'd0;
                                end else if (pkt_seq == expected_seq) begin
                                    // In-sequence! Proceed to decode messages
                                    state            <= MOLD_MSG_LEN;
                                    cur_msg_idx      <= 16'd0;
                                    cur_msg_byte_cnt <= 16'd0;
                                end else if (pkt_seq > expected_seq) begin
                                    // SEQUENCE GAP!
                                    cnt_seq_gaps     <= cnt_seq_gaps + 32'd1;
                                    seq_gap_detected <= 1'b1;
                                    gap_expected_seq <= expected_seq;
                                    gap_received_seq <= pkt_seq;
                                    // The live feed cannot replay missed packets here.
                                    // Record the gap and resume at this packet.
                                    expected_seq     <= pkt_seq;
                                    state            <= MOLD_MSG_LEN;
                                    cur_msg_idx      <= 16'd0;
                                    cur_msg_byte_cnt <= 16'd0;
                                end else begin
                                    // Duplicate / stale packet (pkt_seq < expected_seq)
                                    cnt_duplicates <= cnt_duplicates + 32'd1;
                                    state          <= MOLD_DRAIN;
                                end
                            end
                        end
                    end
                end

                MOLD_MSG_LEN: begin
                    if (udp_payload_valid) begin
                        if (cur_msg_byte_cnt == 16'd0) begin
                            cur_msg_len[15:8] <= udp_payload_byte;
                            cur_msg_byte_cnt  <= 16'd1;
                        end else begin
                            cur_msg_len[7:0] <= udp_payload_byte;
                            cur_msg_byte_cnt <= 16'd0;
                            itch_msg_seq     <= expected_seq;
                            itch_msg_len     <= {cur_msg_len[15:8], udp_payload_byte};
                            state            <= MOLD_STREAM_MSG;
                        end
                    end
                end

                MOLD_STREAM_MSG: begin
                    if (udp_payload_valid) begin
                        cur_msg_byte_cnt <= cur_msg_byte_cnt + 16'd1;

                        itch_msg_valid <= 1'b1;
                        itch_msg_byte  <= udp_payload_byte;
                        if (cur_msg_byte_cnt == 16'd0) begin
                            itch_msg_start <= 1'b1;
                        end

                        if ((cur_msg_byte_cnt + 16'd1) == itch_msg_len) begin
                            itch_msg_last <= 1'b1;
                            cnt_mold_msgs <= cnt_mold_msgs + 32'd1;
                            expected_seq  <= expected_seq + 64'd1; // advance transport sequence per message!

                            if ((cur_msg_idx + 16'd1) == msg_count) begin
                                // All messages in packet processed
                                state <= MOLD_IDLE;
                            end else begin
                                cur_msg_idx      <= cur_msg_idx + 16'd1;
                                cur_msg_byte_cnt <= 16'd0;
                                state            <= MOLD_MSG_LEN;
                            end
                        end
                    end

                    if (udp_payload_last && (cur_msg_byte_cnt + 16'd1) < itch_msg_len) begin
                        // Packet truncated prematurely
                        cnt_trunc_errors <= cnt_trunc_errors + 32'd1;
                        state            <= MOLD_IDLE;
                    end
                end

                MOLD_DRAIN: begin
                    // Discard remaining bytes of ignored packet
                    if (udp_payload_last) begin
                        state <= MOLD_IDLE;
                    end
                end

                default: state <= MOLD_IDLE;
            endcase
        end
    end

endmodule
