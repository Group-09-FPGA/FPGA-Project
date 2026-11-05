`timescale 1ns/1ps
module tb_keyboard_controls;
    reg clk=0,reset_n=0,key_valid=0,key_shift=0;reg [7:0] key=0;
    wire [3:0] page;wire [2:0] focus,hash_way;wire stash_selected;
    wire [10:0] history_offset,slot_addr;wire [9:0] hash_set;wire [13:0] level_addr;
    keyboard_controls dut(.clk(clk),.reset_n(reset_n),.key_valid(key_valid),
        .key_shift(key_shift),.key(key),.page(page),.focus(focus),
        .history_offset(history_offset),.hash_set(hash_set),.hash_way(hash_way),
        .stash_selected(stash_selected),.slot_addr(slot_addr),.level_addr(level_addr));
    always #5 clk=~clk;
    task hit(input [7:0] code,input shift);
        begin
            @(negedge clk);key=code;key_shift=shift;key_valid=1;
            @(negedge clk);key_valid=0;key=0;key_shift=0;
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);reset_n=1;
        if(page!=0) $fatal(1,"Reset page");
        hit(8'h86,0); // F6 -> order slots (page 6)
        if(page!=6) $fatal(1,"F6 page");
        hit(8'h8f,0);hit(8'h8f,0);
        if(slot_addr!=2) $fatal(1,"Slot Right");
        hit(8'h85,0); // F5 skips the removed status page -> levels (page 5)
        if(page!=5) $fatal(1,"F5 page");
        hit("4",0);
        if(page!=3) $fatal(1,"Digit 4 page");
        // The old order-entry keys do nothing: no page 7, F7/F8/7/8 are ignored.
        hit(8'h87,0);hit(8'h88,0);hit("7",0);hit("8",0);
        if(page!=3) $fatal(1,"Order entry page still reachable");
        hit("2",0);
        if(page!=1) $fatal(1,"Digit 2 page");
        hit(8'h8a,0); // Enter on My Orders must not open anything
        if(page!=1) $fatal(1,"Enter changed page on My Orders");
        hit(8'h91,0);hit(8'h91,0);
        if(history_offset!=2) $fatal(1,"Orders scroll");
        hit("3",0); // hash table: arrows walk the 32x32 grid, Tab picks the way
        if(page!=2) $fatal(1,"Digit 3 page");
        hit(8'h8f,0);hit(8'h91,0);
        if(hash_set!=33) $fatal(1,"Hash grid Right+Down");
        hit(8'h8e,0);hit(8'h90,0);
        if(hash_set!=0) $fatal(1,"Hash grid Left+Up");
        hit(8'h8e,0);hit(8'h90,0);
        if(hash_set!=0) $fatal(1,"Hash grid clamps at 0");
        hit(8'h89,0);hit(8'h89,0);
        if(hash_way!=2) $fatal(1,"Hash Tab way");
        hit(8'h93,0);
        if(hash_set!=256) $fatal(1,"Hash PgDn");
        hit("5",0); // price levels: 32x32 grid of 8-step squares
        if(page!=5) $fatal(1,"Digit 5 page");
        hit(8'h8f,0);hit(8'h91,0);
        if(level_addr!=33) $fatal(1,"Levels grid Right+Down");
        hit(8'h93,0);
        if(level_addr!=289) $fatal(1,"Levels PgDn");
        hit("6",0); // order slots: 64x32 grid
        if(page!=6) $fatal(1,"Digit 6 page");
        hit(8'h8f,0);hit(8'h91,0);
        if(slot_addr!=67) $fatal(1,"Slots grid Right+Down");
        hit(8'h93,0);
        if(slot_addr!=579) $fatal(1,"Slots PgDn");
        hit("H",0);
        if(page!=8) $fatal(1,"H history");
        hit("1",0);
        if(page!=0) $fatal(1,"Digit 1 page");
        hit(8'h89,0);hit(8'h89,0);
        if(focus!=2) $fatal(1,"Market Tab focus");
        hit(8'h8a,0);
        if(page!=8) $fatal(1,"Enter on focused history link");
        $display("Read-only keyboard navigation passed");
        $finish;
    end
endmodule
