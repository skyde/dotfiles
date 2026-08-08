/*
 * tight.c -- targeted search of the extremal cubic family for a counterexample
 *            to  i(G) <= mu*(G).
 *
 * Structure theorem (see notes.md).  A cubic graph G on n vertices has the
 * least possible saturation number mu*(G) = 3n/10 exactly when G has a
 * dominating induced matching, and then G is obtained from a cubic multigraph
 * D on 2n/5 vertices by subdividing every edge and adding a perfect matching
 * ("pairing") on the 3n/5 subdivision vertices.  Writing n = 10t:
 *
 *      |V(D)| = 4t,   |E(D)| = 6t,   mu*(G) = 3t,   i(G) <= 4t.
 *
 * So a counterexample inside this family is a pairing with i(G) >= 3t+1.
 * These are the graphs where the conjecture has the least room, so they are
 * the best place to look.  This program reads cubic graphs D in graph6 from
 * stdin and enumerates (or samples) pairings of E(D), testing each G exactly.
 *
 * Build: cc -O3 -march=native -o tight tight.c
 * Usage: nauty-geng -qc -d3 -D3 12 | ./tight            # all pairings, n=30
 *        nauty-geng -qc -d3 -D3 16 | ./tight -s 2000000 # sample, n=40
 *        ... | ./tight --dump                           # emit G in graph6
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

typedef uint64_t u64;
#define MAXN 64

/* ---- the constructed graph G ---- */
static int n;
static u64 clo[MAXN];
static u64 FULL;
static int maxdeg = 3;

static inline int pc(u64 x)  { return __builtin_popcountll(x); }
static inline u64 bit(int i) { return (u64)1 << i; }
static inline int lsb(u64 x) { return __builtin_ctzll(x); }

/* ---- independent domination, identical logic to search.c ---- */
static int ids_cap;

static int ids_rec(u64 dom, int size)
{
    if (dom == FULL) return 1;
    if (size >= ids_cap) return 0;
    int und = pc(FULL & ~dom);
    if (size + (und + maxdeg) / (maxdeg + 1) > ids_cap) return 0;

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

/* ---- D: the base cubic graph ---- */
static int b;                       /* |V(D)| = 4t                 */
static int ne;                      /* |E(D)| = 6t                 */
static int du[64], dv[64];          /* edge endpoints in D         */
static int t;                       /* n = 10t                     */
static int partner[64];             /* pairing on E(D)             */

/* neighbourhood of G built from D + pairing.
 * vertices  0 .. b-1        = V(D)             (independent set B)
 * vertices  b .. b+ne-1     = subdivision      (set A) */
static u64 baseclo[MAXN];           /* the part of N[.] independent of pairing */
static int inc[64][3], incn[64];    /* incident edge slots of each D-vertex */

static void build_base(void)
{
    n = b + ne;
    FULL = (n == 64) ? ~(u64)0 : (bit(n) - 1);
    for (int v = 0; v < n; v++) baseclo[v] = bit(v);
    for (int v = 0; v < b; v++) incn[v] = 0;
    for (int e = 0; e < ne; e++) {
        if (incn[du[e]] < 3) inc[du[e]][incn[du[e]]++] = e;
        if (incn[dv[e]] < 3) inc[dv[e]][incn[dv[e]]++] = e;
    }
    for (int e = 0; e < ne; e++) {
        int a = b + e;
        baseclo[a] |= bit(du[e]) | bit(dv[e]);
        baseclo[du[e]] |= bit(a);
        baseclo[dv[e]] |= bit(a);
    }
}

static void apply_pairing(void)
{
    for (int v = 0; v < n; v++) clo[v] = baseclo[v];
    for (int e = 0; e < ne; e++)
        clo[b + e] |= bit(b + partner[e]);
}

/* ---- graph6 ---- */
static int read_graph6_D(const char *s)
{
    int off;
    if (s[0] == '>') s += 10;
    if ((unsigned char)s[0] != 126) { b = s[0] - 63; off = 1; }
    else if ((unsigned char)s[1] != 126) {
        b = ((s[1] - 63) << 12) | ((s[2] - 63) << 6) | (s[3] - 63); off = 4;
    } else return 0;
    if (b <= 0 || b > 40) return 0;

    int deg[64];
    memset(deg, 0, sizeof deg);
    ne = 0;
    long k = 0;
    for (int j = 1; j < b; j++)
        for (int i = 0; i < j; i++, k++) {
            int c = s[off + k / 6] - 63;
            if ((c >> (5 - k % 6)) & 1) {
                du[ne] = i; dv[ne] = j; ne++;
                deg[i]++; deg[j]++;
            }
        }
    for (int v = 0; v < b; v++) if (deg[v] != 3) return 0;   /* cubic only */
    if (b % 4) return 0;                                     /* need 4 | b  */
    t = b / 4;
    return 1;
}

/* multig -T text format:  nv ne  v1 v2 mult  v1 v2 mult ...
 * Lets D range over loopless cubic MULTIgraphs, which is what the structure
 * theorem actually requires (parallel edges in D still give a simple G). */
static int read_multig_T(const char *s)
{
    int vals[512], nv = 0;
    const char *p = s;
    while (*p && nv < 512) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        if (*p != '-' && (*p < '0' || *p > '9')) return 0;
        vals[nv++] = (int)strtol(p, (char **)&p, 10);
    }
    if (nv < 2) return 0;
    b = vals[0];
    int nedge = vals[1];
    if (b <= 0 || b > 40 || b % 4) return 0;
    if (nv != 2 + 3 * nedge) return 0;

    int deg[64];
    memset(deg, 0, sizeof deg);
    ne = 0;
    for (int k = 0; k < nedge; k++) {
        int x = vals[2 + 3 * k], y = vals[3 + 3 * k], mult = vals[4 + 3 * k];
        if (x == y) return 0;                     /* loops forbidden */
        for (int c = 0; c < mult; c++) {
            if (ne >= 64) return 0;
            du[ne] = x; dv[ne] = y; ne++;
            deg[x]++; deg[y]++;
        }
    }
    for (int v = 0; v < b; v++) if (deg[v] != 3) return 0;
    t = b / 4;
    return 1;
}

static void emit_graph6(char *out)
{
    int p = 0;
    out[p++] = (char)(n + 63);
    int bits = 0, acc = 0;
    for (int j = 1; j < n; j++)
        for (int i = 0; i < j; i++) {
            acc = (acc << 1) | ((clo[i] >> j) & 1);
            if (++bits == 6) { out[p++] = (char)(acc + 63); bits = 0; acc = 0; }
        }
    if (bits) { acc <<= (6 - bits); out[p++] = (char)(acc + 63); }
    out[p] = 0;
}

/* ------------------------------------------------------------------ *
 * Fast exact filter.
 *
 * Pick one edge from each pair of the pairing ("transversal").  If those 3t
 * edges cover every vertex of D then the corresponding 3t subdivision
 * vertices form an independent dominating set of G, so i(G) <= 3t = mu*(G)
 * and G is not a counterexample.  That is a SAT instance with one Boolean
 * per pair and one 3-clause per vertex of D -- ratio 4t/3t = 4/3, far below
 * the 3-SAT threshold, so it is satisfiable for all but rare pairings.
 * When it is unsatisfiable we fall back to the exact i(G) computation,
 * because a counterexample additionally needs no *mixed* independent
 * dominating set (using both subdivision and original vertices) of size 3t.
 * ------------------------------------------------------------------ */
static int pairid[64], side[64];

static int nvars, nclauses;
static short lit_var[64][3];
static char  lit_val[64][3], cllen[64], assignv[64];

static void build_clauses(void)
{
    nvars = ne / 2;
    int id = 0;
    for (int e = 0; e < ne; e++) pairid[e] = -1;
    for (int e = 0; e < ne; e++)
        if (pairid[e] < 0) {
            int f = partner[e];
            pairid[e] = pairid[f] = id++;
            side[e] = 0; side[f] = 1;
        }

    nclauses = 0;
    for (int u = 0; u < b; u++) {
        int len = 0, taut = 0;
        short vs[3]; char vl[3];
        for (int k = 0; k < incn[u]; k++) {
            int e = inc[u][k];
            int var = pairid[e], val = side[e];
            int dup = 0;
            for (int q = 0; q < len; q++)
                if (vs[q] == var) { if (vl[q] != val) taut = 1; dup = 1; }
            if (!dup) { vs[len] = var; vl[len] = val; len++; }
        }
        if (taut) continue;                 /* clause always satisfied */
        for (int q = 0; q < len; q++) { lit_var[nclauses][q] = vs[q];
                                        lit_val[nclauses][q] = vl[q]; }
        cllen[nclauses] = len;
        nclauses++;
    }
}

static int sat_rec(int v)
{
    for (int c = 0; c < nclauses; c++) {
        int sat = 0, unassigned = 0;
        for (int k = 0; k < cllen[c]; k++) {
            int var = lit_var[c][k];
            if (assignv[var] < 0) { unassigned = 1; break; }
            if (assignv[var] == lit_val[c][k]) { sat = 1; break; }
        }
        if (!sat && !unassigned) return 0;          /* clause violated */
    }
    if (v == nvars) return 1;
    assignv[v] = 0; if (sat_rec(v + 1)) return 1;
    assignv[v] = 1; if (sat_rec(v + 1)) return 1;
    assignv[v] = -1;
    return 0;
}

/* Fast exact path for small instances: keep a bitmask over all 2^nvars
 * assignments and intersect the satisfying set of each clause.  Same answer
 * as sat_rec, roughly ten times quicker at t = 3. */
#define MAXW 64                       /* enough for nvars <= 12 */
static u64 varmask[24][2][MAXW];
static int nwords, use_masks;
static int force_slow = 0;

static void build_varmasks(void)
{
    nvars = ne / 2;
    use_masks = (nvars <= 12) && !force_slow;
    if (!use_masks) return;
    long total = 1L << nvars;
    nwords = (int)((total + 63) / 64);
    for (int v = 0; v < nvars; v++)
        for (int val = 0; val < 2; val++) {
            for (int w = 0; w < nwords; w++) varmask[v][val][w] = 0;
            for (long a = 0; a < total; a++)
                if (((a >> v) & 1) == (long)val)
                    varmask[v][val][a >> 6] |= (u64)1 << (a & 63);
        }
}

static int transversal_cover_exists(void)
{
    build_clauses();

    if (use_masks) {
        u64 acc[MAXW];
        for (int w = 0; w < nwords; w++) acc[w] = ~(u64)0;
        long total = 1L << nvars;
        if (total < 64) acc[0] = (((u64)1 << total) - 1);
        for (int c = 0; c < nclauses; c++) {
            u64 any = 0;
            for (int w = 0; w < nwords; w++) {
                u64 cm = 0;
                for (int k = 0; k < cllen[c]; k++)
                    cm |= varmask[lit_var[c][k]][(int)lit_val[c][k]][w];
                any |= (acc[w] &= cm);
            }
            if (!any) return 0;
        }
        return 1;
    }

    for (int v = 0; v < nvars; v++) assignv[v] = -1;
    return sat_rec(0);
}

/* ---- statistics ---- */
static unsigned long long tried = 0, found = 0, unsat = 0;
static int dump = 0, nofilter = 0;

static void test_current(void)
{
    tried++;
    if (dump) { apply_pairing(); char g[512]; emit_graph6(g); puts(g); return; }

    if (!nofilter) {
        if (transversal_cover_exists()) return;    /* i(G) <= 3t: holds */
        unsat++;
    }
    apply_pairing();

    if (!has_ids(3 * t)) {                       /* i(G) > 3t = mu*(G) */
        char g[512];
        emit_graph6(g);
        int i_ex = 3 * t + 1;
        while (i_ex <= n && !has_ids(i_ex)) i_ex++;
        printf("COUNTEREXAMPLE %s n=%d r=3 i=%d mu*=%d\n", g, n, i_ex, 3 * t);
        fflush(stdout);
        found++;
    }
}

/* exhaustive enumeration of pairings of {0..ne-1} */
static void enum_pairings(u64 used)
{
    u64 avail = ~used & (bit(ne) - 1);
    if (!avail) { test_current(); return; }
    int a = lsb(avail);
    u64 rest = avail & ~bit(a);
    while (rest) {
        int c = lsb(rest); rest &= rest - 1;
        partner[a] = c; partner[c] = a;
        enum_pairings(used | bit(a) | bit(c));
    }
}

/* ---- xorshift RNG for sampling mode ---- */
static u64 rng_state = 0x9E3779B97F4A7C15ULL;
static inline u64 rnd(void)
{
    u64 x = rng_state;
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    return rng_state = x;
}

static void sample_pairings(long long count)
{
    int perm[64];
    for (long long s = 0; s < count; s++) {
        for (int e = 0; e < ne; e++) perm[e] = e;
        for (int e = ne - 1; e > 0; e--) {
            int j = (int)(rnd() % (u64)(e + 1));
            int tmp = perm[e]; perm[e] = perm[j]; perm[j] = tmp;
        }
        for (int e = 0; e + 1 < ne; e += 2) {
            partner[perm[e]] = perm[e + 1];
            partner[perm[e + 1]] = perm[e];
        }
        test_current();
    }
}

int main(int argc, char **argv)
{
    long long samples = 0;
    for (int a = 1; a < argc; a++) {
        if (!strcmp(argv[a], "-s") && a + 1 < argc) samples = atoll(argv[++a]);
        else if (!strcmp(argv[a], "--dump")) dump = 1;
        else if (!strcmp(argv[a], "--nofilter")) nofilter = 1;
        else if (!strcmp(argv[a], "--slowsat")) force_slow = 1;
        else if (!strcmp(argv[a], "--seed") && a + 1 < argc)
            rng_state = strtoull(argv[++a], NULL, 10) | 1;
    }

    char line[1 << 16];
    unsigned long long nD = 0;
    while (fgets(line, sizeof line, stdin)) {
        char *p = strchr(line, '\n');
        if (p) *p = 0;
        if (!line[0]) continue;
        int ok = (line[0] >= '0' && line[0] <= '9') ? read_multig_T(line)
                                                    : read_graph6_D(line);
        if (!ok) continue;
        nD++;
        build_base();
        build_varmasks();
        if (samples) sample_pairings(samples);
        else         enum_pairings(0);
    }
    fprintf(stderr, "base_graphs=%llu pairings_tested=%llu counterexamples=%llu no_transversal_cover=%llu\n",
            nD, tried, found, unsat);
    return 0;
}
