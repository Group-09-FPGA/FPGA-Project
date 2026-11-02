`timescale 1ns/1ps
module tb_board_ui_text;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg [5:0] col=0;
    reg [4:0] row=0;
    reg [2:0] page=7;
    wire [7:0] ch;
    wire hi;
    board_ui_text dut(
        .clk(clk),.rst_n(rst_n),.col(col),.row(row),.page(page),.action(3'd0),.hash_way(3'd0),
        .field(2'd0),.side(1'b0),.edit_mode(1'b1),.browse_mode(1'b0),.enabled(1'b1),
        .selected_valid(1'b1),.scan_busy(1'b0),.stash(1'b0),.digit(4'd3),.status(5'd0),
        .price(32'd905000),.quantity(32'd100),.price_base(32'd900000),.price_tick(32'd1000),
        .order_id(64'hB0000000),.new_id(64'hC0000000),.selected_id(64'd123),
        .hash_set(10'd123),.slot_addr(11'd2047),.free_offset(11'd0),.level_addr(14'd5),.history_offset(8'd0),
        .hash_data({532'd0,1'b1,11'd2047,64'd123}),.stash_data(76'd0),
        .slot_data({1'b1,1'b0,13'd5,32'd100}),.level_qty(32'd100),.level_count(12'd1),.free_data(11'd2046),
        .active_orders(12'd1),
        .event_data({32'd6,1'b0,32'd40,13'd5,
            ((316'd1<<315)|(316'd2<<311)|(316'd123<<247))}),.event_visible(1'b1),
        .rx_count(32'd14),.udp_count(32'd6),.mold_count(32'd6),.itch_count(32'd6),.fifo_count(32'd6),
        .completed(32'd6),.book_valid(1'b1),.error_code(8'd0),.character(ch),.highlight(hi)
    );
    // Reuse the actual FPGA font to make simulation previews.
    vga_top font_reference();
    integer p,r,c,y,f,g;
    reg [255:0] filename;
    task expect_char(input [4:0] r0,input [5:0] c0,input [7:0] expected);
        begin row=r0; col=c0; #1;
            if(ch!==expected) $fatal(1,"Text %d,%d: expected %h got %h",r0,c0,expected,ch);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        repeat(250) @(negedge clk);
        expect_char(5,15,"$"); expect_char(5,20,"9"); expect_char(5,22,"."); expect_char(5,23,"5");
        expect_char(7,22,"1"); expect_char(6,23,"^");
        expect_char(9,23,"B"); expect_char(18,9,"R");
        for(p=1;p<=7;p=p+1) begin
            page=p; repeat(250) @(negedge clk);
            $sformat(filename,"ui_page%0d.txt",p); f=$fopen(filename,"w");
            $sformat(filename,"ui_page%0d.glyph",p); g=$fopen(filename,"w");
            if(!f || !g) $fatal(1,"Cannot write preview");
            for(r=0;r<30;r=r+1) begin
                row=r;
                for(c=0;c<40;c=c+1) begin
                    col=c; #1; $fwrite(f,"%c",ch);
                    for(y=0;y<8;y=y+1) $fwrite(g,"%02h\n",font_reference.font_lookup(ch,y));
                end
                $fwrite(f,"\n");
            end
            $fclose(f);$fclose(g);
        end
        $display("PASS VGA page text, decimal editor, digit cursor and font previews");
        $finish;
    end
endmodule
