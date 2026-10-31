#!/bin/bash
# area_by_module.sh LIB : cell area of each module, hierarchy kept (yosys + the nangate45 liberty)
#   ORFS flattens small designs, so its own report shows only the total; this answers "what does the repair cost?"
cd "$(dirname "$0")/.."
yosys -q -p "read_verilog -sv rtl/sram_bisr.v rtl/mbist_prog.v rtl/bira.v rtl/repair_remap.v openroad/sram_array_ff.v;
             synth -top sram_bisr; dfflibmap -liberty $1; abc -liberty $1; opt_clean; tee -o build/area_by_module.txt stat -liberty $1" >/dev/null
grep -E "^=== |Chip area" build/area_by_module.txt
