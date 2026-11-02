`timescale 1ns/1ps
module tb_board_controls;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [13:2] sw=0;
    reg [4:0] btn=0;
    reg paused=0, ready=0, valid_book=1;
    wire [2:0] page, action, way;
    wire [1:0] field;
    wire side, edit_mode, browse, enabled, stash, selected, scanning;
    wire [3:0] digit;
    wire [4:0] status;
    wire [31:0] price,qty;
    wire [63:0] oid,noid,selected_id;
    wire [7:0] history;
    wire [9:0] set_idx;
    wire [10:0] slot,free_offset;
    wire [13:0] level;
    wire event_valid;
    wire [255:0] event_data;
    reg [607:0] hash_data=0;
    reg [75:0] stash_data=0;
    reg [46:0] slot_data=0;
    always @(posedge clk) begin
        hash_data <= set_idx==1 ? {532'd0,1'b1,11'd2047,64'd123} : 608'd0;
        stash_data <= {1'b1,11'd2046,64'd456};
        slot_data <= {1'b1,1'b0,13'd5,32'd100};
    end
    board_controls #(.DEBOUNCE_CYCLES(3)) dut (
        .clk(clk),.rst_n(rst_n),.switches(sw),.buttons(btn),.book_valid(valid_book),
        .price_base(32'd900000),.price_tick(32'd1000),.ram_paused(paused),
        .hash_data(hash_data),.stash_data(stash_data),.slot_data(slot_data),
        .page(page),.action(action),.field(field),.side(side),.edit_mode(edit_mode),
        .browse_mode(browse),.enabled(enabled),.digit(digit),.price(price),.quantity(qty),
        .order_id(oid),.new_id(noid),.history_offset(history),.hash_set(set_idx),.hash_way(way),
        .stash_selected(stash),.slot_addr(slot),.level_addr(level),.free_offset(free_offset),
        .selected_valid(selected),.scan_busy(scanning),.selected_id(selected_id),
        .status(status),.event_valid(event_valid),.event_data(event_data),.event_ready(ready)
    );
    task settle; begin repeat(10) @(negedge clk); end endtask
    task press_button(input integer b);
        begin btn=1<<b; settle; btn=0; settle; end
    endtask
    task ack;
        begin ready=1; @(negedge clk); ready=0; settle; end
    endtask
    task await_event(input [3:0] op);
        integer n;
        begin
            n=0;
            while(!event_valid && n<100) begin @(negedge clk); n=n+1; end
            if(!event_valid || event_data[251:248]!==op) $fatal(1,"Wrong/missing canonical op %d status %d",op,status);
        end
    endtask
    reg [255:0] held;
    integer a;
    initial begin
        settle; rst_n=1; settle;
        sw[4:2]=7; settle;
        press_button(4);
        if(status!==3 || event_valid) $fatal(1,"Disabled submit accepted");
        sw[13]=1; settle;
        // Short electrical bounce cannot submit.
        btn=16; @(negedge clk); btn=0; settle;
        if(event_valid) $fatal(1,"Button bounce submitted");
        btn=16; settle;
        await_event(1);
        if(event_data[79:67]!==13'd5 || event_data[111:80]!==100) $fatal(1,"Price division/layout wrong");
        held=event_data;
        sw[10]=1; settle;
        if(event_data!==held) $fatal(1,"Queued payload changed under backpressure");
        ack; settle;
        if(event_valid) $fatal(1,"Held Center duplicated an order");
        btn=0; settle;
        // F maps to canonical add, with switch-selected sell side.
        sw[7:5]=1; settle; press_button(4); await_event(1);
        if(!event_data[247]) $fatal(1,"Sell side ignored");
        ack;
        // Decimal edit produces an off-tick price; rejection must be local.
        sw[11]=1; sw[9:8]=0; settle; press_button(3);
        if(price!==905001) $fatal(1,"Decimal price editor failed");
        press_button(4); repeat(50) @(negedge clk);
        if(event_valid || status!==5) $fatal(1,"Off-tick price entered core");
        press_button(1);
        // Walk actual hash RAM, pausing if UART owns its read port.
        sw[12]=1; settle; paused=1; press_button(3);
        repeat(20) @(negedge clk);
        if(!scanning || selected) $fatal(1,"RAM preemption ignored");
        paused=0;
        repeat(100) @(negedge clk);
        if(!selected || oid!==123 || slot!==2047 || price!==905000) $fatal(1,"Active order browse failed");
        sw[12]=0; sw[9:8]=1; settle;
        // Select decimal tens then reduce 100 to 40.
        press_button(2);
        repeat(6) press_button(1);
        if(qty!==40) $fatal(1,"Quantity digit editor failed: %d",qty);
        sw[7:5]=2; settle;
        repeat(7) press_button(3);
        press_button(4);
        if(event_valid || status!==11) $fatal(1,"Over-reduction was not rejected locally");
        repeat(7) press_button(1);
        for(a=2;a<=6;a=a+1) begin
            sw[7:5]=a; settle; press_button(4);
            await_event(a<4 ? 2 : a==4 ? 3 : a==5 ? 4 : 5);
            if(event_data[239:176]!==123) $fatal(1,"Selected order ID lost");
            if(event_data[111:80]!== (a==5 ? 0 : 40)) $fatal(1,"Requested shares wrong");
            if(a==6 && event_data[79:67]!==5) $fatal(1,"Replacement price wrong");
            ack;
        end
        sw[7:5]=7; settle; press_button(4);
        if(status!==4 || event_valid) $fatal(1,"Reserved action submitted");
        valid_book=0; press_button(4);
        if(status!==7 || event_valid) $fatal(1,"Invalid book accepted an order");
        valid_book=1;
        sw[12]=1; settle; press_button(3);
        repeat(33000) @(negedge clk);
        if(!selected || oid!==456 || slot!==2046 || !stash) $fatal(1,"Collision stash browse failed");
        sw[12]=0;
        // Full event offset, level side switch and independent slot/free cursors.
        sw[4:2]=3; settle; repeat(5) press_button(3);
        if(history!==5) $fatal(1,"Event navigation failed");
        sw[4:2]=5; settle; press_button(0); press_button(3);
        if(level!==14'h2001) $fatal(1,"Level side/index navigation failed");
        sw[4:2]=6; settle; press_button(0);
        if(free_offset!==1) $fatal(1,"Free stack cursor failed");
        $display("PASS board controls: debounce, seven actions, price/quantity digits, browse, backpressure and pages");
        $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
