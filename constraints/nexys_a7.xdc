################ CLOCK ################
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 [get_ports clk]

# Generated clock for the 1 Hz CPU/system bus clock domain (100 MHz / 100,000,000 = 1 Hz)
create_generated_clock -name slow_clk -source [get_pins slow_clk_reg/C] -divide_by 100000000 [get_pins slow_clk_reg/Q]

# Break the internal divider toggle feedback false path (clock generation circuit)
set_false_path -from [get_cells slow_clk_reg] -to [get_cells slow_clk_reg]

################ RESET ################
set_property PACKAGE_PIN N17 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]
# set_property PULLUP true [get_ports reset]

################ LEDS #################
# LEDs LD0-LD15
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

################ 7-SEGMENT DISPLAY ################
# Segments (active-low cathodes: 0 = segment ON)
# seg[6:0] = {CG, CF, CE, CD, CC, CB, CA}
set_property PACKAGE_PIN T10 [get_ports {seg[0]}]
set_property PACKAGE_PIN R10 [get_ports {seg[1]}]
set_property PACKAGE_PIN K16 [get_ports {seg[2]}]
set_property PACKAGE_PIN K13 [get_ports {seg[3]}]
set_property PACKAGE_PIN P15 [get_ports {seg[4]}]
set_property PACKAGE_PIN T11 [get_ports {seg[5]}]
set_property PACKAGE_PIN L18 [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

# Decimal point (active-low: tied to 1 = always off)
set_property PACKAGE_PIN H15 [get_ports dp]
set_property IOSTANDARD LVCMOS33 [get_ports dp]

# Anodes (active-low: 0 = digit ON)
set_property PACKAGE_PIN J17 [get_ports {an[0]}]
set_property PACKAGE_PIN J18 [get_ports {an[1]}]
set_property PACKAGE_PIN T9  [get_ports {an[2]}]
set_property PACKAGE_PIN J14 [get_ports {an[3]}]
set_property PACKAGE_PIN P14 [get_ports {an[4]}]
set_property PACKAGE_PIN T14 [get_ports {an[5]}]
set_property PACKAGE_PIN K2  [get_ports {an[6]}]
set_property PACKAGE_PIN U13 [get_ports {an[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]