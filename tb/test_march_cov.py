# test_march_cov.py : fault coverage of four March algorithms on the programmable MBIST (mbist_prog.v)
#   for every fault type, inject many random instances one at a time, run each algorithm, and count detections
#   (fail = 1). Also checks that no algorithm fails on a good memory and that each takes its expected 5N..22N cycles.
#   writes the coverage table to coverage_table.md
import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

ROWB, COLB, DW = 4, 2, 8
ROWS, COLS, N = 1 << ROWB, 1 << COLB, 1 << (ROWB + COLB)
ALGS = ["MATS+", "March X", "March C-", "March SS"]
OPS = {"MATS+": 5, "March X": 6, "March C-": 10, "March SS": 22}
FAULTS = {1: "stuck-at-0", 2: "stuck-at-1", 3: "transition 0->1", 6: "transition 1->0",
          4: "inversion coupling (CFin)", 7: "idempotent coupling (CFid)", 8: "state coupling (CFst)",
          12: "address decoder (AF)", 9: "read destructive (RDF)", 10: "deceptive read destructive (DRDF)",
          11: "write destructive (WDF)"}
COUPLED = (4, 7, 8, 12)
SAMPLES = int(os.environ.get("SAMPLES", "40"))


async def run(dut, alg):
    """Run one algorithm; returns (fail, cycles)."""
    dut.alg.value = alg
    await FallingEdge(dut.clk)
    dut.start.value = 1
    await FallingEdge(dut.clk)
    dut.start.value = 0
    for cyc in range(1, 30 * N):
        await RisingEdge(dut.clk)
        if dut.done.value == 1:
            return dut.fail.value == 1, cyc
    assert False, f"{ALGS[alg]} never finished"


def inject(dut, ftype, rng):
    m = dut.u_mem
    row, col, bit = rng.randrange(ROWS), rng.randrange(COLS), rng.randrange(DW)
    arow, acol = row, col
    while (arow, acol) == (row, col):              # aggressor in another word (inter-word coupling)
        arow, acol = rng.randrange(ROWS), rng.randrange(COLS)
    m.f_type[0].value = ftype; m.f_row[0].value = row; m.f_col[0].value = col; m.f_bit[0].value = bit
    m.f_arow[0].value = arow; m.f_acol[0].value = acol; m.f_val[0].value = rng.randrange(2)
    m.f_dir[0].value = rng.randrange(2)            # coupling sensitized by a rising or a falling write


def random_fill(dut, rng):
    """Power-up state is unknown: fill the array with random data before each run."""
    for i in range(N):
        dut.u_mem.mem[i].value = rng.getrandbits(DW)


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def test_march_coverage(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    dut.rst_n.value = 0; dut.start.value = 0; dut.alg.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    m = dut.u_mem
    for s in range(4):
        m.f_type[s].value = 0

    # good memory: no false fails, and the expected test length (ops x N, plus a few control cycles)
    for a, name in enumerate(ALGS):
        fail, cyc = await run(dut, a)
        dut._log.info("%-9s good memory: fail=%d, %d cycles (%dN = %d)", name, fail, cyc, OPS[name], OPS[name] * N)
        assert not fail, f"{name} fails on a good memory"
        assert OPS[name] * N <= cyc <= OPS[name] * N + 4, f"{name}: {cyc} cycles, expected {OPS[name]}N"

    rng = random.Random(1)                          # same fault instances for every algorithm
    table = {}
    for ftype, fname in FAULTS.items():
        insts = [random.Random(rng.random()) for _ in range(SAMPLES)]
        seeds = [r.random() for r in insts]
        row = []
        for a, name in enumerate(ALGS):
            hits = 0
            for sd in seeds:
                r = random.Random(sd)
                inject(dut, ftype, r)
                random_fill(dut, r)
                fail, _ = await run(dut, a)
                hits += fail
            row.append(100.0 * hits / SAMPLES)
        m.f_type[0].value = 0
        table[fname] = row
        dut._log.info("%-36s %s", fname, "  ".join(f"{ALGS[i]} {v:5.1f}%" for i, v in enumerate(row)))

    with open("coverage_table.md", "w") as f:
        f.write("| Fault | " + " | ".join(f"{a} ({OPS[a]}N)" for a in ALGS) + " |\n")
        f.write("|---|" + "---:|" * len(ALGS) + "\n")
        for fname, row in table.items():
            f.write(f"| {fname} | " + " | ".join(f"{v:.0f}%" for v in row) + " |\n")

    # March C- must detect every classic static fault it is designed for; March SS must add the read/write disturbs
    c, ss = 2, 3
    for fname in ("stuck-at-0", "stuck-at-1", "transition 0->1", "transition 1->0", "inversion coupling (CFin)",
                  "idempotent coupling (CFid)", "address decoder (AF)"):
        assert table[fname][c] == 100.0, f"March C- misses {fname}"
    for fname in FAULTS.values():
        assert table[fname][ss] == 100.0, f"March SS misses {fname}"
    await RisingEdge(dut.clk)                       # let the simulator settle before exit (avoids a vvp exit segfault)
    await RisingEdge(dut.clk)
