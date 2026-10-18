// =============================================================================
// File: rmii_rx.v
// Description: RMII 100Mbps Ethernet Receiver with CRC-32 (FCS) verification
//              and BRAM Store-and-Forward Frame Buffer
// Target: AMD/Xilinx Artix-7 (Digilent Nexys A7-100T, LAN8720A PHY)
// =============================================================================

`timescale 1ns / 1ps

module rmii_rx #(
    parameter BUFFER_DEPTH = 2048,  // Stores up to max Ethernet frame (1518 bytes)
    parameter [31:0] CRC32_POLY = 32'hEDB88320 // Reversed polynomial for IEEE 802.3
) (
    input  wire        clk_50,          // 50 MHz RMII Reference Clock
    input  wire        rst_n,           // Active-low synchronous reset

    // RMII Physical Interface (from PHY)
    input  wire        rmii_crs_dv,     // Carrier Sense / Data Valid
    input  wire        rmii_rx_err,     // RX Error
    input  wire [ 1:0] rmii_rxd,        // Dibit Receive Data

    // Validated Frame Egress Interface (to downstream network parser)
    output reg         frame_valid,     // Asserted when a complete, valid frame is ready
    output reg  [11:0] frame_len,       // Frame payload length in bytes (excluding FCS)
    input  wire        frame_read_en,   // Downstream read acknowledge
    output wire [ 7:0] frame_byte_out,  // Read data byte
    output wire        frame_byte_last, // Last byte indicator for current frame
    output reg         frame_done_ack,  // Pulses when downstream completes consumption

    // Diagnostic & Telemetry Counters
    output reg  [31:0] cnt_rx_frames,   // Total valid frames committed
    output reg  [31:0] cnt_crc_err,     // CRC32 mismatch drops
    output reg  [31:0] cnt_len_err,     // Runt (<64B) or Giant (>1518B) drops
    output reg  [31:0] cnt_phy_err,     // PHY rx_err drops
    output reg  [31:0] cnt_overflow_err // Buffer overflow drops
);

    // -------------------------------------------------------------------------
    // 1. Dibit-to-Byte Assembler & Preamble / SFD Detection
    // -------------------------------------------------------------------------
    localparam [2:0]
        RX_IDLE       = 3'd0,
        RX_PREAMBLE   = 3'd1,
        RX_SFD        = 3'd2,
        RX_DATA       = 3'd3,
        RX_CHECK_FCS  = 3'd4,
        RX_DISCARD    = 3'd5;

    reg [2:0] state;

    reg [1:0] dibit_cnt;      // Counts 0..3 dibits per byte
    reg [7:0] shift_byte;     // Shift register for dibit assembly
    reg       byte_valid;     // Pulses 1 cycle every 4 dibits during DATA
    reg [7:0] assembled_byte; // Assembled 8-bit byte

    // Synchronize and filter crs_dv
    reg [1:0] crs_dv_sync;
    reg [1:0] rx_err_sync;
    reg [1:0] rxd_sync [0:1];

    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            crs_dv_sync   <= 2'b0;
            rx_err_sync   <= 2'b0;
            rxd_sync[0]   <= 2'b0;
            rxd_sync[1]   <= 2'b0;
        end else begin
            crs_dv_sync   <= {crs_dv_sync[0], rmii_crs_dv};
            rx_err_sync   <= {rx_err_sync[0], rmii_rx_err};
            rxd_sync[0]   <= rmii_rxd;
            rxd_sync[1]   <= rxd_sync[0];
        end
    end

    wire cur_crs_dv = crs_dv_sync[1];
    wire cur_rx_err = rx_err_sync[1];
    wire [1:0] cur_rxd = rxd_sync[1];

    // -------------------------------------------------------------------------
    // 2. IEEE 802.3 CRC-32 Calculation (Bit-serial / Dibit or Byte-wide)
    // -------------------------------------------------------------------------
    reg [31:0] crc32_reg;

    function [31:0] calc_crc32_byte;
        input [31:0] current_crc;
        input [7:0]  byte_in;
        reg   [31:0] crc;
        integer i;
        begin
            crc = current_crc;
            for (i = 0; i < 8; i = i + 1) begin
                if ((crc[0] ^ byte_in[i]) == 1'b1)
                    crc = (crc >> 1) ^ 32'hEDB88320;
                else
                    crc = (crc >> 1);
            end
            calc_crc32_byte = crc;
        end
    endfunction

    // -------------------------------------------------------------------------
    // 3. Store-and-Forward Dual-Port BRAM Frame Buffer
    // -------------------------------------------------------------------------
    (* ram_style = "distributed" *)
    reg [7:0] frame_mem [0:BUFFER_DEPTH-1];
    reg [10:0] wr_ptr;
    reg [10:0] wr_start_ptr;
    reg [10:0] rd_ptr;
    reg [10:0] committed_frame_len;
    reg [10:0] active_bytes_received;

    reg        buffer_overflow;

    // Buffer read port (asynchronous read for 0-latency streaming)
    assign frame_byte_out = frame_mem[rd_ptr];
    assign frame_byte_last = (rd_ptr == (wr_start_ptr + frame_len - 1'b1));

    // -------------------------------------------------------------------------
    // 4. Receiver FSM & Packet Parsing
    // -------------------------------------------------------------------------
    reg had_phy_error;

    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n) begin
            state                 <= RX_IDLE;
            dibit_cnt             <= 2'd0;
            shift_byte            <= 8'd0;
            byte_valid            <= 1'b0;
            assembled_byte        <= 8'd0;
            crc32_reg             <= 32'hFFFF_FFFF;
            wr_ptr                <= 11'd0;
            wr_start_ptr          <= 11'd0;
            active_bytes_received <= 11'd0;
            committed_frame_len   <= 11'd0;
            buffer_overflow       <= 1'b0;
            had_phy_error         <= 1'b0;
            frame_valid           <= 1'b0;
            frame_len             <= 12'd0;
            frame_done_ack        <= 1'b0;
            cnt_rx_frames         <= 32'd0;
            cnt_crc_err           <= 32'd0;
            cnt_len_err           <= 32'd0;
            cnt_phy_err           <= 32'd0;
            cnt_overflow_err      <= 32'd0;
        end else begin
            byte_valid     <= 1'b0;
            frame_done_ack <= 1'b0;

            // Frame reading progress from downstream parser
            if (frame_valid && frame_read_en) begin
                if (frame_byte_last) begin
                    frame_valid    <= 1'b0;
                    frame_done_ack <= 1'b1;
                    wr_start_ptr   <= wr_ptr; // advance start pointer for next frame
                end else begin
                    rd_ptr <= rd_ptr + 11'd1;
                end
            end

            case (state)
                RX_IDLE: begin
                    dibit_cnt             <= 2'd0;
                    shift_byte            <= 8'd0;
                    active_bytes_received <= 11'd0;
                    buffer_overflow       <= 1'b0;
                    had_phy_error         <= 1'b0;
                    crc32_reg             <= 32'hFFFF_FFFF;

                    if (cur_crs_dv) begin
                        if (cur_rxd == 2'b01) begin
                            // Preamble pattern (01_01_01_01 = 0x55)
                            state <= RX_PREAMBLE;
                        end
                    end
                end

                RX_PREAMBLE: begin
                    if (!cur_crs_dv) begin
                        state <= RX_IDLE;
                    end else if (cur_rx_err) begin
                        had_phy_error <= 1'b1;
                        state <= RX_DISCARD;
                    end else if (cur_rxd == 2'b11) begin
                        // SFD ending nibble/dibit (0xD5: 1101_0101 -> final dibit is 2'b11)
                        dibit_cnt  <= 2'd0;
                        shift_byte <= 8'd0;
                        crc32_reg  <= 32'hFFFF_FFFF;
                        wr_ptr     <= wr_start_ptr;
                        state      <= RX_DATA;
                    end else if (cur_rxd != 2'b01) begin
                        // Malformed preamble
                        state <= RX_DISCARD;
                    end
                end

                RX_DATA: begin
                    if (cur_rx_err) begin
                        had_phy_error <= 1'b1;
                    end

                    // Shift in dibit (LSB first: rxd[1:0] becomes bits 1:0, 3:2, 5:4, 7:6)
                    case (dibit_cnt)
                        2'd0: shift_byte[1:0] <= cur_rxd;
                        2'd1: shift_byte[3:2] <= cur_rxd;
                        2'd2: shift_byte[5:4] <= cur_rxd;
                        2'd3: shift_byte[7:6] <= cur_rxd;
                    endcase

                    if (dibit_cnt == 2'd3) begin
                        dibit_cnt      <= 2'd0;
                        byte_valid     <= 1'b1;
                        assembled_byte <= {cur_rxd, shift_byte[5:0]};

                        // Update CRC-32 with the newly completed byte
                        crc32_reg <= calc_crc32_byte(crc32_reg, {cur_rxd, shift_byte[5:0]});

                        // Write to BRAM frame buffer
                        if (!frame_valid && ((wr_ptr - wr_start_ptr) < BUFFER_DEPTH)) begin
                            frame_mem[wr_ptr] <= {cur_rxd, shift_byte[5:0]};
                            wr_ptr            <= wr_ptr + 11'd1;
                        end else begin
                            buffer_overflow <= 1'b1;
                        end

                        active_bytes_received <= active_bytes_received + 11'd1;
                    end else begin
                        dibit_cnt <= dibit_cnt + 2'd1;
                    end

                    // End of frame detected on falling edge of crs_dv
                    if (!cur_crs_dv) begin
                        state <= RX_CHECK_FCS;
                    end
                end

                RX_CHECK_FCS: begin
                    // Entire frame received. Perform validation checks:
                    // 1. Check for PHY error
                    if (had_phy_error) begin
                        cnt_phy_err  <= cnt_phy_err + 32'd1;
                        wr_ptr       <= wr_start_ptr; // rollback
                        state        <= RX_IDLE;
                    end
                    // 2. Check for buffer overflow
                    else if (buffer_overflow) begin
                        cnt_overflow_err <= cnt_overflow_err + 32'd1;
                        wr_ptr           <= wr_start_ptr;
                        state            <= RX_IDLE;
                    end
                    // 3. Minimum length (64 bytes including 4-byte FCS) and Maximum (1518 bytes)
                    else if (active_bytes_received < 11'd64 || active_bytes_received > 11'd1518) begin
                        cnt_len_err <= cnt_len_err + 32'd1;
                        wr_ptr      <= wr_start_ptr;
                        state       <= RX_IDLE;
                    end
                    // 4. IEEE 802.3 CRC32 verification (magic residue: 32'hDEBB20E3)
                    else if (crc32_reg != 32'hDEBB20E3) begin
                        cnt_crc_err <= cnt_crc_err + 32'd1;
                        wr_ptr      <= wr_start_ptr;
                        state       <= RX_IDLE;
                    end
                    // 5. Valid Frame! Commit to downstream parser
                    else begin
                        cnt_rx_frames       <= cnt_rx_frames + 32'd1;
                        committed_frame_len <= active_bytes_received - 11'd4; // subtract 4-byte FCS
                        frame_len           <= active_bytes_received - 11'd4;
                        frame_valid         <= 1'b1;
                        rd_ptr              <= wr_start_ptr;
                        state               <= RX_IDLE;
                    end
                end

                RX_DISCARD: begin
                    if (!cur_crs_dv) begin
                        wr_ptr <= wr_start_ptr; // rollback
                        state  <= RX_IDLE;
                    end
                end

                default: state <= RX_IDLE;
            endcase
        end
    end

endmodule
