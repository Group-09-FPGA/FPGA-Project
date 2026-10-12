#!/bin/bash
set -e
PROJECT_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$PROJECT_ROOT"

BUILD_DIR="$PROJECT_ROOT/sim/build_cpu_lob"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

ln -sf "$PROJECT_ROOT/software/baremetal/lob_test/imem.hex" imem.hex
ln -sf "$PROJECT_ROOT/software/baremetal/lob_test/dmem.hex" dmem.hex

echo ">>> Analyzing RTL and Testbench files with xvlog..."
xvlog -sv -i "$PROJECT_ROOT/rtl/cpu/core" \
    "$PROJECT_ROOT/rtl/lob/lob_pkg.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_event_decoder.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_slot_table.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_free_list.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_hash_table.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_price_ram.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_occupancy.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_bbo.sv" \
    "$PROJECT_ROOT/rtl/lob/lob_core.sv" \
    "$PROJECT_ROOT/rtl/bus/lob_mmio_slave.sv" \
    "$PROJECT_ROOT/rtl/cpu/core/decoder.v" \
    "$PROJECT_ROOT/rtl/cpu/core/alu.v" \
    "$PROJECT_ROOT/rtl/cpu/core/branch_unit.v" \
    "$PROJECT_ROOT/rtl/cpu/core/reg_file.v" \
    "$PROJECT_ROOT/rtl/cpu/core/forwarding_unit.v" \
    "$PROJECT_ROOT/rtl/cpu/core/hazard_unit.v" \
    "$PROJECT_ROOT/rtl/cpu/core/rv32m_unit.v" \
    "$PROJECT_ROOT/rtl/cpu/core/cpu_core.v" \
    "$PROJECT_ROOT/rtl/cpu/core/sys_bus_interconnect.v" \
    "$PROJECT_ROOT/rtl/cpu/core/memory.v" \
    "$PROJECT_ROOT/rtl/cpu/core/imem_slave.v" \
    "$PROJECT_ROOT/rtl/cpu/core/dmem_slave.v" \
    "$PROJECT_ROOT/sim/integration/tb_cpu_lob_mmio.sv"

echo ">>> Elaborating snapshot with xelab..."
xelab -top tb_cpu_lob_mmio -snapshot sim_cpu_lob -debug typical

echo ">>> Running simulation with xsim..."
xsim sim_cpu_lob -R
