#!/bin/bash
set -e
PROJECT_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$PROJECT_ROOT"

BUILD_DIR="$PROJECT_ROOT/sim/build_system_top"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

ln -sf "$PROJECT_ROOT/software/baremetal/lob_test/imem.hex" imem.hex
ln -sf "$PROJECT_ROOT/software/baremetal/lob_test/dmem.hex" dmem.hex

echo ">>> Analyzing RTL and Testbench files with xvlog..."
xvlog -d SIMULATION \
    -i "$PROJECT_ROOT/rtl/cpu/core" \
    -i "$PROJECT_ROOT/rtl/lob" \
    "$PROJECT_ROOT/rtl/lob/lob_event_decoder.v" \
    "$PROJECT_ROOT/rtl/lob/lob_slot_table.v" \
    "$PROJECT_ROOT/rtl/lob/lob_free_list.v" \
    "$PROJECT_ROOT/rtl/lob/lob_hash_table.v" \
    "$PROJECT_ROOT/rtl/lob/lob_price_ram.v" \
    "$PROJECT_ROOT/rtl/lob/lob_occupancy.v" \
    "$PROJECT_ROOT/rtl/lob/lob_bbo.v" \
    "$PROJECT_ROOT/rtl/lob/lob_core.v" \
    "$PROJECT_ROOT/rtl/bus/lob_mmio_slave.v" \
    "$PROJECT_ROOT/rtl/bus/net_mmio_slave.v" \
    "$PROJECT_ROOT/rtl/common/async_event_fifo.v" \
    "$PROJECT_ROOT/rtl/common/config_cdc.v" \
    "$PROJECT_ROOT/rtl/clocking/clk_rst_mgr.v" \
    "$PROJECT_ROOT/rtl/ethernet/rmii_rx.v" \
    "$PROJECT_ROOT/rtl/network/net_parser.v" \
    "$PROJECT_ROOT/rtl/network/moldudp64_decoder.v" \
    "$PROJECT_ROOT/rtl/itch/itch_decoder.v" \
    "$PROJECT_ROOT/rtl/display/vga_top.v" \
    "$PROJECT_ROOT/rtl/telemetry/uart_telemetry.v" \
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
    "$PROJECT_ROOT/rtl/cpu/core/seven_seg_driver.v" \
    "$PROJECT_ROOT/rtl/top/top_system.v" \
    "$PROJECT_ROOT/sim/integration/tb_system_top.v"

echo ">>> Elaborating snapshot with xelab..."
xelab -top tb_system_top -snapshot sim_system_top -debug typical

echo ">>> Running simulation with xsim..."
xsim sim_system_top -R
