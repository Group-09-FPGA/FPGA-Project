`timescale 1ns / 1ps

// Board LEDs and the 8-digit seven-segment display.
// SW14/SW15 (sw[1:0]) select: 00 best bid, 01 best ask,
// 10 active orders + events, 11 received frames + CPU program counter.
module board_status (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [1:0]   sw,

    input  wire         mmcm_locked,
    input  wire         eth_phy_rst_n,
    input  wire         eth_crsdv,
    input  wire         init_done,
    input  wire         book_valid,
    input  wire         bid_valid,
    input  wire         ask_valid,
    input  wire         busy,
    input  wire         error_valid,
    input  wire [7:0]   error_code,
    input  wire         event_pending,
    input  wire [351:0] net_diag,
    input  wire [31:0]  bid_price,
    input  wire [31:0]  ask_price,
    input  wire [11:0]  active_orders,
    input  wire [31:0]  event_count,
    input  wire [31:0]  cpu_pc,

    output wire [15:0]  led,
    output wire [7:0]   an,
    output wire [6:0]   seg,
    output wire         dp
);
    assign led[0]     = mmcm_locked;
    assign led[1]     = eth_phy_rst_n;
    assign led[2]     = init_done;
    assign led[3]     = book_valid;
    assign led[4]     = bid_valid;
    assign led[5]     = ask_valid;
    assign led[6]     = busy;
    assign led[7]     = error_valid;
    assign led[8]     = eth_crsdv;
    assign led[9]     = event_pending;
    assign led[10]    = net_diag[1];                      // sequence gap seen
    assign led[11]    = net_diag[319:288] != 32'd0;       // CRC errors
    assign led[15:12] = error_valid ? error_code[3:0] : active_orders[3:0];

    reg [31:0] value;
    always @(*) begin
        case (sw)
            2'b00:   value = bid_price;
            2'b01:   value = ask_price;
            2'b10:   value = {4'h0, active_orders, event_count[15:0]};
            default: value = {net_diag[351:336], cpu_pc[15:0]};
        endcase
    end

    wire price_mode = (sw == 2'b00 || sw == 2'b01);

    seven_seg_driver #(.CLK_FREQ_HZ(50_000_000)) u_seven_seg (
        .clk(clk), .reset(rst_n), .value(value),
        .format(price_mode ? 2'b01 : 2'b10),
        .point_mask(price_mode ? 8'b0001_0000 : 8'b0),
        .an(an), .seg(seg), .dp(dp)
    );
endmodule
