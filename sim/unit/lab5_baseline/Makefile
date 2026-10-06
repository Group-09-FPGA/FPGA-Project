# --- Variables ---
INC_DIR  = ../../../rtl/cpu/lab5_baseline
BFLAGS   = -i $(INC_DIR) -f filelist.txt
TOP_MOD  = tb_pipeline
SNAPSHOT = riscv_sim
MEM_GEN  = ./mem_generator

# Vivado Tools
XVLOG = xvlog
XELAB = xelab
XSIM  = xsim

.PHONY: help clean sort addition negative fibo xor

help:
	@echo "Usage: make <program_name> (e.g. make addition)"

# Generic Rule for all programs
sort addition negative fibo xor:
	# 1. Generate Hex Files
	$(MAKE) clean -C $(MEM_GEN)
	$(MAKE) $@ -C $(MEM_GEN)
	
	ln -sf ./mem_generator/imem_dmem/imem.hex . && ln -sf ./mem_generator/imem_dmem/dmem.hex .
	# 2. Vivado Simulation Flow
	$(XVLOG) $(BFLAGS)
	$(XELAB) -top $(TOP_MOD) -snapshot $(SNAPSHOT) -debug typical
	
	# 3. Run Simulation with full WDB wave logging
	echo "log_wave -recursive *; run all; exit" > xsim_run.tcl
	$(XSIM) $(SNAPSHOT) -tclbatch xsim_run.tcl

clean:
	@rm -rf xsim.dir/ .Xil/
	@rm -f xvlog.log xvlog.pb xelab.log xelab.pb xsim.log xsim.jou xsim.pb xsim_run.tcl
	@rm -f pipeline.vcd
