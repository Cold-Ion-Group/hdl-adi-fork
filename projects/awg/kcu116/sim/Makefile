# Makefile for AWG KCU116 Simulations
# Supports both Icarus Verilog and Vivado Simulator

# Paths
HDL_DIR := $(abspath ../../../..)
COMMON_DIR := $(HDL_DIR)/library/common
XILINX_DIR := $(HDL_DIR)/library/xilinx/common
SIM_DIR := $(shell pwd)

# Tools
IVERILOG := iverilog
VVP := vvp
GTKWAVE := gtkwave
PYTHON := python3
XVLOG := xvlog
XELAB := xelab
XSIM := xsim

# Compiler flags
IVERILOG_FLAGS := -g2012 -I$(COMMON_DIR) -I$(XILINX_DIR)
TIMEOUT := -DTIMEOUT=500000

# Source files
CORDIC_SOURCES := \
	$(COMMON_DIR)/ad_dds_sine_cordic.v \
	$(COMMON_DIR)/ad_dds_cordic_pipe.v

DDS_SOURCES := \
	$(CORDIC_SOURCES) \
	$(COMMON_DIR)/ad_dds_sine.v \
	$(COMMON_DIR)/ad_dds_1.v \
	$(COMMON_DIR)/ad_dds_2.v \
	$(COMMON_DIR)/ad_dds.v \
	ad_mul_sim.v

# System testbench sources
SYSTEM_TB_SOURCES := \
	axi4_lite_master_bfm.v \
	ddr4_simple_model.v \
	ad9144_jesd_model.v \
	system_top_tb.v

# Targets
.PHONY: all clean cordic dds system help wave analyze

all: help

help:
	@echo "=========================================="
	@echo "AWG KCU116 Simulation Makefile"
	@echo "=========================================="
	@echo ""
	@echo "Targets:"
	@echo "  cordic      - Run CORDIC sine/cosine unit test"
	@echo "  dds         - Run DDS testbench"
	@echo "  system      - Run system-level testbench"
	@echo "  wave-cordic - View CORDIC waveforms"
	@echo "  wave-dds    - View DDS waveforms"
	@echo "  wave-system - View system testbench waveforms"
	@echo "  analyze     - Analyze DDS output (requires Python)"
	@echo "  clean       - Remove generated files"
	@echo "  help        - Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make cordic      # Run CORDIC test"
	@echo "  make dds         # Run DDS test"
	@echo "  make system      # Run system-level test"
	@echo "  make analyze     # Analyze DDS output"
	@echo ""
	@echo "=========================================="

# CORDIC sine/cosine unit test
cordic: cordic_sine_tb.vvp
	@echo "====================================="
	@echo "Running CORDIC Sine/Cosine Test"
	@echo "====================================="
	$(VVP) cordic_sine_tb.vvp
	@echo ""
	@echo "To view waveforms: make wave-cordic"
	@echo "====================================="

cordic_sine_tb.vvp: cordic_sine_tb.v $(CORDIC_SOURCES)
	@echo "Compiling CORDIC testbench..."
	$(IVERILOG) $(IVERILOG_FLAGS) $(TIMEOUT) \
		-o $@ \
		cordic_sine_tb.v $(CORDIC_SOURCES)

# DDS testbench
dds: ad_dds_cordic_tb.vvp
	@echo "====================================="
	@echo "Running DDS Testbench"
	@echo "====================================="
	$(VVP) ad_dds_cordic_tb.vvp
	@echo ""
	@echo "To view waveforms: make wave-dds"
	@echo "To analyze data: make analyze"
	@echo "====================================="

ad_dds_cordic_tb.vvp: ad_dds_cordic_tb.v $(DDS_SOURCES)
	@echo "Compiling DDS testbench..."
	$(IVERILOG) $(IVERILOG_FLAGS) $(TIMEOUT) \
		-o $@ \
		ad_dds_cordic_tb.v $(DDS_SOURCES)

# View waveforms
wave-cordic: cordic_sine_tb.vcd
	$(GTKWAVE) cordic_sine_tb.vcd &

wave-dds: ad_dds_cordic_tb.vcd
	$(GTKWAVE) ad_dds_cordic_tb.vcd &

wave-system: system_top_tb.vcd
	$(GTKWAVE) system_top_tb.vcd &

# System-level testbench
system: system_top_tb.vvp
	@echo "====================================="
	@echo "Running System-Level Testbench"
	@echo "====================================="
	$(VVP) system_top_tb.vvp
	@echo ""
	@echo "To view waveforms: make wave-system"
	@echo "====================================="

system_top_tb.vvp: $(SYSTEM_TB_SOURCES)
	@echo "Compiling system testbench..."
	$(IVERILOG) $(IVERILOG_FLAGS) $(TIMEOUT) \
		-o $@ \
		$(SYSTEM_TB_SOURCES)

# Analyze DDS output
analyze: dds_output.txt
	@echo "Analyzing DDS output..."
	$(PYTHON) analyze_dds.py

# Clean
clean:
	@echo "Cleaning simulation files..."
	rm -f *.vvp *.vcd *.txt *.png
	rm -rf xsim.dir
	rm -f *.jou *.log *.pb
	rm -f webtalk*.jou webtalk*.log
	@echo "Clean complete!"

# Additional helpers
.PHONY: info env

info:
	@echo "Simulation Environment:"
	@echo "  HDL_DIR: $(HDL_DIR)"
	@echo "  COMMON_DIR: $(COMMON_DIR)"
	@echo "  SIM_DIR: $(SIM_DIR)"
	@echo ""
	@echo "Tools:"
	@echo "  iverilog: $(shell which $(IVERILOG) 2>/dev/null || echo 'NOT FOUND')"
	@echo "  vvp: $(shell which $(VVP) 2>/dev/null || echo 'NOT FOUND')"
	@echo "  gtkwave: $(shell which $(GTKWAVE) 2>/dev/null || echo 'NOT FOUND')"
	@echo "  python3: $(shell which $(PYTHON) 2>/dev/null || echo 'NOT FOUND')"

env: info
