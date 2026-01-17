# combine-text

Below is a standalone combine-text shell program that does exactly this:

- reads from stdin (your left pipe)
- writes stdin through unchanged to stdout
- then appends all “right side” CLI arguments as text (joined with spaces)
- with a configurable separator (default: one blank line) ✅

This is designed for the ergonomic pattern:

```bash
some-command | combine-text "any text you want" "more text"
```

---

## combine-text program

Create a file named `combine-text`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
combine-text — append right-hand text after piped stdin (stdin -> stdout filter)

USAGE
  <left-pipeline> | combine-text [OPTIONS] [TEXT...]
  combine-text [OPTIONS] [TEXT...]         # also works without a pipe (reads stdin until EOF)

DESCRIPTION
  - Streams stdin to stdout unchanged.
  - Then appends TEXT (arguments joined by single spaces) to stdout.
  - By default, inserts a blank line between stdin output and TEXT (when both exist).

OPTIONS
  -b, --blank     Ensure TEXT starts after a blank line (default).
                  (If stdin doesn't end with '\n', it will add what's needed.)
  -1, --newline   Ensure TEXT starts on a new line (no extra blank line).
  -0, --none      Do not insert a separator.
  -h, --help      Show this help.
  --              End of options (useful if TEXT begins with '-')

EXAMPLES
  ls -la | combine-text "---- end ----"
  git status | combine-text -1 "Next:" "run tests"
  printf "no-newline" | combine-text "appended"

NOTES
  - TEXT is treated as literal text; this program does NOT execute commands you pass as arguments.
  - To include spaces/newlines reliably, quote your TEXT.
EOF
}

sep="blank"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -b|--blank) sep="blank"; shift ;;
    -1|--newline) sep="newline"; shift ;;
    -0|--none) sep="none"; shift ;;
    --) shift; break ;;
    -*) printf 'combine-text: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

# We want:
# 1) Stream stdin to stdout unchanged
# 2) Detect whether stdin ended with '\n' (without consuming stdin twice)
#
# Trick:
# - Duplicate stdout to fd 3
# - tee stdin to:
#    a) cat -> fd 3 (so input streams out immediately)
#    b) tail -c 1 -> od (so we can detect last byte as a number)
exec 3>&1
last_byte_code="$(
  tee >(cat >&3) \
  | tail -c 1 \
  | od -An -t u1 \
  | tr -d ' \t\n'
)"

saw_stdin=0
ended_with_nl=0
if [[ -n "$last_byte_code" ]]; then
  saw_stdin=1
  [[ "$last_byte_code" == "10" ]] && ended_with_nl=1
fi

# If no TEXT was provided, we're done after streaming stdin.
if (( $# == 0 )); then
  exit 0
fi

# Insert separator only if stdin had something.
if (( saw_stdin == 1 )); then
  case "$sep" in
    blank)
      # Want TEXT to start after a blank line.
      # If stdin already ended with '\n' -> add 1 more '\n' (creates one blank line).
      # If not -> add "\n\n" (terminates line + blank line).
      if (( ended_with_nl == 1 )); then
        printf '\n'
      else
        printf '\n\n'
      fi
      ;;
    newline)
      # Ensure TEXT starts on a new line, but no extra blank line.
      if (( ended_with_nl == 0 )); then
        printf '\n'
      fi
      ;;
    none)
      ;;
  esac
fi

# Print TEXT args joined by single spaces, then newline.
printf '%s' "$1"
shift
for a in "$@"; do
  printf ' %s' "$a"
done
printf '\n'
```

---

## Install it

```bash
chmod +x ./combine-text
sudo mv ./combine-text /usr/local/bin/combine-text
```

Verify:

```bash
echo "hello" | combine-text "world"
```

Expected output:

```text
hello

world
```

---

## How to use it

### 1) Append a footer to any command output

```bash
make test | combine-text "---- END ----"
```

### 2) Add “next steps” after a noisy command

```bash
git status | combine-text -1 "Next:" "run" "git diff" "and" "tests"
```

`-1/--newline` means: ensure the appended text starts on a new line, but don’t force a blank line.

### 3) Add a multi-line right-hand message

Because shells split arguments on spaces, the clean way is a single quoted argument containing newlines:

```bash
dmesg | combine-text $'--- Notes ---\n1) Check driver versions\n2) Reboot and retry'
```

### 4) If your “text” begins with a dash

Use `--` to stop option parsing:

```bash
cmd | combine-text -- "-this is not an option" "more text"
```

### 5) Append the output of another command as “text”

`combine-text` does not execute arguments, but you can feed it computed text with command substitution:

```bash
uname -a | combine-text "Host=$(hostname) Time=$(date)"
```

(That right-hand side is still just text.)

---

## Use cases (detailed) 🧰

### A) Creating “report-style” CLI output

When you want a command’s output plus commentary:

- system state + diagnosis
- test output + remediation
- inventory + summary

Example:

```bash
kubectl get pods -A | combine-text $'Interpretation:\n- Pending: look at node pressure\n- CrashLoopBackOff: inspect logs'
```

This is excellent for quickly producing copy/paste-ready artifacts.

---

### B) Making logs self-describing in scripts / CI

In automation you often want:

- machine output (what happened)
- human note (what to do next)

Example:

```bash
./run-benchmark | combine-text "If regression > 5%, file a bug and attach this output."
```

This avoids “output without context” in CI logs.

---

### C) Building ticket / bug report payloads

Common workflow: gather command output → append repro steps / environment info → paste into issue tracker.

Example:

```bash
( git rev-parse HEAD; echo; git status ) | combine-text $'Repro:\n1) ...\n2) ...\nExpected:\nActual:'
```

---

### D) Fast “stdout augmentation” without editing pipelines

Instead of rewriting a pipeline or using braces everywhere, `combine-text` is a single, reusable “append text” filter.

Example:

```bash
some_long_pipeline | combine-text "Pipeline finished with exit=$?"
```

---

### E) Normalizing output boundaries

Many tools output without a trailing newline in edge cases. In default `--blank` mode, `combine-text` ensures your appended text never smashes onto the last line, even if the left side didn’t end cleanly.

Example:

```bash
printf "no newline here" | combine-text " <- appended safely"
```

---

## Practical “gotchas” (worth knowing)

- Shell quoting matters.
  `combine-text hello world` prints `hello world` (two args joined with a space).
  If you need multiple spaces, tabs, or newlines: use quotes (or `$'...'`).
- This appends text; it doesn’t run it.
  `combine-text ls -la` prints the text `ls -la`; it does not execute `ls`.
- Binary stdin is preserved, because stdin is streamed with `cat` through `tee`.
  (But the output becomes “binary + appended text”, so it’s still conceptually a text utility.)

---

If you tell me whether your default preference is blank-line separation or single newline, I can set the default behavior accordingly (i.e., default to `--newline` instead of `--blank`).
