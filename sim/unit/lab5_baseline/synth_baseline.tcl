read_verilog [glob ../../../rtl/cpu/lab5_baseline/*.v]
# read_verilog ../../../rtl/cpu/lab5_baseline/opcode.vh (not needed to explicitly read .vh files if included properly, but it's fine)
read_xdc ../../../constraints/nexys_a7.xdc

synth_design -top top_fpga -part xc7a100tcsg324-1

report_utilization -file synth_utilization.rpt
report_timing_summary -file synth_timing.rpt
