// =============================================================================
// File: uart_telemetry.v
// Description: 115200 Baud UART Transmitter & Hardware Telemetry Engine
//              Supports MMIO CPU transmit and optional automated hardware BBO streaming.
// Target: AMD/Xilinx Artix-7 (Digilent Nexys A7-100T)
// =============================================================================

`timescale 1ns / 1ps

module uart_telemetry #(
    parameter CLK_FREQ           = 100000000,
    parameter BAUD_RATE          = 115200,
    parameter DEFAULT_AUTO_TELEM = 1'b1
) (
    input  wire        clk,              // Core clock (50 MHz in top_system)
    input  wire        rst_n,            // Active-low synchronous reset

    // MMIO Bus Slave Interface (decoded at 0x6000_0000)
    input  wire        bus_req_valid,
    input  wire        bus_req_write,
    input  wire [31:0] bus_req_addr,
    input  wire [31:0] bus_req_wdata,
    output reg         bus_rsp_valid,
    output reg  [31:0] bus_rsp_rdata,

    // Hardware Telemetry Inputs (from LOB Accelerator)
    input  wire        hw_telem_trigger, // Pulses on BBO change
    input  wire [31:0] best_bid_price,
    input  wire [31:0] best_bid_qty,
    input  wire [31:0] best_ask_price,
    input  wire [31:0] best_ask_qty,
    input  wire [11:0] active_orders,
    input  wire        book_valid,
    input  wire [7:0]  error_code,
    input  wire [31:0] crc_errors,
    input  wire [31:0] udp_checksum_errors,
    input  wire [31:0] ip_checksum_errors,
    // Cumulative, board-observed boundaries for the narrated order journey.
    input  wire [31:0] pipe_rx_frames,
    input  wire [31:0] pipe_udp_packets,
    input  wire [31:0] pipe_mold_msgs,
    input  wire [31:0] pipe_itch_events,
    input  wire [31:0] pipe_fifo_events,
    input  wire [31:0] pipe_done_events,
    input  wire [315:0] storage_trace,
    input  wire [31:0] price_base,
    input  wire [31:0] price_tick,
    input  wire        readback_valid,
    input  wire [7:0]  readback_byte,
    output wire        readback_ready,

    // Physical Serial Pin (Nexys A7 pin D4)
    output reg         uart_txd
);

    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE; // ~868 cycles

    // -------------------------------------------------------------------------
    // 1. Transmit Byte FIFO (64 entries)
    // -------------------------------------------------------------------------
    reg [7:0] fifo_mem [0:63];
    reg [5:0] fifo_wptr;
    reg [5:0] fifo_rptr;
    reg [6:0] fifo_count;

    wire fifo_empty = (fifo_count == 7'd0);
    wire fifo_full  = (fifo_count >= 7'd64);

    reg        fifo_wr_en;
    reg  [7:0] fifo_wr_data;
    wire       fifo_rd_en;
    wire [7:0] fifo_rd_data = fifo_mem[fifo_rptr];

    // -------------------------------------------------------------------------
    // 2. Hardware UART Baud & Bit Transmitter FSM
    // -------------------------------------------------------------------------
    localparam [1:0]
        TX_IDLE  = 2'd0,
        TX_START = 2'd1,
        TX_DATA  = 2'd2,
        TX_STOP  = 2'd3;

    reg [1:0] tx_state;
    reg [15:0] baud_cnt;
    reg [ 2:0] bit_idx;
    reg [ 7:0] tx_shift;

    assign fifo_rd_en = (tx_state == TX_IDLE) && !fifo_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state  <= TX_IDLE;
            uart_txd  <= 1'b1; // Mark state
            baud_cnt  <= 16'd0;
            bit_idx   <= 3'd0;
            tx_shift  <= 8'd0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    uart_txd <= 1'b1;
                    if (!fifo_empty) begin
                        tx_shift <= fifo_rd_data;
                        baud_cnt <= 16'd0;
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    uart_txd <= 1'b0; // Start bit
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 16'd0;
                        bit_idx  <= 3'd0;
                        tx_state <= TX_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end

                TX_DATA: begin
                    uart_txd <= tx_shift[bit_idx];
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            tx_state <= TX_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end

                TX_STOP: begin
                    uart_txd <= 1'b1; // Stop bit
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 16'd0;
                        tx_state <= TX_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 16'd1;
                    end
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 3. Hardware Automated BBO String Formatter FSM
    // -------------------------------------------------------------------------
    reg auto_telem_en;
    reg [8:0] telem_step;
    reg       telem_busy;
    reg [31:0] lat_bid_p, lat_bid_q, lat_ask_p, lat_ask_q;
    reg lat_book_valid;
    reg [7:0] lat_error_code;
    reg [11:0] lat_active_orders;
    reg [31:0] lat_crc_errors, lat_udp_checksum_errors, lat_ip_checksum_errors;
    reg [31:0] lat_rx, lat_udp, lat_mold, lat_itch, lat_fifo, lat_done;
    reg [315:0] lat_trace;
    reg [31:0] lat_price_base, lat_price_tick;

    function [7:0] hex2ascii;
        input [3:0] nibble;
        begin
            hex2ascii = (nibble < 4'd10) ? (8'h30 + {4'd0, nibble}) : (8'h41 + {4'd0, nibble - 4'd10});
        end
    endfunction

    function [7:0] hex_digit;
        input [31:0] value;
        input [2:0] index;
        begin
            hex_digit = hex2ascii(value[31 - (index * 4) -: 4]);
        end
    endfunction

    reg [7:0] hw_char;
    reg       hw_wr_en;
    reg       readback_line_active;
    assign readback_ready = !fifo_full && (!telem_busy || readback_line_active);

    always @(*) begin
        hw_char  = 8'h20;
        hw_wr_en = 1'b0;
        if (telem_busy && !fifo_full) begin
            hw_wr_en = 1'b1;
            case (telem_step)
                9'd0:  hw_char = "[";
                9'd1:  hw_char = "B";
                9'd2:  hw_char = "B";
                9'd3:  hw_char = "O";
                9'd4:  hw_char = "]";
                9'd5:  hw_char = " ";
                9'd6:  hw_char = "B";
                9'd7:  hw_char = ":";
                9'd8:  hw_char = hex2ascii(lat_bid_p[31:28]);
                9'd9:  hw_char = hex2ascii(lat_bid_p[27:24]);
                9'd10: hw_char = hex2ascii(lat_bid_p[23:20]);
                9'd11: hw_char = hex2ascii(lat_bid_p[19:16]);
                9'd12: hw_char = hex2ascii(lat_bid_p[15:12]);
                9'd13: hw_char = hex2ascii(lat_bid_p[11:8]);
                9'd14: hw_char = hex2ascii(lat_bid_p[7:4]);
                9'd15: hw_char = hex2ascii(lat_bid_p[3:0]);
                9'd16: hw_char = " ";
                9'd17: hw_char = "|";
                9'd18: hw_char = " ";
                9'd19: hw_char = "A";
                9'd20: hw_char = ":";
                9'd21: hw_char = hex2ascii(lat_ask_p[31:28]);
                9'd22: hw_char = hex2ascii(lat_ask_p[27:24]);
                9'd23: hw_char = hex2ascii(lat_ask_p[23:20]);
                9'd24: hw_char = hex2ascii(lat_ask_p[19:16]);
                9'd25: hw_char = hex2ascii(lat_ask_p[15:12]);
                9'd26: hw_char = hex2ascii(lat_ask_p[11:8]);
                9'd27: hw_char = hex2ascii(lat_ask_p[7:4]);
                9'd28: hw_char = hex2ascii(lat_ask_p[3:0]);
                9'd29: hw_char = " ";
                9'd30: hw_char = "|";
                9'd31: hw_char = " ";
                9'd32: hw_char = "V";
                9'd33: hw_char = ":";
                9'd34: hw_char = lat_book_valid ? "1" : "0";
                9'd35: hw_char = " ";
                9'd36: hw_char = "|";
                9'd37: hw_char = " ";
                9'd38: hw_char = "E";
                9'd39: hw_char = ":";
                9'd40: hw_char = hex2ascii(lat_error_code[7:4]);
                9'd41: hw_char = hex2ascii(lat_error_code[3:0]);
                9'd42: hw_char = " ";
                9'd43: hw_char = "|";
                9'd44: hw_char = " ";
                9'd45: hw_char = "Q";
                9'd46: hw_char = "B";
                9'd47: hw_char = ":";
                9'd56: hw_char = " ";
                9'd57: hw_char = "|";
                9'd58: hw_char = " ";
                9'd59: hw_char = "Q";
                9'd60: hw_char = "A";
                9'd61: hw_char = ":";
                9'd70: hw_char = " ";
                9'd71: hw_char = "|";
                9'd72: hw_char = " ";
                9'd73: hw_char = "N";
                9'd74: hw_char = ":";
                9'd78: hw_char = " ";
                9'd79: hw_char = "|";
                9'd80: hw_char = " ";
                9'd81: hw_char = "C";
                9'd82: hw_char = "R";
                9'd83: hw_char = "C";
                9'd84: hw_char = ":";
                9'd93: hw_char = " ";
                9'd94: hw_char = "|";
                9'd95: hw_char = " ";
                9'd96: hw_char = "U";
                9'd97: hw_char = "D";
                9'd98: hw_char = "P";
                9'd99: hw_char = ":";
                9'd108: hw_char = " ";
                9'd109: hw_char = "|";
                9'd110: hw_char = " ";
                9'd111: hw_char = "I";
                9'd112: hw_char = "P";
                9'd113: hw_char = ":";
                9'd125, 9'd138, 9'd151, 9'd164, 9'd177, 9'd190: hw_char = "|";
                9'd127: hw_char = "R";
                9'd128, 9'd141, 9'd154, 9'd167, 9'd180, 9'd193: hw_char = ":";
                9'd140: hw_char = "U";
                9'd153: hw_char = "M";
                9'd166: hw_char = "I";
                9'd179: hw_char = "F";
                9'd192: hw_char = "D";
                9'd202: hw_char = " ";
                9'd203: hw_char = "|";
                9'd204: hw_char = " ";
                9'd205: hw_char = "T";
                9'd206: hw_char = ":";
                9'd286: hw_char = " ";
                9'd287: hw_char = "|";
                9'd288: hw_char = " ";
                9'd289: hw_char = "B";
                9'd290: hw_char = "A";
                9'd291: hw_char = "S";
                9'd292: hw_char = "E";
                9'd293: hw_char = ":";
                9'd302: hw_char = " ";
                9'd303: hw_char = "|";
                9'd304: hw_char = " ";
                9'd305: hw_char = "T";
                9'd306: hw_char = "I";
                9'd307: hw_char = "C";
                9'd308: hw_char = "K";
                9'd309: hw_char = ":";
                9'd318: hw_char = 8'h0D;
                9'd319: hw_char = 8'h0A;
                default: hw_char = " ";
            endcase
            if (telem_step >= 7'd48 && telem_step <= 7'd55)
                hw_char = hex_digit(lat_bid_q, telem_step - 7'd48);
            else if (telem_step >= 7'd62 && telem_step <= 7'd69)
                hw_char = hex_digit(lat_ask_q, telem_step - 7'd62);
            else if (telem_step >= 7'd75 && telem_step <= 7'd77)
                hw_char = hex2ascii(lat_active_orders[11 - ((telem_step - 7'd75) * 4) -: 4]);
            else if (telem_step >= 7'd85 && telem_step <= 7'd92)
                hw_char = hex_digit(lat_crc_errors, telem_step - 7'd85);
            else if (telem_step >= 7'd100 && telem_step <= 7'd107)
                hw_char = hex_digit(lat_udp_checksum_errors, telem_step - 7'd100);
            else if (telem_step >= 7'd114 && telem_step <= 7'd121)
                hw_char = hex_digit(lat_ip_checksum_errors, telem_step - 7'd114);
            else if (telem_step >= 8'd129 && telem_step <= 8'd136)
                hw_char = hex_digit(lat_rx, telem_step - 8'd129);
            else if (telem_step >= 8'd142 && telem_step <= 8'd149)
                hw_char = hex_digit(lat_udp, telem_step - 8'd142);
            else if (telem_step >= 8'd155 && telem_step <= 8'd162)
                hw_char = hex_digit(lat_mold, telem_step - 8'd155);
            else if (telem_step >= 8'd168 && telem_step <= 8'd175)
                hw_char = hex_digit(lat_itch, telem_step - 8'd168);
            else if (telem_step >= 8'd181 && telem_step <= 8'd188)
                hw_char = hex_digit(lat_fifo, telem_step - 8'd181);
            else if (telem_step >= 8'd194 && telem_step <= 8'd201)
                hw_char = hex_digit(lat_done, telem_step - 8'd194);
            else if (telem_step >= 9'd207 && telem_step <= 9'd285)
                hw_char = hex2ascii(lat_trace[315 - ((telem_step - 9'd207) * 4) -: 4]);
            else if (telem_step >= 9'd294 && telem_step <= 9'd301)
                hw_char = hex_digit(lat_price_base, telem_step - 9'd294);
            else if (telem_step >= 9'd310 && telem_step <= 9'd317)
                hw_char = hex_digit(lat_price_tick, telem_step - 9'd310);
        end
    end

    reg        pending_update;
    reg [31:0] pend_bid_p, pend_bid_q, pend_ask_p, pend_ask_q;
    reg pend_book_valid;
    reg [7:0] pend_error_code;
    reg [11:0] pend_active_orders;
    reg [31:0] pend_crc_errors, pend_udp_checksum_errors, pend_ip_checksum_errors;
    reg [31:0] pend_rx, pend_udp, pend_mold, pend_itch, pend_fifo, pend_done;
    reg [315:0] pend_trace;
    reg [31:0] pend_price_base, pend_price_tick;
    reg prev_book_valid;
    reg [7:0] prev_error_code;

    reg [26:0] heartbeat_cnt;
    wire heartbeat_pulse = (heartbeat_cnt >= (CLK_FREQ - 1));
    // lob_core pulses event_done before lob_bbo's tracking and two price
    // pipeline stages have all committed. Wait six clocks before sampling a
    // new telemetry frame so active-order count, price, and quantity agree.
    reg [5:0] event_settle;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            event_settle <= 6'd0;
        else
            event_settle <= {event_settle[4:0], hw_telem_trigger};
    end
    wire settled_event = event_settle[5];
    wire bbo_settling = hw_telem_trigger || (|event_settle[4:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            heartbeat_cnt <= 27'd0;
        else if (heartbeat_pulse)
            heartbeat_cnt <= 27'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 27'd1;
    end

    wire status_changed = book_valid != prev_book_valid || error_code != prev_error_code;
    wire telem_trigger = (settled_event && !bbo_settling) ||
                         ((heartbeat_pulse || status_changed) && !bbo_settling);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_book_valid <= 1'b0;
            prev_error_code <= 8'd0;
        end else begin
            prev_book_valid <= book_valid;
            prev_error_code <= error_code;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            telem_busy     <= 1'b0;
            telem_step     <= 8'd0;
            lat_bid_p      <= 32'd0;
            lat_bid_q      <= 32'd0;
            lat_ask_p      <= 32'd0;
            lat_ask_q      <= 32'd0;
            lat_book_valid <= 1'b0;
            lat_error_code <= 8'd0;
            lat_active_orders <= 12'd0;
            lat_crc_errors <= 32'd0;
            lat_udp_checksum_errors <= 32'd0;
            lat_ip_checksum_errors <= 32'd0;
            lat_rx <= 0; lat_udp <= 0; lat_mold <= 0;
            lat_itch <= 0; lat_fifo <= 0; lat_done <= 0;
            lat_trace <= 316'd0;
            lat_price_base <= 32'd0; lat_price_tick <= 32'd0;
            pending_update <= 1'b0;
            pend_bid_p     <= 32'd0;
            pend_bid_q     <= 32'd0;
            pend_ask_p     <= 32'd0;
            pend_ask_q     <= 32'd0;
            pend_book_valid <= 1'b0;
            pend_error_code <= 8'd0;
            pend_active_orders <= 12'd0;
            pend_crc_errors <= 32'd0;
            pend_udp_checksum_errors <= 32'd0;
            pend_ip_checksum_errors <= 32'd0;
            pend_rx <= 0; pend_udp <= 0; pend_mold <= 0;
            pend_itch <= 0; pend_fifo <= 0; pend_done <= 0;
            pend_trace <= 316'd0;
            pend_price_base <= 32'd0; pend_price_tick <= 32'd0;
        end else begin
            if (!telem_busy && !readback_line_active && !readback_valid &&
                auto_telem_en && telem_trigger) begin
                lat_bid_p      <= best_bid_price;
                lat_bid_q      <= best_bid_qty;
                lat_ask_p      <= best_ask_price;
                lat_ask_q      <= best_ask_qty;
                lat_book_valid <= book_valid;
                lat_error_code <= error_code;
                lat_active_orders <= active_orders;
                lat_crc_errors <= crc_errors;
                lat_udp_checksum_errors <= udp_checksum_errors;
                lat_ip_checksum_errors <= ip_checksum_errors;
                lat_rx <= pipe_rx_frames; lat_udp <= pipe_udp_packets;
                lat_mold <= pipe_mold_msgs; lat_itch <= pipe_itch_events;
                lat_fifo <= pipe_fifo_events; lat_done <= pipe_done_events;
                lat_trace <= storage_trace;
                lat_price_base <= price_base;
                lat_price_tick <= price_tick;
                telem_step     <= 8'd0;
                telem_busy     <= 1'b1;
                pending_update <= 1'b0;
            end else if (telem_busy) begin
                if (auto_telem_en && ((settled_event && !bbo_settling) ||
                                      (status_changed && !bbo_settling))) begin
                    pending_update <= 1'b1;
                    pend_bid_p     <= best_bid_price;
                    pend_bid_q     <= best_bid_qty;
                    pend_ask_p     <= best_ask_price;
                    pend_ask_q     <= best_ask_qty;
                    pend_book_valid <= book_valid;
                    pend_error_code <= error_code;
                    pend_active_orders <= active_orders;
                    pend_crc_errors <= crc_errors;
                    pend_udp_checksum_errors <= udp_checksum_errors;
                    pend_ip_checksum_errors <= ip_checksum_errors;
                    pend_rx <= pipe_rx_frames; pend_udp <= pipe_udp_packets;
                    pend_mold <= pipe_mold_msgs; pend_itch <= pipe_itch_events;
                    pend_fifo <= pipe_fifo_events; pend_done <= pipe_done_events;
                    pend_trace <= storage_trace;
                    pend_price_base <= price_base;
                    pend_price_tick <= price_tick;
                end
                if (hw_wr_en) begin
                    if (telem_step == 9'd319) begin
                        if (pending_update) begin
                            lat_bid_p      <= pend_bid_p;
                            lat_bid_q      <= pend_bid_q;
                            lat_ask_p      <= pend_ask_p;
                            lat_ask_q      <= pend_ask_q;
                            lat_book_valid <= pend_book_valid;
                            lat_error_code <= pend_error_code;
                            lat_active_orders <= pend_active_orders;
                            lat_crc_errors <= pend_crc_errors;
                            lat_udp_checksum_errors <= pend_udp_checksum_errors;
                            lat_ip_checksum_errors <= pend_ip_checksum_errors;
                            lat_rx <= pend_rx; lat_udp <= pend_udp;
                            lat_mold <= pend_mold; lat_itch <= pend_itch;
                            lat_fifo <= pend_fifo; lat_done <= pend_done;
                            lat_trace <= pend_trace;
                            lat_price_base <= pend_price_base;
                            lat_price_tick <= pend_price_tick;
                            telem_step     <= 8'd0;
                            pending_update <= 1'b0;
                            telem_busy     <= 1'b1;
                        end else begin
                            telem_busy <= 1'b0;
                        end
                    end else begin
                        telem_step <= telem_step + 9'd1;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 4. MMIO Bus Transactions & Multiplexing
    // -------------------------------------------------------------------------
    // Register the CPU request before it reaches the FIFO controls. This
    // isolates the long CPU register-file/bus decode path from the FIFO CE.
    reg        req_pending;
    reg        req_write_d;
    reg [7:0]  req_addr_d;
    reg [31:0] req_wdata_d;
    wire mmio_wr_tx   = req_pending && req_write_d && (req_addr_d == 8'h00);
    wire mmio_wr_ctrl = req_pending && req_write_d && (req_addr_d == 8'h08);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wptr     <= 6'd0;
            fifo_rptr     <= 6'd0;
            fifo_count    <= 7'd0;
            auto_telem_en <= DEFAULT_AUTO_TELEM; // Enabled on reset by default
            req_pending   <= 1'b0;
            req_write_d   <= 1'b0;
            req_addr_d    <= 8'd0;
            req_wdata_d   <= 32'd0;
            readback_line_active <= 1'b0;
            bus_rsp_valid <= 1'b0;
            bus_rsp_rdata <= 32'd0;
        end else begin
            // Bus response handshake
            req_pending <= bus_req_valid;
            if (bus_req_valid) begin
                req_write_d <= bus_req_write;
                req_addr_d  <= bus_req_addr[7:0];
                req_wdata_d <= bus_req_wdata;
            end
            bus_rsp_valid <= req_pending;
            if (req_pending) begin
                case (req_addr_d)
                    8'h00: bus_rsp_rdata <= {24'd0, fifo_mem[fifo_rptr]};
                    8'h04: bus_rsp_rdata <= {29'd0, fifo_empty, fifo_full, (tx_state != TX_IDLE)};
                    8'h08: bus_rsp_rdata <= {31'd0, auto_telem_en};
                    default: bus_rsp_rdata <= 32'd0;
                endcase
            end

            // Control register write
            if (mmio_wr_ctrl) begin
                auto_telem_en <= req_wdata_d[0];
            end

            // Keep each readback line contiguous; automated telemetry starts
            // only after its newline. MMIO writes retain their old behavior
            // outside a readback line.
            if (readback_valid && readback_ready) begin
                fifo_mem[fifo_wptr] <= readback_byte;
                fifo_wptr <= fifo_wptr + 6'd1;
                if (!fifo_rd_en) fifo_count <= fifo_count + 7'd1;
                readback_line_active <= (readback_byte != 8'h0A);
            end else if (mmio_wr_tx && !fifo_full) begin
                fifo_mem[fifo_wptr] <= req_wdata_d[7:0];
                fifo_wptr <= fifo_wptr + 6'd1;
                if (!fifo_rd_en) fifo_count <= fifo_count + 7'd1;
            end else if (hw_wr_en && !fifo_full) begin
                fifo_mem[fifo_wptr] <= hw_char;
                fifo_wptr <= fifo_wptr + 6'd1;
                if (!fifo_rd_en) fifo_count <= fifo_count + 7'd1;
            end else if (fifo_rd_en) begin
                fifo_count <= fifo_count - 7'd1;
            end

            // FIFO Read Advance
            if (fifo_rd_en) begin
                fifo_rptr <= fifo_rptr + 6'd1;
            end
        end
    end

endmodule
