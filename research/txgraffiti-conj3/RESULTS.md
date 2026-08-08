# Results

An attack on the third open conjecture of Davila, Brimkov and Pepper,
*In Reverie Together* ([arXiv:2507.17780](https://arxiv.org/abs/2507.17780)):

> If `G` is an `r`-regular graph with `r > 0`, then `i(G) <= mu*(G)`.

**Bottom line: the conjecture was not resolved. No counterexample exists in any
of the ranges searched, and the conjecture is proved here for one natural
extremal class of cubic graphs.** What is new is (a) a structure theorem for the
cubic graphs where the inequality has the least room, (b) a reduction of that
case to a clean transversal question, and (c) exhaustive verification over
ranges far beyond the few hundred graphs the conjecture was originally tested
on.

---

## 1. Why this conjecture

The paper states four open TxGraffiti conjectures. Checking the current
literature first:

| # | Statement | Status |
|---|-----------|--------|
| 1 | `alpha(G) >= (a(G)+R(G))/Delta(G)` | **proved** — Gupta, [arXiv:2606.29553](https://arxiv.org/abs/2606.29553) (Jun 2026), except `K_2` |
| 2 | `Z(G) <= alpha(G)+1` for `Delta <= 3`, `G ≇ K_4` | **refuted** — [arXiv:2607.23664](https://arxiv.org/abs/2607.23664) (Jul 2026), 24-vertex subcubic counterexample |
| 3 | **`i(G) <= mu*(G)` for `r`-regular `G`** | **open** since 2020 |
| 4 | `mu*(G) <= H(G)` | **refuted** — Bıyıkoğlu 2026; smallest counterexample the friendship graph `F_4`, see Gupta [arXiv:2606.15761](https://arxiv.org/abs/2606.15761) |

Only Conjecture 3 is still open, so it is the target. (Conjecture 4's known
counterexample `F_4` is reproduced by the tooling here as a correctness check:
`mu*(F_4) = 4 > 3.6 = H(F_4)`.)

## 2. Correctness of the tooling

`src/search.c` computes `i(G)` and `mu*(G)` exactly by branch and bound.
`src/verify.py` recomputes both by naive enumeration of all vertex subsets and
all edge subsets, sharing no logic with the C code.

* They agree on **all 12,109 connected graphs with `n <= 8`**.
* Hand-checkable values are reproduced: `K_4 (1,2)`, `K_{3,3} (3,3)`,
  Petersen `(3,3)`, `C_5 x K_2 (4,4)`, `K_{4,4} (4,4)`.
* Every graph count produced by the sweeps matches the published enumeration of
  connected cubic graphs (OEIS A002851: 1, 2, 5, 19, 85, 509, 4060, 41301,
  510489, 7319447 for `n = 4, 6, ..., 22`), so the searches really were
  exhaustive.

## 3. Exhaustive verification

### All regular graphs, every degree

Every connected `r`-regular graph of order `n <= 13`, for every `r`, satisfies
`i(G) <= mu*(G)`; no counterexample. Full table in `logs/allreg.summary`.
Order 14 is covered for every degree except `r = 6, 7` in
`logs/order14.summary` (those two classes have about 21.6 million graphs each);
the order-14 sweep also includes disconnected regular graphs, which Lemma 1
does not require but which cost nothing.

A by-product worth recording: in every sweep the observed `min mu*` equals
`ceil(nr/(2(2r-1)))` exactly whenever that value is attainable, i.e. Lemma 2 is
tight across the whole range.

### Cubic graphs

| `n` | connected cubic graphs | counterexamples | `max i` | `min mu*` | ties `i = mu*` |
|-----|-----------------------:|----------------:|--------:|----------:|---------------:|
| 16  | 4,060       | 0 | 6 | 5 | 1,470  |
| 18  | 41,301      | 0 | 6 | 6 | 1,692  |
| 20  | 510,489     | 0 | 7 | 6 | 17,781 |
| 22  | 7,319,447   | 0 | 8 | 7 | 395,378 |

Together with the smaller orders (1, 2, 5, 19, 85, 509 for `n = 4, ..., 14`):
**the conjecture holds for every connected cubic graph on at most 22
vertices** — 7,875,918 graphs in total.

Two things stand out. First, the inequality is *extremely* tight: at `n = 22`,
395,378 cubic graphs (5.4%) attain equality, and the gap `i - mu*` never exceeds
`0`. Second, the extremes are attained separately — at `n = 22` some graph has
`i = 8` and some other graph has `mu* = 7`, so no argument that merely bounds
`max i` against `min mu*` can work. The statement is genuinely per-graph.

## 4. Where the inequality is tightest, and what happens there

`mu*(G) >= nr/(2(2r-1))` for `r`-regular `G`, with equality exactly when `G`
has a dominating induced matching (`notes.md`, Lemma 2). For cubic graphs this
is `mu* >= 3n/10`, and the graphs attaining it are precisely where a
counterexample has the most room, since `i` can be as large as `3n/8`.

**Theorem 3 (notes.md).** A cubic graph `G` has `mu*(G) = 3n/10` iff `n = 10t`
and `G` is obtained from a loopless cubic multigraph `D` on `4t` vertices by
subdividing every edge and adding a perfect pairing of the `6t` subdivision
vertices. The Petersen graph is the case `t = 1`, and it satisfies
`i = mu* = 3` — the conjecture is tight on it.

This was checked computationally as well: all 332,640 pairings over all 32
loopless cubic multigraphs on 8 vertices give graphs with `mu* = 6 = 3t`
exactly, as the theorem predicts.

**Proposition 4/5 (notes.md).** In this family, `i(G) <= 3t = mu*(G)` as soon as
some *transversal* of the pairing (one edge from each pair) covers every vertex
of `D`. So everything reduces to:

> **Q(t).** For every loopless cubic multigraph `D` on `4t` vertices and every
> pairing of `E(D)`, is there a transversal covering all of `V(D)` —
> equivalently, a transversal of maximum degree `<= 2`?

`Q(t)` is a 3-SAT instance with `3t` variables and `4t` clauses, density `4/3`.
Every standard sufficient condition fails on it: the union bound only settles
`t = 1`, and the Lovász Local Lemma is not applicable even in Shearer's sharp
form (`p = 1/8` against a threshold of `9^9/10^10 ≈ 0.039`). So `Q(t)` is not a
routine statement.

**Proposition 6 (notes.md).** `Q(1)` holds, by counting: at most `4` of the `8`
transversals are bad.

**Computational results on `Q(t)`.** Writing `N(D, π)` for the number of
covering transversals, `Q(t)` asks whether `N > 0` always.

| `t` | `n = 10t` | scope | pairings tested | `N = 0` found | `min N` |
|-----|-----------|-------|----------------:|--------------:|--------:|
| 2 | 20 | **exhaustive** — all 32 multigraphs `D`, all pairings | 332,640 | none | **4** |
| 3 | 30 | **exhaustive** — all 709 multigraphs `D`, all pairings | 24,431,732,325 | none | **4** |
| 4 | 40 | local search over pairings, 1,200 sampled `D` | 2.4 x 10^8 | none | <= 42 |
| 5 | 50 | local search over pairings, 301 sampled `D` | 1.1 x 10^7 | none | <= 49 |

So `Q(2)` and `Q(3)` both hold, the second after testing all 24.4 billion
pairings. Consequently:

**The conjecture holds for every cubic graph on at most 30 vertices that attains
the minimum possible saturation number `mu* = 3n/10`** (i.e. for `n = 10, 20,
30`; `n = 10` also follows from Proposition 6 without any computation).

(The `t = 4` and `t = 5` figures are only upper bounds on the true minimum:
hill-climbing on `N` stalls in local minima well above the floor, so they say
nothing beyond the fact that `N = 0` was never reached.)

Two quantitative surprises. First, `min N = 4` at both `t = 2` and `t = 3` — the
floor does not drop as `t` grows, even though the counting bound of §5 gives the
adversary steadily more room. That suggests the stronger statement `N >= 4` for
all `t >= 2`, which would imply `Q(t)`. Second, no pairing anywhere in the
exhaustive range came even close to failing: `N = 0` never occurred, and
`N = 4` was already the worst case at `t = 2`.

## 5. Named and structured families

Exhaustive search only reaches small orders, so 1,001 highly structured regular
graphs on up to 64 vertices were tested separately — the sort of graph that is
usually extremal for domination and matching parameters:

* generalized Petersen graphs `GP(n,k)`, `n <= 32` (240 graphs)
* circulants `C_n(S)` for a range of connection sets (617)
* flower snarks `J_5, J_7, ..., J_15`, Möbius ladders, hypercubes `Q_2..Q_6`
* Kneser graphs `K(n,k)` with at most 64 vertices (20)
* complete graphs and complete bipartite graphs `K_{r,r}`

**979 decided, no counterexample.** The 22 undecided cases are all `K_{r,r}`
with `r >= 11`, where the branch and bound stalls because the minimum maximal
matching is a perfect matching — and those are settled in closed form instead
(`notes.md`, Proposition 7): `i(K_{r,r}) = mu*(K_{r,r}) = r`, equality.

Lemma 2's bound `mu*(G) >= ceil(nr/(2(2r-1)))` is also used as a fast path in
`search.c`: if an independent dominating set of that size exists, the
conjecture holds for `G` without touching the matching side at all. That one
test takes the 64-vertex circulants from "no answer in 25 s" to instant. and across every sweep the observed `min mu*` equals
that bound exactly wherever the bound is achievable, which is an independent
check on the lemma.

## 6. What was not done

* The conjecture remains **open**. Nothing here proves it in general, and no
  counterexample was found.
* `Q(t)` is verified, not proved, for `t = 2, 3`; `t >= 4` is only sampled.
* Only the `mu*`-minimal cubic graphs are covered by the structural argument.
  For `r >= 4` the analogous extremal class involves `(r-1)`-uniform
  hypergraphs (`notes.md`, §6) and was not searched.
* Cubic graphs on 24+ vertices, and non-cubic regular graphs on 14+ vertices,
  were not searched exhaustively.

Random cubic graphs are far from tight (at `n = 50` a random cubic graph
typically has `i ≈ 14`, `mu* ≈ 16`), so unstructured search is not a promising
route; the extremal family really is the place to look.

## 7. Reproducing

```sh
apt-get install -y nauty
cc -O3 -march=native -o src/search src/search.c
cc -O3 -march=native -o src/tight  src/tight.c

# cross-validate the exact code against the naive reference
for n in 4 5 6 7 8; do nauty-geng -qc $n; done > /tmp/g.g6
diff <(./src/search --any --invariants < /tmp/g.g6 | sort) \
     <(python3 src/verify.py          < /tmp/g.g6 | sort) && echo AGREE

./src/allreg.sh 4 13                  # all regular graphs, orders 4..13
./src/order14.sh                      # every degree at order 14
./src/sweep.sh 3 22 4                 # all connected cubic graphs on 22 vertices
./src/tightsweep.sh 12 4 --mincount   # extremal family, n = 30 (24.4e9 pairings)
(cd src && python3 structured.py) > data/structured.tsv
./src/structsweep.sh                  # named families up to 64 vertices
```

## References

* R. Davila, B. Brimkov, R. Pepper, *In Reverie Together: Ten Years of
  Mathematical Discovery with a Machine Collaborator*,
  [arXiv:2507.17780](https://arxiv.org/abs/2507.17780).
* C. Gupta, *An annihilation-number Caro–Wei bound*,
  [arXiv:2606.29553](https://arxiv.org/abs/2606.29553).
* C. Gupta, *Sharp bounds between the saturation number and the harmonic
  index*, [arXiv:2606.15761](https://arxiv.org/abs/2606.15761).
* *A counterexample to the zero forcing versus independence conjecture for
  cubic and subcubic graphs*,
  [arXiv:2607.23664](https://arxiv.org/abs/2607.23664).
* B. McKay, A. Piperno, *nauty and Traces*.
