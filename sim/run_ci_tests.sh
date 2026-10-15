#!/bin/bash
# =============================================================================
# Automated RTL Unit Test Suite Runner for FPGA Limit Order Book System
# Simulator: Icarus Verilog (iverilog -g2012) + vvp
# =============================================================================
set -e

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="${PROJECT_ROOT}/build/ci_sim"
mkdir -p "${BUILD_DIR}"

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
run_test "LOB Event Decoder (tb_lob_event_decoder.sv)" \
    "iverilog -g2012 -I${PROJECT_ROOT}/rtl/cpu/core -I${PROJECT_ROOT}/rtl/lob \
     ${PROJECT_ROOT}/rtl/lob/lob_pkg.sv \
     ${PROJECT_ROOT}/rtl/lob/lob_event_decoder.sv \
     ${PROJECT_ROOT}/sim/unit/lob/tb_lob_event_decoder.sv \
     -o ${BUILD_DIR}/tb_event_decoder.vvp" \
    "vvp ${BUILD_DIR}/tb_event_decoder.vvp"

# 2. LOB Free List Stack Unit Test
run_test "LOB Free List Stack Allocator (tb_lob_free_list.sv)" \
    "iverilog -g2012 -I${PROJECT_ROOT}/rtl/cpu/core -I${PROJECT_ROOT}/rtl/lob \
     ${PROJECT_ROOT}/rtl/lob/lob_pkg.sv \
     ${PROJECT_ROOT}/rtl/lob/lob_free_list.sv \
     ${PROJECT_ROOT}/sim/unit/lob/tb_lob_free_list.sv \
     -o ${BUILD_DIR}/tb_free_list.vvp" \
    "vvp ${BUILD_DIR}/tb_free_list.vvp"

# 3. Ethernet 100M RMII Receiver & CRC-32 Unit Test
run_test "Ethernet RMII Receiver (tb_rmii_rx.sv)" \
    "iverilog -g2012 -I${PROJECT_ROOT}/rtl/cpu/core -I${PROJECT_ROOT}/rtl/lob -I${PROJECT_ROOT}/rtl/ethernet \
     ${PROJECT_ROOT}/rtl/ethernet/rmii_rx.sv \
     ${PROJECT_ROOT}/sim/unit/tb_rmii_rx.sv \
     -o ${BUILD_DIR}/tb_rmii.vvp" \
    "vvp ${BUILD_DIR}/tb_rmii.vvp"

# 4. RV32IM CPU Core Full Pipeline & Memory Bus Test
run_test "RV32IM CPU Pipeline & Hardware Multiplier/Divider (tb_cpu_core.v)" \
    "iverilog -g2012 -I${PROJECT_ROOT}/rtl/cpu/core \
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
    "(cd ${PROJECT_ROOT}/sim/unit/core && vvp ${BUILD_DIR}/tb_cpu_core.vvp | grep -E 'ALL|FAIL|ERRORS')"

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
