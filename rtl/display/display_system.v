`timescale 1ns / 1ps

// Keyboard-driven 720p display: PS/2 input and order form, the display CPU, and
// the video output, plus arbitration of the book's read ports.
module display_system #(
    parameter [31:0] DEFAULT_PRICE_BASE = 32'd900000,
    parameter [31:0] DEFAULT_TICK       = 32'd1000
) (
    input  wire         clk_100,
    input  wire         rst_100_n,
    input  wire         clk,             // UI clock (25 MHz)
    input  wire         rst_n,

    input  wire         ps2_clk,
    input  wire         ps2_data,

    // Orders typed on the keyboard
    output wire         event_valid,
    output wire [255:0] event_data,
    input  wire         event_ready,

    // Live state, already in the UI clock domain
    input  wire [174:0] book,
    input  wire [127:0] net,
    input  wire [95:0]  pipe,
    input  wire [7:0]   error,
    input  wire [63:0]  settings,
    input  wire [31:0]  history,
    input  wire [40:0]  local_done,

    // Book read ports and their data
    input  wire         readback_active,
    input  wire [7:0]   readback_kind,
    input  wire [13:0]  readback_addr,
    input  wire [9:0]   readback_scan_set,
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
    input  wire [393:0] event_history,
    output wire [607:0] readback_data,
    output wire [7:0]   hash_valid,

    output wire         vga_hs,
    output wire         vga_vs,
    output wire [3:0]   vga_r,
    output wire [3:0]   vga_g,
    output wire [3:0]   vga_b
);
    // ---- keyboard ---------------------------------------------------------
    wire       byte_valid, frame_error, key_valid, key_shift;
    wire [7:0] byte_data, key;

    ps2_receiver u_ps2_receiver (
        .clk(clk), .reset_n(rst_n), .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .byte_valid(byte_valid), .byte_data(byte_data), .frame_error(frame_error)
    );
    ps2_key_decoder u_ps2_decoder (
        .clk(clk), .reset_n(rst_n), .byte_valid(byte_valid), .byte_data(byte_data),
        .key_valid(key_valid), .key(key), .key_shift(key_shift), .reconnect()
    );

    wire [31:0] frame_errors;
    event_counter u_frame_errors (.clk(clk), .rst_n(rst_n), .inc(frame_error), .count(frame_errors));

    wire [3:0]   page;
    wire [2:0]   action, focus, hash_way;
    wire         side, editing, focused_valid, selected_valid, scan_busy, stash_selected, ram_hold;
    wire [4:0]   status;
    wire [31:0]  price, quantity;
    wire [63:0]  order_id, new_id, selected_id;
    wire [511:0] form_text;
    wire [19:0]  form_lengths, form_cursors;
    wire [10:0]  history_offset, slot, free_offset;
    wire [9:0]   hash_set_ui;
    wire [13:0]  level;

    keyboard_controls u_keyboard (
        .clk(clk), .reset_n(rst_n),
        .key_valid(key_valid), .key_shift(key_shift), .key(key),
        .book_valid(book[174]),
        .price_base(settings[63:32]), .price_tick(settings[31:0]),
        .ram_paused(readback_active), .hash_data(hash_ways),
        .stash_data(stash_data), .slot_data(slot_data),
        .page(page), .action(action), .side(side), .focus(focus),
        .editing(editing), .focused_valid(focused_valid),
        .form_text(form_text), .form_lengths(form_lengths), .form_cursors(form_cursors),
        .price(price), .quantity(quantity), .order_id(order_id), .new_id(new_id),
        .history_offset(history_offset), .hash_set(hash_set_ui), .hash_way(hash_way),
        .stash_selected(stash_selected), .slot_addr(slot), .level_addr(level),
        .free_offset(free_offset), .selected_valid(selected_valid),
        .scan_busy(scan_busy), .ram_hold(ram_hold), .selected_id(selected_id),
        .status(status),
        .event_valid(event_valid), .event_data(event_data), .event_ready(event_ready)
    );

    // ---- display CPU ------------------------------------------------------
    wire [2047:0] registers;
    ui_registers u_registers (
        .page(page), .action(action), .focus(focus), .side(side), .editing(editing),
        .focused_valid(focused_valid), .selected_valid(selected_valid),
        .scan_busy(scan_busy), .status(status),
        .form_lengths(form_lengths), .form_cursors(form_cursors),
        .price(price), .quantity(quantity), .order_id(order_id), .new_id(new_id),
        .selected_id(selected_id), .stash_selected(stash_selected), .hash_way(hash_way),
        .hash_set(hash_set_ui), .free_offset(free_offset), .slot(slot), .level(level),
        .history_offset(history_offset), .form_text(form_text),
        .keyboard_frame_errors(frame_errors),
        .book(book), .net(net), .pipe(pipe), .error(error), .settings(settings),
        .history(history), .local_done(local_done),
        .registers(registers)
    );

    wire        ram_request, ram_grant;
    wire [3:0]  ram_kind;
    wire [13:0] ram_address;
    wire [607:0] ram_data;

    ram_ports u_ram_ports (
        .readback_active(readback_active), .readback_kind(readback_kind),
        .readback_addr(readback_addr), .readback_scan_set(readback_scan_set),
        .ui_request(ram_request), .ui_kind(ram_kind), .ui_address(ram_address),
        .ui_hold(ram_hold), .ui_hold_slot(slot), .ui_hold_hash_set(hash_set_ui),
        .ui_hold_hash_way(hash_way), .ui_grant(ram_grant),
        .slot_addr(slot_addr), .hash_set(hash_set), .stash_idx(stash_idx),
        .price_addr(price_addr), .free_addr(free_addr),
        .quote_addr(quote_addr), .event_addr(event_addr),
        .slot_data(slot_data), .hash_ways(hash_ways), .stash_data(stash_data),
        .price_data(price_data), .free_data(free_data), .level_count(level_count),
        .quote_data(quote_data), .event_data(event_history),
        .ui_data(ram_data), .readback_data(readback_data), .hash_valid(hash_valid)
    );

    wire        cell_we, plot_we, front_bank, requested_bank, requested_market;
    wire [13:0] cell_addr;
    wire [15:0] cell_data;
    wire [10:0] plot_addr;
    wire [31:0] plot_data;

    kitty_ui_cpu u_ui_cpu (
        .clk(clk), .reset_n(rst_n), .registers(registers),
        .ram_request(ram_request), .ram_kind(ram_kind), .ram_address(ram_address),
        .ram_grant(ram_grant), .ram_data(ram_data),
        .cell_we(cell_we), .cell_addr(cell_addr), .cell_data(cell_data),
        .plot_we(plot_we), .plot_addr(plot_addr), .plot_data(plot_data),
        .requested_bank(requested_bank), .requested_market(requested_market),
        .front_bank(front_bank), .completed_frames(), .exception(), .pc()
    );

    // ---- video ------------------------------------------------------------
    wire pixel_clk, pixel_rst_n;
    kitty_pixel_clock u_pixel_clock (
        .clk100(clk_100), .reset_n(rst_100_n),
        .pixel_clk(pixel_clk), .pixel_reset_n(pixel_rst_n)
    );
    kitty_video u_video (
        .ui_clk(clk), .ui_reset_n(rst_n),
        .pixel_clk(pixel_clk), .pixel_reset_n(pixel_rst_n),
        .cell_we(cell_we), .cell_addr(cell_addr), .cell_data(cell_data),
        .plot_we(plot_we), .plot_addr(plot_addr), .plot_data(plot_data),
        .requested_bank(requested_bank), .requested_market(requested_market),
        .front_bank_ui(front_bank),
        .hs(vga_hs), .vs(vga_vs), .red(vga_r), .green(vga_g), .blue(vga_b)
    );
endmodule
