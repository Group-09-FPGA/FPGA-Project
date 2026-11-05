`timescale 1ns/1ps
module tb_keyboard_actions;
    reg clk=0,reset_n=0,key_valid=0,key_shift=0;
    reg [7:0] key=0;
    reg [607:0] hash_data=0;
    reg [46:0] slot_data=0;
    wire [2:0] action;
    wire [3:0] page;
    wire [2:0] focus;
    wire scan_busy,selected_valid,event_valid;
    wire [4:0] status;
    wire [255:0] event_data;
    always #5 clk=~clk;
    keyboard_controls dut(.clk(clk),.reset_n(reset_n),.key_valid(key_valid),
        .key_shift(key_shift),.key(key),.book_valid(1'b1),
        .price_base(32'd900000),.price_tick(32'd1000),
        .ram_paused(1'b0),.hash_data(hash_data),.stash_data(76'd0),.slot_data(slot_data),
        .page(page),.action(action),.side(),.focus(focus),.editing(),.focused_valid(),
        .form_text(),.form_lengths(),.form_cursors(),.price(),.quantity(),
        .order_id(),.new_id(),.history_offset(),.hash_set(),.hash_way(),
        .stash_selected(),.slot_addr(),.level_addr(),.free_offset(),
        .selected_valid(selected_valid),.scan_busy(scan_busy),.ram_hold(),.selected_id(),
        .status(status),.event_valid(event_valid),.event_data(event_data),.event_ready(1'b0));
    task hit(input [7:0] code,input shift);
        begin
            @(negedge clk);key=code;key_shift=shift;key_valid=1;
            @(negedge clk);key_valid=0;key=0;key_shift=0;
            repeat(80) @(negedge clk);
        end
    endtask
    task reset_form;
        begin
            reset_n=0;repeat(3) @(negedge clk);reset_n=1;
            hit(8'h87,0);
        end
    endtask
    task choose(input [7:0] letter);
        begin hit(letter,0);end
    endtask
    task add_fields;
        begin
            hit(8'h89,0);hit(8'h89,0);
            hit("9",0);hit("0",0);hit(".",0);hit("5",0);
            hit("0",0);hit("0",0);hit("0",0);
            hit(8'h89,0);hit("1",0);hit("0",0);hit("0",0);
            hit(8'h89,0);hit("B",0);hit("0",0);hit("0",0);hit("0",0);
            hit("0",0);hit("0",0);hit("0",0);hit("0",0);
        end
    endtask
    task browse;
        integer cycles;
        begin
            hit(8'h89,1); // Shift+Tab wraps Action to Orders list
            hit(8'h91,0); // Down finds first live hash way
            cycles=0;
            while(scan_busy && cycles<100) begin @(negedge clk);cycles=cycles+1;end
            if(!selected_valid || cycles>=100) $fatal(1,"FPGA RAM order browse failed");
        end
    endtask
    task check_event(input [7:0] letter,input [3:0] op,input existing);
        begin
            reset_form();choose(letter);
            if(existing) begin
                browse();
                if(op==5) begin
                    hit(8'h89,1); // New ID from Orders list
                    hit("C",0);hit("0",0);hit("0",0);hit("0",0);
                    hit("0",0);hit("0",0);hit("0",0);hit("0",0);
                end
            end else add_fields();
            hit(8'h8a,0);repeat(40) @(negedge clk);
            if(!event_valid || event_data[251:248]!=op)
                $fatal(1,"Action %c did not emit operation %d, status=%d",letter,op,status);
        end
    endtask
    initial begin
        hash_data[76+75]=1;
        hash_data[76+:64]=64'hb0000000;
        slot_data={1'b1,1'b0,13'd5,32'd100};
        check_event("A",1,0);
        check_event("F",1,0);
        check_event("E",2,1);
        check_event("C",2,1);
        check_event("X",3,1);
        check_event("D",4,1);
        check_event("U",5,1);
        reset_form();choose("E");browse();
        slot_data[31:0]=99; // network order changed after selection
        hit(8'h8a,0);repeat(10) @(negedge clk);
        if(event_valid || status!=8) $fatal(1,"Stale selection submitted");
        $display("All seven keyboard actions and stale-RAM rejection passed");
        $finish;
    end
endmodule
