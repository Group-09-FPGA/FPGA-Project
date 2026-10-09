read_verilog [glob ../../../rtl/cpu/core/*.v]
read_xdc ../../../constraints/nexys_a7.xdc

synth_design -top top_fpga -part xc7a100tcsg324-1

report_utilization -file ../../../docs/core_synth_utilization.rpt
report_timing_summary -file ../../../docs/core_synth_timing.rpt
