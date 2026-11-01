#!/bin/bash
# regress.sh : open-source regression (Verilator lint, cocotb + Icarus, SymbiYosys); exits non-zero if any check fails
#   usage: ci/regress.sh [lint|sim|2d|formal|all]      (default all)
cd "$(dirname "$0")/.."; mkdir -p build; fails=0
check() {   # check <name> <log> <pattern that must appear>
  if grep -q "$3" "$2"; then echo "PASS  $1"; else echo "FAIL  $1  (see $2)"; fails=$((fails+1)); fi
}
what=${1:-all}
if [[ $what == lint || $what == all ]]; then
  verilator --lint-only -Wall ci/lint_waivers.vlt --top-module sram_bisr rtl/*.v model/sram_array.v > build/lint.log 2>&1 && echo LINT_CLEAN >> build/lint.log
  check "lint: Verilator -Wall clean" build/lint.log LINT_CLEAN
  verilator --lint-only -Wall ci/lint_waivers.vlt --top-module sram_bisr2d rtl/*.v model/sram_array.v > build/lint_2d.log 2>&1 && echo LINT_CLEAN >> build/lint_2d.log
  check "lint sram_bisr2d: Verilator -Wall clean" build/lint_2d.log LINT_CLEAN
fi
if [[ $what == sim || $what == all ]]; then   # 9 repair tests (3 seeds, then March SS) + the March coverage experiment
  for s in 1 2 3; do
    (cd tb && rm -rf sim_build && make COCOTB_RANDOM_SEED=$s > ../build/sim_$s.log 2>&1)
    check "sim seed $s: PASS / REPAIRED / FAIL and spare count for each fault case, memory works after repair" build/sim_$s.log "FAIL=0 SKIP="
  done
  (cd tb && rm -rf sim_build && make ALG=3 > ../build/sim_ss.log 2>&1)
  check "sim March SS: the same 9 repair tests with the 22N algorithm" build/sim_ss.log "FAIL=0 SKIP="
  (cd tb && rm -rf sim_build_cov && make -f Makefile.cov > ../build/march_cov.log 2>&1; cp coverage_table.md ../build/ 2>/dev/null)
  check "march coverage: 4 algorithms x 11 fault types, March C- and March SS detect what they are designed for" build/march_cov.log "FAIL=0 SKIP="
fi
if [[ $what == 2d || $what == all ]]; then    # spare rows + spare columns: Python models, then the RTL against them
  (cd analysis && python3 -m pytest -q test_redundancy.py > ../build/analysis.log 2>&1)
  check "analysis: exhaustive allocator = brute force, every allocator returns a real repair" build/analysis.log " passed"
  (cd tb && rm -rf sim_build_2d && make -f Makefile.2d ROUNDS=100 > ../build/sim_2d.log 2>&1)
  check "sim 2d: bit-line and must-repair cases, 100 random fault maps vs the greedy and exhaustive models" build/sim_2d.log "FAIL=0 SKIP="
fi
if [[ $what == formal || $what == all ]]; then
  (cd formal && for t in prove cover; do sby -f repair.sby $t > ../build/formal_$t.log 2>&1; done)
  check "formal prove: repair table has no duplicates, remap is one-to-one and uses only valid spares (unbounded)" build/formal_prove.log "DONE (PASS"
  check "formal cover: full table, unrepairable, remap to spare 1 are reachable (prove is not vacuous)" build/formal_cover.log "DONE (PASS"
  (cd formal && for t in bmc prove; do sby -f equiv.sby $t > ../build/formal_equiv_$t.log 2>&1; done)
  check "formal equiv bmc: programmable MBIST (March C-) = original controller, 2 complete runs, any read data" build/formal_equiv_bmc.log "DONE (PASS"
  check "formal equiv prove: the same, unbounded (k-induction, 8-word memory)" build/formal_equiv_prove.log "DONE (PASS"
fi
echo "---- $fails failing check(s)"; exit $fails
