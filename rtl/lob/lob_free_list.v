// LIFO free slot allocator and reclamation stack (2,048 x 11 bits)

`timescale 1ns / 1ps

`include "lob_defines.vh"

module lob_free_list #(
    parameter NUM_SLOTS   = `NUM_SLOTS,
    parameter SLOT_ADDR_W = `SLOT_ADDR_W
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // Hardware Initialization
    input  wire                   init_start,
    output wire                   init_busy,
    output reg                    init_done,

    // Allocation (Pop / Prefetch)
    input  wire                   rd_top_en,      // Read stack[sp-1]
    output wire [SLOT_ADDR_W-1:0] top_slot,       // Registered output (latency = 1 cycle)
    output wire                   top_valid,      // High if sp > 0
    input  wire                   pop_commit,     // Decrement sp

    // Reclamation (Push)
    input  wire                   push_en,        // Write stack[sp] = push_slot & sp++
    input  wire [SLOT_ADDR_W-1:0] push_slot,

    // Status & Telemetry
    output wire                   empty,
    output wire                   full,
    output wire [SLOT_ADDR_W:0]   free_count,     // 0..2048
    output wire [SLOT_ADDR_W:0]   active_count,   // 2048 - sp
    input  wire                   dbg_clk,
    input  wire [SLOT_ADDR_W-1:0] dbg_addr,
    output reg  [SLOT_ADDR_W-1:0] dbg_data
);

    // 2,048 x 11-bit BRAM storage (2 x RAMB18 in 2Kx9 mode)
    (* ram_style = "block" *)
    reg [SLOT_ADDR_W-1:0] stack_mem [0:NUM_SLOTS-1];

    // Stack pointer: 0 to NUM_SLOTS (12 bits)
    reg [SLOT_ADDR_W:0] sp;

    // Initialization counter
    reg [SLOT_ADDR_W:0] init_cnt;
    reg                 initializing;

    assign init_busy    = initializing;
    assign empty        = (sp == {SLOT_ADDR_W+1{1'b0}});
    assign full         = (sp == NUM_SLOTS);
    assign free_count   = sp;
    assign active_count = NUM_SLOTS - sp;

    // Effective write signals to stack memory
    reg                   eff_wr_en;
    reg [SLOT_ADDR_W-1:0] eff_wr_addr;
    reg [SLOT_ADDR_W-1:0] eff_wr_data;

    always @* begin
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
            eff_wr_addr = {SLOT_ADDR_W{1'b0}};
            eff_wr_data = {SLOT_ADDR_W{1'b0}};
        end
    end

    // Memory write
    always @(posedge clk) begin
        if (eff_wr_en) begin
            stack_mem[eff_wr_addr] <= eff_wr_data;
        end
    end

    always @(posedge dbg_clk)
        dbg_data <= stack_mem[dbg_addr];

    // Memory read for top_slot (latency = 1)
    wire [SLOT_ADDR_W-1:0] rd_addr;
    assign rd_addr = (sp > 0) ? (sp[SLOT_ADDR_W-1:0] - 1'b1) : {SLOT_ADDR_W{1'b0}};

    reg [SLOT_ADDR_W-1:0] top_slot_reg;
    reg                   top_valid_reg;

    always @(posedge clk) begin
        if (rd_top_en) begin
            top_slot_reg <= stack_mem[rd_addr];
        end
    end

    always @(posedge clk or negedge rst_n) begin
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
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sp           <= {SLOT_ADDR_W+1{1'b0}};
            init_cnt     <= {SLOT_ADDR_W+1{1'b0}};
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= {SLOT_ADDR_W+1{1'b0}};
                initializing <= 1'b1;
                init_done    <= 1'b0;
                sp           <= {SLOT_ADDR_W+1{1'b0}};
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
            end
        end
    end

endmodule
