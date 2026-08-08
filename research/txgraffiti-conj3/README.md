# TxGraffiti Conjecture 3: `i(G) <= mu*(G)` for regular graphs

An attempt on an open problem in graph theory: does every `r`-regular graph
(`r > 0`) satisfy

        i(G)  <=  mu*(G)

where `i` is the independent domination number (smallest maximal independent
set) and `mu*` is the saturation number (smallest maximal matching)?

Conjectured by the automated system **TxGraffiti** in 2020 and published as one
of four open problems in Davila–Brimkov–Pepper,
[*In Reverie Together*](https://arxiv.org/abs/2507.17780). It is known for
`r <= 2` and open for `r >= 3`. It is sharp: `K_{r,r}` and the Petersen graph
give equality.

**The conjecture is still open — nothing here settles it.** What is here:

* [`notes.md`](notes.md) — the mathematics: a structure theorem for the cubic
  graphs with the smallest possible `mu*`, and a reduction of that case to a
  transversal question `Q(t)` about pairings of the edges of a cubic multigraph.
* [`RESULTS.md`](RESULTS.md) — what was computed and what it shows, including
  what was *not* done.

Headline findings:

* Verified for **all connected cubic graphs on at most 22 vertices**
  (7,876,000 graphs) and **all regular graphs of every degree on at most 13
  vertices**. No counterexample.
* Verified for **every cubic graph on at most 30 vertices attaining the minimum
  saturation number** `mu* = 3n/10` — the class where the inequality has the
  least room.
* The inequality is remarkably tight: 5.4% of cubic graphs on 22 vertices
  attain equality, and `max i` and `min mu*` are attained by different graphs,
  so no purely extremal argument can prove it.

## Layout

    src/search.c       exact i(G), mu*(G) by branch and bound; reads graph6
    src/verify.py      naive brute-force reference, shares no logic with the C
    src/tight.c        search of the extremal cubic family (structure theorem)
    src/g6.py          graph6 encoder for the named test graphs
    src/sweep.sh       parallel exhaustive sweep of r-regular graphs of order n
    src/allreg.sh      sweep over every degree for a range of orders
    src/tightsweep.sh  parallel driver for the extremal-family search
    logs/*.summary     results

Requires `nauty` (`apt-get install nauty`) and a C compiler. See
[`RESULTS.md`](RESULTS.md) §6 for exact reproduction commands.
