#!/bin/bash
set -e
PROJECT_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$PROJECT_ROOT"

BUILD_DIR="$PROJECT_ROOT/sim/build_system_top"
python3 "$PROJECT_ROOT/firmware/kitty_ui/build.py"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

ln -sf "$PROJECT_ROOT/firmware/lob_test/imem.hex" imem.hex
ln -sf "$PROJECT_ROOT/firmware/lob_test/dmem.hex" dmem.hex
ln -sf "$PROJECT_ROOT/firmware/kitty_ui/kitty_ui.hex" kitty_ui.hex
ln -sf "$PROJECT_ROOT/firmware/kitty_ui/kitty_font.hex" kitty_font.hex

echo ">>> Analyzing RTL and Testbench files with xvlog..."
xvlog -d SIMULATION \
    -i "$PROJECT_ROOT/rtl/cpu/core" \
    -i "$PROJECT_ROOT/rtl/lob" \
    $(find "$PROJECT_ROOT/rtl" -name '*.v') \
    "$PROJECT_ROOT/sim/integration/tb_system_top.v"

echo ">>> Elaborating snapshot with xelab..."
xelab -top tb_system_top -snapshot sim_system_top -debug typical

echo ">>> Running simulation with xsim..."
xsim sim_system_top -R
