#!/bin/bash
# summary.sh RESULT_DIR : key numbers of an ORFS run, plus the cell area of each module (repair cost vs memory)
D=$1; R=$D/reports/6_finish.rpt
echo "== design area";             grep -h -m1 "Design area" $R $D/logs/6_report.log 2>/dev/null | head -1
echo "== setup (finish)";          grep -h -E "^(tns|wns|worst slack) max" $R 2>/dev/null
echo "== power (default activity)"; grep -h -m1 "Total power" $D/logs/6_report.log 2>/dev/null
echo "== detailed route DRC";      grep -h -E "Number of violations" $D/logs/5_2_route.log 2>/dev/null | tail -1
echo "== equivalence (ORFS LEC)";  grep -h "passed lec test\|failed lec test" $D/logs/*.log 2>/dev/null
echo "== synthesis area per module (um^2)"
S=$(ls $D/reports/synth_stat.txt 2>/dev/null)
[ -n "$S" ] && grep -E "^=== |Chip area" $S
