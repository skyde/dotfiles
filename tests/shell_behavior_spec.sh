#!/bin/bash
# Behavior tests for the POSIX-facing dotfile scripts. No external test framework required.
set -u -o pipefail

SOURCE="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd -- "$(dirname "$SOURCE")/.." && pwd)"
PASSED=0
FAILED=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local context="$3"
    [ "$expected" = "$actual" ] || fail "$context (expected '$expected', got '$actual')"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local context="$3"
    grep -Fq -- "$needle" <<<"$haystack" || fail "$context (missing '$needle')"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local context="$3"
    if grep -Fq -- "$needle" <<<"$haystack"; then
        fail "$context (unexpected '$needle')"
    fi
}

line_count() {
    if [ ! -f "$1" ]; then
        printf '0\n'
        return
    fi
    wc -l < "$1" | tr -d '[:space:]'
}

new_temp_dir() {
    mktemp -d "${TMPDIR:-/tmp}/dotfiles-spec.XXXXXX"
}

write_executable() {
    local path="$1"
    shift
    cat > "$path"
    chmod +x "$path"
}

make_fake_commands() {
    local fake_bin="$1"
    mkdir -p "$fake_bin"

    write_executable "$fake_bin/uname" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "${FAKE_UNAME:-Linux}"
SCRIPT

    write_executable "$fake_bin/stow" <<'SCRIPT'
#!/bin/bash
{
    printf 'CALL'
    for argument in "$@"; do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >> "${STOW_LOG:?}"
exit "${STOW_EXIT_CODE:-0}"
SCRIPT

    write_executable "$fake_bin/chkstow" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

    write_executable "$fake_bin/git" <<'SCRIPT'
#!/bin/bash
{
    printf 'CALL'
    for argument in "$@"; do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >> "${GIT_LOG:?}"
exit "${GIT_EXIT_CODE:-0}"
SCRIPT
}

make_local_apply() {
    local home="$1"
    mkdir -p "$home/dotfiles-local"
    write_executable "$home/dotfiles-local/apply.sh" <<'SCRIPT'
#!/bin/bash
{
    printf 'CALL'
    for argument in "$@"; do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >> "${LOCAL_APPLY_LOG:?}"
SCRIPT
}

test_apply_normalizes_arguments_and_runs_local_once() {
    local temp home fake_bin output calls local_calls
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home with spaces"
    fake_bin="$temp/bin"
    mkdir -p "$home"
    make_fake_commands "$fake_bin"
    make_local_apply "$home"

    output="$(
        HOME="$home" \
        PATH="$fake_bin:$PATH" \
        FAKE_UNAME=Linux \
        STOW_LOG="$temp/stow.log" \
        LOCAL_APPLY_LOG="$temp/local.log" \
        "$REPO_ROOT/apply.sh" --no-act --yes --restow
    )"

    calls="$(cat "$temp/stow.log")"
    local_calls="$(cat "$temp/local.log")"
    assert_equals 1 "$(line_count "$temp/stow.log")" "Linux should stow one package"
    assert_contains "$calls" "--target=$home" "HOME with spaces must remain one target argument"
    assert_contains "$calls" $'\t--no\t' "--no-act should normalize to --no"
    assert_contains "$calls" $'\t--restow\tcommon' "restow should reach the common package"
    assert_not_contains "$calls" "--no-act" "unsupported alias must not reach Stow"
    assert_not_contains "$calls" "--yes" "wrapper confirmation flag must not reach Stow"
    assert_equals 1 "$(line_count "$temp/local.log")" "dotfiles-local must run exactly once"
    assert_contains "$local_calls" $'\t--no-act\t--yes\t--restow' "local apply should receive original arguments"
    assert_contains "$output" "Dry run completed" "dry-run completion should be reported"
    [ ! -e "$home/.config" ] || fail "dry run created HOME/.config"
}

test_apply_selects_platform_packages() {
    local temp fake_bin platform expected_count expected_package home log
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    fake_bin="$temp/bin"
    make_fake_commands "$fake_bin"

    for platform in Darwin MINGW64_NT UnknownOS; do
        case "$platform" in
            Darwin)
                expected_count=2
                expected_package=mac
                ;;
            MINGW64_NT)
                expected_count=2
                expected_package=windows
                ;;
            *)
                expected_count=1
                expected_package=common
                ;;
        esac

        home="$temp/home-$platform"
        log="$temp/stow-$platform.log"
        mkdir -p "$home"
        HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME="$platform" STOW_LOG="$log" \
            "$REPO_ROOT/apply.sh" --no >/dev/null

        assert_equals "$expected_count" "$(line_count "$log")" "$platform package count"
        assert_contains "$(cat "$log")" $'\t'"$expected_package" "$platform expected package"
    done
}

test_apply_propagates_stow_failure_before_local_apply() {
    local temp home fake_bin status
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home"
    fake_bin="$temp/bin"
    mkdir -p "$home"
    make_fake_commands "$fake_bin"
    make_local_apply "$home"

    set +e
    HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME=Linux \
        STOW_LOG="$temp/stow.log" STOW_EXIT_CODE=23 LOCAL_APPLY_LOG="$temp/local.log" \
        "$REPO_ROOT/apply.sh" --no >/dev/null 2>&1
    status=$?
    set -e

    assert_equals 23 "$status" "Stow exit status should propagate"
    [ ! -e "$temp/local.log" ] || fail "local apply ran after Stow failed"
}

test_apply_delete_does_not_create_directories() {
    local temp home fake_bin
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home"
    fake_bin="$temp/bin"
    mkdir -p "$home"
    make_fake_commands "$fake_bin"

    HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME=Linux STOW_LOG="$temp/stow.log" \
        "$REPO_ROOT/apply.sh" --delete >/dev/null

    if find "$home" -mindepth 1 -print -quit | grep -q .; then
        fail "delete created paths in an empty HOME"
    fi
}

test_apply_dry_run_requires_stow_without_installing() {
    local temp home fake_bin output status
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home"
    fake_bin="$temp/bin"
    mkdir -p "$home"
    make_fake_commands "$fake_bin"

    set +e
    output="$(
        HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME=Linux \
        DOTFILES_STOW_COMMAND=definitely-missing-stow \
        "$REPO_ROOT/apply.sh" --no 2>&1
    )"
    status=$?
    set -e

    assert_equals 127 "$status" "missing Stow during dry run should fail clearly"
    assert_contains "$output" "required to preview" "missing-Stow diagnostic"
}

test_init_noninteractive_skips_missing_bat() {
    local temp home fake_bin output
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home"
    fake_bin="$temp/bin"
    mkdir -p "$home"
    make_fake_commands "$fake_bin"

    output="$(
        HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME=Linux AUTO_INSTALL=0 \
        DOTFILES_BAT_COMMAND=definitely-missing-bat STOW_LOG="$temp/stow.log" \
        "$REPO_ROOT/init.sh" --no
    )"

    assert_equals 1 "$(line_count "$temp/stow.log")" "init should apply common once"
    assert_contains "$output" "bat not found, skipping" "missing bat should be optional"
    assert_contains "$output" "Init complete" "init should complete without bat"
}

test_init_builds_bat_cache_when_available() {
    local temp home fake_bin
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home"
    fake_bin="$temp/bin"
    mkdir -p "$home"
    make_fake_commands "$fake_bin"

    write_executable "$fake_bin/bat" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >> "${BAT_LOG:?}"
SCRIPT

    HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME=Linux AUTO_INSTALL=0 \
        STOW_LOG="$temp/stow.log" BAT_LOG="$temp/bat.log" \
        "$REPO_ROOT/init.sh" --no >/dev/null

    assert_equals 1 "$(line_count "$temp/bat.log")" "bat cache should run once"
    assert_equals "cache --build" "$(cat "$temp/bat.log")" "bat cache arguments"
}

test_update_pulls_both_repositories_and_applies_local_once() {
    local temp home fake_bin git_calls stow_calls local_calls
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home with spaces"
    fake_bin="$temp/bin"
    mkdir -p "$home/dotfiles-local/.git"
    make_fake_commands "$fake_bin"
    make_local_apply "$home"

    HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME=Linux \
        GIT_LOG="$temp/git.log" STOW_LOG="$temp/stow.log" LOCAL_APPLY_LOG="$temp/local.log" \
        "$REPO_ROOT/update.sh" --no --yes >/dev/null

    git_calls="$(cat "$temp/git.log")"
    stow_calls="$(cat "$temp/stow.log")"
    local_calls="$(cat "$temp/local.log")"
    assert_equals 2 "$(line_count "$temp/git.log")" "update should pull main and local repositories"
    assert_contains "$git_calls" $'CALL\tpull\t--ff-only' "main pull should be fast-forward only"
    assert_contains "$git_calls" $'\t-C\t'"$home/dotfiles-local"$'\tpull\t--ff-only' "local pull should preserve path arguments"
    assert_equals 1 "$(line_count "$temp/stow.log")" "Linux restow should apply common once"
    assert_contains "$stow_calls" $'\t--restow\t--no\tcommon' "update arguments should reach Stow"
    assert_not_contains "$stow_calls" "--yes" "update should filter wrapper confirmation flags"
    assert_equals 1 "$(line_count "$temp/local.log")" "update must apply dotfiles-local exactly once"
    assert_contains "$local_calls" $'\t--restow\t--no\t--yes' "local restow should receive complete original operation"
}

test_update_stops_when_git_pull_fails() {
    local temp home fake_bin status
    temp="$(new_temp_dir)"
    trap "rm -rf '$temp'" EXIT
    home="$temp/home"
    fake_bin="$temp/bin"
    mkdir -p "$home/dotfiles-local/.git"
    make_fake_commands "$fake_bin"
    make_local_apply "$home"

    set +e
    HOME="$home" PATH="$fake_bin:$PATH" FAKE_UNAME=Linux GIT_EXIT_CODE=41 \
        GIT_LOG="$temp/git.log" STOW_LOG="$temp/stow.log" LOCAL_APPLY_LOG="$temp/local.log" \
        "$REPO_ROOT/update.sh" --no >/dev/null 2>&1
    status=$?
    set -e

    assert_equals 41 "$status" "git failure should stop update"
    [ ! -e "$temp/stow.log" ] || fail "Stow ran after git pull failed"
    [ ! -e "$temp/local.log" ] || fail "local apply ran after git pull failed"
}

test_hosted_test_helper_is_current_and_non_mutating() {
    local output status
    assert_contains "$(cat "$REPO_ROOT/test-all-platforms.sh")" 'comprehensive-test.yml' "helper should target an existing workflow"
    [ -f "$REPO_ROOT/.github/workflows/comprehensive-test.yml" ] || fail "configured workflow file does not exist"

    if grep -Eq 'git[[:space:]]+(add|commit|push)([[:space:]]|$)' "$REPO_ROOT/test-all-platforms.sh"; then
        fail "hosted test helper contains repository-mutating git commands"
    fi

    output="$("$REPO_ROOT/test-all-platforms.sh" --help)"
    assert_contains "$output" "Usage:" "helper help"

    set +e
    "$REPO_ROOT/test-all-platforms.sh" 0 >/dev/null 2>&1
    status=$?
    set -e
    assert_equals 2 "$status" "invalid cycle count should be rejected before triggering CI"
}

test_all_shell_scripts_parse() {
    local script
    while IFS= read -r -d '' script; do
        bash -n "$script"
    done < <(find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o -type f -name '*.sh' -print0)
}

run_test() {
    local name="$1"
    shift
    printf 'TEST %s\n' "$name"
    if (set -euo pipefail; "$@"); then
        printf 'PASS %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL %s\n' "$name" >&2
        FAILED=$((FAILED + 1))
    fi
}

run_test "apply normalizes args and runs local once" test_apply_normalizes_arguments_and_runs_local_once
run_test "apply selects platform packages" test_apply_selects_platform_packages
run_test "apply propagates Stow failures" test_apply_propagates_stow_failure_before_local_apply
run_test "delete does not create directories" test_apply_delete_does_not_create_directories
run_test "dry run requires Stow without installing" test_apply_dry_run_requires_stow_without_installing
run_test "init skips missing bat" test_init_noninteractive_skips_missing_bat
run_test "init builds bat cache" test_init_builds_bat_cache_when_available
run_test "update pulls and applies local once" test_update_pulls_both_repositories_and_applies_local_once
run_test "update stops on pull failure" test_update_stops_when_git_pull_fails
run_test "hosted helper is current and non-mutating" test_hosted_test_helper_is_current_and_non_mutating
run_test "all shell scripts parse" test_all_shell_scripts_parse

printf '\nShell behavior tests: %d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
