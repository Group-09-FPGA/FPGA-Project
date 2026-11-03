`timescale 1ns / 1ps

// Chooses who owns the book's read ports (UART readback or the display CPU)
// and routes the RAM data back to the requester.
// Display kinds: 1 slot, 2 hash, 3 stash, 4 price, 5 free list, 6 level count,
// 7 quote history, 8 event history. Readback kinds use the letters
// S H X P F L Q E (same order).
module ram_ports (
    input  wire         readback_active,
    input  wire [7:0]   readback_kind,
    input  wire [13:0]  readback_addr,
    input  wire [9:0]   readback_scan_set,

    input  wire         ui_request,
    input  wire [3:0]   ui_kind,
    input  wire [13:0]  ui_address,
    input  wire         ui_hold,          // keyboard form is reading slot/hash itself
    input  wire [10:0]  ui_hold_slot,
    input  wire [9:0]   ui_hold_hash_set,
    input  wire [2:0]   ui_hold_hash_way,
    output wire         ui_grant,

    output wire [10:0]  slot_addr,
    output wire [9:0]   hash_set,
    output wire [2:0]   stash_idx,
    output wire [13:0]  price_addr,
    output wire [10:0]  free_addr,
    output wire [6:0]   quote_addr,
    output wire [7:0]   event_addr,

    input  wire [46:0]  slot_data,
    input  wire [607:0] hash_ways,
    input  wire [75:0]  stash_data,
    input  wire [31:0]  price_data,
    input  wire [10:0]  free_data,
    input  wire [11:0]  level_count,
    input  wire [174:0] quote_data,
    input  wire [393:0] event_data,

    output wire [607:0] ui_data,
    output wire [607:0] readback_data,
    output wire [7:0]   hash_valid
);
    assign ui_grant = ui_request && !readback_active && !ui_hold;

    wire rb_slot  = readback_active && readback_kind == "S";
    wire rb_hash  = readback_active && readback_kind == "H";
    wire rb_scan  = readback_active && readback_kind == "B";
    wire rb_stash = readback_active && readback_kind == "X";
    wire rb_price = readback_active && (readback_kind == "P" || readback_kind == "L");
    wire rb_free  = readback_active && readback_kind == "F";

    wire [10:0] ui_slot_addr  = ui_hold ? ui_hold_slot     : ui_kind == 1 ? ui_address[10:0] : 11'd0;
    wire [9:0]  ui_hash_addr  = ui_hold ? ui_hold_hash_set : ui_kind == 2 ? ui_address[9:0]  : 10'd0;
    wire [2:0]  ui_stash_addr = ui_hold ? ui_hold_hash_way : ui_kind == 3 ? ui_address[2:0]  : 3'd0;

    assign slot_addr  = rb_slot  ? readback_addr[10:0] : ui_slot_addr;
    assign hash_set   = rb_scan  ? readback_scan_set :
                        rb_hash  ? readback_addr[9:0] : ui_hash_addr;
    assign stash_idx  = rb_stash ? readback_addr[2:0]  : ui_stash_addr;
    assign price_addr = rb_price ? readback_addr       : ui_address;
    assign free_addr  = rb_free  ? readback_addr[10:0] : ui_address[10:0];
    assign quote_addr = readback_active && readback_kind == "Q" ? readback_addr[6:0] :
                        ui_grant && ui_kind == 7 ? ui_address[6:0] : 7'd0;
    assign event_addr = readback_active && readback_kind == "E" ? readback_addr[7:0] :
                        ui_grant && ui_kind == 8 ? ui_address[7:0] : 8'd0;

    genvar way;
    generate
        for (way = 0; way < 8; way = way + 1) begin : g_valid
            assign hash_valid[way] = hash_ways[way*76 + 75];
        end
    endgenerate

    assign ui_data =
        ui_kind == 1 ? {{561{1'b0}}, slot_data} :
        ui_kind == 2 ? hash_ways :
        ui_kind == 3 ? {{532{1'b0}}, stash_data} :
        ui_kind == 4 ? {{576{1'b0}}, price_data} :
        ui_kind == 5 ? {{597{1'b0}}, free_data} :
        ui_kind == 6 ? {{596{1'b0}}, level_count} :
        ui_kind == 7 ? {{433{1'b0}}, quote_data} :
        ui_kind == 8 ? {{214{1'b0}}, event_data} : 608'd0;

    assign readback_data =
        readback_kind == "S" ? {{561{1'b0}}, slot_data} :
        readback_kind == "H" ? hash_ways :
        readback_kind == "X" ? {{532{1'b0}}, stash_data} :
        readback_kind == "P" ? {{576{1'b0}}, price_data} :
        readback_kind == "F" ? {{597{1'b0}}, free_data} :
        readback_kind == "L" ? {{596{1'b0}}, level_count} :
        readback_kind == "Q" ? {{433{1'b0}}, quote_data} :
        readback_kind == "E" ? {{214{1'b0}}, event_data} : 608'd0;
endmodule
