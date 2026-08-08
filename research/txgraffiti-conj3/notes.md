# Independent domination vs. saturation number in regular graphs

Working notes on the third open conjecture of *In Reverie Together: Ten Years of
Mathematical Discovery with a Machine Collaborator* (Davila, Brimkov, Pepper,
[arXiv:2507.17780](https://arxiv.org/abs/2507.17780)).

> **Conjecture (TxGraffiti, open since 2020).**
> If `G` is an `r`-regular graph with `r > 0`, then `i(G) <= mu*(G)`.

* `i(G)` — *independent domination number*: the least size of a maximal
  independent set (equivalently, of an independent dominating set).
* `mu*(G)` — *saturation number*: the least size of a maximal matching.

The conjecture is known for `r = 1, 2` and is open for `r >= 3`.  It is sharp:
`K_{r,r}` has `i = mu* = r`, and the Petersen graph has `i = mu* = 3`.

Throughout, `n = |V(G)|` and `m = |E(G)|`.

---

## 1. Reduction to connected graphs

**Lemma 1.** `i` and `mu*` are both additive over connected components.
Consequently the conjecture for all `r`-regular graphs follows from the
connected case.

*Proof.* A set `S` is independent and dominating in `G` iff `S ∩ V(G_j)` is
independent and dominating in each component `G_j`, so `i(G) = Σ i(G_j)`.  A
matching `M` is maximal in `G` iff `M ∩ E(G_j)` is maximal in each `G_j`, so
`mu*(G) = Σ mu*(G_j)`.  Every component of an `r`-regular graph is
`r`-regular. ∎

This is why the searches below range over *connected* regular graphs only.

## 2. How small can `mu*` be?

**Lemma 2.** If `G` is `r`-regular of order `n` then

        mu*(G) >= n r / (2 (2r - 1)),

with equality if and only if `G` has a *dominating induced matching* (i.e. `G`
is efficiently edge-dominatable).

*Proof.* A maximal matching `M` is an edge dominating set.  An edge `uv ∈ M` is
adjacent to at most `(r-1) + (r-1)` other edges, so it dominates at most
`2r - 1` edges in total.  Every edge is dominated, hence
`|M| (2r-1) >= m = nr/2`.

For equality every edge must be dominated exactly once.  If an edge `g` joined
an endpoint of `f_1 ∈ M` to an endpoint of `f_2 ∈ M` with `f_1 ≠ f_2`, then `g`
would be dominated twice; so no such `g` exists and `G[V(M)] = M`, i.e. `M` is
induced.  Conversely, for a dominating induced matching the count is exact. ∎

For cubic graphs this reads `mu*(G) >= 3n/10`.

## 3. Structure of the extremal cubic graphs

Write `n = 10t`, so the bound of Lemma 2 is `mu* = 3t`.

Given a loopless cubic multigraph `D` on `4t` vertices (it has `6t` edges) and a
perfect *pairing* `π` of `E(D)`, let

        S(D, π)

be the graph obtained by subdividing every edge of `D` once and then joining the
two subdivision vertices of each pair of `π` by an edge.

**Theorem 3.** A cubic graph `G` of order `n` satisfies `mu*(G) = 3n/10` if and
only if `10 | n` and `G ≅ S(D, π)` for some loopless cubic multigraph `D` on
`4t` vertices and some pairing `π` of `E(D)`, where `n = 10t`.

*Proof.* (⇒) Let `M` be a dominating induced matching (Lemma 2), `A = V(M)`,
`B = V ∖ A`.  Then `|A| = 6t` and `|B| = 4t`.  `B` is independent because `M` is
maximal.  Each `a ∈ A` has its `M`-partner as one neighbour and, since
`G[A] = M`, its two remaining neighbours lie in `B`; they are distinct as `G` is
simple.  Each `b ∈ B` has all three neighbours in `A`.  Put `D` on the vertex
set `B`, with one edge for each `a ∈ A` joining the two `B`-neighbours of `a`.
Then `D` is loopless with `6t` edges and every vertex has degree `3`, and `G`
is `S(D, π)` with `π = M`.

(⇐) `S(D, π)` is cubic of order `4t + 6t = 10t`, the subdivision vertices carry
a dominating induced matching of size `3t`, and Lemma 2 applies. ∎

Note that `D` need **not** be connected: the pairing can join components of `D`
while `S(D, π)` is connected.  The enumeration must therefore range over all
loopless cubic multigraphs, connected or not.

*Example.* `t = 1`, `D = K_4`: `S(K_4, π)` is the Petersen graph for a suitable
`π`, and indeed `i = mu* = 3` there — the conjecture is tight.

## 4. The extremal case reduces to a transversal problem

Call `T ⊆ E(D)` a **transversal** of `π` if it contains exactly one edge from
each pair.  Both `T` and its complement `T' = E(D) ∖ T` are transversals, of
size `3t` each.

**Proposition 4.** If some transversal `T` covers every vertex of `D` (i.e. `T`
is an edge cover), then `i(S(D,π)) <= 3t = mu*(S(D,π))`.

*Proof.* Let `S` be the set of subdivision vertices of the edges in `T`;
`|S| = 3t`.  Two subdivision vertices are adjacent only when paired, and `T`
picks one edge per pair, so `S` is independent.  A vertex `b ∈ B` is dominated
because some edge of `T` meets `b`.  A subdivision vertex is either in `S` or
has its partner in `S`.  So `S` is an independent dominating set. ∎

**Proposition 5.** `T` is an edge cover of `D` if and only if the complementary
transversal `T'` has maximum degree at most `2` in `D`.

*Proof.* A vertex `u` is uncovered by `T` exactly when all three edges at `u`
lie in `T'`, i.e. `deg_{T'}(u) = 3`.  As `D` is cubic there is no other way to
exceed degree `2`. ∎

So everything in the extremal case hangs on:

> **Question Q(t).** For every loopless cubic multigraph `D` on `4t` vertices and
> every pairing `π` of `E(D)`, is there a transversal of maximum degree `<= 2`
> (equivalently, a disjoint union of paths and cycles)?

An affirmative answer to `Q(t)` proves the TxGraffiti conjecture for *every*
cubic graph attaining the minimum saturation number `3n/10`.

## 5. Why `Q(t)` is delicate

`Q(t)` is a satisfiability question: one Boolean per pair (`3t` variables), one
width-3 clause per vertex of `D` (`4t` clauses) saying "at least one incident
edge is chosen".  The clause/variable density is `4/3`, far below the 3-SAT
threshold `≈ 4.267` — but the instance is not random, and every standard
sufficient condition fails:

* **Union bound.** A vertex whose three edges lie in three distinct pairs is
  uncovered by exactly `2^{3t-3}` of the `2^{3t}` transversals, so at most
  `4t · 2^{3t}/8 = t · 2^{3t}/2` transversals are bad.  That is smaller than
  `2^{3t}` only when `t = 1`.
* **Lovász Local Lemma.** The bad event at `u` has probability `1/8` and
  involves the three pairs meeting `u`.  Each pair consists of two edges with
  four endpoints in total, so it is used by at most three *other* vertices;
  hence the dependency degree is `d <= 9`.  Even Shearer's exact bound for
  degree `d` needs `p <= d^d/(d+1)^{d+1} = 9^9/10^10 ≈ 0.0387`, and here
  `p = 1/8 = 0.125`.  The LLL genuinely does not apply.
* **Harris/FKG.** The bad events are not monotone under any re-orientation of
  the variables: each variable occurs twice positively and twice negatively.

**Proposition 6.** `Q(1)` holds.

*Proof.* Here `D` has `4` vertices and `3` pairs, so there are `8` transversals,
and each of the `4` vertices is bad for at most `2^{3-3} = 1` of them.  At most
`4 < 8` transversals are bad. ∎

Hence no cubic graph on `10` vertices with `mu* = 3` is a counterexample. For
`t >= 2` counting no longer suffices; `Q(2)` and `Q(3)` are settled here by
exhaustive computation (see `RESULTS.md`).

A sharper quantity than "is there one?" is *how many* transversals work.  Let
`N(D, π)` be the number of covering transversals, so `Q(t)` asks whether
`N > 0` always.  Exhaustively,

        min N = 4   over all pairings of all cubic multigraphs on  8 vertices (t = 2)
        min N = 4   over all pairings of all cubic multigraphs on 12 vertices (t = 3)

the second over all 24,431,732,325 pairings.  The floor does not fall as `t`
grows, even though the counting bound above gives the adversary steadily more
room, which suggests:

> **Question Q'(t).** Is `N(D, π) >= 4` for every loopless cubic multigraph `D`
> on `4t` vertices with `t >= 2` and every pairing `π`?

An affirmative answer to `Q'` implies `Q`, hence the conjecture for all
`mu*`-minimal cubic graphs.

## 6. The sharpness example, in closed form

**Proposition 7.** `i(K_{r,r}) = mu*(K_{r,r}) = r` for every `r >= 1`.

*Proof.* Let the sides be `X` and `Y`. An independent set is contained in one
side; a nonempty `S ⊆ X` dominates all of `Y`, but the vertices of `X ∖ S` are
not adjacent to anything in `S`, so a maximal independent set is exactly `X` or
exactly `Y`. Hence `i = r`. For the matching, if `M` is a matching with
`|M| = k < r` then at least one vertex of `X` and one of `Y` are unsaturated,
and they are adjacent, so `M` is not maximal. Hence every maximal matching is
perfect and `mu* = r`. ∎

This is why brute force stalls on `K_{r,r}` for large `r` — the minimum maximal
matching is a perfect matching, the worst case for the branch and bound — and
why it does not matter: the family is settled in closed form, with equality.

## 7. General `r`

Lemma 2 holds for all `r`.  In the extremal case `mu* = nr/(2(2r-1))` the same
argument gives `|A| = nr/(2r-1)`, `|B| = n(r-1)/(2r-1)`, with `B` independent,
every `A`-vertex having `r-1` neighbours in `B` and every `B`-vertex having `r`
neighbours in `A`.  For `r = 3` the `A`-vertices have two `B`-neighbours and so
are edges of a multigraph, which is what makes Theorem 3 so concrete; for
`r >= 4` they become hyperedges of size `r-1`, i.e. `D` is an `(r-1)`-uniform
`r`-regular hypergraph.  The analogue of Proposition 4 goes through verbatim, so
the same transversal question governs the extremal case for every `r`.
