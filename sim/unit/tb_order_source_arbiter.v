`timescale 1ns/1ps
module tb_order_source_arbiter;
    reg clk=0,rst_n=0,ready=0;
    always #5 clk=~clk;
    reg nv=0,bv=0;
    reg [255:0] nd=0,bd=0;
    wire nr,br,valid;
    wire [255:0] data;
    order_source_arbiter dut(.clk(clk),.rst_n(rst_n),.net_valid(nv),.local_valid(bv),
        .net_data(nd),.local_data(bd),.net_ready(nr),.local_ready(br),
        .valid(valid),.data(data),.ready(ready));
    integer n=0,b=0,cycles=0;
    reg held=0;
    reg [255:0] previous;
    always @(posedge clk) if(rst_n) begin
        if(held && (!valid || data!==previous)) $fatal(1,"Payload changed during stall");
        held=valid && !ready; previous=data;
        if(valid && ready) begin
            if(data[255]) begin
                if(data[31:0]!==b) $fatal(1,"Local event lost/reordered");
                b=b+1;
            end else begin
                if(data[31:0]!==n) $fatal(1,"Network event lost/reordered");
                n=n+1;
            end
        end
    end
    initial begin
        repeat(3) @(negedge clk); rst_n=1; nv=1; nd=0;
        repeat(3) @(negedge clk); bv=1; bd={1'b1,255'd0};
        repeat(3) @(negedge clk);
        while(n<40 || b<40) begin
            @(negedge clk);
            nv=n<40; bv=b<40; nd=n; bd={1'b1,223'd0,b[31:0]};
            ready=($random & 3)!=0;
            cycles=cycles+1;
            if(cycles>500) $fatal(1,"Arbiter stalled/starved");
        end
        @(negedge clk); nv=0; bv=0;
        $display("PASS mixed order sources: 80 events, backpressure, stability and source ordering");
        $finish;
    end
endmodule
