// Hardware Ethernet II + IPv4 + UDP packet header parser
//              with IPv4 header checksum verification and destination port filter

`timescale 1ns / 1ps

module net_parser #(
    parameter [15:0] DEFAULT_UDP_PORT = 16'd10443 // Default TotalView-ITCH UDP port
) (
    input  wire        clk,             // System clock or network domain clock
    input  wire        rst_n,           // Active-low synchronous reset

    // Ingress interface from rmii_rx frame buffer
    input  wire        frame_valid,     // Complete validated Ethernet frame available
    input  wire [11:0] frame_len,       // Length in bytes (excluding FCS)
    output wire        frame_read_en,   // Read strobe to rmii_rx
    input  wire [ 7:0] frame_byte_in,   // Byte data from buffer
    input  wire        frame_byte_last, // Last byte of Ethernet frame

    // Configuration
    input  wire [15:0] cfg_udp_port,    // Configurable UDP destination port
    input  wire [47:0] cfg_dst_mac,     // Zero accepts any Ethernet destination
    input  wire [31:0] cfg_dst_ip,      // Zero accepts any IPv4 destination

    // Egress interface to MoldUDP64 decoder
    output reg         udp_payload_valid, // Asserted while UDP payload bytes are streaming
    output reg  [11:0] udp_payload_len,   // Total bytes in current UDP payload
    output reg  [ 7:0] udp_payload_byte,  // Payload byte data
    output reg         udp_payload_start, // 1-cycle pulse on first byte of UDP payload
    output reg         udp_payload_last,  // Asserted on final byte of UDP payload
    input  wire        udp_payload_ready, // Downstream ready handshake

    // Diagnostic & Telemetry Counters
    output reg  [31:0] cnt_ipv4_frames,
    output reg  [31:0] cnt_udp_packets,
    output reg  [31:0] cnt_non_ipv4_drop,
    output reg  [31:0] cnt_ip_csum_err,
    output reg  [31:0] cnt_ip_frag_drop,
    output reg  [31:0] cnt_non_udp_drop,
    output reg  [31:0] cnt_port_mismatch_drop,
    output reg  [31:0] cnt_udp_len_err,
    output reg  [31:0] cnt_udp_csum_err
);

    localparam [3:0]
        ST_IDLE          = 4'd0,
        ST_ETH_HEADER    = 4'd1,
        ST_IPV4_HEADER   = 4'd2,
        ST_UDP_HEADER    = 4'd3,
        ST_STREAM_UDP    = 4'd4,
        ST_DRAIN_DROP    = 4'd5,
        ST_DRAIN_PAD     = 4'd6,
        ST_REPLAY_UDP    = 4'd7;

    reg [3:0] state;

    reg [11:0] byte_idx;
    reg [15:0] ethertype;
    reg [47:0] dst_mac;
    reg [31:0] dst_ip;
    reg [ 3:0] ip_version;
    reg [ 3:0] ip_ihl;
    reg [15:0] ip_total_len;
    reg [15:0] ip_flags_frag;
    reg [ 7:0] ip_proto;
    reg [15:0] ip_checksum;
    reg [15:0] udp_src_port;
    reg [15:0] udp_dst_port;
    reg [15:0] udp_len;
    reg [11:0] udp_bytes_streamed;
    reg [11:0] replay_idx;
    reg replay_allowed;
    (* ram_style = "block" *) reg [7:0] payload_mem [0:1471];
    wire [11:0] payload_read_idx = udp_payload_valid ? replay_idx + 12'd1 : 12'd0;
    reg [31:0] pseudo_acc, udp_sum;
    reg [7:0] udp_hi_byte, udp_checksum_hi;
    reg [15:0] udp_checksum;

    // 16-bit One's Complement Checksum Accumulator for IPv4 Header
    reg [31:0] csum_acc;
    reg [ 7:0] csum_hi_byte;

    wire [15:0] active_target_port = (cfg_udp_port != 16'd0) ? cfg_udp_port : DEFAULT_UDP_PORT;
    wire [31:0] final_udp_sum = udp_bytes_streamed[0] ?
        udp_sum + {udp_hi_byte, frame_byte_in} :
        udp_sum + {frame_byte_in, 8'd0};

    // Fold 32-bit checksum accumulator to 16-bit
    function [15:0] fold_checksum;
        input [31:0] acc;
        reg   [31:0] sum;
        begin
            sum = (acc[31:16] + acc[15:0]);
            sum = sum + sum[31:16];
            fold_checksum = ~sum[15:0];
        end
    endfunction

    // Combinational read enable to rmii_rx frame buffer
    assign frame_read_en = (state == ST_ETH_HEADER) ||
                           (state == ST_IPV4_HEADER) ||
                           (state == ST_UDP_HEADER) ||
                           (state == ST_STREAM_UDP) ||
                           (state == ST_DRAIN_DROP) ||
                           (state == ST_DRAIN_PAD);

    // Keep RAM writes in a clock-only process; reset gating in the main FSM
    // otherwise makes Vivado implement the 1472-byte payload buffer as flops.
    always @(posedge clk) begin
        if (rst_n && state == ST_STREAM_UDP)
            payload_mem[udp_bytes_streamed] <= frame_byte_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                  <= ST_IDLE;
            byte_idx               <= 12'd0;
            ethertype              <= 16'd0;
            dst_mac                <= 48'd0;
            dst_ip                 <= 32'd0;
            ip_version             <= 4'd0;
            ip_ihl                 <= 4'd0;
            ip_total_len           <= 16'd0;
            ip_flags_frag          <= 16'd0;
            ip_proto               <= 8'd0;
            ip_checksum            <= 16'd0;
            udp_src_port           <= 16'd0;
            udp_dst_port           <= 16'd0;
            udp_len                <= 16'd0;
            udp_bytes_streamed     <= 12'd0;
            replay_idx             <= 12'd0;
            replay_allowed         <= 1'b0;
            pseudo_acc             <= 32'd0;
            udp_sum                <= 32'd0;
            udp_hi_byte            <= 8'd0;
            udp_checksum_hi        <= 8'd0;
            udp_checksum           <= 16'd0;
            csum_acc               <= 32'd0;
            csum_hi_byte           <= 8'd0;
            udp_payload_valid      <= 1'b0;
            udp_payload_len        <= 12'd0;
            udp_payload_byte       <= 8'd0;
            udp_payload_start      <= 1'b0;
            udp_payload_last       <= 1'b0;
            cnt_ipv4_frames        <= 32'd0;
            cnt_udp_packets        <= 32'd0;
            cnt_non_ipv4_drop      <= 32'd0;
            cnt_ip_csum_err        <= 32'd0;
            cnt_ip_frag_drop       <= 32'd0;
            cnt_non_udp_drop       <= 32'd0;
            cnt_port_mismatch_drop <= 32'd0;
            cnt_udp_len_err        <= 32'd0;
            cnt_udp_csum_err       <= 32'd0;
        end else begin
            if (state != ST_REPLAY_UDP) begin
                udp_payload_start <= 1'b0;
                udp_payload_valid <= 1'b0;
                udp_payload_last  <= 1'b0;
            end

            case (state)
                ST_IDLE: begin
                    byte_idx           <= 12'd0;
                    csum_acc           <= 32'd0;
                    udp_bytes_streamed <= 12'd0;

                    pseudo_acc <= 32'd0;
                    if (frame_valid) begin
                        state <= ST_ETH_HEADER;
                    end
                end

                ST_ETH_HEADER: begin
                    byte_idx <= byte_idx + 12'd1;

                    // Ethernet Header (14 bytes): DMAC[0..5], SMAC[6..11], EtherType[12..13]
                    if (byte_idx < 12'd6) dst_mac <= {dst_mac[39:0], frame_byte_in};
                    if (byte_idx == 12'd12) ethertype[15:8] <= frame_byte_in;
                    if (byte_idx == 12'd13) begin
                        ethertype[7:0] <= frame_byte_in;
                        if ({ethertype[15:8], frame_byte_in} == 16'h0800 &&
                            (cfg_dst_mac == 48'd0 || dst_mac == cfg_dst_mac)) begin
                            // Valid IPv4!
                            cnt_ipv4_frames <= cnt_ipv4_frames + 32'd1;
                            csum_acc        <= 32'd0;
                            state           <= ST_IPV4_HEADER;
                        end else begin
                            cnt_non_ipv4_drop <= cnt_non_ipv4_drop + 32'd1;
                            state             <= ST_DRAIN_DROP;
                        end
                    end
                end

                ST_IPV4_HEADER: begin
                    byte_idx <= byte_idx + 12'd1;

                    // Accumulate 16-bit words for IPv4 header checksum
                    if ((byte_idx - 12'd14) % 2 == 0) begin
                        csum_hi_byte <= frame_byte_in;
                    end else begin
                        csum_acc <= csum_acc + {csum_hi_byte, frame_byte_in};
                        if (byte_idx == 12'd27 || byte_idx == 12'd29 ||
                            byte_idx == 12'd31 || byte_idx == 12'd33)
                            pseudo_acc <= pseudo_acc + {csum_hi_byte, frame_byte_in};
                    end

                    case (byte_idx)
                        12'd14: begin
                            ip_version <= frame_byte_in[7:4];
                            ip_ihl     <= frame_byte_in[3:0];
                        end
                        12'd16: ip_total_len[15:8] <= frame_byte_in;
                        12'd17: ip_total_len[7:0]  <= frame_byte_in;
                        12'd20: ip_flags_frag[15:8] <= frame_byte_in;
                        12'd21: ip_flags_frag[7:0]  <= frame_byte_in;
                        12'd23: ip_proto           <= frame_byte_in;
                        12'd24: ip_checksum[15:8]  <= frame_byte_in;
                        12'd25: ip_checksum[7:0]   <= frame_byte_in;
                        12'd30: dst_ip[31:24] <= frame_byte_in;
                        12'd31: dst_ip[23:16] <= frame_byte_in;
                        12'd32: dst_ip[15:8]  <= frame_byte_in;

                        12'd33: begin
                            udp_sum <= pseudo_acc + {csum_hi_byte, frame_byte_in} + 32'd17;
                            // End of standard 20-byte IPv4 header (byte 14..33)
                            // 1. Verify Version == 4 and IHL == 5
                            if ((cfg_dst_ip != 32'd0 &&
                                 {dst_ip[31:8], frame_byte_in} != cfg_dst_ip) ||
                                ip_version != 4'd4 || ip_ihl != 4'd5) begin
                                cnt_non_ipv4_drop <= cnt_non_ipv4_drop + 32'd1;
                                state <= ST_DRAIN_DROP;
                            end
                            // 2. Reject fragments (More Fragments == 1 or Fragment Offset != 0)
                            else if ((ip_flags_frag & 16'h3FFF) != 16'h0000) begin
                                cnt_ip_frag_drop <= cnt_ip_frag_drop + 32'd1;
                                state <= ST_DRAIN_DROP;
                            end
                            // 3. Verify Protocol == UDP (17)
                            else if (ip_proto != 8'd17) begin
                                cnt_non_udp_drop <= cnt_non_udp_drop + 32'd1;
                                state <= ST_DRAIN_DROP;
                            end
                            // 4. Verify Checksum (sum + checksum word must fold to 16'h0000)
                            else if (ip_total_len < 16'd28 ||
                                     ip_total_len > {4'd0, frame_len} - 16'd14) begin
                                cnt_non_ipv4_drop <= cnt_non_ipv4_drop + 32'd1;
                                state <= ST_DRAIN_DROP;
                            end else if (fold_checksum(csum_acc + {csum_hi_byte, frame_byte_in}) != 16'h0000) begin
                                cnt_ip_csum_err <= cnt_ip_csum_err + 32'd1;
                                state <= ST_DRAIN_DROP;
                            end
                            else begin
                                state <= ST_UDP_HEADER;
                            end
                        end

                        default: ;
                    endcase
                end

                ST_UDP_HEADER: begin
                    byte_idx <= byte_idx + 12'd1;
                    if (byte_idx[0] == 1'b0)
                        udp_hi_byte <= frame_byte_in;
                    else
                        udp_sum <= udp_sum + {udp_hi_byte, frame_byte_in} +
                                   (byte_idx == 12'd39 ? {udp_hi_byte, frame_byte_in} : 16'd0);

                    case (byte_idx)
                        12'd34: udp_src_port[15:8] <= frame_byte_in;
                        12'd35: udp_src_port[7:0]  <= frame_byte_in;
                        12'd36: udp_dst_port[15:8] <= frame_byte_in;
                        12'd37: udp_dst_port[7:0]  <= frame_byte_in;
                        12'd38: udp_len[15:8]      <= frame_byte_in;
                        12'd39: udp_len[7:0]       <= frame_byte_in;
                        12'd40: udp_checksum_hi     <= frame_byte_in;
                        12'd41: begin
                            udp_checksum <= {udp_checksum_hi, frame_byte_in};
                            // Finished 8-byte UDP header (bytes 34..41)
                            if (udp_dst_port != active_target_port) begin
                                cnt_port_mismatch_drop <= cnt_port_mismatch_drop + 32'd1;
                                state <= ST_DRAIN_DROP;
                            end else if (udp_len < 16'd9 ||
                                         udp_len != ip_total_len - 16'd20 ||
                                         udp_len > {4'd0, frame_len} - 16'd34 ||
                                         udp_len > 16'd1480) begin
                                cnt_udp_len_err <= cnt_udp_len_err + 32'd1;
                                state <= ST_DRAIN_DROP;
                            end else begin
                                udp_payload_len    <= udp_len[11:0] - 12'd8; // Subtract 8-byte UDP header
                                udp_bytes_streamed <= 12'd0;
                                state              <= ST_STREAM_UDP;
                            end
                        end

                        default: ;
                    endcase
                end

                ST_STREAM_UDP: begin
                    byte_idx <= byte_idx + 12'd1;
                    udp_bytes_streamed <= udp_bytes_streamed + 12'd1;
                    if (udp_bytes_streamed[0])
                        udp_sum <= udp_sum + {udp_hi_byte, frame_byte_in};
                    else
                        udp_hi_byte <= frame_byte_in;

                    if (udp_bytes_streamed + 12'd1 == udp_payload_len) begin
                        replay_allowed <= udp_checksum == 16'd0 ||
                                          fold_checksum(final_udp_sum) == 16'd0;
                        if (udp_checksum == 16'd0 || fold_checksum(final_udp_sum) == 16'd0)
                            cnt_udp_packets <= cnt_udp_packets + 32'd1;
                        if (udp_checksum != 16'd0 && fold_checksum(final_udp_sum) != 16'd0)
                            cnt_udp_csum_err <= cnt_udp_csum_err + 32'd1;
                        state <= frame_byte_last ?
                            ((udp_checksum == 16'd0 || fold_checksum(final_udp_sum) == 16'd0) ?
                             ST_REPLAY_UDP : ST_IDLE) : ST_DRAIN_PAD;
                    end else if (frame_byte_last) begin
                        cnt_udp_len_err <= cnt_udp_len_err + 32'd1;
                        state <= ST_IDLE;
                    end
                end

                ST_DRAIN_PAD: if (frame_byte_last)
                    state <= replay_allowed ? ST_REPLAY_UDP : ST_IDLE;

                ST_REPLAY_UDP: begin
                    if (!udp_payload_valid) begin
                        replay_idx <= 12'd0;
                        udp_payload_start <= 1'b1;
                        udp_payload_last <= udp_payload_len == 12'd1;
                        udp_payload_valid <= 1'b1;
                    end else if (udp_payload_ready) begin
                        if (udp_payload_last) begin
                            udp_payload_valid <= 1'b0;
                            udp_payload_start <= 1'b0;
                            udp_payload_last <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            replay_idx <= replay_idx + 12'd1;
                            udp_payload_start <= 1'b0;
                            udp_payload_last <= replay_idx + 12'd2 == udp_payload_len;
                        end
                    end
                    // One synchronous read site allows a single RAM read port.
                    if (!udp_payload_valid || (udp_payload_ready && !udp_payload_last))
                        udp_payload_byte <= payload_mem[payload_read_idx];
                end

                ST_DRAIN_DROP: begin
                    // Consume remaining bytes of rejected frame
                    if (frame_byte_last) begin
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
