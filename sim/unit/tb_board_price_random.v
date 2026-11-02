`timescale 1ns/1ps
// Exercise the actual button editor and serial price conversion using runtime
// configuration and prices outside the demo's constants. No internal force.
module tb_board_price_random;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [13:2] sw=0;
    reg [4:0] btn=0;
    reg [31:0] base=900000,tick=1000;
    reg ready=0;
    wire [31:0] price,qty;
    wire valid;
    wire [255:0] data;
    wire [4:0] status;
    board_controls #(.DEBOUNCE_CYCLES(1)) dut(
        .clk(clk),.rst_n(rst_n),.switches(sw),.buttons(btn),.book_valid(1'b1),
        .price_base(base),.price_tick(tick),.ram_paused(1'b0),
        .hash_data(608'd0),.stash_data(76'd0),.slot_data(47'd0),
        .price(price),.quantity(qty),.event_valid(valid),.event_data(data),.event_ready(ready),.status(status)
    );
    task settle; begin repeat(7) @(negedge clk); end endtask
    task hit(input integer button);
        begin btn=1<<button; settle; btn=0; settle; end
    endtask
    task enter_decimal(input [1:0] f,input [31:0] target);
        reg [31:0] step,current;
        integer position,want,have,difference,j;
        begin
            // Switching fields resets the cursor through public switches.
            sw[9:8]=f==0 ? 1 : 0; settle;
            sw[9:8]=f; settle;
            step=1;
            for(position=0;position<10;position=position+1) begin
                current=f==0 ? price : qty;
                want=(target/step)%10; have=(current/step)%10;
                difference=want-have;
                for(j=0;j<(difference<0 ? -difference : difference);j=j+1)
                    hit(difference<0 ? 1 : 3);
                if(position<9) begin hit(2);step=step*10;end
            end
            current=f==0 ? price : qty;
            if(current!==target) $fatal(1,"Public digit editor failed: %d != %d",current,target);
        end
    endtask
    integer trial,seed=32'h1A87C249,n;
    reg [31:0] sample,shares,target;
    reg [12:0] index;
    initial begin
        settle;rst_n=1;settle;
        sw[4:2]=7;sw[13]=1;sw[11]=1;settle;
        for(trial=0;trial<64;trial=trial+1) begin
            sample=$random(seed);base=sample%1000000;
            sample=$random(seed);tick=1+sample%10000;
            sample=$random(seed);index=trial==0 ? 0 : trial==1 ? 8191 : sample[12:0];
            target=base+tick*index;
            sample=$random(seed);shares=1+sample%1000000;
            sw[10]=sample[31];sw[7:5]=trial[0];settle;
            enter_decimal(0,target);enter_decimal(1,shares);
            hit(4);n=0;
            while(!valid && n<100) begin @(negedge clk);n=n+1;end
            if(!valid || data[79:67]!==index || data[111:80]!==shares ||
               data[247]!==sw[10] || data[251:248]!==1)
                $fatal(1,"Random configuration %d failed: base %d tick %d pidx %d status %d",trial,base,tick,index,status);
            ready=1;@(negedge clk);ready=0;settle;
        end
        // The same datapath must reject an index beyond capacity.
        enter_decimal(0,base+tick*8192);hit(4);repeat(50) @(negedge clk);
        if(valid || status!==5) $fatal(1,"Out-of-range price accepted");
        $display("PASS 64 randomized runtime bases/ticks/prices/shares/sides through physical button interface");
        $finish;
    end
    initial begin #50000000;$fatal(1,"timeout");end
endmodule
