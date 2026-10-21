#!/bin/bash
set -e

# The former CPU/LOB bench used a removed SystemVerilog package and stale ports.
# The maintained full-system Verilog bench exercises the current SoC integration.
exec "$(dirname "$0")/run_system_top.sh"
