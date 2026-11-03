`timescale 1ns / 1ps

// 8N1 UART transmitter fed by a 64-byte FIFO.
module uart_tx #(
    parameter CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_en,        // push wr_data (caller checks `full`)
    input  wire [7:0] wr_data,
    output wire       full,
    output wire       empty,
    output wire       busy,         // a byte is being shifted out
    output wire [7:0] head_byte,    // oldest queued byte
    output reg        txd
);
    reg [7:0] mem [0:63];
    reg [5:0] wptr, rptr;
    reg [6:0] count;

    assign empty     = (count == 7'd0);
    assign full      = (count >= 7'd64);
    assign head_byte = mem[rptr];

    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;
    reg [1:0]  state;
    reg [15:0] baud_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift;

    assign busy = (state != IDLE);
    wire rd_en = (state == IDLE) && !empty;
    wire bit_done = (baud_cnt == CLKS_PER_BIT - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= 6'd0; rptr <= 6'd0; count <= 7'd0;
        end else begin
            if (wr_en) begin
                mem[wptr] <= wr_data;
                wptr      <= wptr + 6'd1;
            end
            if (rd_en)
                rptr <= rptr + 6'd1;
            if (wr_en && !rd_en)
                count <= count + 7'd1;
            else if (!wr_en && rd_en)
                count <= count - 7'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; txd <= 1'b1; baud_cnt <= 16'd0; bit_idx <= 3'd0; shift <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    txd <= 1'b1;
                    if (!empty) begin
                        shift    <= head_byte;
                        baud_cnt <= 16'd0;
                        state    <= START;
                    end
                end
                START: begin
                    txd <= 1'b0;
                    if (bit_done) begin
                        baud_cnt <= 16'd0; bit_idx <= 3'd0; state <= DATA;
                    end else
                        baud_cnt <= baud_cnt + 16'd1;
                end
                DATA: begin
                    txd <= shift[bit_idx];
                    if (bit_done) begin
                        baud_cnt <= 16'd0;
                        if (bit_idx == 3'd7) state <= STOP;
                        else                 bit_idx <= bit_idx + 3'd1;
                    end else
                        baud_cnt <= baud_cnt + 16'd1;
                end
                STOP: begin
                    txd <= 1'b1;
                    if (bit_done) begin
                        baud_cnt <= 16'd0; state <= IDLE;
                    end else
                        baud_cnt <= baud_cnt + 16'd1;
                end
            endcase
        end
    end
endmodule
