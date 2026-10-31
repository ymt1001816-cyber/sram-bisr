# test_bisr.py : cocotb testbench for sram_bisr (MBIST + redundancy analysis + row repair)
#   each test injects faults into the SRAM model, runs the built-in self-test / repair, and checks
#     - bist_status (PASS / REPAIRED / FAIL) and how many spare rows were used, against what the faults require
#     - after PASS or REPAIRED: the memory works through the normal port (random writes and reads vs a reference)
import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

ROWB, COLB, DW, SPARES = 4, 2, 8, 2
ROWS, COLS = 1 << ROWB, 1 << COLB
NAMES = {0: "NONE", 1: "PASS", 2: "REPAIRED", 3: "FAIL"}
SA0, SA1, TF, CF, COL0 = 1, 2, 3, 4, 5


class Tb:
    def __init__(self, dut):
        self.dut = dut
        self.mem = dut.u_mem

    async def reset(self):
        d = self.dut
        cocotb.start_soon(Clock(d.clk, 10, unit="ns").start())
        d.rst_n.value = 0; d.bist_start.value = 0; d.we.value = 0; d.addr.value = 0; d.wdata.value = 0
        self.clear_faults()                                 # faults from the previous test stay in the model otherwise
        for _ in range(3):
            await RisingEdge(d.clk)
        d.rst_n.value = 1
        await RisingEdge(d.clk)

    def fault(self, slot, ftype, row=0, col=0, bit=0, arow=0, acol=0):
        """Inject fault number `slot` (0..3). Rows >= 16 are spare rows."""
        m = self.mem
        m.f_type[slot].value = ftype; m.f_row[slot].value = row; m.f_col[slot].value = col
        m.f_bit[slot].value = bit; m.f_arow[slot].value = arow; m.f_acol[slot].value = acol

    def clear_faults(self):
        for s in range(4):
            self.fault(s, 0)

    async def bist(self):
        d = self.dut
        await FallingEdge(d.clk)
        d.bist_start.value = 1
        await FallingEdge(d.clk)
        d.bist_start.value = 0
        for _ in range(5000):
            await RisingEdge(d.clk)
            if d.bist_done.value == 1:
                break
        else:
            assert False, "bist_done never came"
        status = NAMES[int(d.bist_status.value)]
        used = bin(int(d.spares_used.value)).count("1")
        return status, used

    async def functional(self, n=600):
        """Random writes / reads through the normal port; every read must return the last written value."""
        d = self.dut
        ref = {}
        for a in range(ROWS * COLS):                       # fill every word first
            await self.write(a, random.getrandbits(DW), ref)
        for _ in range(n):
            a = random.randrange(ROWS * COLS)
            if random.random() < 0.5:
                await self.write(a, random.getrandbits(DW), ref)
            else:
                got = await self.read(a)
                assert got == ref[a], f"address {a} (row {a >> COLB}): read {got:#x}, expected {ref[a]:#x}"
        d.we.value = 0

    async def write(self, a, v, ref):
        d = self.dut
        await FallingEdge(d.clk)
        d.we.value = 1; d.addr.value = a; d.wdata.value = v
        ref[a] = v
        await RisingEdge(d.clk)

    async def read(self, a):
        d = self.dut
        await FallingEdge(d.clk)
        d.we.value = 0; d.addr.value = a
        await Timer(1, unit="ns")
        return int(d.rdata.value)

    async def check(self, exp_status, exp_used, name):
        status, used = await self.bist()
        self.dut._log.info("%s: %s, %d spare row(s) used", name, status, used)
        assert status == exp_status, f"{name}: status {status}, expected {exp_status}"
        assert used == exp_used, f"{name}: {used} spare rows used, expected {exp_used}"
        if status in ("PASS", "REPAIRED"):
            await self.functional()


@cocotb.test()
async def test_no_fault(dut):
    """Good memory: PASS, no spare used."""
    tb = Tb(dut); await tb.reset()
    await tb.check("PASS", 0, "no fault")


@cocotb.test()
async def test_one_cell(dut):
    """One stuck-at-0 cell: its row is replaced by a spare."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, SA0, row=5, col=2, bit=3)
    await tb.check("REPAIRED", 1, "one stuck-at-0 cell")


@cocotb.test()
async def test_two_rows(dut):
    """Stuck-at-1 and transition faults in two rows: both spares used."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, SA1, row=1, col=0, bit=7)
    tb.fault(1, TF, row=14, col=3, bit=0)
    await tb.check("REPAIRED", 2, "two faulty rows")


@cocotb.test()
async def test_same_row(dut):
    """Three faults in the same row need only one spare."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, SA0, row=9, col=0, bit=1)
    tb.fault(1, SA1, row=9, col=1, bit=4)
    tb.fault(2, TF, row=9, col=3, bit=6)
    await tb.check("REPAIRED", 1, "three faults in one row")


@cocotb.test()
async def test_too_many_rows(dut):
    """Three faulty rows, only two spares: FAIL."""
    tb = Tb(dut); await tb.reset()
    for s, r in enumerate((2, 7, 12)):
        tb.fault(s, SA0, row=r, col=1, bit=2)
    await tb.check("FAIL", 2, "three faulty rows")


@cocotb.test()
async def test_coupling(dut):
    """Coupling fault: writing row 3 flips a cell in row 10. The victim row is replaced."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, CF, row=10, col=2, bit=5, arow=3, acol=1)
    await tb.check("REPAIRED", 1, "coupling fault")


@cocotb.test()
async def test_bad_spare(dut):
    """Row 4 is faulty and so is the spare that replaces it: the retest after repair catches it."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, SA0, row=4, col=0, bit=0)
    tb.fault(1, SA1, row=ROWS + 0, col=3, bit=2)        # first spare row
    await tb.check("FAIL", 1, "faulty spare row")


@cocotb.test()
async def test_column(dut):
    """A broken bit line fails every row: spare rows cannot repair it."""
    tb = Tb(dut); await tb.reset()
    tb.fault(0, COL0, col=1, bit=6)
    await tb.check("FAIL", 2, "column fault")


@cocotb.test()
async def test_random(dut):
    """Random cell faults in random rows, many rounds: status and spare count must match the number of faulty rows."""
    tb = Tb(dut); await tb.reset()
    for k in range(int(os.environ.get("ROUNDS", "20"))):
        tb.clear_faults()
        n = random.randint(0, 4)
        rows = set()
        for s in range(n):
            r = random.randrange(ROWS)
            tb.fault(s, random.choice((SA0, SA1, TF)), row=r, col=random.randrange(COLS), bit=random.randrange(DW))
            rows.add(r)
        exp = "PASS" if not rows else "REPAIRED" if len(rows) <= SPARES else "FAIL"
        await tb.check(exp, min(len(rows), SPARES), f"round {k}: {n} faults in rows {sorted(rows)}")
