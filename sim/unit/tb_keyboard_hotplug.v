`timescale 1ns/1ps
module tb_keyboard_hotplug;
    reg clk=0,reset_n=0,byte_valid=0;
    reg [7:0] byte_data=0;
    always #5 clk=~clk;
    wire key_valid,key_shift,reconnect,editing;
    wire [7:0] key;
    wire [3:0] page;
    wire [2:0] focus;
    wire [31:0] price;
    ps2_key_decoder #(.CLK_HZ(1000)) dec(.clk(clk),.reset_n(reset_n),
        .byte_valid(byte_valid),.byte_data(byte_data),
        .key_valid(key_valid),.key(key),.key_shift(key_shift),.reconnect(reconnect));
    keyboard_controls form(.clk(clk),.reset_n(reset_n),.key_valid(key_valid),
        .key_shift(key_shift),.key(key),.book_valid(1'b1),
        .price_base(32'd900000),.price_tick(32'd1000),.ram_paused(1'b0),
        .hash_data(608'd0),.stash_data(76'd0),.slot_data(47'd0),
        .page(page),.action(),.side(),.focus(focus),.editing(editing),
        .focused_valid(),.form_text(),.form_lengths(),.form_cursors(),
        .price(price),.quantity(),.order_id(),.new_id(),.history_offset(),
        .hash_set(),.hash_way(),.stash_selected(),.slot_addr(),.level_addr(),
        .free_offset(),.selected_valid(),.scan_busy(),.ram_hold(),.selected_id(),
        .status(),.event_valid(),.event_data(),.event_ready(1'b0));
    task send(input [7:0] code);
        begin
            @(negedge clk);byte_valid=1;byte_data=code;
            @(negedge clk);byte_valid=0;byte_data=0;
            repeat(80) @(negedge clk);
        end
    endtask
    task release_key(input [7:0] code);
        begin send(8'hf0);send(code);end
    endtask
    initial begin
        repeat(3) @(negedge clk);reset_n=1;
        send(8'h0a); // F8
        send(8'h0d);release_key(8'h0d);
        send(8'h0d);release_key(8'h0d); // price focus
        send(8'h16); // first digit replaces old price
        if(page!=7 || focus!=2 || price!=1 || !editing) $fatal(1,"Pre-unplug edit wrong");
        send(8'haa); // PIC self-test after reconnect
        if(page!=7 || focus!=2 || price!=1 || !editing) $fatal(1,"Reconnect reset form");
        send(8'h16); // the old held bitmap must be cleared by BAT
        if(price!=11) $fatal(1,"Reconnected key remained stuck");
        $display("Reconnect preserves form, cursor/focus and clears held key");
        $finish;
    end
endmodule
