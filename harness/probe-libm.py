#!/usr/bin/env python3
"""T-c libm value probe (hypotheses.md): print system-libm results for the
same argument set on both machines; diff the two transcripts.

Design: libm-only — arguments chosen at the scales the cluster's formulas
evaluate (eggholder's sqrt(abs(x/2+y+47)) composites, Ackley3/4
exp(-0.02*sqrt(...)) and exp(cos(3x)+sin(3y)) shapes, pi-adjacent angles,
near-zero squares/sqrts, long-stay rounding boundaries). Pure arithmetic is
excluded on purpose (that is codegen, tested by T-b/T-d, not libm).

Run:  python3 probe-libm.py > out.txt   on cell C's host and inside cell D's image.
"""
import math

ARGS = [
    0.0, 5e-324, 1e-300, 2.2250738585072014e-308,
    0.1, 0.3, 1/3, 0.5471499753164672, 1.5410437815483437,
    1.0, 2.0, 8.787792382, 65964.0, 2865083.0, 567495437.0,
    26760.9911, 474.247, 0.839583,
    2.0 ** 0.5, 3.0, 3.5, 1.0 / 47.0, 44.0,
    100.7, 311.7, 511.69999999, -47.0 + 256.0, 404.2158,
    math.pi, math.pi / 2, 3 * math.pi / 2, math.e, 1e308, -1e308,
    3.141592653589793, 47.0, 512.0, -512.0, 35.0, 2.0,
    0.9999999999999999, 1.0000000000000002,
]


def safe(fn, a):
    try:
        v = fn(a)
        return v
    except (OverflowError, ValueError, ZeroDivisionError):
        return float("nan")


def bits(x):
    return struct.pack(">d", x).hex()


import struct

rows = []
for a in ARGS:
    vals = [
        ("sin", safe(math.sin, a)),
        ("cos", safe(math.cos, a)),
        ("exp", safe(math.exp, a) if abs(a) < 710 else float("nan")),
        ("sqrt", safe(math.sqrt, abs(a))),
        ("atan", safe(math.atan, a)),
        ("log", safe(math.log1p, a) if a > -1 else float("nan")),
        ("pow2-5", safe(lambda x: math.pow(x + 1.0, 2.5), abs(a))),
        ("eggholder", safe(lambda x: math.sin(math.sqrt(abs(x / 2 + 47.0))), a)),
        ("ackley_exp", safe(lambda x: math.exp(-0.002 * math.sqrt(x * x + 1.0)), a)),
        ("ackley_trig", safe(lambda x: math.exp(math.cos(3.0 * x) + math.sin(3.0 * (x + 1.1))), a)),
    ]
    for name, v in vals:
        rows.append("%.17g %s %.17g %s" % (a, name, v, bits(v)))

print("\n".join(rows))
