# =============================================================================
# File: nexys_a7_system.xdc
# Description: Physical pin and timing constraints for Full Market Data Processor
# Target: AMD/Xilinx Artix-7 (Digilent Nexys A7-100T, XC7A100T-1CSG324C)
# Reference: Official Digilent Nexys A7 Master XDC
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Master Clock (100.0 MHz oscillator on board)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]

# -----------------------------------------------------------------------------
# 2. Reset (CPU_RESETN active-low pushbutton, pin C12)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN C12 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

# -----------------------------------------------------------------------------
# 3. Slide Switches (sw[3:0])
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN J15 [get_ports {sw[0]}]
set_property PACKAGE_PIN L16 [get_ports {sw[1]}]
set_property PACKAGE_PIN M13 [get_ports {sw[2]}]
set_property PACKAGE_PIN R15 [get_ports {sw[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

# -----------------------------------------------------------------------------
# 4. User Diagnostic LEDs (led[15:0])
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN H17 [get_ports {led[0]}]
set_property PACKAGE_PIN K15 [get_ports {led[1]}]
set_property PACKAGE_PIN J13 [get_ports {led[2]}]
set_property PACKAGE_PIN N14 [get_ports {led[3]}]
set_property PACKAGE_PIN R18 [get_ports {led[4]}]
set_property PACKAGE_PIN V17 [get_ports {led[5]}]
set_property PACKAGE_PIN U17 [get_ports {led[6]}]
set_property PACKAGE_PIN U16 [get_ports {led[7]}]
set_property PACKAGE_PIN V16 [get_ports {led[8]}]
set_property PACKAGE_PIN T15 [get_ports {led[9]}]
set_property PACKAGE_PIN U14 [get_ports {led[10]}]
set_property PACKAGE_PIN T16 [get_ports {led[11]}]
set_property PACKAGE_PIN V15 [get_ports {led[12]}]
set_property PACKAGE_PIN V14 [get_ports {led[13]}]
set_property PACKAGE_PIN V12 [get_ports {led[14]}]
set_property PACKAGE_PIN V11 [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# -----------------------------------------------------------------------------
# 5. 7-Segment Multiplexed Display (Cathodes + Decimal Point + Anodes)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN T10 [get_ports {seg[0]}]
set_property PACKAGE_PIN R10 [get_ports {seg[1]}]
set_property PACKAGE_PIN K16 [get_ports {seg[2]}]
set_property PACKAGE_PIN K13 [get_ports {seg[3]}]
set_property PACKAGE_PIN P15 [get_ports {seg[4]}]
set_property PACKAGE_PIN T11 [get_ports {seg[5]}]
set_property PACKAGE_PIN L18 [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

set_property PACKAGE_PIN H15 [get_ports dp]
set_property IOSTANDARD LVCMOS33 [get_ports dp]

set_property PACKAGE_PIN J17 [get_ports {an[0]}]
set_property PACKAGE_PIN J18 [get_ports {an[1]}]
set_property PACKAGE_PIN T9  [get_ports {an[2]}]
set_property PACKAGE_PIN J14 [get_ports {an[3]}]
set_property PACKAGE_PIN P14 [get_ports {an[4]}]
set_property PACKAGE_PIN T14 [get_ports {an[5]}]
set_property PACKAGE_PIN K2  [get_ports {an[6]}]
set_property PACKAGE_PIN U13 [get_ports {an[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]

# -----------------------------------------------------------------------------
# 6. SMSC LAN8720A Fast Ethernet RMII PHY
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN D5  [get_ports eth_refclk]
set_property IOSTANDARD LVCMOS33 [get_ports eth_refclk]

set_property PACKAGE_PIN B3  [get_ports eth_rstn]
set_property IOSTANDARD LVCMOS33 [get_ports eth_rstn]

set_property PACKAGE_PIN D9  [get_ports eth_crsdv]
set_property IOSTANDARD LVCMOS33 [get_ports eth_crsdv]

set_property PACKAGE_PIN C10 [get_ports eth_rxerr]
set_property IOSTANDARD LVCMOS33 [get_ports eth_rxerr]

set_property PACKAGE_PIN C11 [get_ports {eth_rxd[0]}]
set_property PACKAGE_PIN D10 [get_ports {eth_rxd[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rxd[*]}]

# LAN8720A REF_CLK In Mode, Microchip DS00002165B Table 5-10:
# RX outputs are valid within 14 ns and held for at least 3 ns after the
# supplied 50-MHz clock edge. The extra +/-1 ns covers board clock/data skew.
# Capture is on the next clk_eth edge; clk_eth_phy has the 45-degree phase
# used to forward REF_CLK to the PHY.
set_input_delay -clock [get_clocks clk_eth_phy_unbuf] -max 15.000 [get_ports {eth_crsdv eth_rxerr eth_rxd[*]}]
set_input_delay -clock [get_clocks clk_eth_phy_unbuf] -min 2.000 [get_ports {eth_crsdv eth_rxerr eth_rxd[*]}]

# -----------------------------------------------------------------------------
# 7. USB-UART Serial Interface (FTDI FT2232HQ Bridge)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN D4 [get_ports uart_txd_out]
set_property IOSTANDARD LVCMOS33 [get_ports uart_txd_out]

set_property PACKAGE_PIN C4 [get_ports uart_rxd_in]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rxd_in]

# -----------------------------------------------------------------------------
# 8. VGA 12-bit Video DAC (4 bits per color)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN A3 [get_ports {vga_r[0]}]
set_property PACKAGE_PIN B4 [get_ports {vga_r[1]}]
set_property PACKAGE_PIN C5 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN A4 [get_ports {vga_r[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

set_property PACKAGE_PIN C6 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN A5 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN B6 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN A6 [get_ports {vga_g[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

set_property PACKAGE_PIN B7 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN C7 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN D7 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN D8 [get_ports {vga_b[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

set_property PACKAGE_PIN B11 [get_ports vga_hs]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hs]

set_property PACKAGE_PIN B12 [get_ports vga_vs]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vs]

# -----------------------------------------------------------------------------
# 9. Clock Domain Crossing & False Path Constraints
# -----------------------------------------------------------------------------
# Async FIFO Gray pointer CDC synchronizers: ensure datapath delay < 10ns
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *u_async_fifo*wptr_gray_reg*}] -to [get_cells -hier -filter {NAME =~ *u_async_fifo*wptr_gray_sync1_reg*}] 10.000
set_max_delay -datapath_only -from [get_cells -hier -filter {NAME =~ *u_async_fifo*rptr_gray_reg*}] -to [get_cells -hier -filter {NAME =~ *u_async_fifo*rptr_gray_sync1_reg*}] 10.000

# Async FIFO dual-clock distributed RAM memory cross-clock false path (pointer synchronizer protected)
set_false_path -from [get_cells -hier -filter {NAME =~ *u_async_fifo*mem_reg*}] -to [get_clocks -include_generated_clocks clk_core_unbuf]

# Global asynchronous reset recovery false paths (deasserted after MMCM lock)
set_false_path -from [get_cells -hier -filter {NAME =~ *u_clk_mgr*rst_*_sync_reg[3]*}]

# Bundled-data CDC bridges hold source data until the destination acknowledges
# it. Only their asynchronous synchronizer first stages and held data buses
# are exempted; destination-to-VGA snapshot paths are timed normally.
set_false_path -to [get_cells -hier -filter {NAME =~ *u_*_cdc*req_sync1_reg* || NAME =~ *u_*_cdc*ack_sync1_reg*}]
set_false_path -from [get_cells -hier -filter {NAME =~ *u_*_cdc*held_data_reg*}] -to [get_cells -hier -filter {NAME =~ *u_*_cdc*dst_data_reg*}]

# Static user input false paths
set_false_path -from [get_ports {sw[*]}]
set_false_path -from [get_ports reset]
set_false_path -to [get_ports {led[*]}]
set_false_path -to [get_ports {seg[*]}]
set_false_path -to [get_ports {an[*]}]
set_false_path -to [get_ports dp]

# net_mmio_slave: snapshot latching stage.
# The config_cdc module presents already-stable diagnostic counters in dst_data_reg.
# net_mmio_slave deliberately re-registers them (snap_* FFs) before the address mux,
# adding one cycle of intentional latency.  Both stages are in clk_core, so we
# declare a 2-cycle multicycle setup path from the CDC destination register to the
# snap_* registers.  Hold is left at 1 cycle (default).
set_multicycle_path 2 -setup \
    -from [get_cells -hier -filter {NAME =~ *u_net_diag_cdc*dst_data_reg*}] \
    -to   [get_cells -hier -filter {NAME =~ *u_net_mmio*snap_*}]

# -----------------------------------------------------------------------------
# 10. Bitstream Generation Properties
# -----------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
