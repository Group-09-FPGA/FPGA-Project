// =============================================================================
// File: lob_slot_table.sv
// Description: Active order slot storage (2,048 entries x 47 bits)
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §12, §15
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module lob_slot_table #(
    parameter int unsigned NUM_SLOTS   = lob_pkg::NUM_SLOTS,
    parameter int unsigned SLOT_ADDR_W = lob_pkg::SLOT_ADDR_W
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Hardware Initialization
    input  logic                   init_start,
    output logic                   init_busy,
    output logic                   init_done,

    // Write Port
    input  logic                   wr_en,
    input  logic [SLOT_ADDR_W-1:0] wr_addr,
    input  slot_entry_t            wr_data,

    // Read Port (Latency = 1 cycle)
    input  logic                   rd_en,
    input  logic [SLOT_ADDR_W-1:0] rd_addr,
    output slot_entry_t            rd_data
);

    // 2,048 x 47-bit storage array
    // Synthesizes cleanly into RAMB18E1 primitives (3 x RAMB18 in 2Kx18 mode)
    (* ram_style = "block" *)
    logic [46:0] mem [0:NUM_SLOTS-1];

    // Initialization Counter
    logic [SLOT_ADDR_W:0] init_cnt;
    logic                 initializing;

    assign init_busy = initializing;

    // Synchronous memory port signals
    logic [SLOT_ADDR_W-1:0] eff_wr_addr;
    logic [46:0]            eff_wr_data;
    logic                   eff_wr_en;

    assign eff_wr_en   = initializing ? 1'b1 : wr_en;
    assign eff_wr_addr = initializing ? init_cnt[SLOT_ADDR_W-1:0] : wr_addr;
    assign eff_wr_data = initializing ? 47'd0 : wr_data;

    // Write operation
    always_ff @(posedge clk) begin
        if (eff_wr_en) begin
            mem[eff_wr_addr] <= eff_wr_data;
        end
    end

    // Read operation (1 cycle latency)
    logic [46:0] rd_data_reg;
    always_ff @(posedge clk) begin
        if (rd_en) begin
            rd_data_reg <= mem[rd_addr];
        end
    end

    assign rd_data = slot_entry_t'(rd_data_reg);

    // Initialization FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt     <= '0;
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= '0;
                initializing <= 1'b1;
                init_done    <= 1'b0;
            end else if (initializing) begin
                if (init_cnt == NUM_SLOTS - 1) begin
                    initializing <= 1'b0;
                    init_done    <= 1'b1;
                end else begin
                    init_cnt <= init_cnt + 1'b1;
                end
            end
        end
    end

endmodule
