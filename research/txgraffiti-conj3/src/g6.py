#!/usr/bin/env python3
"""Minimal graph6 encoder/decoder used to build named test graphs."""


def encode(n, edges):
    adj = set()
    for u, v in edges:
        adj.add((min(u, v), max(u, v)))
    bits = []
    for j in range(1, n):
        for i in range(j):
            bits.append(1 if (i, j) in adj else 0)
    while len(bits) % 6:
        bits.append(0)
    out = chr(n + 63) if n < 63 else (
        chr(126) + chr(((n >> 12) & 63) + 63) + chr(((n >> 6) & 63) + 63) + chr((n & 63) + 63))
    for k in range(0, len(bits), 6):
        v = 0
        for b in bits[k:k + 6]:
            v = (v << 1) | b
        out += chr(v + 63)
    return out


def complete(n):
    return encode(n, [(i, j) for i in range(n) for j in range(i + 1, n)])


def cycle(n):
    return encode(n, [(i, (i + 1) % n) for i in range(n)])


def complete_bipartite(a, b):
    return encode(a + b, [(i, a + j) for i in range(a) for j in range(b)])


def petersen():
    e = [(i, (i + 1) % 5) for i in range(5)]
    e += [(5 + i, 5 + (i + 2) % 5) for i in range(5)]
    e += [(i, 5 + i) for i in range(5)]
    return encode(10, e)


def friendship(k):
    """k triangles sharing one vertex; 2k+1 vertices, centre = 0."""
    e = []
    for t in range(k):
        a, b = 1 + 2 * t, 2 + 2 * t
        e += [(0, a), (0, b), (a, b)]
    return encode(2 * k + 1, e)


def prism(k):
    """Circular ladder CL_k = C_k x K_2, cubic on 2k vertices."""
    e = [(i, (i + 1) % k) for i in range(k)]
    e += [(k + i, k + (i + 1) % k) for i in range(k)]
    e += [(i, k + i) for i in range(k)]
    return encode(2 * k, e)


if __name__ == '__main__':
    print(complete(4))                 # K4
    print(complete_bipartite(3, 3))    # K3,3
    print(petersen())                  # Petersen
    print(cycle(5))
    print(cycle(6))
    print(cycle(7))
    print(cycle(9))
    print(prism(5))                    # pentagonal prism C5 x K2
    print(complete(5))
    print(complete_bipartite(4, 4))
    print(friendship(4))               # not regular; mu* = 4 (Conj-4 counterexample)
