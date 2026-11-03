`timescale 1ns/1ps
module tb_kitty_preview;
    reg clk=0,pixel_clk=0,reset_n=0;
    always #20 clk=~clk;
    always #5 pixel_clk=~pixel_clk;
    reg [2047:0] registers=0;
    wire ram_request,ram_grant,cell_we,plot_we,requested_bank,requested_market;
    wire [3:0] ram_kind;
    wire [13:0] ram_address,cell_addr;
    wire [15:0] cell_data;
    wire [10:0] plot_addr;
    wire [31:0] plot_data,frames,pc;
    wire exception,front_bank,hs,vs;
    wire [3:0] red,green,blue;
    reg [174:0] quotes[0:3];
    wire [607:0] ram_data=ram_kind==7 ? {{433{1'b0}},quotes[ram_address[1:0]]} : 608'd0;
    assign ram_grant=ram_request;
    kitty_ui_cpu cpu(.clk(clk),.reset_n(reset_n),.registers(registers),
        .ram_request(ram_request),.ram_kind(ram_kind),.ram_address(ram_address),
        .ram_grant(ram_grant),.ram_data(ram_data),
        .cell_we(cell_we),.cell_addr(cell_addr),.cell_data(cell_data),
        .plot_we(plot_we),.plot_addr(plot_addr),.plot_data(plot_data),
        .requested_bank(requested_bank),.requested_market(requested_market),
        .front_bank(front_bank),.completed_frames(frames),.exception(exception),.pc(pc));
    kitty_video video(.ui_clk(clk),.ui_reset_n(reset_n),
        .pixel_clk(pixel_clk),.pixel_reset_n(reset_n),
        .cell_we(cell_we),.cell_addr(cell_addr),.cell_data(cell_data),
        .plot_we(plot_we),.plot_addr(plot_addr),.plot_data(plot_data),
        .requested_bank(requested_bank),.requested_market(requested_market),
        .front_bank_ui(front_bank),.hs(hs),.vs(vs),.red(red),.green(green),.blue(blue));
    integer file,expected=0,page_select=0,k;
    reg [127:0] form[0:3];
    initial begin
        if(!$value$plusargs("PAGE=%d",page_select)) page_select=0;
        registers[0*32+:32]=page_select==7 ? (7 | (2<<4) | (1<<12)) : page_select;
        form[0]="90.5000         ";form[1]="100             ";
        form[2]="B0000000        ";form[3]="C0000000        ";
        registers[1*32+:32]=7 | (3<<5) | (8<<10) | (8<<15);
        registers[2*32+:32]=7 | (3<<5) | (8<<10) | (8<<15);
        for(k=0;k<4;k=k+1) begin
            registers[(33+k*4+0)*32+:32]=form[k][127:96];
            registers[(33+k*4+1)*32+:32]=form[k][95:64];
            registers[(33+k*4+2)*32+:32]=form[k][63:32];
            registers[(33+k*4+3)*32+:32]=form[k][31:0];
        end
        registers[15*32+:32]=7; // valid book, bid, ask
        registers[16*32+:32]=905000;
        registers[17*32+:32]=100;
        registers[18*32+:32]=910000;
        registers[19*32+:32]=200;
        registers[20*32+:32]=2;
        registers[21*32+:32]=2;
        registers[30*32+:32]=900000;
        registers[31*32+:32]=1000;
        registers[32*32+:32]=32'h00000404; // four FPGA-journal fixture samples
        quotes[0]={1'b1,1'b1,32'd901000,32'd100,1'b1,32'd911000,32'd200,12'd2,32'd1};
        quotes[1]={1'b1,1'b1,32'd903000,32'd100,1'b1,32'd910000,32'd200,12'd2,32'd2};
        quotes[2]={1'b1,1'b1,32'd902000,32'd100,1'b1,32'd912000,32'd200,12'd2,32'd3};
        quotes[3]={1'b1,1'b1,32'd905000,32'd100,1'b1,32'd913000,32'd200,12'd2,32'd4};
        #100;reset_n=1;
        wait(frames!=0);
        wait(video.front_bank==1);
        wait(video.x==0 && video.y==0);
        file=$fopen(page_select==7 ? "kitty_entry.ppm" : "kitty_market.ppm","wb");
        $fwrite(file,"P6\n1280 720\n255\n");
        while(expected<1280*720) begin
            @(posedge pixel_clk);#1;
            if(video.x<1280 && video.y<720) begin
                $fwrite(file,"%c%c%c",{red,red},{green,green},{blue,blue});
                expected=expected+1;
            end
        end
        $fclose(file);
        $display("Rendered %0d VGA pixels, frames=%0d PC=%h exception=%b",expected,frames,pc,exception);
        $finish;
    end
    initial begin #100000000;$fatal(1,"Renderer preview timed out: frames=%0d PC=%h exception=%b",frames,pc,exception);end
endmodule
