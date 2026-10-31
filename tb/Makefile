# Makefile : cocotb testbench (test_bisr.py) on Icarus Verilog
#   make  [ROUNDS=random rounds]  [COCOTB_RANDOM_SEED=n]
# needs OSS CAD Suite (cocotb + iverilog) on PATH:  source ~/tools/oss-cad-suite/environment
SIM ?= icarus
TOPLEVEL_LANG = verilog
TOPLEVEL = sram_bisr
COCOTB_TEST_MODULES = test_bisr
VERILOG_SOURCES = ../rtl/sram_bisr.v ../rtl/mbist_march.v ../rtl/bira.v ../rtl/repair_remap.v ../model/sram_array.v
COCOTB_HDL_TIMEPRECISION = 1ps
include $(shell cocotb-config --makefiles)/Makefile.sim
