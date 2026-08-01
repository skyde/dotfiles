#!/usr/bin/env bash
# Drive the diff view interactively: a real nvim with the real config inside a
# tmux pane, fed actual keystrokes, with assertions on the rendered screen and
# on editor state. Complements the headless specs, which cannot see anything
# that needs the interactive main loop (BufModifiedSet re-listing, echo area,
# window scrolling).
#
#   tests/check-nvim-interactive.sh            # against the installed config
#   tests/check-nvim-interactive.sh /path/dir  # against a checkout's common/.config
#
# Needs tmux and a nvim with the config's plugins already installed.
set -uo pipefail

if [[ $# -ge 1 ]]; then
  export XDG_CONFIG_HOME="$1/common/.config"
fi
command -v tmux >/dev/null 2>&1 || { echo "tmux not found" >&2; exit 1; }
command -v nvim >/dev/null 2>&1 || { echo "nvim not found" >&2; exit 1; }

sandbox="$(mktemp -d)"
trap 'tmux kill-session -t nvimcheck 2>/dev/null; rm -rf "$sandbox"' EXIT
repo="$sandbox/repo"
git init -q -b main "$repo"
cd "$repo" || exit 1
mkdir -p src/deeply/nested
seq 1 120 | sed 's/^/line /' > src/deeply/nested/mod.c
printf 'alpha\nbeta\n' > src/top.c
printf 'keep\n' > README.md
git add -A
git -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false commit -qm init
git update-ref refs/remotes/origin/main HEAD
git checkout -qb feature
{ seq 1 60 | sed 's/^/line /'; echo CHANGED; seq 62 120 | sed 's/^/line /'; } > src/deeply/nested/mod.c
printf 'alpha\nbeta\ngamma\n' > src/top.c
printf 'brand new\n' > extra.txt

S=nvimcheck
tmux kill-session -t $S 2>/dev/null || true
tmux new-session -d -s $S -x 220 -y 50 "cd $repo && nvim README.md"

pass=0; fail=0; failures=()
capture() { tmux capture-pane -p -t $S; }
sendkeys() { tmux send-keys -t $S "$@"; }
wait_for() { local deadline=$((SECONDS + $1)); while ((SECONDS < deadline)); do
    if capture | grep -qE "$2"; then return 0; fi; sleep 0.3; done; return 1; }
check() { if [[ "$2" == 0 ]]; then pass=$((pass+1)); else fail=$((fail+1)); failures+=("$1"); echo "FAIL $1"; fi; }
probe_expr() { rm -f "$sandbox/probe.txt"
  tmux send-keys -t $S ":call writefile([string($1)], '$sandbox/probe.txt')" Enter
  local i; for i in $(seq 1 20); do [[ -s "$sandbox/probe.txt" ]] && break; sleep 0.2; done
  cat "$sandbox/probe.txt" 2>/dev/null; }

wait_for 30 'README' ; check "startup" $?

sendkeys Space g c
wait_for 20 'git · uncommitted' ; check "gc: panel opens" $?
sleep 2
capture > "$sandbox/screen_open.txt"
grep -q '    src/' "$sandbox/screen_open.txt" ; check "gc: tree dir row" $?
grep -q 'deeply/nested/' "$sandbox/screen_open.txt" ; check "gc: compacted chain" $?
grep -qE ' M +mod.c' "$sandbox/screen_open.txt" ; check "gc: status letter" $?

sendkeys j; sleep 1.2; sendkeys j; sleep 1.5
wait_for 6 'brand new' ; check "scrub: preview follows" $?
sendkeys k; sleep 1.2; sendkeys k; sleep 1.5

sendkeys Enter; sleep 1
name=$(probe_expr "bufname('%')"); [[ "$name" == *mod.c* ]] ; check "Enter: focus in mod.c" $?
sendkeys Space g c; sleep 1.5
name=$(probe_expr "bufname('%')"); [[ "$name" == *vcs://changes* ]] ; check "gc from inside: instant return" $?

sendkeys Enter; sleep 1; sendkeys ] c; sleep 0.6
capture | grep -qE 'Change [0-9]+ of [0-9]+' ; check "]c: counter echoed" $?
rel=$(probe_expr "&relativenumber"); [[ "$rel" == "1" ]] ; check "diff: relativenumber on" $?

sendkeys Space g c; sleep 1
before=$(probe_expr "line('w0', bufwinid('mod.c'))")
sendkeys J; sleep 0.6
after=$(probe_expr "line('w0', bufwinid('mod.c'))")
(( after > before )) ; check "J: preview scrolled ($before -> $after)" $?
sendkeys K; sleep 0.6
back=$(probe_expr "line('w0', bufwinid('mod.c'))")
(( back < after )) ; check "K: scrolled back ($after -> $back)" $?
name=$(probe_expr "bufname('%')"); [[ "$name" == *vcs://changes* ]] ; check "J/K: focus stays in panel" $?

sendkeys l; sleep 0.8
name=$(probe_expr "bufname('%')"); [[ "$name" != *vcs://changes* ]] ; check "l: enters the diff" $?

# Editing a preview earns it a buffer-list place that survives closing.
sendkeys i; sleep 0.3; sendkeys -l "EDITED"; sleep 0.3; sendkeys Escape; sleep 0.8
listed=$(probe_expr "len(getbufinfo({'buflisted':1}))")
[[ "$listed" == "2" ]] ; check "editing a preview lists it (got $listed)" $?
sendkeys u; sleep 0.5
sendkeys Space g c; sleep 0.8; sendkeys q; sleep 1.5
name=$(probe_expr "bufname('%')"); [[ "$name" == *README.md* ]] ; check "q: back on README" $?
names=$(probe_expr "join(map(getbufinfo({'buflisted':1}), {_, b -> fnamemodify(b.name, ':t')}), ',')")
[[ "$names" == *mod.c* ]] ; check "q: the edited preview survives (got $names)" $?
loaded=$(probe_expr "len(filter(getbufinfo(), {_, b -> b.loaded && b.name =~# 'extra.txt'}))")
[[ "$loaded" == "0" ]] ; check "q: unedited previews are gone (got $loaded)" $?

sendkeys Space g d; sleep 1.5
d=$(probe_expr "&diff"); [[ "$d" == "1" ]] ; check "gd: file diff opens" $?
sendkeys Space g w; sleep 1.2
name=$(probe_expr "bufname('%')"); [[ "$name" == *README.md* ]] ; check "gw: back to the file" $?

sendkeys Space g c; sleep 2; sendkeys j; sleep 1; sendkeys j; sleep 1.2
tmux send-keys -t $S ':tabclose' Enter; sleep 1.5
loaded=$(probe_expr "len(filter(getbufinfo(), {_, b -> b.loaded && b.name =~# 'extra.txt'}))")
[[ "$loaded" == "0" ]] ; check "external :tabclose drops previews (got $loaded)" $?

tmux send-keys -t $S ':messages' Enter; sleep 1
capture > "$sandbox/screen_messages.txt"
grep -qE 'E5108|E37|Error detected|stack traceback' "$sandbox/screen_messages.txt" && merr=1 || merr=0
check "no errors in :messages" $merr

echo; echo "$pass passed, $fail failed"
if ((fail > 0)); then printf '%s\n' "${failures[@]}"; exit 1; fi
