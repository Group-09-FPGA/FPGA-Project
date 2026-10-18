# Master Command Reference & Cheatsheet

This document provides a copy-pasteable command reference for developing, simulating, synthesizing, implementing, and hardware-testing the **FPGA Limit Order Book (LOB) Accelerator & RV32IM SoC** on the Digilent Nexys A7-100T.

---

## Table of Contents

1. [Environment Setup](#1-environment-setup)
   - [Vivado EDA Toolchain](#vivado-eda-toolchain)
   - [Python Environment via `uv`](#python-environment-via-uv)
2. [Software Golden Reference Model](#2-software-golden-reference-model)
3. [RTL Simulation & Waveform Debugging](#3-rtl-simulation--waveform-debugging)
   - [Full System End-to-End Simulation](#full-system-end-to-end-simulation)
   - [Unit-Level Simulations](#unit-level-simulations)
   - [Inspecting Waveforms (Vivado XSim GUI)](#inspecting-waveforms-vivado-xsim-gui)
4. [Synthesis & Bitstream Implementation](#4-synthesis--bitstream-implementation)
   - [Out-of-Context LOB Core Synthesis](#out-of-context-lob-core-synthesis)
   - [Full System Implementation & Bitstream Generation](#full-system-implementation--bitstream-generation)
   - [Inspecting Build Reports](#inspecting-build-reports)
5. [Hardware Programming & Bringup](#5-hardware-programming--bringup)
   - [JTAG Bitstream Programming](#jtag-bitstream-programming)
   - [Physical Cable & Device Connections](#physical-cable--device-connections)
6. [Hardware Verification & Telemetry](#6-hardware-verification--telemetry)
   - [UART Serial Telemetry Monitor](#uart-serial-telemetry-monitor)
   - [Ethernet Packet Injection (MoldUDP64 / ITCH 5.0)](#ethernet-packet-injection-moldudp64--itch-50)
7. [Interactive Block Diagram Application](#7-interactive-block-diagram-application)

---

## 1. Environment Setup

### Vivado EDA Toolchain

To initialize AMD Vivado 2026.1 in your active shell:

```bash
# Source official Xilinx 64-bit environment settings
source /tools/Xilinx/2026.1/Vivado/settings64.sh

# Verify Vivado and simulator binaries are in PATH
which vivado xvlog xelab xsim
```

*Note:* You can also launch the Vivado GUI wrapper via:
```bash
~/.local/bin/vivado
```

### Python Environment via `uv`

The software golden model and test helper scripts rely on Python >= 3.12 managed via `uv`:

```bash
# Navigate to the Python LOB workspace
cd software_lob

# Create/sync virtual environment with development dependencies (pytest, hypothesis, rich, sortedcontainers)
uv sync --extra dev

# Run a quick check
uv run python --version
```

---

## 2. Software Golden Reference Model

The Python model (`software_lob`) provides a deterministic, cycle-accurate reference implementation of NASDAQ MoldUDP64, TotalView-ITCH 5.0 decoding, and order book matching with invariant testing:

```bash
cd software_lob

# Run entire test suite (42 unit, scenario, invariant, and differential tests)
uv run pytest

# Run tests with detailed verbose output
uv run pytest -v

# Run with property-based hypothesis tests
uv run pytest tests/property/ -v

# Run interactive CLI order book simulator
uv run lob-sim --help
```

---

## 3. RTL Simulation & Waveform Debugging

### Full System End-to-End Simulation

Runs the top-level integration testbench (`sim/integration/tb_system_top.v`), validating the complete pipeline:
`RMII 100Mbps Ethernet -> CRC32 -> IPv4/UDP -> MoldUDP64 -> ITCH 5.0 -> Async FIFO CDC -> LOB Accelerator -> BBO Engine -> MMIO -> UART / VGA / 7-Segment`.

```bash
# From repository root:
./sim/integration/run_system_top.sh
```

Simulation outputs will be generated in `sim/build_system_top/`.

### Unit-Level Simulations

To run dedicated core or MMIO integration testbenches:

```bash
# Run CPU + LOB MMIO Co-simulation
cd sim/integration
./run_cpu_lob.sh
```

### Inspecting Waveforms (Vivado XSim GUI)

#### Method A: Interactive Simulation with Waveform Window

To launch the simulator directly in graphical mode and add all waveform signals:

```bash
cd sim/build_system_top

# Launch Vivado XSim GUI with compiled snapshot
xsim sim_system_top -gui
```

Inside the Vivado GUI Tcl console:
```tcl
# Add all top-level and DUT signals to waveform
add_wave /tb_system_top/*
add_wave /tb_system_top/dut/*
add_wave /tb_system_top/dut/u_lob/*

# Run simulation
run all
```

#### Method B: Batch Waveform Capture and Post-Run Viewing

To generate a waveform database (`.wdb`) non-interactively and open it afterwards:

```bash
cd sim/build_system_top

# Create a small waveform batch script
cat << 'EOF' > wave.tcl
log_wave -r /tb_system_top/*
run all
exit
EOF

# Run batch simulation generating wave dump
xsim sim_system_top -tclbatch wave.tcl -wdb system_top.wdb

# View the waveform database
xsim system_top.wdb -gui &
```

---

## 4. Synthesis & Bitstream Implementation

### Out-of-Context LOB Core Synthesis

To verify resource utilization and timing closure for the standalone hardware Limit Order Book (LOB) core without peripheral overhead:

```bash
# Execute out-of-context batch synthesis
vivado -mode batch -source vivado/scripts/synth_lob.tcl

# Review generated reports
cat build/synth_lob/lob_synth_utilization.rpt
cat build/synth_lob/lob_synth_timing.rpt
```

### Full System Implementation & Bitstream Generation

To synthesize the complete end-to-end SoC (RMII MAC, MoldUDP64, ITCH 5.0, LOB Accelerator, RV32IM CPU, UART telemetry, and VGA):

```bash
# Execute automated batch implementation & bitstream flow
vivado -mode batch -source vivado/scripts/build_system_bitstream.tcl
```

This automated flow:
1. Stages `imem.hex` and `dmem.hex` memory payloads.
2. Compiles pure Verilog-2001 sources with `read_verilog`.
3. Runs `synth_design`, `opt_design`, `place_design`, `phys_opt_design`, and `route_design`.
4. Enforces timing closure and writes `build_system/top_system.bit`.

### Inspecting Build Reports

```bash
# View timing closure summary (WNS and TNS should be >= 0.000 ns)
cat build_system/post_route_timing.rpt | grep -E "WNS|TNS|Slack"

# View device utilization metrics
cat build_system/post_route_utilization.rpt | head -n 45
```

---

## 5. Hardware Programming & Bringup

### JTAG Bitstream Programming

Connect the Digilent Nexys A7-100T via the **PROG / UART** micro-USB port (J6) to your laptop. Ensure the board power switch is turned **ON** and jumper **JP1** is set to **JTAG**.

```bash
# Flash the generated bitstream via Vivado Hardware Manager
vivado -mode batch -source vivado/scripts/program_fpga.tcl
```

Once programming finishes, verify that the green **DONE** LED on the board illuminates.

### Physical Cable & Device Connections

| Board Interface | Connector | Destination | Cable Required | Function |
| :--- | :--- | :--- | :--- | :--- |
| **PROG / UART** | Micro-USB (J6) | Host Laptop USB Port | Micro-USB Cable | JTAG Programming, Power, & USB-UART Telemetry |
| **Ethernet** | RJ45 (J2) | Host Laptop / Network | Standard RJ45 Cat5e/6 | 100 Mbps Market Feed (MoldUDP64 / ITCH 5.0) |
| **VGA Video** | DB15 VGA (J4) | External Desktop Monitor | Standard VGA Cable *(Optional)* | 640x480 @ 60Hz Market Visualizer |

---

## 6. Hardware Verification & Telemetry

### Real-Time Terminal Visualizer (Recommended for Laptops)

You can visualize live order book updates directly on your laptop screen over the micro-USB connection without an external VGA monitor:

```bash
# 1. Run in self-contained demo/test mode (works without board)
python3 tools/lob_telemetry_visualizer.py --demo

# 2. Connect to live FPGA board over USB-UART (/dev/ttyUSB1 at 115200 baud)
python3 tools/lob_telemetry_visualizer.py --port /dev/ttyUSB1
```

The visualizer provides:
- Live Top of Book (BBO) with color-coded Bid (Buy) and Ask (Sell) ladders.
- Real-time spread in dollars and ticks.
- Event counters and update frequency (Hz).
- Telemetry activity log.

### Basic Serial Monitor

Alternatively, use the lightweight command-line monitor:

```bash
python3 tools/hardware_test_helper.py --uart
```

### Ethernet Packet Injection (MoldUDP64 / ITCH 5.0)

In a separate terminal, inject synthetic market orders into the Nexys A7 board via Ethernet:

```bash
# Inject sample NASDAQ ITCH 5.0 Add Order messages over UDP port 10443
python3 tools/hardware_test_helper.py --inject --ip 192.168.1.10 --port 10443
```

Observe the live updates simultaneously reflected on:
1. Your laptop terminal visualizer (`tools/lob_telemetry_visualizer.py`).
2. The board's 8-digit 7-segment display (toggle slide switches `sw[1:0]` for Bid, Ask, or Active Orders).
3. The board diagnostic LEDs (`LD0`–`LD15`).

---

## 7. Interactive Block Diagram Application

The repository includes an interactive Vite/React visualization app for the architecture and timing diagrams:

```bash
cd docs/diagrams

# Install node dependencies
pnpm install   # or npm install

# Start local interactive server
pnpm dev
```

Open `http://localhost:5173` in your browser to view interactive animated diagrams for the CPU pipeline, DSP multiplier/divider, LOB core, and timing traces.

