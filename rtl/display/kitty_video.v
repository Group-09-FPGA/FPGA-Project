`timescale 1ns/1ps
// Independent 720p pixel clock. Existing 50 MHz book/network and 25 MHz UI
// clocks remain unchanged. 100 * 37.125 / 5 / 10 = 74.25 MHz.
module kitty_pixel_clock (
    input wire clk100, reset_n,
    output wire pixel_clk, pixel_reset_n
);
    wire locked;
`ifdef SIMULATION
    assign pixel_clk=clk100;
    assign locked=reset_n;
`else
    wire feedback,feedback_buf,unbuffered;
    MMCME2_BASE #(.CLKIN1_PERIOD(10.0),.CLKFBOUT_MULT_F(37.125),
        .DIVCLK_DIVIDE(5),.CLKOUT0_DIVIDE_F(10.0),.BANDWIDTH("OPTIMIZED")) u_pixel_mmcm (
        .CLKIN1(clk100),.CLKFBIN(feedback_buf),.CLKFBOUT(feedback),.CLKFBOUTB(),
        .CLKOUT0(unbuffered),.CLKOUT0B(),.CLKOUT1(),.CLKOUT1B(),.CLKOUT2(),.CLKOUT2B(),
        .CLKOUT3(),.CLKOUT3B(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),
        .LOCKED(locked),.PWRDWN(1'b0),.RST(!reset_n)
    );
    BUFG fb(.I(feedback),.O(feedback_buf));
    BUFG px(.I(unbuffered),.O(pixel_clk));
`endif
    (* ASYNC_REG="TRUE" *) reg [3:0] reset_pipe;
    always @(posedge pixel_clk or negedge reset_n) begin
        if(!reset_n) reset_pipe<=0;
        else if(!locked) reset_pipe<=0;
        else reset_pipe<={reset_pipe[2:0],1'b1};
    end
    assign pixel_reset_n=reset_pipe[3];
endmodule

// Double-buffered 160x45 character terminal with anti-aliased 8x16 Geist Mono
// glyphs and per-pixel step charts. All buffers are written by the on-FPGA UI
// processor. The laptop never supplies pixels or reconstructed order state.
module kitty_video #(
    parameter FONT_FILE="kitty_font.hex"
) (
    input wire ui_clk,ui_reset_n,
    input wire pixel_clk,pixel_reset_n,
    input wire cell_we,
    input wire [13:0] cell_addr,
    input wire [15:0] cell_data,
    input wire plot_we,
    input wire [10:0] plot_addr,
    input wire [31:0] plot_data,
    input wire requested_bank,
    input wire requested_market,
    output wire front_bank_ui,
    output reg hs,vs,
    output reg [3:0] red,green,blue
);
`ifndef SYNTHESIS
    reg [15:0] cells[0:16383];
`endif
    (* ram_style="block" *) reg [31:0] plots[0:2047];
    (* rom_style="block" *) reg [31:0] font[0:4095];
    initial $readmemh(FONT_FILE,font);
    always @(posedge ui_clk) begin
`ifndef SYNTHESIS
        if(cell_we) cells[cell_addr]<=cell_data;
`endif
        if(plot_we) plots[plot_addr]<=plot_data;
    end
    wire [1:0] present_pixel;
    config_cdc #(.WIDTH(2)) u_present_cdc (
        .src_clk(ui_clk),.src_rst_n(ui_reset_n),.src_data({requested_market,requested_bank}),
        .src_busy(),.src_ready(),.dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),
        .dst_data(present_pixel),.dst_update()
    );
    reg front_bank,front_market,front_valid;
    (* ASYNC_REG="TRUE" *) reg front_meta_ui,front_sync_ui;
    always @(posedge ui_clk or negedge ui_reset_n) begin
        if(!ui_reset_n) begin front_meta_ui<=0;front_sync_ui<=0;end
        else begin front_meta_ui<=front_bank;front_sync_ui<=front_meta_ui;end
    end
    assign front_bank_ui=front_sync_ui;
    reg [10:0] x;
    reg [9:0] y;
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin
            x<=0;y<=0;
            front_bank<=0;front_market<=0;front_valid<=0;
        end else begin
            if(x==1649) begin x<=0;y<=y==749 ? 0 : y+1'b1;end
            else x<=x+1'b1;
            // The requested page flag is held with its bank until acknowledgement.
            if(x==0 && y==720) begin
                if(present_pixel[0]!=front_bank) front_valid<=1;
                front_bank<=present_pixel[0];front_market<=present_pixel[1];
            end
        end
    end
    wire active=x<1280 && y<720;
    wire hs_now=!(x>=1390 && x<1430);
    wire vs_now=!(y>=725 && y<730);
    wire [7:0] col=x[10:3];
    wire [5:0] row=y[9:4];
    wire [12:0] index=({7'd0,row}<<7)+({7'd0,row}<<5)+col;
    wire [8:0] local_x=x-104;
    wire is_ask=y>=384;
    wire [8:0] local_y=is_ask ? y-384 : y-80;
    wire chart=front_market && x>=104 && x<616 &&
        ((y>=80 && y<336) || (y>=384 && y<640));
`ifdef SYNTHESIS
    wire [15:0] char_q;
    xpm_memory_sdpram #(
        .MEMORY_SIZE(262144),.MEMORY_PRIMITIVE("block"),
        .CLOCKING_MODE("independent_clock"),.MEMORY_INIT_FILE("none"),
        .USE_MEM_INIT(0),.WRITE_DATA_WIDTH_A(16),.BYTE_WRITE_WIDTH_A(16),
        .ADDR_WIDTH_A(14),.READ_DATA_WIDTH_B(16),.ADDR_WIDTH_B(14),
        .READ_LATENCY_B(1),.WRITE_MODE_B("read_first")
    ) u_cells (
        .sleep(1'b0),.clka(ui_clk),.ena(1'b1),.wea(cell_we),
        .addra(cell_addr),.dina(cell_data),.injectsbiterra(1'b0),
        .injectdbiterra(1'b0),.clkb(pixel_clk),.rstb(1'b0),
        .enb(1'b1),.regceb(1'b1),.addrb({front_bank,index}),
        .doutb(char_q),.sbiterrb(),.dbiterrb()
    );
`else
    reg [15:0] char_q;
`endif
    reg [31:0] plot_q,font_q;
    reg [2:0] fx1,fx2;
    reg [3:0] fy1;
    reg [7:0] attributes2;
    reg active1,active2,hs1,hs2,vs1,vs2,chart1,chart2;
    reg [8:0] plot_y1,plot_y2;
    reg [31:0] plot2;
    always @(posedge pixel_clk) begin
`ifndef SYNTHESIS
        char_q<=cells[{front_bank,index}];
`endif
        plot_q<=plots[{front_bank,is_ask,local_x}];
        fx1<=x[2:0];fy1<=y[3:0];active1<=active;hs1<=hs_now;vs1<=vs_now;
        chart1<=chart;plot_y1<=local_y;
        font_q<=font[{char_q[7:0],fy1}];
        attributes2<=char_q[15:8];fx2<=fx1;active2<=active1;hs2<=hs1;vs2<=vs1;
        chart2<=chart1;plot_y2<=plot_y1;plot2<=plot_q;
    end
    function [11:0] palette;
        input [3:0] n;
        begin
            case(n)
                0:palette=12'heDF; // foreground #e0def4
                1:palette=12'h9CD; // Kitty color2 #9ccfd8 (rising)
                2:palette=12'he69; // Kitty color1 #eb6f92 (falling)
                3:palette=12'h768; // dim
                4:palette=12'hcAe;
                5:palette=12'hfc7;
                6:palette=12'h224;
                7:palette=12'h435; // selected row
                8:palette=12'h112; // background #191724
                9:palette=12'h323;
                default:palette=12'heDF;
            endcase
        end
    endfunction
    function [3:0] blend;
        input [3:0] foreground,background,alpha;
        reg [8:0] value;
        begin
            value=foreground*alpha + background*(5'd16-{1'b0,alpha});
            blend=alpha==15 ? foreground : value[7:4];
        end
    endfunction
    wire [3:0] coverage=(font_q >> ((7-fx2)*4)) & 4'hf;
    wire [11:0] foreground=palette(attributes2[3:0]);
    wire [11:0] background=palette(attributes2[7:4]);
    wire [8:0] hy=plot2[8:0],vlo=plot2[17:9],vhi=plot2[26:18];
    wire stroke=chart2 && plot2[28:27]!=3 &&
        ((hy<256 && plot_y2==hy) || (vlo<256 && vhi<256 && plot_y2>=vlo && plot_y2<=vhi));
    wire [11:0] trace_color=palette(plot2[28:27]==1 ? 4'd1 : plot2[28:27]==2 ? 4'd2 : 4'd0);
    always @(posedge pixel_clk or negedge pixel_reset_n) begin
        if(!pixel_reset_n) begin hs<=0;vs<=0;red<=0;green<=0;blue<=0;end
        else begin
            hs<=hs2;vs<=vs2;
            if(!active2 || !front_valid) begin red<=0;green<=0;blue<=0;end
            else if(stroke) begin red<=trace_color[11:8];green<=trace_color[7:4];blue<=trace_color[3:0];end
            else begin
                red<=blend(foreground[11:8],background[11:8],coverage);
                green<=blend(foreground[7:4],background[7:4],coverage);
                blue<=blend(foreground[3:0],background[3:0],coverage);
            end
        end
    end
endmodule
