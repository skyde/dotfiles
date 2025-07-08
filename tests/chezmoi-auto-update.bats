setup() {
  TMPDIR=$(mktemp -d)
  STUB=$TMPDIR/chezmoi
  cat > "$STUB" <<'SH'
#!/bin/sh
if [ "$1" = "git" ] && [ "$2" = "status" ] && [ "$3" = "--porcelain" ]; then
  printf "%s" "$GIT_STATUS_OUTPUT"
elif [ "$1" = "update" ] && [ "$2" = "--init" ]; then
  echo update >> "$CALLED_FILE"
fi
SH
  chmod +x "$STUB"
  export PATH="$TMPDIR:$PATH"
  export CALLED_FILE="$TMPDIR/called"
}

teardown() {
  rm -rf "$TMPDIR"
}

@test "does nothing when chezmoi missing" {
  PATH="/nonexistent" run "$BATS_TEST_DIRNAME/../bin/chezmoi-auto-update"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "runs update when repo is clean" {
  GIT_STATUS_OUTPUT=""
  run "$BATS_TEST_DIRNAME/../bin/chezmoi-auto-update"
  [ "$status" -eq 0 ]
  [ -f "$CALLED_FILE" ]
}

@test "skips update when repo has changes" {
  GIT_STATUS_OUTPUT=" M file"
  DEBUG=1 run "$BATS_TEST_DIRNAME/../bin/chezmoi-auto-update"
  [ "$status" -eq 0 ]
  [ ! -f "$CALLED_FILE" ]
  [ "$output" = "chezmoi has local changes, skipping auto update." ]
}
