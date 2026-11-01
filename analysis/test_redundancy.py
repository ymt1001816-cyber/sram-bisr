"""test_redundancy.py : the exhaustive allocator must agree with brute force over every row / column choice"""
import itertools
import random

from redundancy import ALLOCATORS, check, optimal, random_faults


def test_optimal_matches_brute_force():
    rng = random.Random(5)
    rows, cols, sr, sc = 6, 6, 2, 2
    for _ in range(3000):
        f = random_faults(rng.randint(1, 9), rows, cols, rng, 0.15)
        brute = any(all(r in rs or c in cs for r, c in f)
                    for k in range(sr + 1) for rs in itertools.combinations(range(rows), k)
                    for m in range(sc + 1) for cs in itertools.combinations(range(cols), m))
        assert (optimal(f, sr, sc) is not None) == brute


def test_every_answer_is_a_real_repair():
    rng = random.Random(9)
    for _ in range(2000):
        f = random_faults(rng.randint(1, 8), 16, 32, rng, 0.2)
        for name, fn in ALLOCATORS.items():
            sr, sc = (4, 0) if name == "row only" else (2, 2)
            assert check(f, fn(f, 2, 2), sr, sc), name


if __name__ == "__main__":         # also runs without pytest (python3 test_redundancy.py)
    test_optimal_matches_brute_force()
    test_every_answer_is_a_real_repair()
    print("2 passed")
