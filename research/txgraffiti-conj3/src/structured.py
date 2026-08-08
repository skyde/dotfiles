#!/usr/bin/env python3
"""Emit well-known families of regular graphs in graph6, for testing against
the conjecture.  Exhaustive search only reaches small orders, so this covers
named and highly structured graphs up to 64 vertices instead -- snarks,
generalized Petersen graphs, hypercubes, Kneser graphs, circulants -- the kind
of graph that tends to be extremal for domination and matching parameters.
"""
import sys
from itertools import combinations
from math import gcd

from g6 import encode


def emit(name, n, edges, seen):
    """Emit if the graph is simple and regular."""
    es = set()
    for u, v in edges:
        if u == v:
            return
        es.add((min(u, v), max(u, v)))
    deg = [0] * n
    for u, v in es:
        deg[u] += 1
        deg[v] += 1
    if len(set(deg)) != 1 or deg[0] == 0 or n > 64:
        return
    g = encode(n, es)
    if g in seen:
        return
    seen.add(g)
    print("%s\t%s\t%d\t%d" % (g, name, n, deg[0]))


def generalized_petersen(n, k):
    e = [(i, (i + 1) % n) for i in range(n)]
    e += [(n + i, n + (i + k) % n) for i in range(n)]
    e += [(i, n + i) for i in range(n)]
    return 2 * n, e


def flower_snark(k):
    """J_k for odd k >= 5: 4k vertices, cubic."""
    e = []
    for i in range(k):
        a, b, c, d = 4 * i, 4 * i + 1, 4 * i + 2, 4 * i + 3
        e += [(a, b), (a, c), (a, d)]              # star centre a
    for i in range(k):                             # outer 2k-cycle
        e.append((4 * i + 1, 4 * ((i + 1) % k) + 1))
    for i in range(k - 1):
        e.append((4 * i + 2, 4 * (i + 1) + 2))
        e.append((4 * i + 3, 4 * (i + 1) + 3))
    e.append((4 * (k - 1) + 2, 3))                 # the twist
    e.append((4 * (k - 1) + 3, 2))
    return 4 * k, e


def hypercube(d):
    n = 1 << d
    return n, [(x, x ^ (1 << i)) for x in range(n) for i in range(d) if x < (x ^ (1 << i))]


def kneser(n, k):
    verts = list(combinations(range(n), k))
    idx = {v: i for i, v in enumerate(verts)}
    e = []
    for a, b in combinations(verts, 2):
        if not set(a) & set(b):
            e.append((idx[a], idx[b]))
    return len(verts), e


def circulant(n, conn):
    e = []
    for i in range(n):
        for s in conn:
            e.append((i, (i + s) % n))
    return n, e


def mobius_ladder(k):
    n = 2 * k
    return n, [(i, (i + 1) % n) for i in range(n)] + [(i, i + k) for i in range(k)]


def main():
    seen = set()

    for n in range(3, 33):
        for k in range(1, (n + 1) // 2):
            if 2 * k == n:
                continue
            N, e = generalized_petersen(n, k)
            emit("GP(%d,%d)" % (n, k), N, e, seen)

    for k in range(5, 17, 2):
        N, e = flower_snark(k)
        emit("FlowerSnark J%d" % k, N, e, seen)

    for d in range(2, 7):
        N, e = hypercube(d)
        emit("Q%d" % d, N, e, seen)

    for n in range(4, 13):
        for k in range(1, n // 2 + 1):
            N, e = kneser(n, k)
            if N <= 64:
                emit("Kneser(%d,%d)" % (n, k), N, e, seen)

    for n in range(5, 65):
        for conn in ([1, 2], [1, 3], [1, 4], [2, 3], [1, 2, 3], [1, 2, 4],
                     [1, 3, 5], [1, 2, 3, 4], [1, 5], [2, 5], [1, 2, 5]):
            if max(conn) * 2 < n:
                N, e = circulant(n, conn)
                emit("C%d(%s)" % (n, ",".join(map(str, conn))), N, e, seen)

    for k in range(2, 33):
        N, e = mobius_ladder(k)
        emit("MobiusLadder%d" % k, N, e, seen)

    for r in range(1, 33):
        emit("K%d,%d" % (r, r), 2 * r,
             [(i, r + j) for i in range(r) for j in range(r)], seen)

    for n in range(2, 65):                       # complete graphs
        emit("K%d" % n, n, [(i, j) for i in range(n) for j in range(i + 1, n)], seen)


if __name__ == '__main__':
    main()
