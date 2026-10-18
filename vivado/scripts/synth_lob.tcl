# ==============================================================================
# synth_lob.tcl
# Non-project batch synthesis and timing verification for LOB Accelerator (lob_core)
# Target: Digilent Nexys A7-100T (AMD Artix-7 XC7A100T-1CSG324C)
# Authoritative spec: docs/phase1_architecture_final_v7.md §12, §18
# ==============================================================================

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/../.."]
set BUILD_DIR  [file normalize "$REPO_ROOT/build/synth_lob"]

file mkdir $BUILD_DIR
cd $BUILD_DIR

set PART "xc7a100tcsg324-1"
set TOP  "lob_core"

puts "=============================================================================="
puts "Starting LOB Accelerator Synthesis: $TOP on $PART"
puts "Repository Root : $REPO_ROOT"
puts "Build Directory : $BUILD_DIR"
puts "=============================================================================="

# 1. Read Verilog sources
puts "Reading LOB Verilog sources..."
read_verilog [list \
    "$REPO_ROOT/rtl/lob/lob_event_decoder.v" \
    "$REPO_ROOT/rtl/lob/lob_slot_table.v" \
    "$REPO_ROOT/rtl/lob/lob_free_list.v" \
    "$REPO_ROOT/rtl/lob/lob_hash_table.v" \
    "$REPO_ROOT/rtl/lob/lob_price_ram.v" \
    "$REPO_ROOT/rtl/lob/lob_occupancy.v" \
    "$REPO_ROOT/rtl/lob/lob_bbo.v" \
    "$REPO_ROOT/rtl/lob/lob_core.v" \
]

# Enforce single-threaded execution to prevent high RAM usage and helper process spawning
set_param general.maxThreads 1
set_param synth.maxThreads 1

# 2. Run Out-of-Context Synthesis with RuntimeOptimized directive (low memory)
puts "Synthesizing design (single-threaded, low RAM footprint)..."
synth_design -top $TOP -part $PART -mode out_of_context -directive RuntimeOptimized -include_dirs "$REPO_ROOT/rtl/lob"

# 3. Create 100 MHz target clock constraint (10.000 ns period, 50% duty cycle)
puts "Applying 100 MHz clock constraint on port clk..."
create_clock -period 10.000 -name clk [get_ports clk]

# 4. Generate Reports
puts "Generating utilization and timing reports..."
report_utilization -file "$BUILD_DIR/lob_synth_utilization.rpt"
report_utilization -hierarchical -file "$BUILD_DIR/lob_synth_hierarchical.rpt"
report_timing_summary -file "$BUILD_DIR/lob_synth_timing.rpt"
report_drc -file "$BUILD_DIR/lob_synth_drc.rpt"

# 5. Save Synthesized Design Checkpoint
write_checkpoint -force "$BUILD_DIR/lob_core_synth.dcp"

puts "=============================================================================="
puts "LOB Accelerator Synthesis Finished Successfully!"
puts "Artifacts saved in: $BUILD_DIR"
puts "=============================================================================="
