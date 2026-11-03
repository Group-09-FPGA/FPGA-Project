#!/bin/bash
# =============================================================================
# Automated RTL Unit Test Suite Runner for FPGA Limit Order Book System
# Simulator: Icarus Verilog (iverilog -g2001) + vvp
# =============================================================================
set -e -o pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/ci_sim"
CORE_RTL_FILES=$(find "${PROJECT_ROOT}/rtl/cpu/core" -maxdepth 1 -name '*.v' ! -name top_fpga.v | tr '\n' ' ')
LOB_RTL_FILES=$(find "${PROJECT_ROOT}/rtl/lob" -maxdepth 1 -name '*.v' | tr '\n' ' ')
mkdir -p "${BUILD_DIR}"
python3 "${PROJECT_ROOT}/firmware/kitty_ui/build.py"
ln -sf "${PROJECT_ROOT}/firmware/lob_test/imem.hex" "${BUILD_DIR}/imem.hex"
ln -sf "${PROJECT_ROOT}/firmware/lob_test/dmem.hex" "${BUILD_DIR}/dmem.hex"
ln -sf "${PROJECT_ROOT}/firmware/kitty_ui/kitty_ui.hex" "${BUILD_DIR}/kitty_ui.hex"
ln -sf "${PROJECT_ROOT}/firmware/kitty_ui/kitty_font.hex" "${BUILD_DIR}/kitty_font.hex"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local name="$1"
    local compile_cmd="$2"
    local sim_cmd="$3"
    
    echo "----------------------------------------------------------------------"
    echo ">>> Running Testbench: ${name}"
    echo "----------------------------------------------------------------------"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval "${compile_cmd}" && eval "${sim_cmd}"; then
        echo ">>> [PASS] ${name}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo ">>> [FAIL] ${name}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

echo "======================================================================"
echo " Starting Automated Hardware Simulation Suite"
echo " Project: FPGA Limit Order Book (RV32IM + Artix-7 LOB Accelerator)"
echo "======================================================================"

# 1. Canonical Event Decoder Unit Test
run_test "LOB Event Decoder (tb_lob_event_decoder.v)" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/cpu/core -I${PROJECT_ROOT}/rtl/lob \
     ${PROJECT_ROOT}/rtl/lob/lob_event_decoder.v \
     ${PROJECT_ROOT}/sim/unit/lob/tb_lob_event_decoder.v \
     -o ${BUILD_DIR}/tb_event_decoder.vvp" \
    "vvp -N ${BUILD_DIR}/tb_event_decoder.vvp"

# 2. LOB Free List Stack Unit Test
run_test "LOB Free List Stack Allocator (tb_lob_free_list.v)" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/cpu/core -I${PROJECT_ROOT}/rtl/lob \
     ${PROJECT_ROOT}/rtl/lob/lob_free_list.v \
     ${PROJECT_ROOT}/sim/unit/lob/tb_lob_free_list.v \
     -o ${BUILD_DIR}/tb_free_list.vvp" \
    "vvp -N ${BUILD_DIR}/tb_free_list.vvp"

run_test "LOB MMIO zero configuration" \
    "iverilog -g2001 -s tb_lob_mmio_config -o ${BUILD_DIR}/tb_lob_mmio_config.vvp ${PROJECT_ROOT}/rtl/bus/lob_mmio_slave.v ${PROJECT_ROOT}/sim/unit/lob/tb_lob_mmio_config.v" \
    "vvp -N ${BUILD_DIR}/tb_lob_mmio_config.vvp"

run_test "LOB RTL versus Python golden vectors" \
    "python3 ${PROJECT_ROOT}/sim/golden/generate_rtl_vectors.py ${BUILD_DIR} && iverilog -g2001 -I${PROJECT_ROOT}/rtl/lob -s tb_lob_golden -o ${BUILD_DIR}/tb_lob_golden.vvp ${LOB_RTL_FILES} ${PROJECT_ROOT}/sim/golden/tb_lob_golden.v" \
    "(cd ${BUILD_DIR} && vvp -N ${BUILD_DIR}/tb_lob_golden.vvp)"

# 3. Ethernet 100M RMII Receiver & CRC-32 Unit Test
run_test "Three random LOB sequences versus independent dictionary book" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/lob -s tb_lob_random -o ${BUILD_DIR}/tb_lob_random.vvp ${LOB_RTL_FILES} ${PROJECT_ROOT}/sim/golden/tb_lob_random.v" \
    "for random_seed in 7 20261102 942931; do python3 ${PROJECT_ROOT}/sim/golden/generate_random_vectors.py ${BUILD_DIR}/random_\${random_seed} --seed \${random_seed} && (cd ${BUILD_DIR}/random_\${random_seed} && vvp -N ${BUILD_DIR}/tb_lob_random.vvp) || exit 1; done"

run_test "Ethernet RMII Receiver (tb_rmii_rx.v)" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/cpu/core -I${PROJECT_ROOT}/rtl/lob -I${PROJECT_ROOT}/rtl/ethernet \
     ${PROJECT_ROOT}/rtl/ethernet/rmii_rx.v \
     ${PROJECT_ROOT}/sim/unit/tb_rmii_rx.v \
     -o ${BUILD_DIR}/tb_rmii.vvp" \
    "vvp -N ${BUILD_DIR}/tb_rmii.vvp"

# 4. RV32IM CPU Core Full Pipeline & Memory Bus Test
run_test "RV32IM CPU Pipeline & Hardware Multiplier/Divider (tb_cpu_core.v)" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/cpu/core \
     ${PROJECT_ROOT}/rtl/cpu/core/decoder.v \
     ${PROJECT_ROOT}/rtl/cpu/core/alu.v \
     ${PROJECT_ROOT}/rtl/cpu/core/branch_unit.v \
     ${PROJECT_ROOT}/rtl/cpu/core/reg_file.v \
     ${PROJECT_ROOT}/rtl/cpu/core/forwarding_unit.v \
     ${PROJECT_ROOT}/rtl/cpu/core/hazard_unit.v \
     ${PROJECT_ROOT}/rtl/cpu/core/rv32m_unit.v \
     ${PROJECT_ROOT}/rtl/cpu/core/cpu_core.v \
     ${PROJECT_ROOT}/rtl/cpu/core/sys_bus_interconnect.v \
     ${PROJECT_ROOT}/rtl/cpu/core/memory.v \
     ${PROJECT_ROOT}/rtl/cpu/core/imem_slave.v \
     ${PROJECT_ROOT}/rtl/cpu/core/dmem_slave.v \
     ${PROJECT_ROOT}/sim/unit/core/tb_cpu_core.v \
     -o ${BUILD_DIR}/tb_cpu_core.vvp" \
    "(cd ${PROJECT_ROOT}/sim/unit/core && vvp -N ${BUILD_DIR}/tb_cpu_core.vvp | grep -E 'ALL|FAIL|ERRORS')"

run_test "RV32M arithmetic unit corner cases" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/cpu/core -s tb_rv32m_unit -o ${BUILD_DIR}/tb_rv32m_unit.vvp ${CORE_RTL_FILES} ${PROJECT_ROOT}/sim/unit/core/tb_rv32m_unit.v" \
    "(cd ${BUILD_DIR} && vvp -N ${BUILD_DIR}/tb_rv32m_unit.vvp | tail -8)"

run_test "RV32M pipeline stalls and forwarding" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/cpu/core -s tb_rv32m_pipeline -o ${BUILD_DIR}/tb_rv32m_pipeline.vvp ${CORE_RTL_FILES} ${PROJECT_ROOT}/sim/unit/core/tb_rv32m_pipeline.v" \
    "(cd ${BUILD_DIR} && vvp -N ${BUILD_DIR}/tb_rv32m_pipeline.vvp | tail -9)"

run_test "CPU unmapped bus access" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/cpu/core -s tb_bus_error -o ${BUILD_DIR}/tb_bus_error.vvp ${CORE_RTL_FILES} ${PROJECT_ROOT}/sim/unit/core/tb_bus_error.v" \
    "(cd ${BUILD_DIR} && vvp -N ${BUILD_DIR}/tb_bus_error.vvp)"

run_test "Seven segment decimal rendering" \
    "iverilog -g2001 -s tb_seven_seg_decimal -o ${BUILD_DIR}/tb_seven_seg_decimal.vvp ${PROJECT_ROOT}/rtl/cpu/core/seven_seg_driver.v ${PROJECT_ROOT}/sim/unit/tb_seven_seg_decimal.v" \
    "vvp -N ${BUILD_DIR}/tb_seven_seg_decimal.vvp"

run_test "MoldUDP64 gap fail-stop" \
    "iverilog -g2001 -s tb_moldudp64_gap ${PROJECT_ROOT}/rtl/network/moldudp64_decoder.v ${PROJECT_ROOT}/sim/unit/tb_moldudp64_gap.v -o ${BUILD_DIR}/tb_mold_gap.vvp" \
    "vvp -N ${BUILD_DIR}/tb_mold_gap.vvp"

run_test "ITCH configurable tick and input validation" \
    "iverilog -g2001 -I${PROJECT_ROOT}/rtl/lob -s tb_itch_decoder_config ${PROJECT_ROOT}/rtl/itch/itch_decoder.v ${PROJECT_ROOT}/sim/unit/tb_itch_decoder_config.v -o ${BUILD_DIR}/tb_itch_config.vvp" \
    "vvp -N ${BUILD_DIR}/tb_itch_config.vvp"

run_test "Bundled configuration clock crossing" \
    "iverilog -g2001 -s tb_config_cdc ${PROJECT_ROOT}/rtl/common/config_cdc.v ${PROJECT_ROOT}/sim/unit/tb_config_cdc.v -o ${BUILD_DIR}/tb_config_cdc.vvp" \
    "vvp -N ${BUILD_DIR}/tb_config_cdc.vvp"

run_test "Async event FIFO wrap and backpressure" \
    "iverilog -g2001 -s tb_async_event_fifo_wrap ${PROJECT_ROOT}/rtl/common/async_event_fifo.v ${PROJECT_ROOT}/sim/unit/tb_async_event_fifo_wrap.v -o ${BUILD_DIR}/tb_async_event_fifo_wrap.vvp" \
    "vvp -N ${BUILD_DIR}/tb_async_event_fifo_wrap.vvp"

run_test "Network parser padding" \
    "iverilog -g2001 -s tb_net_parser_padding ${PROJECT_ROOT}/rtl/network/net_parser.v ${PROJECT_ROOT}/sim/unit/tb_net_parser_padding.v -o ${BUILD_DIR}/tb_net_padding.vvp" \
    "vvp -N ${BUILD_DIR}/tb_net_padding.vvp"

run_test "Network parser maximum UDP payload" \
    "iverilog -g2001 -s tb_net_parser_max_payload ${PROJECT_ROOT}/rtl/network/net_parser.v ${PROJECT_ROOT}/sim/unit/tb_net_parser_max_payload.v -o ${BUILD_DIR}/tb_net_max_payload.vvp" \
    "vvp -N ${BUILD_DIR}/tb_net_max_payload.vvp"

run_test "RMII queue and ring wrap" \
    "iverilog -g2001 -s tb_rmii_rx_queue ${PROJECT_ROOT}/rtl/ethernet/rmii_rx.v ${PROJECT_ROOT}/sim/unit/tb_rmii_rx_queue.v -o ${BUILD_DIR}/tb_rmii_queue.vvp" \
    "vvp -N ${BUILD_DIR}/tb_rmii_queue.vvp"

run_test "PS/2 framing, scan codes, key release and reconnect" \
    "iverilog -g2001 -s tb_ps2_keyboard -o ${BUILD_DIR}/tb_ps2_keyboard.vvp ${PROJECT_ROOT}/rtl/ui/ps2_keyboard.v ${PROJECT_ROOT}/sim/unit/tb_ps2_keyboard.v" \
    "vvp -N ${BUILD_DIR}/tb_ps2_keyboard.vvp"

run_test "Keyboard form editing and local Add submission" \
    "iverilog -g2001 -s tb_keyboard_controls -o ${BUILD_DIR}/tb_keyboard_controls.vvp ${PROJECT_ROOT}/rtl/ui/keyboard_controls.v ${PROJECT_ROOT}/sim/unit/tb_keyboard_controls.v" \
    "vvp -N ${BUILD_DIR}/tb_keyboard_controls.vvp"

run_test "Seven keyboard actions and stale FPGA selection" \
    "iverilog -g2001 -s tb_keyboard_actions -o ${BUILD_DIR}/tb_keyboard_actions.vvp ${PROJECT_ROOT}/rtl/ui/keyboard_controls.v ${PROJECT_ROOT}/sim/unit/tb_keyboard_actions.v" \
    "vvp -N ${BUILD_DIR}/tb_keyboard_actions.vvp"

run_test "Keyboard reconnect preserves form and clears held state" \
    "iverilog -g2001 -s tb_keyboard_hotplug -o ${BUILD_DIR}/tb_keyboard_hotplug.vvp ${PROJECT_ROOT}/rtl/ui/ps2_keyboard.v ${PROJECT_ROOT}/rtl/ui/keyboard_controls.v ${PROJECT_ROOT}/sim/unit/tb_keyboard_hotplug.v" \
    "vvp -N ${BUILD_DIR}/tb_keyboard_hotplug.vvp"

run_test "Mixed network and keyboard-local sources under backpressure" \
    "iverilog -g2001 -s tb_order_source_arbiter -o ${BUILD_DIR}/tb_order_sources.vvp ${PROJECT_ROOT}/rtl/ui/order_source_arbiter.v ${PROJECT_ROOT}/sim/unit/tb_order_source_arbiter.v" \
    "vvp -N ${BUILD_DIR}/tb_order_sources.vvp"

run_test "1280x720 renderer from presentation firmware and quote journal" \
    "iverilog -g2001 -DSIMULATION -I${PROJECT_ROOT}/rtl/cpu/core -s tb_kitty_preview -o ${BUILD_DIR}/tb_kitty_preview.vvp ${PROJECT_ROOT}/rtl/display/kitty_ui_cpu.v ${PROJECT_ROOT}/rtl/display/kitty_video.v ${PROJECT_ROOT}/rtl/common/config_cdc.v ${CORE_RTL_FILES} ${PROJECT_ROOT}/sim/unit/tb_kitty_preview.v" \
    "(cd ${BUILD_DIR} && vvp -N ${BUILD_DIR}/tb_kitty_preview.vvp)"

run_test "UART transmitter frames and FIFO flags" \
    "iverilog -g2001 -s tb_uart_tx -o ${BUILD_DIR}/tb_uart_tx.vvp ${PROJECT_ROOT}/rtl/telemetry/uart_tx.v ${PROJECT_ROOT}/sim/unit/tb_uart_tx.v" \
    "vvp -N ${BUILD_DIR}/tb_uart_tx.vvp"

run_test "UART status line carries storage trace and price configuration" \
    "iverilog -g2001 -s tb_uart_storage_trace -o ${BUILD_DIR}/tb_uart_storage_trace.vvp ${PROJECT_ROOT}/rtl/telemetry/uart_telemetry.v ${PROJECT_ROOT}/rtl/telemetry/uart_tx.v ${PROJECT_ROOT}/sim/unit/tb_uart_storage_trace.v" \
    "vvp -N ${BUILD_DIR}/tb_uart_storage_trace.vvp"

run_test "UART RAM readback request and response" \
    "iverilog -g2001 -s tb_uart_readback -o ${BUILD_DIR}/tb_uart_readback.vvp ${PROJECT_ROOT}/rtl/telemetry/uart_readback.v ${PROJECT_ROOT}/sim/unit/tb_uart_readback.v" \
    "vvp -N ${BUILD_DIR}/tb_uart_readback.vvp"

run_test "Quote/event history rings" \
    "iverilog -g2001 -s tb_lob_display_journal -o ${BUILD_DIR}/tb_lob_display_journal.vvp ${PROJECT_ROOT}/rtl/display/lob_display_journal.v ${PROJECT_ROOT}/sim/unit/tb_lob_display_journal.v" \
    "vvp -N ${BUILD_DIR}/tb_lob_display_journal.vvp"

run_test "Orders per price level" \
    "iverilog -g2001 -s tb_lob_level_order_count -o ${BUILD_DIR}/tb_lob_level_order_count.vvp ${PROJECT_ROOT}/rtl/display/lob_level_order_count.v ${PROJECT_ROOT}/sim/unit/tb_lob_level_order_count.v" \
    "vvp -N ${BUILD_DIR}/tb_lob_level_order_count.vvp"

run_test "Full Ethernet-to-book integration" \
    "iverilog -g2001 -DSIMULATION -I${PROJECT_ROOT}/rtl/lob -I${PROJECT_ROOT}/rtl/cpu/core -s tb_system_top -o ${BUILD_DIR}/tb_system_top.vvp \$(find ${PROJECT_ROOT}/rtl -name '*.v') ${PROJECT_ROOT}/sim/integration/tb_system_top.v" \
    "(cd ${BUILD_DIR} && vvp -N ${BUILD_DIR}/tb_system_top.vvp)"

echo "======================================================================"
echo " Simulation Summary: ${PASSED_TESTS}/${TOTAL_TESTS} testbenches passed."
if [ "${FAILED_TESTS}" -eq 0 ]; then
    echo " Result: SUCCESS (0 errors detected)"
    echo "======================================================================"
    exit 0
else
    echo " Result: FAILURE (${FAILED_TESTS} testbenches failed)"
    echo "======================================================================"
    exit 1
fi
