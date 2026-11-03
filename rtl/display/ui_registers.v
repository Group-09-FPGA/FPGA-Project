`timescale 1ns / 1ps

// Packs everything the display firmware reads into 52 word-wide registers.
// Register numbers are the contract with firmware/kitty_ui/main.c.
module ui_registers (
    // keyboard form state
    input  wire [3:0]   page,
    input  wire [2:0]   action,
    input  wire [2:0]   focus,
    input  wire         side,
    input  wire         editing,
    input  wire         focused_valid,
    input  wire         selected_valid,
    input  wire         scan_busy,
    input  wire [4:0]   status,
    input  wire [19:0]  form_lengths,
    input  wire [19:0]  form_cursors,
    input  wire [31:0]  price,
    input  wire [31:0]  quantity,
    input  wire [63:0]  order_id,
    input  wire [63:0]  new_id,
    input  wire [63:0]  selected_id,
    input  wire         stash_selected,
    input  wire [2:0]   hash_way,
    input  wire [9:0]   hash_set,
    input  wire [10:0]  free_offset,
    input  wire [10:0]  slot,
    input  wire [13:0]  level,
    input  wire [10:0]  history_offset,
    input  wire [511:0] form_text,
    input  wire [31:0]  keyboard_frame_errors,
    // live book and network state
    input  wire [174:0] book,
    input  wire [127:0] net,
    input  wire [95:0]  pipe,
    input  wire [7:0]   error,
    input  wire [63:0]  settings,
    input  wire [31:0]  history,
    input  wire [40:0]  local_done,

    output reg  [2047:0] registers
);
    integer row, col;

    always @* begin
        registers = 2048'd0;
        registers[0*32+:32]  = {12'd0, status, scan_busy, selected_valid, focused_valid,
                                editing, side, action, focus, page};
        registers[1*32+:32]  = {12'd0, form_lengths};
        registers[2*32+:32]  = {12'd0, form_cursors};
        registers[3*32+:32]  = price;
        registers[4*32+:32]  = quantity;
        registers[5*32+:32]  = order_id[31:0];
        registers[6*32+:32]  = order_id[63:32];
        registers[7*32+:32]  = new_id[31:0];
        registers[8*32+:32]  = new_id[63:32];
        registers[9*32+:32]  = selected_id[31:0];
        registers[10*32+:32] = selected_id[63:32];
        registers[11*32+:32] = {18'd0, stash_selected, hash_way, hash_set};
        registers[12*32+:32] = {10'd0, free_offset, slot};
        registers[13*32+:32] = {18'd0, level};
        registers[14*32+:32] = {21'd0, history_offset};
        registers[15*32+:32] = {29'd0, book[108], book[173], book[174]};
        registers[16*32+:32] = book[172:141];
        registers[17*32+:32] = book[140:109];
        registers[18*32+:32] = book[107:76];
        registers[19*32+:32] = book[75:44];
        registers[20*32+:32] = {20'd0, book[43:32]};
        registers[21*32+:32] = book[31:0];
        registers[22*32+:32] = net[127:96];
        registers[23*32+:32] = net[95:64];
        registers[24*32+:32] = net[63:32];
        registers[25*32+:32] = net[31:0];
        registers[26*32+:32] = pipe[95:64];
        registers[27*32+:32] = pipe[63:32];
        registers[28*32+:32] = pipe[31:0];
        registers[29*32+:32] = {24'd0, error};
        registers[30*32+:32] = settings[63:32];
        registers[31*32+:32] = settings[31:0];
        registers[32*32+:32] = {history[7:0], history[23:15], history[14:8], history[31:24]};
        for (row = 0; row < 4; row = row + 1)
            for (col = 0; col < 4; col = col + 1)
                registers[(33 + row*4 + col)*32+:32] = form_text[row*128 + (3-col)*32 +: 32];
        registers[49*32+:32] = keyboard_frame_errors;
        registers[50*32+:32] = local_done[40:9];
        registers[51*32+:32] = {23'd0, local_done[8:0]};
    end
endmodule
