# config.mk : OpenROAD-flow-scripts (ORFS) design config, open-source RTL-to-GDS for sram_bisr
#   the memory is the flip-flop stand-in openroad/sram_array_ff.v; hierarchy is kept so the report shows
#   how much area the self-repair logic (MBIST, BIRA, remap, FSM) costs next to the memory
#   run (inside the ORFS image):  make -C $FLOW_HOME DESIGN_CONFIG=<repo>/openroad/config.mk REPO=<repo>
export PLATFORM        = nangate45
export DESIGN_NAME     = sram_bisr
export DESIGN_NICKNAME = sram_bisr
export VERILOG_FILES   = $(REPO)/rtl/sram_bisr.v $(REPO)/rtl/mbist_prog.v $(REPO)/rtl/bira.v \
                         $(REPO)/rtl/repair_remap.v $(REPO)/openroad/sram_array_ff.v
export SDC_FILE        = $(REPO)/openroad/constraint.sdc
export SYNTH_HIERARCHICAL = 1

export CORE_UTILIZATION = 40
export PLACE_DENSITY    = 0.65
