# =============================================================================
# File: build_bitstream.tcl
# Description: Automated, non-project Vivado build script for Full Market Data
#              Processor on Digilent Nexys A7-100T (XC7A100T-1CSG324C).
#              Synthesizes, implements, verifies timing closure, and writes bitstream.
# =============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/.."]
set BUILD_PROFILE release
if {[info exists ::env(FPGA_BUILD_PROFILE)]} {
    set BUILD_PROFILE $::env(FPGA_BUILD_PROFILE)
}
if {$BUILD_PROFILE ni {release fast}} {
    puts "ERROR: FPGA_BUILD_PROFILE must be release or fast"
    exit 1
}
if {[info exists ::env(FPGA_BUILD_DIR)]} {
    set BUILD_DIR [file normalize $::env(FPGA_BUILD_DIR)]
} elseif {$BUILD_PROFILE eq "fast"} {
    set BUILD_DIR [file normalize "$REPO_ROOT/build/keyboard_vga_720p_fast"]
} else {
    set BUILD_DIR [file normalize "$REPO_ROOT/build/keyboard_vga_720p"]
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

# Four workers suit the 8-core host. Use two if the memory-limited build
# reaches its cgroup ceiling; this is intentionally independent of profile.
set MAX_THREADS 4
if {[info exists ::env(FPGA_MAX_THREADS)]} {
    set MAX_THREADS $::env(FPGA_MAX_THREADS)
}
if {![string is integer -strict $MAX_THREADS] || $MAX_THREADS < 1 || $MAX_THREADS > 4} {
    puts "ERROR: FPGA_MAX_THREADS must be an integer from 1 to 4"
    exit 1
}
set_param general.maxThreads $MAX_THREADS
set_param synth.maxThreads $MAX_THREADS

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
puts "Build Profile   : $BUILD_PROFILE"
puts "Max Threads Set : $MAX_THREADS"
puts "Place Directive : $PLACE_DIRECTIVE"
puts "Route Directive : $ROUTE_DIRECTIVE"
puts "=========================================================="

# 1. Prepare Memory Hex Payloads
if {[catch {exec python3 "$REPO_ROOT/firmware/kitty_ui/build.py" 2>@1} build_result]} {
    puts "ERROR: Presentation firmware build failed: $build_result"
    exit 1
}
puts $build_result
set HEX_DIR [file normalize "$REPO_ROOT/firmware/lob_test"]
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
file copy -force "$REPO_ROOT/firmware/kitty_ui/kitty_ui.hex" "$BUILD_DIR/kitty_ui.hex"
file copy -force "$REPO_ROOT/firmware/kitty_ui/kitty_font.hex" "$BUILD_DIR/kitty_font.hex"

puts "Memory payloads staged in build directory:"
puts "  imem: $IMEM_HEX -> $BUILD_DIR/imem.hex"
puts "  dmem: $DMEM_HEX -> $BUILD_DIR/dmem.hex"

cd $BUILD_DIR

# 2. Add Sources
set PART "xc7a100tcsg324-1"
set TOP  "top_system"

puts "Reading Verilog modules..."
foreach dir {bus clocking common cpu cpu/core display ethernet itch lob network telemetry top ui} {
    read_verilog [glob "$REPO_ROOT/rtl/$dir/*.v"]
}

puts "Reading physical and timing constraints..."
read_xdc "$REPO_ROOT/fpga/nexys_a7_system.xdc"

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
if {$BUILD_PROFILE eq "release"} {
    puts "=== [3b/5] RUNNING PHYS_OPT_DESIGN ==="
    phys_opt_design -directive Explore
} else {
    puts "=== [3b/5] SKIPPING PRE-ROUTE PHYS_OPT (fast profile) ==="
}

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
    if {$BUILD_PROFILE eq "release"} {
        route_design -directive $ROUTE_DIRECTIVE
    }
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
report_drc -file "$BUILD_DIR/post_route_drc.rpt"
if {$BUILD_PROFILE eq "release"} {
    report_utilization -file "$BUILD_DIR/post_route_utilization.rpt"
    report_clock_utilization -file "$BUILD_DIR/post_route_clock_util.rpt"
    report_methodology -file "$BUILD_DIR/post_route_methodology.rpt"
    report_clock_interaction -file "$BUILD_DIR/post_route_clock_interaction.rpt"
}

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
