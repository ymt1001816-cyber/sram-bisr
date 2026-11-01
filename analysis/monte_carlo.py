"""monte_carlo.py : repair rate vs number of faults for each allocator (16 rows x 32 bit-columns, 2 + 2 spares)"""
import random
import sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
from redundancy import ALLOCATORS, random_faults, check

ROWS, COLS, SR, SC, TRIALS = 16, 32, 2, 2, 2000
for p_line, title in ((0.0, "random cell faults"), (0.2, "20% of faults are a whole broken row or column")):
    print(f"\n{title}: repair rate (%), {TRIALS} trials each, {SR} spare rows + {SC} spare columns "
          f"(row only: {SR + SC} spare rows)")
    print("faults " + "".join(f"{n:>22}" for n in ALLOCATORS))
    for n in range(1, 11):
        rng = random.Random(n * 7 + int(p_line * 100))
        ok = {k: 0 for k in ALLOCATORS}
        for _ in range(TRIALS):
            f = random_faults(n, ROWS, COLS, rng, p_line)
            for k, fn in ALLOCATORS.items():
                sol = fn(f, SR, SC)
                assert check(f, sol, SR if k != "row only" else SR + SC, SC if k != "row only" else 0), k
                ok[k] += sol is not None
        assert ok["optimal"] >= max(v for k, v in ok.items() if k != "row only")
        print(f"{n:>6} " + "".join(f"{100 * ok[k] / TRIALS:>22.1f}" for k in ALLOCATORS))
