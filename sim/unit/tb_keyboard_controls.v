`timescale 1ns/1ps
module tb_keyboard_controls;
    reg clk=0,reset_n=0,key_valid=0,key_shift=0;
    reg [7:0] key=0;
    reg ready=0;
    always #5 clk=~clk;
    wire [3:0] page;wire [2:0] action,focus;
    wire side,editing,focused_valid,event_valid;
    wire [511:0] text;
    wire [19:0] lengths,cursors;
    wire [31:0] price,qty;
    wire [63:0] oid,nid;
    wire [255:0] event_data;
    wire [4:0] status;
    keyboard_controls dut(.clk(clk),.reset_n(reset_n),.key_valid(key_valid),
        .key_shift(key_shift),.key(key),.book_valid(1'b1),
        .price_base(32'd900000),.price_tick(32'd1000),
        .ram_paused(1'b0),.hash_data(608'd0),.stash_data(76'd0),.slot_data(47'd0),
        .page(page),.action(action),.side(side),.focus(focus),.editing(editing),
        .focused_valid(focused_valid),.form_text(text),.form_lengths(lengths),
        .form_cursors(cursors),.price(price),.quantity(qty),.order_id(oid),.new_id(nid),
        .history_offset(),.hash_set(),.hash_way(),.stash_selected(),.slot_addr(),
        .level_addr(),.free_offset(),.selected_valid(),.scan_busy(),.selected_id(),
        .status(status),.event_valid(event_valid),.event_data(event_data),.event_ready(ready));
    task hit(input [7:0] code,input shift);
        begin
            @(negedge clk);key=code;key_shift=shift;key_valid=1;
            @(negedge clk);key_valid=0;key=0;key_shift=0;
            repeat(120) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);reset_n=1;
        hit(8'h87,0); // F7
        if(page!=7) $fatal(1,"F7 page");
        hit(8'h8b,0);hit(8'h85,0); // F5 skips the removed status page
        if(page!=5) $fatal(1,"F5 page");
        hit(8'h88,0); // F8 is unused
        if(page!=5) $fatal(1,"F8 changed page");
        hit(8'h87,0);
        hit(8'h89,0);hit(8'h89,0); // price
        hit("9",0);hit("0",0);hit(".",0);hit("5",0);
        hit("0",0);hit("0",0);hit("0",0);
        hit(8'h89,0); // quantity
        hit("1",0);hit("0",0);hit("0",0);
        hit(8'h89,0); // ID
        hit("B",0);hit("0",0);hit("0",0);hit("0",0);
        hit("0",0);hit("0",0);hit("0",0);hit("0",0);
        hit(8'h89,1);hit(8'h89,1); // back to price
        if(focus!=2) $fatal(1,"Tab focus");
        hit("1",0); // replaces old price; incomplete value
        if(price!=1 || focused_valid) $fatal(1,"First typed digit did not replace price");
        hit(8'h89,0); // invalid price blocks Tab
        if(focus!=2 || status!=3) $fatal(1,"Invalid Tab was not blocked");
        hit(8'h8b,0); // Escape restores
        if(price!=905000 || editing) $fatal(1,"Escape did not restore price");
        hit(8'h89,0); // quantity
        hit("2",0);hit("5",0);hit("0",0);
        if(qty!=250 || !focused_valid) $fatal(1,"Quantity text edit");
        hit(8'h8c,0);hit("0",0); // backspace, then 0 => 250
        if(qty!=250) $fatal(1,"Backspace repair");
        hit(8'h8b,0);
        if(qty!=100) $fatal(1,"Quantity Escape snapshot");
        repeat(10) hit("9",0);
        if(focused_valid) $fatal(1,"32-bit quantity overflow accepted");
        hit(8'h89,0);
        if(focus!=3 || status!=3) $fatal(1,"Overflow did not block Tab");
        hit(8'h8b,0);
        if(qty!=100) $fatal(1,"Overflow Escape restore failed");
        hit(8'h8a,0);
        repeat(40) @(negedge clk);
        if(!event_valid || event_data[251:248]!=1 || event_data[242:176]!=64'hb0000000 ||
           event_data[111:80]!=100 || event_data[79:67]!=5)
            $fatal(1,"Add event was not built from current form");
        ready=1;repeat(2) @(negedge clk);
        if(event_valid) $fatal(1,"Event did not hand off");
        $display("Keyboard form editing, Escape, validation, and Add submission passed");
        $finish;
    end
endmodule
