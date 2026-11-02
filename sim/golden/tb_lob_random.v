`timescale 1ns/1ps
module tb_lob_random;
    reg clk=0,rst_n=0,valid=0;
    always #10 clk=~clk;
    reg [255:0] data=0;
    wire ready,init_done,book_valid,error_valid,done;
    wire [7:0] error_code;
    wire [11:0] active;
    wire [31:0] bp,bq,ap,aq;
    reg [255:0] events[0:511];
    reg [140:0] expected[0:511];
    integer i,cycles;
    lob_core #(.DEFAULT_PRICE_BASE(123456),.DEFAULT_TICK(37)) dut(
        .clk(clk),.rst_n(rst_n),.event_valid(valid),.event_ready(ready),.event_data(data),
        .cfg_clear(1'b0),.cfg_fail_stop_en(1'b1),.run_enable(1'b1),.feed_fault(1'b0),
        .cfg_price_base(32'd123456),.cfg_tick(32'd37),.book_valid(book_valid),.init_done(init_done),
        .error_valid(error_valid),.error_code(error_code),.active_order_count(active),.event_done(done),
        .best_bid_price(bp),.best_bid_qty(bq),.best_ask_price(ap),.best_ask_qty(aq)
    );
    initial begin
        $readmemh("random_events.hex",events);$readmemh("random_expected.hex",expected);
        repeat(3) @(negedge clk);rst_n=1;wait(init_done);repeat(3) @(negedge clk);
        for(i=0;i<512;i=i+1) begin
            data=events[i];valid=1;cycles=0;
            @(posedge clk);
            while(!ready) begin @(posedge clk);cycles=cycles+1;if(cycles>10000)$fatal(1,"ready timeout");end
            @(negedge clk);valid=0;cycles=0;
            while(!done && !error_valid) begin @(negedge clk);cycles=cycles+1;if(cycles>10000)$fatal(1,"done timeout");end
            repeat(8) @(negedge clk);
            if(error_valid || {book_valid,active,bp,bq,ap,aq}!==expected[i]) begin
                $display("Random event %d op %d err %h",i+1,events[i][251:248],error_code);
                $display("actual   %h",{book_valid,active,bp,bq,ap,aq});
                $display("expected %h",expected[i]);
                $fatal(1,"Independent random book mismatch");
            end
        end
        $display("PASS 512 randomized LOB operations match independent book after every commit (non-demo base/tick)");
        $finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
