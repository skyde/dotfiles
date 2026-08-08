/*
 * search.c -- exhaustive test of the TxGraffiti conjecture (open since 2020)
 *
 *      G r-regular, r > 0   ==>   i(G) <= mu*(G)
 *
 * i(G)   = independent domination number (minimum maximal independent set)
 * mu*(G) = saturation number             (minimum maximal matching)
 *
 * Reads graph6 from stdin, one graph per line.  Everything is exact: the
 * searches are complete branch-and-bound, no heuristics or sampling.
 *
 * Decision strategy per graph (avoids computing both invariants in full):
 *   1. greedy independent dominating set  ->  s, an upper bound on i(G)
 *   2. minimum-maximal-matching search seeded with best = s.
 *        - if it cannot beat s then mu*(G) >= s >= i(G): conjecture holds
 *        - otherwise it returns mu*(G) = t exactly
 *   3. decide whether an independent dominating set of size <= t exists.
 *        - yes: i(G) <= t = mu*(G), holds.   no: i(G) > mu*(G), COUNTEREXAMPLE
 *
 * Build: cc -O3 -march=native -o search search.c
 * Usage: nauty-geng -qc -d3 -D3 20 | ./search
 *        ./search --invariants < graphs.g6   (exact n, r, i, mu* per graph)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef uint64_t u64;
#define MAXN 64

static int n;
static u64 nbr[MAXN];         /* open neighbourhood N(v)   */
static u64 clo[MAXN];         /* closed neighbourhood N[v] */
static int deg[MAXN];
static int maxdeg;
static u64 FULL;

static inline int pc(u64 x)   { return __builtin_popcountll(x); }
static inline u64 bit(int i)  { return (u64)1 << i; }
static inline int lsb(u64 x)  { return __builtin_ctzll(x); }

/* ------------------------------------------------------------------ */
/* graph6 decoding                                                      */
/* ------------------------------------------------------------------ */
static int read_graph6(const char *s)
{
    int off;

    if (s[0] == '>') s += 10;                    /* optional >>graph6<< */

    if ((unsigned char)s[0] != 126) {
        n = s[0] - 63; off = 1;
    } else if ((unsigned char)s[1] != 126) {
        n = ((s[1] - 63) << 12) | ((s[2] - 63) << 6) | (s[3] - 63); off = 4;
    } else {
        return 0;
    }
    if (n <= 0 || n > MAXN) return 0;

    FULL = (n == 64) ? ~(u64)0 : (bit(n) - 1);
    for (int v = 0; v < n; v++) nbr[v] = 0;

    long k = 0;
    for (int j = 1; j < n; j++)
        for (int i = 0; i < j; i++, k++) {
            int c = s[off + k / 6] - 63;
            if ((c >> (5 - k % 6)) & 1) { nbr[i] |= bit(j); nbr[j] |= bit(i); }
        }

    maxdeg = 0;
    for (int v = 0; v < n; v++) {
        clo[v] = nbr[v] | bit(v);
        deg[v] = pc(nbr[v]);
        if (deg[v] > maxdeg) maxdeg = deg[v];
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/* mu*(G): minimum maximal matching                                     */
/*                                                                      */
/* State is the set of vertices left free by the partial matching.  A    */
/* matching is maximal iff no two free vertices are adjacent.  If x, y   */
/* are free and adjacent then every maximal extension saturates x or y,  */
/* by an edge whose other endpoint is also currently free -- so branching */
/* over N(x) & free and N(y) & free is exhaustive.                       */
/* ------------------------------------------------------------------ */
static int best_mm;

/* Lower bound on the number of further edges needed: a set of free edges
 * that are pairwise disjoint with no edge between them.  A single new
 * matching edge can saturate an endpoint of at most one of them. */
static int mm_lower_bound(u64 freev)
{
    u64 avail = freev;
    int cnt = 0;
    while (avail) {
        int x = lsb(avail);
        u64 cand = nbr[x] & avail;
        if (!cand) { avail &= avail - 1; continue; }
        int y = lsb(cand);
        cnt++;
        avail &= ~(clo[x] | clo[y]);
    }
    return cnt;
}

static void mm_rec(u64 freev, int size)
{
    /* locate a free edge */
    int x = -1;
    u64 t = freev;
    while (t) {
        int v = lsb(t); t &= t - 1;
        if (nbr[v] & freev) { x = v; break; }
    }
    if (x < 0) {                                  /* maximal */
        if (size < best_mm) best_mm = size;
        return;
    }
    if (size + 1 >= best_mm) return;
    if (size + mm_lower_bound(freev) >= best_mm) return;

    int y = lsb(nbr[x] & freev);

    u64 c = nbr[x] & freev;                       /* edges saturating x */
    while (c) {
        int w = lsb(c); c &= c - 1;
        mm_rec(freev & ~(bit(x) | bit(w)), size + 1);
    }
    c = nbr[y] & freev & ~bit(x);                 /* edges saturating y, x left free */
    while (c) {
        int w = lsb(c); c &= c - 1;
        mm_rec(freev & ~(bit(y) | bit(w)), size + 1);
    }
}

/* Exact mu*, but abandons the search as soon as it is clear that no
 * maximal matching smaller than `cap` exists (then it returns cap). */
static int mu_star_capped(int cap)
{
    best_mm = cap;
    mm_rec(FULL, 0);
    return best_mm;
}

/* ------------------------------------------------------------------ */
/* independent domination                                               */
/*                                                                      */
/* In an independent dominating set the dominated vertices are exactly    */
/* the vertices forbidden from further selection, so one mask suffices,   */
/* and the next chosen vertex is always an undominated one.              */
/* ------------------------------------------------------------------ */
static int ids_cap;

static int ids_rec(u64 dom, int size)
{
    if (dom == FULL) return 1;
    if (size >= ids_cap) return 0;

    int und = pc(FULL & ~dom);
    if (size + (und + maxdeg) / (maxdeg + 1) > ids_cap) return 0;

    /* branch on the undominated vertex with fewest candidates */
    int bv = -1, bc = MAXN + 1;
    u64 u = FULL & ~dom;
    while (u) {
        int v = lsb(u); u &= u - 1;
        int c = pc(clo[v] & ~dom);
        if (c < bc) { bc = c; bv = v; if (c <= 1) break; }
    }
    if (bc == 0) return 0;

    u64 cand = clo[bv] & ~dom;
    while (cand) {
        int w = lsb(cand); cand &= cand - 1;
        if (ids_rec(dom | clo[w], size + 1)) return 1;
    }
    return 0;
}

static int has_ids(int cap) { ids_cap = cap; return ids_rec(0, 0); }

static int i_exact(void)
{
    for (int k = 1; k <= n; k++) if (has_ids(k)) return k;
    return n;
}

/* Greedy independent dominating set: repeatedly take the undominated
 * vertex that newly dominates the most.  Returns its size (>= i(G)). */
static int greedy_ids(void)
{
    u64 dom = 0;
    int size = 0;
    while (dom != FULL) {
        int bv = -1, bg = -1;
        u64 u = FULL & ~dom;
        while (u) {
            int v = lsb(u); u &= u - 1;
            int g = pc(clo[v] & ~dom);
            if (g > bg) { bg = g; bv = v; }
        }
        dom |= clo[bv];
        size++;
    }
    return size;
}

/* ------------------------------------------------------------------ */
int main(int argc, char **argv)
{
    int show_invariants = 0, require_regular = 1, stats = 0;
    for (int a = 1; a < argc; a++) {
        if (!strcmp(argv[a], "--invariants")) show_invariants = 1;
        if (!strcmp(argv[a], "--any"))        require_regular = 0;
        if (!strcmp(argv[a], "--stats"))      stats = 1;
    }

    char line[1 << 16];
    unsigned long long seen = 0, tested = 0, ce = 0;
    /* histogram of i(G) - mu*(G), offset by MAXN */
    unsigned long long hist[2 * MAXN + 1];
    memset(hist, 0, sizeof hist);
    int max_i = -1, min_mu = 1 << 30;
    unsigned long long ties = 0;

    while (fgets(line, sizeof line, stdin)) {
        char *p = strchr(line, '\n');
        if (p) *p = 0;
        if (!line[0]) continue;
        if (!read_graph6(line)) { fprintf(stderr, "bad graph6: %s\n", line); continue; }
        seen++;

        int r = deg[0], regular = 1;
        for (int v = 1; v < n; v++) if (deg[v] != r) { regular = 0; break; }
        if (require_regular && (!regular || r == 0)) continue;
        tested++;

        if (show_invariants) {
            printf("%s n=%d r=%d i=%d mu*=%d\n", line, n, regular ? r : -1,
                   i_exact(), mu_star_capped(n));
            continue;
        }

        if (stats) {                       /* exact both; record the gap */
            int ii = i_exact(), mm = mu_star_capped(n);
            hist[ii - mm + MAXN]++;
            if (ii > max_i) max_i = ii;
            if (mm < min_mu) min_mu = mm;
            if (ii == mm) {
                if (ties < 40)
                    printf("TIE %s n=%d r=%d i=%d mu*=%d\n", line, n, r, ii, mm);
                ties++;
            }
            if (ii > mm) {
                ce++;
                printf("COUNTEREXAMPLE %s n=%d r=%d i=%d mu*=%d\n", line, n, r, ii, mm);
                fflush(stdout);
            }
            continue;
        }

        /* Lemma 2: for r-regular G, mu*(G) >= ceil(nr / (2(2r-1))).  So if an
         * independent dominating set of that size exists we are done without
         * touching the matching side at all, which is the expensive one. */
        if (regular && r >= 1) {
            int den = 2 * (2 * r - 1);
            int lb  = (n * r + den - 1) / den;
            if (has_ids(lb)) continue;     /* i(G) <= lb <= mu*(G) */
        }

        int s  = greedy_ids();             /* i(G) <= s */
        int mu = mu_star_capped(s);        /* mu >= s, or mu == mu*(G) < s */
        if (mu >= s) continue;             /* i(G) <= s <= mu*(G): holds */
        if (has_ids(mu)) continue;         /* i(G) <= mu*(G): holds       */

        ce++;
        printf("COUNTEREXAMPLE %s n=%d r=%d i=%d mu*=%d\n",
               line, n, r, i_exact(), mu_star_capped(n));
        fflush(stdout);
    }

    if (stats) {
        fprintf(stderr, "maxi %d minmu %d ties %llu\n", max_i, min_mu, ties);
        for (int g = -MAXN; g <= MAXN; g++)
            if (hist[g + MAXN])
                fprintf(stderr, "gap %+d : %llu\n", g, hist[g + MAXN]);
    }
    fprintf(stderr, "read=%llu tested=%llu counterexamples=%llu\n", seen, tested, ce);
    return 0;
}
