// =============================================================================
// File: lob_price_ram.v
// Description: Price-level aggregate quantity RAM (16,384 x 32 bits, 3-cycle read latency)
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §13, §15, §16
// =============================================================================

`timescale 1ns / 1ps

`include "lob_defines.vh"

module lob_price_ram #(
    parameter TOTAL_PRICE_LEVELS = `TOTAL_PRICE_LEVELS, // 16,384
    parameter PRICE_ADDR_W        = `PRICE_ADDR_W         // 14
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Hardware Initialization
    input  wire                    init_start,
    output wire                    init_busy,
    output reg                     init_done,

    // Write Port
    input  wire                    wr_en,
    input  wire [PRICE_ADDR_W-1:0] wr_addr, // {side, pidx[12:0]}
    input  wire [31:0]             wr_data,

    // Read Port (Deterministic 3-cycle read latency)
    input  wire                    rd_en,
    input  wire [PRICE_ADDR_W-1:0] rd_addr,
    output wire                    rd_valid,
    output wire [31:0]             rd_data
);

    // 16,384 x 32-bit BRAM storage array
    // Synthesizes cleanly into 16 x RAMB36 (or 32 x RAMB18) in 1Kx36 SDP mode
    (* ram_style = "block" *)
    reg [31:0] price_mem [0:TOTAL_PRICE_LEVELS-1];

    // Initialization Counter (16,384 cycles)
    reg [PRICE_ADDR_W:0] init_cnt;
    reg                  initializing;

    assign init_busy = initializing;

    // Effective Write Port
    wire                    eff_wr_en;
    wire [PRICE_ADDR_W-1:0] eff_wr_addr;
    wire [31:0]             eff_wr_data;

    assign eff_wr_en   = initializing ? 1'b1 : wr_en;
    assign eff_wr_addr = initializing ? init_cnt[PRICE_ADDR_W-1:0] : wr_addr;
    assign eff_wr_data = initializing ? 32'd0 : wr_data;

    always @(posedge clk) begin
        if (eff_wr_en) begin
            price_mem[eff_wr_addr] <= eff_wr_data;
        end
    end

    // -------------------------------------------------------------------------
    // 3-Stage Read Pipeline (DOB_REG + Registered Output Mux)
    // -------------------------------------------------------------------------
    // Stage 1: Memory primitive output register (Latency 1)
    reg [31:0] stage1_data;
    always @(posedge clk) begin
        if (rd_en) begin
            stage1_data <= price_mem[rd_addr];
        end
    end

    // Stage 2: Embedded DOB_REG register (Latency 2)
    reg [31:0] stage2_data;
    always @(posedge clk) begin
        stage2_data <= stage1_data;
    end

    // Stage 3: Output Pipeline Register (Latency 3)
    reg [31:0] stage3_data;
    always @(posedge clk) begin
        stage3_data <= stage2_data;
    end

    // Valid Pipeline
    reg stage1_valid;
    reg stage2_valid;
    reg stage3_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            stage3_valid <= 1'b0;
        end else begin
            stage1_valid <= rd_en;
            stage2_valid <= stage1_valid;
            stage3_valid <= stage2_valid;
        end
    end

    assign rd_data  = stage3_data;
    assign rd_valid = stage3_valid;

    // -------------------------------------------------------------------------
    // Initialization FSM (16,384 cycles)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt     <= {PRICE_ADDR_W+1{1'b0}};
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= {PRICE_ADDR_W+1{1'b0}};
                initializing <= 1'b1;
                init_done    <= 1'b0;
            end else if (initializing) begin
                if (init_cnt == TOTAL_PRICE_LEVELS - 1) begin
                    initializing <= 1'b0;
                    init_done    <= 1'b1;
                end else begin
                    init_cnt <= init_cnt + 1'b1;
                end
            end
        end
    end

endmodule
