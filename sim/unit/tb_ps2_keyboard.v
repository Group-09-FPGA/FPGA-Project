`timescale 1ns/1ps
module tb_ps2_keyboard;
    reg clk=0,reset_n=0,ps2_clk=1,ps2_data=1;
    always #5 clk=~clk;
    wire valid,error,key_valid,shift,reconnect;
    wire [7:0] data,key;
    integer events=0,errors=0;
    ps2_receiver #(.CLK_HZ(1_000_000)) rx(
        .clk(clk),.reset_n(reset_n),.ps2_clk(ps2_clk),.ps2_data(ps2_data),
        .byte_valid(valid),.byte_data(data),.frame_error(error));
    ps2_key_decoder #(.CLK_HZ(1_000_000)) dec(
        .clk(clk),.reset_n(reset_n),.byte_valid(valid),.byte_data(data),
        .key_valid(key_valid),.key(key),.key_shift(shift),.reconnect(reconnect));
    always @(posedge clk) begin
        if(key_valid) events=events+1;
        if(error) errors=errors+1;
    end
    task bit_send(input value);
        begin
            ps2_data=value;repeat(15) @(negedge clk);
            ps2_clk=0;repeat(15) @(negedge clk);
            ps2_clk=1;repeat(15) @(negedge clk);
        end
    endtask
    task send(input [7:0] code,input bad_parity);
        integer j;
        begin
            bit_send(0);
            for(j=0;j<8;j=j+1) bit_send(code[j]);
            bit_send((~^code)^bad_parity);bit_send(1);
            ps2_data=1;repeat(20) @(negedge clk);
        end
    endtask
    initial begin
        repeat(8) @(negedge clk);reset_n=1;
        send(8'h16,0); // 1
        if(events!=1 || key!="1") $fatal(1,"digit make failed");
        send(8'h16,0); // repeated make suppressed
        if(events!=1) $fatal(1,"held key repeated");
        send(8'hf0,0);send(8'h16,0);send(8'h16,0);
        if(events!=2) $fatal(1,"break failed");
        send(8'h12,0);send(8'h0d,0);
        if(key!=8'h89 || !shift) $fatal(1,"Shift+Tab failed");
        send(8'he0,0);send(8'h75,0);
        if(key!=8'h90) $fatal(1,"extended arrow failed");
        send(8'h45,1);
        if(errors!=1 || events!=4) $fatal(1,"parity error accepted");
        send(8'haa,0);send(8'h16,0);
        if(events!=5) $fatal(1,"reconnect did not clear held key");
        $display("PS/2 framing, parity, repeat, break, Shift, extended code, reconnect passed");
        $finish;
    end
endmodule
