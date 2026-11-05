`timescale 1ns / 1ps

// Packs everything the display firmware reads into read-only word-wide registers.
// Register numbers are the contract with firmware/kitty_ui/main.c.
module ui_registers (
    // keyboard navigation state
    input  wire [3:0]   page,
    input  wire [2:0]   focus,
    input  wire         stash_selected,
    input  wire [2:0]   hash_way,
    input  wire [9:0]   hash_set,
    input  wire [10:0]  slot,
    input  wire [13:0]  level,
    input  wire [10:0]  history_offset,
    input  wire [31:0]  keyboard_frame_errors,
    // live book and network state
    input  wire [174:0] book,
    input  wire [127:0] net,
    input  wire [95:0]  pipe,
    input  wire [7:0]   error,
    input  wire [63:0]  settings,
    input  wire [31:0]  history,

    output reg  [2047:0] registers
);
    always @* begin
        registers = 2048'd0;
        registers[0*32+:32]  = {25'd0, focus, page};
        registers[11*32+:32] = {18'd0, stash_selected, hash_way, hash_set};
        registers[12*32+:32] = {21'd0, slot};
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
        registers[49*32+:32] = keyboard_frame_errors;
    end
endmodule
