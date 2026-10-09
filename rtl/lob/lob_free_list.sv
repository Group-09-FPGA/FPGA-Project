// =============================================================================
// File: lob_free_list.sv
// Description: LIFO free slot allocator and reclamation stack (2,048 x 11 bits)
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// Authoritative spec: docs/phase1_architecture_final_v7.md §12, §15, §16
// =============================================================================

`timescale 1ns / 1ps

import lob_pkg::*;

module lob_free_list #(
    parameter int unsigned NUM_SLOTS   = lob_pkg::NUM_SLOTS,
    parameter int unsigned SLOT_ADDR_W = lob_pkg::SLOT_ADDR_W
) (
    input  logic                   clk,
    input  logic                   rst_n,

    // Hardware Initialization
    input  logic                   init_start,
    output logic                   init_busy,
    output logic                   init_done,

    // Allocation (Pop / Prefetch)
    input  logic                   rd_top_en,      // Read stack[sp-1]
    output logic [SLOT_ADDR_W-1:0] top_slot,       // Registered output (latency = 1 cycle)
    output logic                   top_valid,      // High if sp > 0
    input  logic                   pop_commit,     // Decrement sp

    // Reclamation (Push)
    input  logic                   push_en,        // Write stack[sp] = push_slot & sp++
    input  logic [SLOT_ADDR_W-1:0] push_slot,

    // Status & Telemetry
    output logic                   empty,
    output logic                   full,
    output logic [SLOT_ADDR_W:0]   free_count,     // 0..2048
    output logic [SLOT_ADDR_W:0]   active_count    // 2048 - sp
);

    // 2,048 x 11-bit BRAM storage (2 x RAMB18 in 2Kx9 mode)
    (* ram_style = "block" *)
    logic [SLOT_ADDR_W-1:0] stack_mem [0:NUM_SLOTS-1];

    // Stack pointer: 0 to NUM_SLOTS (12 bits)
    logic [SLOT_ADDR_W:0] sp;

    // Initialization counter
    logic [SLOT_ADDR_W:0] init_cnt;
    logic                 initializing;

    assign init_busy    = initializing;
    assign empty        = (sp == '0);
    assign full         = (sp == NUM_SLOTS);
    assign free_count   = sp;
    assign active_count = NUM_SLOTS - sp;

    // Effective write signals to stack memory
    logic                   eff_wr_en;
    logic [SLOT_ADDR_W-1:0] eff_wr_addr;
    logic [SLOT_ADDR_W-1:0] eff_wr_data;

    always_comb begin
        if (initializing) begin
            eff_wr_en   = 1'b1;
            eff_wr_addr = init_cnt[SLOT_ADDR_W-1:0];
            eff_wr_data = init_cnt[SLOT_ADDR_W-1:0]; // Initialize slot i = i
        end else if (push_en && !full) begin
            eff_wr_en   = 1'b1;
            eff_wr_addr = sp[SLOT_ADDR_W-1:0];
            eff_wr_data = push_slot;
        end else begin
            eff_wr_en   = 1'b0;
            eff_wr_addr = '0;
            eff_wr_data = '0;
        end
    end

    // Memory write
    always_ff @(posedge clk) begin
        if (eff_wr_en) begin
            stack_mem[eff_wr_addr] <= eff_wr_data;
        end
    end

    // Memory read for top_slot (latency = 1)
    logic [SLOT_ADDR_W-1:0] rd_addr;
    assign rd_addr = (sp > 0) ? (sp[SLOT_ADDR_W-1:0] - 1'b1) : '0;

    logic [SLOT_ADDR_W-1:0] top_slot_reg;
    logic                   top_valid_reg;

    always_ff @(posedge clk) begin
        if (rd_top_en) begin
            top_slot_reg <= stack_mem[rd_addr];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_valid_reg <= 1'b0;
        end else begin
            if (rd_top_en) begin
                top_valid_reg <= (sp > 0);
            end
        end
    end

    assign top_slot  = top_slot_reg;
    assign top_valid = top_valid_reg;

    // Pointer update & Initialization FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sp           <= '0;
            init_cnt     <= '0;
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= '0;
                initializing <= 1'b1;
                init_done    <= 1'b0;
                sp           <= '0;
            end else if (initializing) begin
                if (init_cnt == NUM_SLOTS - 1) begin
                    initializing <= 1'b0;
                    init_done    <= 1'b1;
                    sp           <= NUM_SLOTS; // All slots free
                end else begin
                    init_cnt <= init_cnt + 1'b1;
                end
            end else begin
                if (pop_commit && !push_en && !empty) begin
                    sp <= sp - 1'b1;
                end else if (push_en && !pop_commit && !full) begin
                    sp <= sp + 1'b1;
                end
                // Simultaneous push and pop (should not occur in v7 schedules, but holds sp steady)
            end
        end
    end

endmodule
