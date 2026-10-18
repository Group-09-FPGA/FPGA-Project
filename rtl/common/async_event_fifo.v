// =============================================================================
// File: async_event_fifo.v
// Description: Dual-clock Asynchronous FIFO for Clock Domain Crossing (CDC)
//              Crosses 256-bit canonical market data events from 50 MHz RMII/Network
//              domain to 100 MHz Core/LOB domain with Gray pointer synchronizers
//              and First-Word Fall-Through (FWFT) ready/valid handshaking.
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// =============================================================================

`timescale 1ns / 1ps

module async_event_fifo #(
    parameter DATA_WIDTH = 256,
    parameter ADDR_WIDTH = 6,               // Depth = 2^ADDR_WIDTH = 64
    parameter RAM_STYLE  = "distributed"    // "distributed" or "block"
) (
    // -------------------------------------------------------------------------
    // Write Clock Domain (50 MHz RMII / ITCH Parser)
    // -------------------------------------------------------------------------
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_valid,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_ready,
    output wire                  wr_full,
    output reg                   wr_overflow,

    // -------------------------------------------------------------------------
    // Read Clock Domain (100 MHz Core / LOB Engine)
    // -------------------------------------------------------------------------
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_ready,
    output wire                  rd_valid,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_empty,
    output reg                   rd_underflow,

    // -------------------------------------------------------------------------
    // Diagnostics & Occupancy
    // -------------------------------------------------------------------------
    output wire [ADDR_WIDTH:0]   wr_count,
    output wire [ADDR_WIDTH:0]   rd_count
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // -------------------------------------------------------------------------
    // Dual-Port Memory Storage
    // -------------------------------------------------------------------------
    (* ram_style = RAM_STYLE *)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Write domain pointers
    reg [ADDR_WIDTH:0] wptr_bin;
    reg [ADDR_WIDTH:0] wptr_gray;

    // Read domain pointers
    reg [ADDR_WIDTH:0] rptr_bin;
    reg [ADDR_WIDTH:0] rptr_gray;

    // -------------------------------------------------------------------------
    // Gray to Binary Conversion Function
    // -------------------------------------------------------------------------
    function [ADDR_WIDTH:0] gray_to_bin;
        input [ADDR_WIDTH:0] g;
        reg   [ADDR_WIDTH:0] b;
        integer i;
        begin
            b[ADDR_WIDTH] = g[ADDR_WIDTH];
            for (i = ADDR_WIDTH - 1; i >= 0; i = i - 1) begin
                b[i] = b[i+1] ^ g[i];
            end
            gray_to_bin = b;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Clock Domain Crossing: 2-Stage Flip-Flop Synchronizers
    // -------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] rptr_gray_sync1, rptr_gray_sync2;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_WIDTH:0] wptr_gray_sync1, wptr_gray_sync2;

    // Synchronize rptr_gray into wr_clk domain
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rptr_gray_sync1 <= {ADDR_WIDTH+1{1'b0}};
            rptr_gray_sync2 <= {ADDR_WIDTH+1{1'b0}};
        end else begin
            rptr_gray_sync1 <= rptr_gray;
            rptr_gray_sync2 <= rptr_gray_sync1;
        end
    end

    // Synchronize wptr_gray into rd_clk domain
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wptr_gray_sync1 <= {ADDR_WIDTH+1{1'b0}};
            wptr_gray_sync2 <= {ADDR_WIDTH+1{1'b0}};
        end else begin
            wptr_gray_sync1 <= wptr_gray;
            wptr_gray_sync2 <= wptr_gray_sync1;
        end
    end

    // -------------------------------------------------------------------------
    // Write Logic & Full Generation
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH:0] wptr_bin_next  = wptr_bin + (wr_valid && wr_ready ? 1'b1 : 1'b0);
    wire [ADDR_WIDTH:0] wptr_gray_next = wptr_bin_next ^ (wptr_bin_next >> 1);

    // Full condition: MSBs inverted, remaining bits identical
    wire is_full = (wptr_gray_next == {~rptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],
                                        rptr_gray_sync2[ADDR_WIDTH-2:0]});

    reg full_reg;
    assign wr_full  = full_reg;
    assign wr_ready = ~full_reg;

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wptr_bin    <= {ADDR_WIDTH+1{1'b0}};
            wptr_gray   <= {ADDR_WIDTH+1{1'b0}};
            full_reg    <= 1'b0;
            wr_overflow <= 1'b0;
        end else begin
            if (wr_valid && wr_ready) begin
                mem[wptr_bin[ADDR_WIDTH-1:0]] <= wr_data;
                wptr_bin  <= wptr_bin_next;
                wptr_gray <= wptr_gray_next;
            end

            // Full updates continuously
            full_reg <= is_full;

            // Overflow pulse on attempted write while full
            if (wr_valid && full_reg) begin
                wr_overflow <= 1'b1;
            end else begin
                wr_overflow <= 1'b0;
            end
        end
    end

    // Write occupancy count
    wire [ADDR_WIDTH:0] rptr_bin_in_wr = gray_to_bin(rptr_gray_sync2);
    assign wr_count = wptr_bin - rptr_bin_in_wr;

    // -------------------------------------------------------------------------
    // Read Logic & Empty Generation (First-Word Fall-Through)
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH:0] rptr_bin_next  = rptr_bin + (rd_valid && rd_ready ? 1'b1 : 1'b0);
    wire [ADDR_WIDTH:0] rptr_gray_next = rptr_bin_next ^ (rptr_bin_next >> 1);

    wire is_empty = (rptr_gray == wptr_gray_sync2);

    reg empty_reg;
    assign rd_empty = empty_reg;
    assign rd_valid = ~empty_reg;

    // Asynchronous read for FWFT with distributed RAM
    assign rd_data = mem[rptr_bin[ADDR_WIDTH-1:0]];

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rptr_bin     <= {ADDR_WIDTH+1{1'b0}};
            rptr_gray    <= {ADDR_WIDTH+1{1'b0}};
            empty_reg    <= 1'b1;
            rd_underflow <= 1'b0;
        end else begin
            if (rd_valid && rd_ready) begin
                rptr_bin  <= rptr_bin_next;
                rptr_gray <= rptr_gray_next;
                // Next empty evaluated with next rptr
                empty_reg <= (rptr_gray_next == wptr_gray_sync2);
            end else begin
                // Empty evaluated with current rptr
                empty_reg <= is_empty;
            end

            if (rd_ready && empty_reg) begin
                rd_underflow <= 1'b1;
            end else begin
                rd_underflow <= 1'b0;
            end
        end
    end

    // Read occupancy count
    wire [ADDR_WIDTH:0] wptr_bin_in_rd = gray_to_bin(wptr_gray_sync2);
    assign rd_count = wptr_bin_in_rd - rptr_bin;

endmodule
