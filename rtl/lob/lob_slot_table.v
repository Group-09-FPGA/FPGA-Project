// Active order slot storage (2,048 entries x 47 bits)

`timescale 1ns / 1ps

`include "lob_defines.vh"

module lob_slot_table #(
    parameter NUM_SLOTS   = `NUM_SLOTS,
    parameter SLOT_ADDR_W = `SLOT_ADDR_W
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // Hardware Initialization
    input  wire                   init_start,
    output wire                   init_busy,
    output reg                    init_done,

    // Write Port
    input  wire                   wr_en,
    input  wire [SLOT_ADDR_W-1:0] wr_addr,
    input  wire [46:0]            wr_data,

    // Read Port (Latency = 1 cycle)
    input  wire                   rd_en,
    input  wire [SLOT_ADDR_W-1:0] rd_addr,
    output wire [46:0]            rd_data,
    input  wire                   dbg_clk,
    input  wire [SLOT_ADDR_W-1:0] dbg_addr,
    output reg  [46:0]            dbg_data
);

    // 2,048 x 47-bit storage array
    // Synthesizes cleanly into RAMB18E1 primitives (3 x RAMB18 in 2Kx18 mode)
    (* ram_style = "block" *)
    reg [46:0] mem [0:NUM_SLOTS-1];

    // Initialization Counter
    reg [SLOT_ADDR_W:0] init_cnt;
    reg                 initializing;

    assign init_busy = initializing;

    // Synchronous memory port signals
    wire [SLOT_ADDR_W-1:0] eff_wr_addr;
    wire [46:0]            eff_wr_data;
    wire                   eff_wr_en;

    assign eff_wr_en   = initializing ? 1'b1 : wr_en;
    assign eff_wr_addr = initializing ? init_cnt[SLOT_ADDR_W-1:0] : wr_addr;
    assign eff_wr_data = initializing ? 47'd0 : wr_data;

    // Write operation
    always @(posedge clk) begin
        if (eff_wr_en) begin
            mem[eff_wr_addr] <= eff_wr_data;
        end
    end

    // Read operation (1 cycle latency)
    reg [46:0] rd_data_reg;
    always @(posedge clk) begin
        if (rd_en) begin
            rd_data_reg <= mem[rd_addr];
        end
    end

    assign rd_data = rd_data_reg;

    // Independent read-only VGA port; the matching write/read cycle is
    // intentionally not used as a coherent snapshot.
    always @(posedge dbg_clk)
        dbg_data <= mem[dbg_addr];

    // Initialization FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt     <= {SLOT_ADDR_W+1{1'b0}};
            initializing <= 1'b0;
            init_done    <= 1'b0;
        end else begin
            if (init_start && !initializing) begin
                init_cnt     <= {SLOT_ADDR_W+1{1'b0}};
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
