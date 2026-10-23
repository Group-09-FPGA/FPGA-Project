`timescale 1ns/1ps
// Accepted Python-model events are compared against the RTL after each commit.
// The single rejected model event is skipped because the RTL intentionally
// enters fail-stop on an invalid order, while the Python model continues.
module tb_lob_golden;
reg clk=0; always #10 clk=~clk;
reg rst_n=0, valid=0; reg [255:0] data=0;
wire ready,book_valid,init_done,busy,error_valid,event_done,bid_valid,ask_valid;
wire [7:0] error_code; wire [11:0] active;
wire [31:0] bp,bq,ap,aq;
reg [255:0] events[0:30]; reg [255:0] rejected[0:0];
reg [140:0] expected[0:30];
integer i,wait_cycles;
lob_core #(.DEFAULT_PRICE_BASE(32'd900000),.DEFAULT_TICK(32'd1000)) dut (
 .clk(clk),.rst_n(rst_n),.event_valid(valid),.event_ready(ready),.event_data(data),
 .cfg_clear(1'b0),.cfg_fail_stop_en(1'b1),.run_enable(1'b1),.feed_fault(1'b0),
 .cfg_price_base(32'd900000),.cfg_tick(32'd1000),.book_valid(book_valid),.init_done(init_done),.busy(busy),.error_valid(error_valid),.error_code(error_code),.active_order_count(active),.event_done(event_done),
 .best_bid_valid(bid_valid),.best_bid_price(bp),.best_bid_qty(bq),.best_ask_valid(ask_valid),.best_ask_price(ap),.best_ask_qty(aq));
initial begin
 $readmemh("golden_events.hex",events); $readmemh("golden_expected.hex",expected);
 $readmemh("golden_rejected.hex",rejected);
 repeat(3) @(negedge clk); rst_n=1;
 wait(init_done); repeat(3) @(negedge clk);
 for(i=0;i<31;i=i+1) begin
  data=events[i];valid=1;
  wait_cycles=0;
  @(posedge clk); while(!ready) begin @(posedge clk); wait_cycles=wait_cycles+1; if(wait_cycles>10000) $fatal(1,"ready timeout %0d",i); end
  @(negedge clk); valid=0;
  wait_cycles=0;
  while(!event_done) begin @(negedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>10000) $fatal(1,"done timeout %0d",i);end
  repeat(8) @(negedge clk);
  if(error_valid || book_valid!==expected[i][140] || active!==expected[i][139:128] || bp!==expected[i][127:96] || bq!==expected[i][95:64] || ap!==expected[i][63:32] || aq!==expected[i][31:0]) begin
   $display("step %0d err=%0d active=%0d bp=%0d bq=%0d ap=%0d aq=%0d",i+1,error_code,active,bp,bq,ap,aq);
   $display("expect active=%0d bp=%0d bq=%0d ap=%0d aq=%0d",expected[i][139:128],expected[i][127:96],expected[i][95:64],expected[i][63:32],expected[i][31:0]);
   $fatal(1,"golden mismatch");end
 end
 // Rebuild the first four orders, then exercise the model's rejected duplicate.
 @(negedge clk); rst_n=0;
 repeat(3) @(negedge clk); rst_n=1;
 wait(init_done); repeat(3) @(negedge clk);
 for(i=0;i<4;i=i+1) begin
  data=events[i];valid=1;
  wait_cycles=0;
  @(posedge clk); while(!ready) begin @(posedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>10000) $fatal(1,"replay ready timeout %0d",i);end
  @(negedge clk);valid=0;
  wait_cycles=0;
  while(!event_done) begin @(negedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>10000) $fatal(1,"replay done timeout %0d",i);end
  repeat(8) @(negedge clk);
 end
 data=rejected[0];valid=1;
 wait_cycles=0;
 @(posedge clk); while(!ready) begin @(posedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>10000) $fatal(1,"duplicate ready timeout");end
 @(negedge clk);valid=0;
 wait_cycles=0;
 while(!error_valid) begin @(negedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>10000) $fatal(1,"duplicate error timeout");end
 repeat(8) @(negedge clk);
 if(book_valid!==1'b0 || ready!==1'b0 || active!==12'd4 || error_code!==8'h02)
  $fatal(1,"duplicate did not fail-stop: valid=%b ready=%b active=%0d code=%h",book_valid,ready,active,error_code);
 $display("PASS: 31 valid golden-model events match RTL; duplicate order fail-stops");$finish;
end
endmodule
