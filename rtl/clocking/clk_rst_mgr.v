// =============================================================================
// File: clk_rst_mgr.v
// Description: Clock Generation and Reset Management Module
//              Generates:
//                - clk_core:  50.0 MHz (Core CPU, LOB accelerator, memory bus)
//                - clk_eth:   50.0 MHz (RMII PHY refclk and network pipeline)
//                - clk_vga:   25.0 MHz (VGA 640x480 @ 60Hz pixel clock)
//              Provides glitch-free asynchronous-assert, synchronous-deassert
//              reset trees and LAN8720A PHY hardware power-up reset sequence.
// Target: AMD/Xilinx Artix-7 XC7A100T-1CSG324C
// =============================================================================

`timescale 1ns / 1ps

module clk_rst_mgr #(
    parameter SIM_BYPASS = 1'b0  // Set 1 in testbench to bypass MMCM lock wait
) (
    // Physical Board Pins
    input  wire clk_100mhz_in,       // 100.0 MHz oscillator (pin E3)
    input  wire rst_btn_n,           // CPU_RESETN push button (pin C12, active-low)

    // Derived Clock Outputs
    output wire clk_core,            // 50.0 MHz
    output wire clk_eth,             // 50.0 MHz (to RMII internal logic)
    output wire clk_eth_phy,         // 50.0 MHz, 45-deg phase shifted (to pin D5 via ODDR)
    output wire clk_vga,             // 25.0 MHz (to VGA DAC)

    // Synchronized Active-Low Resets
    output wire rst_core_n,          // Synchronized to clk_core
    output wire rst_eth_n,           // Synchronized to clk_eth
    output wire rst_vga_n,           // Synchronized to clk_vga

    // External PHY Reset
    output reg  phy_rst_n,           // Dedicated pin B3 to LAN8720A PHY

    // Diagnostics
    output wire mmcm_locked
);

`ifdef SIMULATION
    // =========================================================================
    // Simulation Clock Generator (Immediate lock, deterministic behavioral RTL)
    // =========================================================================
    assign clk_core = clk_100mhz_in;

    reg clk_50_reg = 1'b0;
    always @(posedge clk_100mhz_in or negedge rst_btn_n) begin
        if (!rst_btn_n)
            clk_50_reg <= 1'b0;
        else
            clk_50_reg <= ~clk_50_reg;
    end
    assign clk_eth     = clk_50_reg;
    assign clk_eth_phy = clk_50_reg;

    reg [1:0] clk_25_cnt = 2'b0;
    always @(posedge clk_100mhz_in or negedge rst_btn_n) begin
        if (!rst_btn_n)
            clk_25_cnt <= 2'b0;
        else
            clk_25_cnt <= clk_25_cnt + 1'b1;
    end
    assign clk_vga = clk_25_cnt[1];

    assign mmcm_locked = 1'b1;

`else
    // =========================================================================
    // Hardware Xilinx 7-Series MMCM Primitive
    // =========================================================================
    wire clkfbout, clkfbout_buf;
    wire clk_core_unbuf, clk_eth_unbuf, clk_eth_phy_unbuf, clk_vga_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(10.000),      // VCO = 100 MHz * 10 = 1000.0 MHz
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.000),        // Input = 100.0 MHz (10.0 ns)
        .CLKOUT0_DIVIDE_F(20.000),     // CLKOUT0 = 1000 / 20 = 50.0 MHz
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(20),           // CLKOUT1 = 1000 / 20 = 50.0 MHz (Internal MAC)
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(0.0),
        .CLKOUT2_DIVIDE(40),           // CLKOUT2 = 1000 / 40 = 25.0 MHz (VGA)
        .CLKOUT2_DUTY_CYCLE(0.5),
        .CLKOUT2_PHASE(0.0),
        .CLKOUT3_DIVIDE(20),           // CLKOUT3 = 1000 / 20 = 50.0 MHz (External LAN8720A PHY)
        .CLKOUT3_DUTY_CYCLE(0.5),
        .CLKOUT3_PHASE(45.0),          // 45.0 deg phase shift per Digilent Nexys A7 manual
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKOUT0   (clk_core_unbuf),
        .CLKOUT0B  (),
        .CLKOUT1   (clk_eth_unbuf),
        .CLKOUT1B  (),
        .CLKOUT2   (clk_vga_unbuf),
        .CLKOUT2B  (),
        .CLKOUT3   (clk_eth_phy_unbuf),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .CLKOUT6   (),
        .CLKFBOUT  (clkfbout),
        .CLKFBOUTB (),
        .LOCKED    (mmcm_locked),
        .CLKIN1    (clk_100mhz_in),
        .PWRDWN    (1'b0),
        .RST       (!rst_btn_n),
        .CLKFBIN   (clkfbout_buf)
    );

    BUFG u_bufg_fb   (.I(clkfbout),          .O(clkfbout_buf));
    BUFG u_bufg_core (.I(clk_core_unbuf),    .O(clk_core));
    BUFG u_bufg_eth  (.I(clk_eth_unbuf),     .O(clk_eth));
    BUFG u_bufg_phy  (.I(clk_eth_phy_unbuf), .O(clk_eth_phy));
    BUFG u_bufg_vga  (.I(clk_vga_unbuf),     .O(clk_vga));

`endif

    // =========================================================================
    // Synchronous Reset Deassertion Generator (per clock domain)
    // =========================================================================
    wire global_rst_condition = rst_btn_n && mmcm_locked;

    // Core Domain Reset Synchronizer
    (* ASYNC_REG = "TRUE" *) reg [3:0] rst_core_sync;
    always @(posedge clk_core or negedge global_rst_condition) begin
        if (!global_rst_condition)
            rst_core_sync <= 4'b0000;
        else
            rst_core_sync <= {rst_core_sync[2:0], 1'b1};
    end
    assign rst_core_n = rst_core_sync[3];

    // Ethernet Domain Reset Synchronizer
    (* ASYNC_REG = "TRUE" *) reg [3:0] rst_eth_sync;
    always @(posedge clk_eth or negedge global_rst_condition) begin
        if (!global_rst_condition)
            rst_eth_sync <= 4'b0000;
        else
            rst_eth_sync <= {rst_eth_sync[2:0], 1'b1};
    end
    assign rst_eth_n = rst_eth_sync[3];

    // VGA Domain Reset Synchronizer
    (* ASYNC_REG = "TRUE" *) reg [3:0] rst_vga_sync;
    always @(posedge clk_vga or negedge global_rst_condition) begin
        if (!global_rst_condition)
            rst_vga_sync <= 4'b0000;
        else
            rst_vga_sync <= {rst_vga_sync[2:0], 1'b1};
    end
    assign rst_vga_n = rst_vga_sync[3];

    // =========================================================================
    // External LAN8720A PHY Power-Up Hardware Reset Controller
    // Holds PHY in reset for ~65,536 cycles (~1.3ms at 50MHz) after clock lock
    // =========================================================================
    reg [16:0] phy_rst_cnt;
    always @(posedge clk_eth or negedge global_rst_condition) begin
        if (!global_rst_condition) begin
            phy_rst_cnt <= 17'd0;
            phy_rst_n   <= 1'b0;
        end else begin
            if (phy_rst_cnt < 17'd65535) begin
                phy_rst_cnt <= phy_rst_cnt + 1'b1;
                phy_rst_n   <= 1'b0;
            end else begin
                phy_rst_n   <= 1'b1; // Release PHY from reset
            end
        end
    end

endmodule
