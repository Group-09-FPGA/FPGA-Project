`timescale 1ns / 1ps

// Records the RAM writes committed by one event so the UART can report them.
// One event writes at most one slot, one hash insert, one hash invalidation and
// two price levels. The record is published when the event completes.
module lob_storage_trace (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         event_accept,     // a new event starts: clear the collectors
    input  wire         event_done,       // the event finished: publish
    input  wire [3:0]   op,
    input  wire [63:0]  oid,
    input  wire [63:0]  noid,

    input  wire         slot_wr_en,
    input  wire [10:0]  slot_wr_addr,
    input  wire [46:0]  slot_wr_data,
    input  wire         inv_way_en,
    input  wire         inv_stash_en,
    input  wire [9:0]   inv_set,          // set of the invalidated way, or of the old id for a stash entry
    input  wire [2:0]   inv_way_idx,
    input  wire [2:0]   inv_stash_idx,
    input  wire         ins_way_en,
    input  wire         ins_stash_en,
    input  wire [9:0]   ins_set,
    input  wire [2:0]   ins_way_idx,
    input  wire [2:0]   ins_stash_idx,
    input  wire         price_wr_en,
    input  wire [13:0]  price_wr_addr,
    input  wire [31:0]  price_wr_data,

    output reg  [315:0] trace
);
    reg        slot_v, inv_v, ins_v, p0_v, p1_v;
    reg [10:0] slot_addr;
    reg [46:0] slot_data;
    reg [9:0]  inv_set_r, ins_set_r;
    reg [2:0]  inv_idx, ins_idx;
    reg        inv_stash, ins_stash;
    reg [13:0] p0_addr, p1_addr;
    reg [31:0] p0_qty, p1_qty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trace <= 316'd0;
            {slot_v, inv_v, ins_v, p0_v, p1_v} <= 5'd0;
            slot_addr <= 0; slot_data <= 0;
            inv_set_r <= 0; ins_set_r <= 0; inv_idx <= 0; ins_idx <= 0;
            inv_stash <= 0; ins_stash <= 0;
            p0_addr <= 0; p1_addr <= 0; p0_qty <= 0; p1_qty <= 0;
        end else begin
            // Completion and acceptance can coincide for back-to-back events,
            // so publish the old record before clearing the collectors.
            if (event_done)
                trace <= {1'b1, op, oid, noid,
                          slot_v, slot_addr, slot_data,
                          inv_v, inv_set_r, inv_idx, inv_stash,
                          ins_v, ins_set_r, ins_idx, ins_stash,
                          p0_v, p0_addr, p0_qty,
                          p1_v, p1_addr, p1_qty};

            if (event_accept) begin
                {slot_v, inv_v, ins_v, p0_v, p1_v} <= 5'd0;
            end else begin
                if (slot_wr_en) begin
                    slot_v <= 1'b1; slot_addr <= slot_wr_addr; slot_data <= slot_wr_data;
                end
                if (inv_way_en || inv_stash_en) begin
                    inv_v <= 1'b1; inv_stash <= inv_stash_en; inv_set_r <= inv_set;
                    inv_idx <= inv_stash_en ? inv_stash_idx : inv_way_idx;
                end
                if (ins_way_en || ins_stash_en) begin
                    ins_v <= 1'b1; ins_stash <= ins_stash_en; ins_set_r <= ins_set;
                    ins_idx <= ins_stash_en ? ins_stash_idx : ins_way_idx;
                end
                if (price_wr_en) begin
                    if (!p0_v) begin
                        p0_v <= 1'b1; p0_addr <= price_wr_addr; p0_qty <= price_wr_data;
                    end else begin
                        p1_v <= 1'b1; p1_addr <= price_wr_addr; p1_qty <= price_wr_data;
                    end
                end
            end
        end
    end
endmodule
