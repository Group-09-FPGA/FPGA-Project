# build_bitstream.tcl
# Fully automated, reproducible non-project Vivado build script for Digilent Nexys A7-100T
# Synthesizes, implements, verifies timing, and generates bitstream for top_fpga.

# 1. Resolve paths relative to script location
set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/../.."]
set BUILD_DIR  [file normalize "$REPO_ROOT/build"]

file mkdir $BUILD_DIR

puts "=========================================================="
puts "Starting reproducible FPGA build for top_fpga"
puts "Repository Root : $REPO_ROOT"
puts "Build Directory : $BUILD_DIR"
puts "=========================================================="

# 2. Verify existence of memory initialization files
if {[info exists ::env(HEX_DIR)]} {
    set HEX_DIR [file normalize $::env(HEX_DIR)]
} else {
    set HEX_DIR [file normalize "$REPO_ROOT/sim/unit/core/mem_generator/imem_dmem"]
}

set IMEM_HEX "$HEX_DIR/imem.hex"
set DMEM_HEX "$HEX_DIR/dmem.hex"

if {![file exists $IMEM_HEX]} {
    puts "CRITICAL ERROR: Instruction memory file not found at: $IMEM_HEX"
    puts "Please run 'make rv32m' in sim/unit/core to generate it first."
    exit 1
}

if {![file exists $DMEM_HEX]} {
    puts "CRITICAL ERROR: Data memory file not found at: $DMEM_HEX"
    puts "Please run 'make rv32m' in sim/unit/core to generate it first."
    exit 1
}

# Copy hex files directly to BUILD_DIR so $readmemh("imem.hex", ...) finds them in cwd
file copy -force $IMEM_HEX "$BUILD_DIR/imem.hex"
file copy -force $DMEM_HEX "$BUILD_DIR/dmem.hex"

puts "Loaded memory payloads:"
puts "  imem: $IMEM_HEX -> $BUILD_DIR/imem.hex"
puts "  dmem: $DMEM_HEX -> $BUILD_DIR/dmem.hex"

# Change working directory so relative $readmemh resolves unconditionally
cd $BUILD_DIR

# 3. Read RTL sources and constraints
set PART "xc7a100tcsg324-1"
set TOP  "top_fpga"

puts "Reading RTL sources from $REPO_ROOT/rtl/cpu/core/*.v ..."
read_verilog [glob "$REPO_ROOT/rtl/cpu/core/*.v"]

puts "Reading constraints from $REPO_ROOT/constraints/nexys_a7.xdc ..."
read_xdc "$REPO_ROOT/constraints/nexys_a7.xdc"

# 4. Synthesis
puts "=== [1/5] RUNNING SYNTH_DESIGN ==="
synth_design -top $TOP -part $PART
write_checkpoint -force "$BUILD_DIR/post_synth.dcp"
report_utilization -file "$BUILD_DIR/post_synth_utilization.rpt"
report_timing_summary -file "$BUILD_DIR/post_synth_timing.rpt"

# Verify that $readmemh did NOT fail
set readmem_warnings [get_msg_config -count -id {Synth 8-4445}]
if {$readmem_warnings > 0} {
    puts "CRITICAL ERROR: \$readmemh failed to read memory initialization files during synthesis!"
    exit 1
}

# 5. Logic Optimization
puts "=== [2/5] RUNNING OPT_DESIGN ==="
opt_design
write_checkpoint -force "$BUILD_DIR/post_opt.dcp"

# 6. Placement
puts "=== [3/5] RUNNING PLACE_DESIGN ==="
place_design
write_checkpoint -force "$BUILD_DIR/post_place.dcp"

# 7. Routing
puts "=== [4/5] RUNNING ROUTE_DESIGN ==="
route_design
write_checkpoint -force "$BUILD_DIR/post_route.dcp"

# 8. Post-Route Analysis & Reports
puts "=== [5/5] POST-ROUTE TIMING, UTILIZATION & DRC REPORTS ==="
report_timing_summary -file "$BUILD_DIR/post_route_timing.rpt"
report_utilization -file "$BUILD_DIR/post_route_utilization.rpt"
report_drc -file "$BUILD_DIR/post_route_drc.rpt"
report_clock_utilization -file "$BUILD_DIR/post_route_clock_util.rpt"

# Check post-route slack
set wns [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -hold]]

puts "=========================================================="
puts "POST-ROUTE TIMING RESULTS:"
puts "Worst Negative Slack (Setup WNS) : $wns ns"
puts "Worst Hold Slack     (Hold WHS)  : $whs ns"
puts "=========================================================="

if {$wns < 0.0} {
    puts "CRITICAL ERROR: Setup timing violated after routing! WNS = $wns ns"
    exit 1
}
if {$whs < 0.0} {
    puts "CRITICAL ERROR: Hold timing violated after routing! WHS = $whs ns"
    exit 1
}

# Set Artix-7 configuration properties for Nexys A7 3.3V bank voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# 9. Bitstream Generation
puts "=== GENERATING BITSTREAM ==="
write_bitstream -force "$BUILD_DIR/top_fpga.bit"

puts "=========================================================="
puts "BUILD SUCCESSFUL!"
puts "Bitstream generated at: $BUILD_DIR/top_fpga.bit"
puts "Timing report at     : $BUILD_DIR/post_route_timing.rpt"
puts "Utilization report at: $BUILD_DIR/post_route_utilization.rpt"
puts "=========================================================="
