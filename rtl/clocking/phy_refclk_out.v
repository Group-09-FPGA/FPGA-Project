`timescale 1ns / 1ps

// Drives the 50 MHz reference clock to the Ethernet PHY pin.
module phy_refclk_out (
    input  wire clk_phy,
    input  wire clk_eth,
    output wire refclk
);
`ifdef SIMULATION
    assign refclk = clk_eth;
`else
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("SYNC")) u_oddr (
        .Q(refclk), .C(clk_phy), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0)
    );
`endif
endmodule
