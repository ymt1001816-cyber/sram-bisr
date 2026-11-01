# test_bisr2d.py : cocotb testbench for sram_bisr2d (spare rows + spare bit-columns, 2D redundancy analysis)
#   directed cases where columns matter, then random fault maps checked against the Python models in analysis/:
#     - soundness : if no assignment of 2 rows + 2 columns covers the faults (exhaustive search), the result is FAIL
#     - repair    : after REPAIRED (or PASS) the memory works through the normal port (random writes / reads)
#     - quality   : the hardware repairs (nearly) every map the greedy model repairs; the rate is logged
import os
import random
import sys

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "analysis"))
from redundancy import greedy, optimal  # noqa: E402

ROWB, COLB, DW, SR, SC = 4, 2, 8, 2, 2
ROWS, COLS = 1 << ROWB, 1 << COLB
NAMES = {0: "NONE", 1: "PASS", 2: "REPAIRED", 3: "FAIL"}
SA0, SA1, TF, COL0, SCOL = 1, 2, 3, 5, 13


class Tb:
    def __init__(self, dut):
        self.dut = dut
        self.m = dut.u_mem

    async def reset(self):
        d = self.dut
        cocotb.start_soon(Clock(d.clk, 10, unit="ns").start())
        d.rst_n.value = 0; d.bist_start.value = 0; d.we.value = 0; d.addr.value = 0; d.wdata.value = 0
        d.alg.value = int(os.environ.get("ALG", "2"))
        self.clear_faults()
        for _ in range(3):
            await RisingEdge(d.clk)
        d.rst_n.value = 1
        await RisingEdge(d.clk)

    def fault(self, slot, ftype, row=0, col=0, bit=0, val=0):
        m = self.m
        m.f_type[slot].value = ftype; m.f_row[slot].value = row; m.f_col[slot].value = col
        m.f_bit[slot].value = bit; m.f_val[slot].value = val; m.f_arow[slot].value = 0; m.f_acol[slot].value = 0

    def clear_faults(self):
        for s in range(8):
            self.fault(s, 0)

    async def bist(self):
        d = self.dut
        await FallingEdge(d.clk)
        d.bist_start.value = 1
        await FallingEdge(d.clk)
        d.bist_start.value = 0
        for _ in range(8000):
            await RisingEdge(d.clk)
            if d.bist_done.value == 1:
                break
        else:
            assert False, "bist_done never came"
        rows = bin(int(d.rows_used.value)).count("1")
        cols = bin(int(d.cols_used.value)).count("1")
        return NAMES[int(d.bist_status.value)], rows, cols

    async def functional(self, n=400):
        d = self.dut
        ref = {}
        for a in range(ROWS * COLS):
            await self.write(a, random.getrandbits(DW), ref)
        for _ in range(n):
            a = random.randrange(ROWS * COLS)
            if random.random() < 0.5:
                await self.write(a, random.getrandbits(DW), ref)
            else:
                await FallingEdge(d.clk)
                d.we.value = 0; d.addr.value = a
                await Timer(1, unit="ns")
                got = int(d.rdata.value)
                assert got == ref[a], f"address {a} (row {a >> COLB}): read {got:#x}, expected {ref[a]:#x}"
        d.we.value = 0

    async def write(self, a, v, ref):
        d = self.dut
        await FallingEdge(d.clk)
        d.we.value = 1; d.addr.value = a; d.wdata.value = v
        ref[a] = v
        await RisingEdge(d.clk)

    async def check(self, name, exp_status, exp_rows=None, exp_cols=None):
        status, rows, cols = await self.bist()
        self.dut._log.info("%s: %s, %d spare row(s) + %d spare column(s)", name, status, rows, cols)
        assert status == exp_status, f"{name}: {status}, expected {exp_status}"
        if exp_rows is not None:
            assert (rows, cols) == (exp_rows, exp_cols), f"{name}: {rows} rows + {cols} cols, expected {exp_rows} + {exp_cols}"
        if status in ("PASS", "REPAIRED"):
            await self.functional()


@cocotb.test()
async def test_no_fault(dut):
    """Good memory: PASS, no spare used."""
    tb = Tb(dut); await tb.reset()
    await tb.check("no fault", "PASS", 0, 0)


@cocotb.test()
async def test_bit_line(dut):
    """A broken bit line (one bit of one column, every row): ONE spare column repairs it (rows-only BISR fails)."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, COL0, col=1, bit=6)
    await tb.check("broken bit line", "REPAIRED", 0, 1)


@cocotb.test()
async def test_three_rows_one_column(dut):
    """Three faulty rows, all in the same bit-column: one spare column instead of three rows."""
    tb = Tb(dut); await tb.reset()
    for s, r in enumerate((2, 7, 12)):
        tb.fault(s, SA0, row=r, col=1, bit=2)
    await tb.check("three rows, same bit-column", "REPAIRED", 0, 1)


@cocotb.test()
async def test_bad_row(dut):
    """Three bad bits in one row: more than the 2 spare columns can fix, so the row MUST take a spare row."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, SA0, row=5, col=0, bit=1)
    tb.fault(1, SA1, row=5, col=2, bit=4)
    tb.fault(2, TF, row=5, col=3, bit=7)
    await tb.check("three faults in one row", "REPAIRED", 1, 0)


@cocotb.test()
async def test_two_lines_two_cells(dut):
    """Two broken bit lines plus two faulty cells elsewhere: all four spares used."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, COL0, col=0, bit=3)
    tb.fault(1, COL0, col=2, bit=5)
    tb.fault(2, SA1, row=4, col=1, bit=0)
    tb.fault(3, SA0, row=11, col=3, bit=7)
    await tb.check("two bit lines + two cells", "REPAIRED", 2, 2)


@cocotb.test()
async def test_three_lines(dut):
    """Three broken bit lines, two spare columns: FAIL."""
    tb = Tb(dut); await tb.reset()
    for s, (c, b) in enumerate(((0, 1), (1, 4), (3, 6))):
        tb.fault(s, COL0, col=c, bit=b)
    await tb.check("three bit lines", "FAIL")


@cocotb.test()
async def test_bad_spare_column(dut):
    """A broken bit line, and the spare column that replaces it is stuck at 1 in row 9: test 2 catches it."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, COL0, col=2, bit=2)
    tb.fault(1, SCOL, row=9, col=0, val=1)          # spare column 0
    await tb.check("faulty spare column", "FAIL")


def fault_cells(faults):
    """The faulty (row, bit-column) cells of a list of injected faults, for the Python models."""
    cells = set()
    for ftype, row, col, bit in faults:
        if ftype == COL0:
            cells |= {(r, col * DW + bit) for r in range(ROWS)}
        else:
            cells.add((row, col * DW + bit))
    return cells


@cocotb.test()
async def test_random_vs_model(dut):
    """Random fault maps (cells and bit lines) against the exhaustive and greedy Python models."""
    tb = Tb(dut); await tb.reset()
    rounds = int(os.environ.get("ROUNDS", "60"))
    rng = random.Random(int(os.environ.get("RA_SEED", "3")))
    stats = {"hw": 0, "greedy": 0, "optimal": 0, "greedy_only": 0}
    for k in range(rounds):
        tb.clear_faults()
        faults = []
        for s in range(rng.randint(2, 8)):
            ftype = COL0 if rng.random() < 0.2 else rng.choice((SA0, SA1, TF))
            f = (ftype, rng.randrange(ROWS), rng.randrange(COLS), rng.randrange(DW))
            tb.fault(s, *f)
            faults.append(f)
        cells = fault_cells(faults)
        can = optimal(cells, SR, SC) is not None
        grd = greedy(cells, SR, SC) is not None
        status, rows, cols = await tb.bist()
        hw = status == "REPAIRED"
        dut._log.info("round %2d: %d faults, %3d cells: hw %-8s (%d+%d)  greedy %s  optimal %s",
                      k, len(faults), len(cells), status, rows, cols, grd, can)
        assert status != "PASS", f"round {k}: faults present but PASS"
        if not can:
            assert status == "FAIL", f"round {k}: no 2+2 repair exists, but the hardware says {status}"
        if hw:
            await tb.functional(150)
        stats["hw"] += hw; stats["greedy"] += grd; stats["optimal"] += can
        stats["greedy_only"] += grd and not hw
    dut._log.info("repaired: hardware %d, greedy model %d, optimal %d of %d; greedy-repairable but hardware FAIL: %d",
                  stats["hw"], stats["greedy"], stats["optimal"], rounds, stats["greedy_only"])
    assert stats["greedy_only"] <= rounds // 20, "the hardware misses too many maps the greedy model repairs"
