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
    input  wire        clk,              // Core 100 MHz clock
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
    reg [5:0] telem_step;
    reg       telem_busy;
    reg [31:0] lat_bid_p, lat_bid_q, lat_ask_p, lat_ask_q;
    reg lat_book_valid;
    reg [7:0] lat_error_code;

    function [7:0] hex2ascii;
        input [3:0] nibble;
        begin
            hex2ascii = (nibble < 4'd10) ? (8'h30 + {4'd0, nibble}) : (8'h41 + {4'd0, nibble - 4'd10});
        end
    endfunction

    reg [7:0] hw_char;
    reg       hw_wr_en;

    always @(*) begin
        hw_char  = 8'h20;
        hw_wr_en = 1'b0;
        if (telem_busy && !fifo_full) begin
            hw_wr_en = 1'b1;
            case (telem_step)
                6'd0:  hw_char = "[";
                6'd1:  hw_char = "B";
                6'd2:  hw_char = "B";
                6'd3:  hw_char = "O";
                6'd4:  hw_char = "]";
                6'd5:  hw_char = " ";
                6'd6:  hw_char = "B";
                6'd7:  hw_char = ":";
                6'd8:  hw_char = hex2ascii(lat_bid_p[31:28]);
                6'd9:  hw_char = hex2ascii(lat_bid_p[27:24]);
                6'd10: hw_char = hex2ascii(lat_bid_p[23:20]);
                6'd11: hw_char = hex2ascii(lat_bid_p[19:16]);
                6'd12: hw_char = hex2ascii(lat_bid_p[15:12]);
                6'd13: hw_char = hex2ascii(lat_bid_p[11:8]);
                6'd14: hw_char = hex2ascii(lat_bid_p[7:4]);
                6'd15: hw_char = hex2ascii(lat_bid_p[3:0]);
                6'd16: hw_char = " ";
                6'd17: hw_char = "|";
                6'd18: hw_char = " ";
                6'd19: hw_char = "A";
                6'd20: hw_char = ":";
                6'd21: hw_char = hex2ascii(lat_ask_p[31:28]);
                6'd22: hw_char = hex2ascii(lat_ask_p[27:24]);
                6'd23: hw_char = hex2ascii(lat_ask_p[23:20]);
                6'd24: hw_char = hex2ascii(lat_ask_p[19:16]);
                6'd25: hw_char = hex2ascii(lat_ask_p[15:12]);
                6'd26: hw_char = hex2ascii(lat_ask_p[11:8]);
                6'd27: hw_char = hex2ascii(lat_ask_p[7:4]);
                6'd28: hw_char = hex2ascii(lat_ask_p[3:0]);
                6'd29: hw_char = " ";
                6'd30: hw_char = "|";
                6'd31: hw_char = " ";
                6'd32: hw_char = "V";
                6'd33: hw_char = ":";
                6'd34: hw_char = lat_book_valid ? "1" : "0";
                6'd35: hw_char = " ";
                6'd36: hw_char = "|";
                6'd37: hw_char = " ";
                6'd38: hw_char = "E";
                6'd39: hw_char = ":";
                6'd40: hw_char = hex2ascii(lat_error_code[7:4]);
                6'd41: hw_char = hex2ascii(lat_error_code[3:0]);
                6'd42: hw_char = 8'h0D;
                6'd43: hw_char = 8'h0A;
                default: begin hw_char = " "; hw_wr_en = 1'b0; end
            endcase
        end
    end

    reg        pending_update;
    reg [31:0] pend_bid_p, pend_bid_q, pend_ask_p, pend_ask_q;
    reg pend_book_valid;
    reg [7:0] pend_error_code;
    reg prev_book_valid;
    reg [7:0] prev_error_code;

    reg [26:0] heartbeat_cnt;
    wire heartbeat_pulse = (heartbeat_cnt >= (CLK_FREQ - 1));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            heartbeat_cnt <= 27'd0;
        else if (heartbeat_pulse)
            heartbeat_cnt <= 27'd0;
        else
            heartbeat_cnt <= heartbeat_cnt + 27'd1;
    end

    wire status_changed = book_valid != prev_book_valid || error_code != prev_error_code;
    wire telem_trigger = hw_telem_trigger || heartbeat_pulse || status_changed;

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
            telem_step     <= 6'd0;
            lat_bid_p      <= 32'd0;
            lat_bid_q      <= 32'd0;
            lat_ask_p      <= 32'd0;
            lat_ask_q      <= 32'd0;
            lat_book_valid <= 1'b0;
            lat_error_code <= 8'd0;
            pending_update <= 1'b0;
            pend_bid_p     <= 32'd0;
            pend_bid_q     <= 32'd0;
            pend_ask_p     <= 32'd0;
            pend_ask_q     <= 32'd0;
            pend_book_valid <= 1'b0;
            pend_error_code <= 8'd0;
        end else begin
            if (!telem_busy && auto_telem_en && telem_trigger) begin
                lat_bid_p      <= best_bid_price;
                lat_bid_q      <= best_bid_qty;
                lat_ask_p      <= best_ask_price;
                lat_ask_q      <= best_ask_qty;
                lat_book_valid <= book_valid;
                lat_error_code <= error_code;
                telem_step     <= 6'd0;
                telem_busy     <= 1'b1;
                pending_update <= 1'b0;
            end else if (telem_busy) begin
                if (auto_telem_en && (hw_telem_trigger || status_changed)) begin
                    pending_update <= 1'b1;
                    pend_bid_p     <= best_bid_price;
                    pend_bid_q     <= best_bid_qty;
                    pend_ask_p     <= best_ask_price;
                    pend_ask_q     <= best_ask_qty;
                    pend_book_valid <= book_valid;
                    pend_error_code <= error_code;
                end
                if (hw_wr_en) begin
                    if (telem_step == 6'd43) begin
                        if (pending_update) begin
                            lat_bid_p      <= pend_bid_p;
                            lat_bid_q      <= pend_bid_q;
                            lat_ask_p      <= pend_ask_p;
                            lat_ask_q      <= pend_ask_q;
                            lat_book_valid <= pend_book_valid;
                            lat_error_code <= pend_error_code;
                            telem_step     <= 6'd0;
                            pending_update <= 1'b0;
                            telem_busy     <= 1'b1;
                        end else begin
                            telem_busy <= 1'b0;
                        end
                    end else begin
                        telem_step <= telem_step + 6'd1;
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

            // FIFO Write Arbitrator (MMIO priority, fallback hardware)
            if (mmio_wr_tx && !fifo_full) begin
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
