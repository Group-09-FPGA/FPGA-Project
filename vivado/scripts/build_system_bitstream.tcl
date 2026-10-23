# =============================================================================
# File: build_system_bitstream.tcl
# Description: Automated, non-project Vivado build script for Full Market Data
#              Processor on Digilent Nexys A7-100T (XC7A100T-1CSG324C).
#              Synthesizes, implements, verifies timing closure, and writes bitstream.
# =============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/../.."]
if {[info exists ::env(FPGA_BUILD_DIR)]} {
    set BUILD_DIR [file normalize $::env(FPGA_BUILD_DIR)]
} else {
    set BUILD_DIR [file normalize "$REPO_ROOT/build_system"]
}

file mkdir $BUILD_DIR

# A failed rebuild must not leave an older bitstream or routed report looking
# like the result of the current sources. Keep only final implementation output.
foreach output_name {
    top_system.bit post_route.dcp post_route_timing.rpt
    post_route_utilization.rpt post_route_drc.rpt post_route_clock_util.rpt
    post_route_methodology.rpt post_route_clock_interaction.rpt
} {
    file delete -force "$BUILD_DIR/$output_name"
}

# Optimize thread count for Intel Core Ultra 8-core host
set_param general.maxThreads 4
set_param synth.maxThreads 4

set PLACE_DIRECTIVE Default
set ROUTE_DIRECTIVE Default
if {[info exists ::env(FPGA_PLACE_DIRECTIVE)]} {
    set PLACE_DIRECTIVE $::env(FPGA_PLACE_DIRECTIVE)
}
if {[info exists ::env(FPGA_ROUTE_DIRECTIVE)]} {
    set ROUTE_DIRECTIVE $::env(FPGA_ROUTE_DIRECTIVE)
}

puts "=========================================================="
puts "Starting FPGA Market Data Processor Implementation"
puts "Repository Root : $REPO_ROOT"
puts "Build Directory : $BUILD_DIR"
puts "Max Threads Set : 4"
puts "Place Directive : $PLACE_DIRECTIVE"
puts "Route Directive : $ROUTE_DIRECTIVE"
puts "=========================================================="

# 1. Prepare Memory Hex Payloads
set HEX_DIR [file normalize "$REPO_ROOT/software/baremetal/lob_test"]
set IMEM_HEX "$HEX_DIR/imem.hex"
set DMEM_HEX "$HEX_DIR/dmem.hex"

if {![file exists $IMEM_HEX]} {
    puts "CRITICAL ERROR: imem.hex not found at $IMEM_HEX"
    exit 1
}
if {![file exists $DMEM_HEX]} {
    puts "CRITICAL ERROR: dmem.hex not found at $DMEM_HEX"
    exit 1
}

file copy -force $IMEM_HEX "$BUILD_DIR/imem.hex"
file copy -force $DMEM_HEX "$BUILD_DIR/dmem.hex"

puts "Memory payloads staged in build directory:"
puts "  imem: $IMEM_HEX -> $BUILD_DIR/imem.hex"
puts "  dmem: $DMEM_HEX -> $BUILD_DIR/dmem.hex"

cd $BUILD_DIR

# 2. Add Sources
set PART "xc7a100tcsg324-1"
set TOP  "top_system"

puts "Reading Verilog modules..."
read_verilog "$REPO_ROOT/rtl/lob/lob_event_decoder.v"
read_verilog "$REPO_ROOT/rtl/lob/lob_slot_table.v"
read_verilog "$REPO_ROOT/rtl/lob/lob_free_list.v"
read_verilog "$REPO_ROOT/rtl/lob/lob_hash_table.v"
read_verilog "$REPO_ROOT/rtl/lob/lob_price_ram.v"
read_verilog "$REPO_ROOT/rtl/lob/lob_occupancy.v"
read_verilog "$REPO_ROOT/rtl/lob/lob_bbo.v"
read_verilog "$REPO_ROOT/rtl/lob/lob_core.v"
read_verilog "$REPO_ROOT/rtl/bus/lob_mmio_slave.v"
read_verilog "$REPO_ROOT/rtl/bus/net_mmio_slave.v"
read_verilog "$REPO_ROOT/rtl/common/async_event_fifo.v"
read_verilog "$REPO_ROOT/rtl/common/config_cdc.v"
read_verilog "$REPO_ROOT/rtl/clocking/clk_rst_mgr.v"
read_verilog "$REPO_ROOT/rtl/ethernet/rmii_rx.v"
read_verilog "$REPO_ROOT/rtl/network/net_parser.v"
read_verilog "$REPO_ROOT/rtl/network/moldudp64_decoder.v"
read_verilog "$REPO_ROOT/rtl/itch/itch_decoder.v"
read_verilog "$REPO_ROOT/rtl/display/vga_top.v"
read_verilog "$REPO_ROOT/rtl/telemetry/uart_telemetry.v"
read_verilog "$REPO_ROOT/rtl/top/top_system.v"

puts "Reading CPU Verilog core modules..."
read_verilog [glob "$REPO_ROOT/rtl/cpu/core/*.v"]

puts "Reading physical and timing constraints..."
read_xdc "$REPO_ROOT/constraints/nexys_a7_system.xdc"

# 3. Synthesis
puts "=== [1/5] RUNNING SYNTH_DESIGN ==="
synth_design -top $TOP -part $PART -include_dirs [list "$REPO_ROOT/rtl/cpu/core" "$REPO_ROOT/rtl/lob"]

set readmem_warnings [get_msg_config -count -id {Synth 8-4445}]
if {$readmem_warnings > 0} {
    puts "CRITICAL ERROR: \$readmemh failed during synthesis!"
    exit 1
}

# 4. Logic Optimization
puts "=== [2/5] RUNNING OPT_DESIGN ==="
opt_design

# 5. Placement
puts "=== [3/5] RUNNING PLACE_DESIGN ==="
place_design -directive $PLACE_DIRECTIVE

# 5b. Physical Optimization
puts "=== [3b/5] RUNNING PHYS_OPT_DESIGN ==="
phys_opt_design -directive Explore

# 6. Routing
puts "=== [4/5] RUNNING ROUTE_DESIGN ==="
route_design -directive $ROUTE_DIRECTIVE

# 7. Post-route timing, including recovery if needed
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

puts "=========================================================="
puts "POST-ROUTE TIMING RESULTS:"
puts "Worst Negative Slack (Setup WNS) : $wns ns"
puts "Worst Hold Slack     (Hold WHS)  : $whs ns"
puts "=========================================================="

if {$wns < 0.0} {
    puts "Setup timing negative ($wns ns). Running post-route phys_opt_design to recover slack..."
    phys_opt_design -directive Explore
    route_design -directive $ROUTE_DIRECTIVE
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
    puts "After post-route optimization: WNS = $wns ns, WHS = $whs ns"
}

if {$wns < 0.0} {
    puts "ERROR: Setup timing violated! WNS = $wns ns"
}
if {$whs < 0.0} {
    puts "ERROR: Hold timing violated! WHS = $whs ns"
}
if {$wns < 0.0 || $whs < 0.0} {
    puts "Build failed timing checks. No candidate bitstream will be generated."
    exit 1
}

puts "=== [5/5] POST-ROUTE TIMING & UTILIZATION REPORTS ==="
write_checkpoint -force "$BUILD_DIR/post_route.dcp"
report_timing_summary -file "$BUILD_DIR/post_route_timing.rpt"
report_utilization -file "$BUILD_DIR/post_route_utilization.rpt"
report_drc -file "$BUILD_DIR/post_route_drc.rpt"
report_clock_utilization -file "$BUILD_DIR/post_route_clock_util.rpt"
report_methodology -file "$BUILD_DIR/post_route_methodology.rpt"
report_clock_interaction -file "$BUILD_DIR/post_route_clock_interaction.rpt"

# 8. Bitstream Generation
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]

puts "=== GENERATING BITSTREAM ==="
write_bitstream -force "$BUILD_DIR/top_system.bit"
foreach staged_name {imem.hex dmem.hex clockInfo.txt} {
    file delete -force "$BUILD_DIR/$staged_name"
}

puts "=========================================================="
puts "BUILD COMPLETE!"
puts "Bitstream generated at : $BUILD_DIR/top_system.bit"
puts "Timing report at       : $BUILD_DIR/post_route_timing.rpt"
puts "Utilization report at  : $BUILD_DIR/post_route_utilization.rpt"
puts "=========================================================="
