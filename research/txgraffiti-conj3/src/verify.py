#!/usr/bin/env python3
"""Independent brute-force reference implementation.

Deliberately naive -- it enumerates every vertex subset and every edge subset
-- so that it shares no logic with the branch-and-bound search in search.c.
Used to cross-check search.c on every small graph.

Usage:  ./verify.py < graphs.g6          # prints "<g6> n=.. r=.. i=.. mu*=.."
"""
import sys
from itertools import combinations


def read_graph6(s):
    s = s.strip()
    if s.startswith('>>graph6<<'):
        s = s[10:]
    data = [ord(c) - 63 for c in s]
    if data[0] != 63 + 63:  # not 126
        n, off = data[0], 1
    else:
        n, off = (data[1] << 12) | (data[2] << 6) | data[3], 4
    bits = []
    for c in data[off:]:
        bits.extend((c >> k) & 1 for k in range(5, -1, -1))
    adj = [set() for _ in range(n)]
    k = 0
    for j in range(1, n):
        for i in range(j):
            if bits[k]:
                adj[i].add(j)
                adj[j].add(i)
            k += 1
    return n, adj


def independent_domination_number(n, adj):
    """Minimum size of a set that is both independent and dominating."""
    for k in range(0, n + 1):
        for S in combinations(range(n), k):
            Ss = set(S)
            if any(adj[u] & Ss for u in S):          # not independent
                continue
            if all(v in Ss or adj[v] & Ss for v in range(n)):  # dominating
                return k
    return n


def saturation_number(n, adj):
    """Minimum size of a maximal matching."""
    edges = [(u, v) for u in range(n) for v in adj[u] if u < v]
    for k in range(0, len(edges) + 1):
        for M in combinations(edges, k):
            used = set()
            ok = True
            for u, v in M:
                if u in used or v in used:
                    ok = False
                    break
                used.add(u)
                used.add(v)
            if not ok:
                continue
            # maximal iff no edge has both endpoints free
            if all(u in used or v in used for u, v in edges):
                return k
    return len(edges)


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        n, adj = read_graph6(line)
        degs = {len(a) for a in adj}
        r = degs.pop() if len(degs) == 1 else -1
        print("%s n=%d r=%d i=%d mu*=%d" % (
            line, n, r,
            independent_domination_number(n, adj),
            saturation_number(n, adj)))


if __name__ == '__main__':
    main()
