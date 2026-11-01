"""redundancy.py : redundancy analysis (RA) for a memory with spare rows AND spare columns

A fault map is a set of (row, col) cells (col = bit-column: word position x bit). With SR spare rows and SC spare
columns, the memory is repairable if every faulty cell is covered by a replaced row or a replaced column.
Choosing the lines is the 2D redundancy allocation problem (NP-complete in general); four allocators:

  row_only      : rows only (the current hardware), SR + SC spare rows
  greedy        : repeatedly replace the line (row or column) with the most uncovered faults
  must_greedy   : must-repair first (a row with more faults than SC columns can fix MUST take a spare row,
                  a column with more faults than SR rows can fix MUST take a spare column; repeat), then greedy
  optimal       : exhaustive search (branch on "this fault's row or this fault's column"), the true answer

Each returns (rows, cols) or None if it finds no repair.
"""
import random


def row_only(faults, sr, sc):
    rows = {r for r, _ in faults}
    return (rows, set()) if len(rows) <= sr + sc else None


def _left(faults, rows, cols):
    return {(r, c) for r, c in faults if r not in rows and c not in cols}


def _greedy_fill(faults, rows, cols, sr, sc):
    rows, cols = set(rows), set(cols)
    left = _left(faults, rows, cols)
    while left:
        best = None
        for line, n in _line_counts(left).items():
            kind = line[0]
            if (kind == "r" and len(rows) >= sr) or (kind == "c" and len(cols) >= sc):
                continue
            if best is None or n > best[1]:
                best = (line, n)
        if best is None:
            return None
        kind, idx = best[0]
        (rows if kind == "r" else cols).add(idx)
        left = _left(left, rows, cols)
    return rows, cols


def _line_counts(cells):
    cnt = {}
    for r, c in cells:
        cnt[("r", r)] = cnt.get(("r", r), 0) + 1
        cnt[("c", c)] = cnt.get(("c", c), 0) + 1
    return cnt


def greedy(faults, sr, sc):
    return _greedy_fill(faults, set(), set(), sr, sc)


def must_greedy(faults, sr, sc):
    rows, cols = set(), set()
    while True:                       # one must-repair at a time: counts change after every replaced line
        left = _left(faults, rows, cols)
        must = next(((k, i) for (k, i), n in _line_counts(left).items()
                     if (k == "r" and n > sc - len(cols)) or (k == "c" and n > sr - len(rows))), None)
        if must is None:
            break
        (rows if must[0] == "r" else cols).add(must[1])
        if len(rows) > sr or len(cols) > sc:
            return None
    return _greedy_fill(faults, rows, cols, sr, sc)


def optimal(faults, sr, sc):
    def search(left, rows, cols):
        if not left:
            return rows, cols
        r, c = next(iter(left))
        if len(rows) < sr:
            res = search(_left(left, rows | {r}, cols), rows | {r}, cols)
            if res:
                return res
        if len(cols) < sc:
            res = search(_left(left, rows, cols | {c}), rows, cols | {c})
            if res:
                return res
        return None
    return search(set(faults), frozenset(), frozenset())


ALLOCATORS = {"row only": row_only, "greedy": greedy, "must-repair + greedy": must_greedy, "optimal": optimal}


def random_faults(n, rows, cols, rng, p_line=0.0):
    """n random faulty cells; with probability p_line each fault is a whole broken row or column instead."""
    f = set()
    for _ in range(n):
        if rng.random() < p_line:
            if rng.random() < 0.5:
                r = rng.randrange(rows); f |= {(r, c) for c in range(cols)}
            else:
                c = rng.randrange(cols); f |= {(r, c) for r in range(rows)}
        else:
            f.add((rng.randrange(rows), rng.randrange(cols)))
    return f


def check(faults, sol, sr, sc):
    if sol is None:
        return True
    rows, cols = sol
    return len(rows) <= sr and len(cols) <= sc and not _left(faults, set(rows), set(cols))
