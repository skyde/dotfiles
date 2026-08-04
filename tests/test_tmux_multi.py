"""Tests for common/.local/bin/tmux-multi.

The script orchestrates ssh and tmux; these tests replace both with stub
executables that log every invocation (fields separated by \\x1f) and emit
canned responses, so host aggregation, window reuse, kill behavior and remote
quoting can be asserted without real machines.
"""

import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / 'common/.local/bin/tmux-multi'
TMUX_CONF = REPO_ROOT / 'common/.tmux.conf'

SEP = '\x1f'

SSH_STUB = textwrap.dedent(
    r'''    #!/usr/bin/env bash
    line='ssh'
    for a in "$@"; do line="$line"$'\x1f'"$a"; done
    printf '%s\n' "$line" >>"$STUB_LOG"

    host= cmd= gflag=
    args=("$@")
    i=0
    while [ $i -lt ${#args[@]} ]; do
      a=${args[$i]}
      case $a in
        -o) i=$((i + 1)) ;;
        -t | -n | --) ;;
        -G) gflag=1 ;;
        *) if [ -z "$host" ]; then host=$a; else cmd="$cmd $a"; fi ;;
      esac
      i=$((i + 1))
    done

    if [ -n "$gflag" ]; then
      echo 'controlmaster false'
      exit 0
    fi

    case $host in
      beta | flaky) exit 255 ;;
    esac

    case $cmd in
      *list-sessions*)
        var="STUB_SESSIONS_${host}"
        sessions=${!var:-}
        [ -n "$sessions" ] || exit 1
        fmt=$(printf '%s' "$cmd" | sed -n "s/.*-F '\(.*\)' 2>.*/\1/p")
        while IFS='|' read -r act name wins att; do
          [ -z "$act" ] && continue
          out=${fmt//"#{session_activity}"/$act}
          out=${out//"#{session_name}"/$name}
          out=${out//"#{session_windows}"/$wins}
          if [ "$att" = 1 ]; then
            out=${out//"#{?session_attached,attached,-}"/attached}
          else
            out=${out//"#{?session_attached,attached,-}"/-}
          fi
          printf '%s\n' "$out"
        done <<<"$sessions"
        ;;
      # The preview's combined window-walk snippet (list-windows piped into
      # per-window capture-pane): emit a canned marker stream.
      *while*capture-pane*) [ -n "${STUB_REMOTE_DUMP:-}" ] && printf '%s\n' "$STUB_REMOTE_DUMP" ;;
      *kill-session*) exit 0 ;;
      *'tmux -V'*) echo 'tmux 3.4a' ;;
      *new-session* | *tmux-session*) exit "${STUB_ATTACH_EXIT:-0}" ;;
    esac
    exit 0
    '''
)

TMUX_STUB = textwrap.dedent(
    r'''    #!/usr/bin/env bash
    line='tmux'
    for a in "$@"; do line="$line"$'\x1f'"$a"; done
    printf '%s\n' "$line" >>"$STUB_LOG"

    case $1 in
      list-sessions)
        [ -n "${STUB_LOCAL_SESSIONS:-}" ] || exit 1
        fmt=$3
        while IFS='|' read -r act name wins att; do
          [ -z "$act" ] && continue
          out=${fmt//"#{session_activity}"/$act}
          out=${out//"#{session_name}"/$name}
          out=${out//"#{session_windows}"/$wins}
          if [ "$att" = 1 ]; then
            out=${out//"#{?session_attached,attached,-}"/attached}
          else
            out=${out//"#{?session_attached,attached,-}"/-}
          fi
          printf '%s\n' "$out"
        done <<<"$STUB_LOCAL_SESSIONS"
        ;;
      has-session)
        name=${3#=}
        for s in ${STUB_EXISTING_SESSIONS:-}; do
          [ "$s" = "$name" ] && exit 0
        done
        exit 1
        ;;
      display-message)
        if [ "$3" = '#{@tmux_multi_target}' ]; then
          printf '%s\n' "${STUB_CURRENT_TAG:-}"
        elif [ "$2" = -p ]; then
          printf '%s\n' "${STUB_CURRENT_SESSION:-}"
        fi
        ;;
      list-windows)
        if [ "$2" = -a ] && [ -n "${STUB_WINDOWS:-}" ]; then
          printf '%s\n' "$STUB_WINDOWS"
        elif [ "$2" = -t ] && [ -n "${STUB_SESSION_WINDOWS:-}" ]; then
          printf '%s\n' "$STUB_SESSION_WINDOWS"
        elif [ "$2" = -F ] && [ -n "${STUB_CURRENT_WINDOWS:-}" ]; then
          printf '%s\n' "$STUB_CURRENT_WINDOWS"
        fi
        ;;
      capture-pane)
        [ -n "${STUB_PANE:-}" ] && printf '%s\n' "$STUB_PANE"
        ;;
      new-window)
        for a in "$@"; do [ "$a" = -P ] && { echo '@9'; break; }; done
        ;;
    esac
    exit 0
    '''
)

HOSTNAME_STUB = '#!/usr/bin/env bash\necho hubbox\n'


class TmuxMultiTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix='tmux-multi-test.'))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.bin = self.tmp / 'bin'
        self.bin.mkdir()
        for name, body in (
            ('ssh', SSH_STUB),
            ('tmux', TMUX_STUB),
            ('hostname', HOSTNAME_STUB),
        ):
            self.make_stub(name, body)
        self.log = self.tmp / 'invocations.log'
        self.hosts = self.tmp / 'hosts'
        self.hosts.write_text('# my machines\nalpha\nbeta\n\nhubbox  # this box\n')

    def make_stub(self, name, body):
        """Add an executable stub to the test bin, shadowing any real one."""
        path = self.bin / name
        path.write_text(body)
        path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        return path

    def env(self, **extra):
        env = dict(os.environ)
        env.pop('TMUX', None)
        env.pop('TMUX_PANE', None)
        env.pop('TMUX_MULTI_SELF', None)
        # Deliberately NOT inheriting the caller's PATH: on a machine with these
        # dotfiles installed, the real tmux-session (and friends) would shadow
        # the stubs and make branch coverage depend on the developer's setup.
        env.update(
            PATH=f"{self.bin}:/usr/bin:/bin:/usr/sbin:/sbin",
            STUB_LOG=str(self.log),
            TMUX_MULTI_HOSTS_FILE=str(self.hosts),
            # Isolate the cache dir (preview caches, unreachable markers).
            TMPDIR=str(self.tmp),
        )
        env.update({k: v for k, v in extra.items() if v is not None})
        return env

    def run_script(self, *args, env=None, input=None, check=True):
        result = subprocess.run(
            [str(SCRIPT), *args],
            env=env or self.env(),
            input=input,
            text=True,
            capture_output=True,
        )
        if check:
            self.assertEqual(
                0, result.returncode,
                f'{args} failed: {result.stdout!r} {result.stderr!r}',
            )
        return result

    def calls(self):
        if not self.log.exists():
            return []
        return [
            line.split(SEP)
            for line in self.log.read_text().splitlines()
            if line
        ]

    def calls_for(self, cmd):
        return [c for c in self.calls() if c[0] == cmd]

    # ---- host list ----

    def test_hosts_skips_comments_blanks_and_self(self):
        result = self.run_script('hosts')
        self.assertEqual(['alpha', 'beta'], result.stdout.splitlines())

    def test_self_can_be_forced_with_env(self):
        result = self.run_script('hosts', env=self.env(TMUX_MULTI_SELF='alpha'))
        self.assertEqual(['beta'], result.stdout.splitlines())

    # ---- ls ----

    def test_ls_merges_hosts_and_sorts_by_activity(self):
        env = self.env(
            STUB_LOCAL_SESSIONS='100|notes|1|0',
            STUB_SESSIONS_alpha='300|build|2|1\n50|logs|1|0',
        )
        result = self.run_script('ls', env=env)
        self.assertEqual(
            [
                'alpha\tbuild\t2w\tattached',
                'hubbox\tnotes\t1w\t-',
                'alpha\tlogs\t1w\t-',
            ],
            result.stdout.splitlines(),
        )
        # beta is unreachable (ssh exits 255) yet ls succeeds without it.
        ssh_hosts = {c[c.index('--') - 1] for c in self.calls_for('ssh')}
        self.assertEqual({'alpha', 'beta'}, ssh_hosts)

    def test_ls_handles_session_names_with_spaces(self):
        env = self.env(STUB_LOCAL_SESSIONS='100|my build sess|1|0')
        result = self.run_script('ls', env=env)
        self.assertEqual(
            ['hubbox\tmy build sess\t1w\t-'], result.stdout.splitlines()
        )

    def test_tmux_facing_formats_contain_no_tabs(self):
        # tmux replaces control characters in expanded formats with '_', so a
        # tab-separated -F format silently loses its field boundaries. The
        # script must only pass space-separated formats to tmux/ssh.
        self.run_script('ls', env=self.env(STUB_LOCAL_SESSIONS='1|notes|1|0'))
        for call in self.calls():
            for arg in call:
                if '#{session_' in arg or '#{window_' in arg:
                    self.assertNotIn('\t', arg, f'tab in tmux format: {call}')

    def test_ls_queries_use_batch_mode(self):
        self.run_script('ls', env=self.env(STUB_LOCAL_SESSIONS='1|notes|1|0'))
        for call in self.calls_for('ssh'):
            self.assertIn('BatchMode=yes', call)

    def test_ls_skips_recently_unreachable_host(self):
        # beta's ssh exits 255; the first ls marks it down, the second skips
        # it entirely instead of paying the connect timeout again. alpha
        # (reachable) is queried both times.
        env = self.env(STUB_SESSIONS_alpha='300|build|2|1')
        self.run_script('ls', env=env)
        beta_first = len([c for c in self.calls_for('ssh') if 'beta' in c])
        alpha_first = len([c for c in self.calls_for('ssh') if 'alpha' in c])
        self.assertEqual(1, beta_first)
        self.run_script('ls', env=env)
        self.assertEqual(beta_first, len([c for c in self.calls_for('ssh') if 'beta' in c]))
        self.assertEqual(alpha_first * 2, len([c for c in self.calls_for('ssh') if 'alpha' in c]))

    def test_ls_labels_local_with_first_self_alias(self):
        # With TMUX_MULTI_SELF set, the local machine is listed under its
        # fleet name (the first alias) rather than its hostname.
        env = self.env(
            TMUX_MULTI_SELF='hub hubbox',
            STUB_LOCAL_SESSIONS='100|notes|1|0',
        )
        result = self.run_script('ls', env=env)
        self.assertIn('hub\tnotes\t1w\t-', result.stdout.splitlines())

    def test_ls_without_hosts_file_lists_local_only(self):
        env = self.env(
            TMUX_MULTI_HOSTS_FILE=str(self.tmp / 'missing'),
            STUB_LOCAL_SESSIONS='100|notes|1|0',
        )
        result = self.run_script('ls', env=env)
        self.assertEqual(['hubbox\tnotes\t1w\t-'], result.stdout.splitlines())
        self.assertEqual([], self.calls_for('ssh'))

    # ---- open ----

    def test_open_remote_creates_tagged_window(self):
        env = self.env(TMUX='/tmp/fake,1,0', TMUX_PANE='%5')
        self.run_script('open', 'alpha', 'build', env=env)
        new_windows = [c for c in self.calls_for('tmux') if c[1] == 'new-window']
        self.assertEqual(1, len(new_windows))
        self.assertEqual(
            ['-P', '-F', '#{window_id}', '--', str(SCRIPT), 'shell-attach', 'alpha', 'build'],
            new_windows[0][2:],
        )
        # Tagged and flattened synchronously: the flat-view hook fires before
        # anything inside the new window runs, so open must do both itself.
        self.assertIn(
            ['tmux', 'set-option', '-w', '-t', '@9', '@tmux_multi_target', 'alpha:build'],
            self.calls(),
        )
        self.assertIn(['tmux', 'set-option', '-t', '@9', 'status', 'off'], self.calls())

    def test_open_remote_reuses_existing_window(self):
        env = self.env(
            TMUX='/tmp/fake,1,0',
            TMUX_PANE='%5',
            STUB_WINDOWS='$3 @7 alpha:build',
        )
        self.run_script('open', 'alpha', 'build', env=env)
        tmux_cmds = [c[1] for c in self.calls_for('tmux')]
        self.assertNotIn('new-window', tmux_cmds)
        self.assertIn(['tmux', 'select-window', '-t', '@7'], self.calls())
        self.assertIn(['tmux', 'switch-client', '-t', '$3'], self.calls())

    def test_open_local_attaches_outside_tmux(self):
        env = self.env(STUB_EXISTING_SESSIONS='notes')
        self.run_script('open', 'hubbox', 'notes', env=env)
        self.assertIn(['tmux', 'attach-session', '-t', '=notes'], self.calls())

    def test_open_local_creates_missing_session(self):
        # No tmux-session helper on PATH: fall back to a plain new-session.
        self.run_script('open', 'hubbox', 'fresh')
        self.assertIn(['tmux', 'new-session', '-d', '-s', 'fresh'], self.calls())
        self.assertIn(['tmux', 'attach-session', '-t', '=fresh'], self.calls())

    def test_open_local_prefers_tmux_session_helper(self):
        # With the helper installed it wins, so new sessions get the layout.
        self.make_stub(
            'tmux-session',
            "#!/usr/bin/env bash\n"
            "line='tmux-session'\n"
            'for a in "$@"; do line="$line"$\'\\x1f\'"$a"; done\n'
            "printf '%s\\n' \"$line\" >>\"$STUB_LOG\"\n",
        )
        self.run_script('open', 'hubbox', 'fresh')
        self.assertIn(['tmux-session', 'fresh', '', '--no-attach'], self.calls())
        tmux_cmds = [c[1] for c in self.calls_for('tmux')]
        self.assertNotIn('new-session', tmux_cmds)
        self.assertIn(['tmux', 'attach-session', '-t', '=fresh'], self.calls())

    def test_open_local_escapes_remote_window_of_same_session(self):
        # Viewing a remote window of session "notes" and picking "notes"
        # itself: switch-client alone is a no-op, so open must land on the
        # most recently used LOCAL window first (here @4, not the newer but
        # tagged @9).
        env = self.env(
            TMUX='/tmp/fake,1,0',
            STUB_EXISTING_SESSIONS='notes',
            STUB_CURRENT_SESSION='notes',
            STUB_CURRENT_TAG='alpha:build',
            STUB_CURRENT_WINDOWS='100 @4 \n900 @9 alpha:build',
        )
        self.run_script('open', 'hubbox', 'notes', env=env)
        self.assertIn(['tmux', 'select-window', '-t', '@4'], self.calls())
        self.assertIn(['tmux', 'switch-client', '-t', '=notes'], self.calls())

    def test_open_local_switches_inside_tmux(self):
        env = self.env(TMUX='/tmp/fake,1,0', STUB_EXISTING_SESSIONS='notes')
        self.run_script('open', 'hubbox', 'notes', env=env)
        self.assertIn(['tmux', 'switch-client', '-t', '=notes'], self.calls())

    # ---- preview ----

    def test_preview_local_renders_every_window(self):
        env = self.env(
            STUB_SESSION_WINDOWS='1 0 shell\n2 1 logs',
            STUB_PANE='listening on :8080',
        )
        out = self.run_script('preview', 'hubbox', 'build', env=env).stdout
        # One header cell per window column: active reverse-video, inactive
        # dimmed (cell padding varies with the preview width).
        self.assertIn('\033[7;1m 2:logs', out)
        self.assertIn('\033[2m 1:shell', out)
        self.assertIn('listening on :8080', out)
        captures = [c for c in self.calls_for('tmux') if c[1] == 'capture-pane']
        # One coloured capture per window, exact-match targets.
        self.assertEqual(
            [['-ep', '-t', '=build:1'], ['-ep', '-t', '=build:2']],
            [c[2:] for c in captures],
        )

    def test_preview_remote_quotes_session_name(self):
        env = self.env(STUB_REMOTE_DUMP='\x011\x011\x01main\nremote screen text')
        out = self.run_script('preview', 'alpha', "it's got spaces", env=env).stdout
        self.assertIn('\033[7;1m 1:main', out)
        self.assertIn('remote screen text', out)
        remote = ' '.join(' '.join(c) for c in self.calls_for('ssh'))
        self.assertIn("list-windows -t '=it'\\''s got spaces'", remote)
        self.assertIn("capture-pane -ep -t '=it'\\''s got spaces':", remote)

    def test_preview_remote_is_cached(self):
        env = self.env(
            STUB_REMOTE_DUMP='\x011\x011\x01main\nremote screen text',
            TMPDIR=str(self.tmp),
        )
        first = self.run_script('preview', 'alpha', 'build', env=env).stdout
        after_first = len(self.calls_for('ssh'))
        second = self.run_script('preview', 'alpha', 'build', env=env).stdout
        self.assertEqual(first, second)
        # Second render came from the cache: no further ssh round trips.
        self.assertEqual(after_first, len(self.calls_for('ssh')))

    def test_preview_trims_trailing_blank_lines(self):
        env = self.env(
            STUB_SESSION_WINDOWS='1 1 shell',
            STUB_PANE='top line\n\n\n',
        )
        out = self.run_script('preview', 'hubbox', 'build', env=env).stdout
        self.assertTrue(out.endswith('top line\n'), repr(out[-40:]))

    def test_preview_of_missing_session_is_not_an_error(self):
        result = self.run_script('preview', 'hubbox', 'ghost')
        self.assertEqual(0, result.returncode)

    # ---- picker rows ----

    def test_rows_put_session_name_first(self):
        env = self.env(STUB_LOCAL_SESSIONS='100|notes|1|0')
        out = self.run_script('rows', env=env).stdout
        # Session before host, colourised and padded for the picker.
        self.assertRegex(out, r'notes\s.*hubbox')
        self.assertIn('\033[1;38;2;255;158;100m', out)

    # ---- kill ----

    def test_kill_remote_session_and_its_local_window(self):
        env = self.env(
            TMUX='/tmp/fake,1,0',
            STUB_WINDOWS='$3 @7 alpha:build',
        )
        self.run_script('kill', 'alpha', 'build', env=env)
        kill_calls = [c for c in self.calls_for('ssh') if 'kill-session' in ' '.join(c)]
        self.assertEqual(1, len(kill_calls))
        self.assertIn("kill-session -t '=build'", ' '.join(kill_calls[0]))
        self.assertIn(['tmux', 'kill-window', '-t', '@7'], self.calls())

    def test_kill_local_session(self):
        env = self.env(TMUX='/tmp/fake,1,0', STUB_CURRENT_SESSION='notes')
        self.run_script('kill', 'hubbox', 'scratch', env=env)
        self.assertIn(['tmux', 'kill-session', '-t', '=scratch'], self.calls())

    def test_kill_refuses_current_local_session(self):
        env = self.env(TMUX='/tmp/fake,1,0', STUB_CURRENT_SESSION='notes')
        result = self.run_script('kill', 'hubbox', 'notes', env=env, check=False)
        self.assertNotEqual(0, result.returncode)
        self.assertNotIn('kill-session', [c[1] for c in self.calls_for('tmux')])

    # ---- shell-attach ----

    def test_shell_attach_quotes_awkward_session_names(self):
        self.run_script('shell-attach', 'alpha', "it's got spaces")
        (ssh_call,) = self.calls_for('ssh')
        remote = ssh_call[-1]
        self.assertIn("exec tmux-session 'it'\\''s got spaces'", remote)
        self.assertIn("exec tmux new-session -A -s 'it'\\''s got spaces'", remote)

    def test_shell_attach_tags_and_names_its_window(self):
        env = self.env(TMUX='/tmp/fake,1,0', TMUX_PANE='%5')
        self.run_script('shell-attach', 'alpha', 'build', env=env)
        calls = self.calls()
        self.assertIn(
            ['tmux', 'set-option', '-w', '-t', '%5', '@tmux_multi_target', 'alpha:build'],
            calls,
        )
        self.assertIn(['tmux', 'rename-window', '-t', '%5', 'build@alpha'], calls)
        self.assertIn(
            ['tmux', 'set-option', '-w', '-t', '%5', 'automatic-rename', 'off'],
            calls,
        )

    def test_shell_attach_offers_reconnect_on_lost_connection(self):
        result = self.run_script('shell-attach', 'flaky', 'build', input='q\n')
        self.assertIn('connection to flaky lost (ssh exit 255)', result.stdout)
        self.assertEqual(1, len(self.calls_for('ssh')))

    # ---- doctor ----

    def test_doctor_reports_per_host_state(self):
        env = self.env(STUB_SESSIONS_alpha='300|build|2|1\n50|logs|1|0')
        result = self.run_script('doctor', env=env, check=False)
        self.assertNotEqual(0, result.returncode)  # beta is down
        self.assertIn('alpha: ok (tmux 3.4a, 2 sessions)', result.stdout)
        self.assertIn('beta: FAILED', result.stdout)

    def test_doctor_survives_host_with_no_tmux_server(self):
        # tmux present (tmux -V works) but list-sessions exits non-zero
        # because no server is running: doctor must report 0 sessions and
        # carry on, not die mid-report under set -e/pipefail.
        result = self.run_script('doctor', check=False)
        self.assertIn('alpha: ok (tmux 3.4a, 0 sessions)', result.stdout)
        self.assertIn('beta: FAILED', result.stdout)


@unittest.skipUnless(shutil.which('tmux'), 'tmux not installed')
class TmuxConfSmokeTest(unittest.TestCase):
    """The committed tmux.conf must load without errors on a real tmux."""

    def test_conf_loads_cleanly(self):
        home = Path(tempfile.mkdtemp(prefix='tmux-conf-test.'))
        self.addCleanup(shutil.rmtree, home, ignore_errors=True)
        socket = 'tmux-multi-conf-test'
        env = dict(os.environ, HOME=str(home))
        env.pop('TMUX', None)
        try:
            result = subprocess.run(
                ['tmux', '-L', socket, '-f', str(TMUX_CONF),
                 'new-session', '-d', '-s', 'smoke'],
                env=env,
                text=True,
                capture_output=True,
                timeout=30,
            )
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertNotIn('.tmux.conf', result.stderr)
        finally:
            subprocess.run(
                ['tmux', '-L', socket, 'kill-server'],
                env=env,
                capture_output=True,
                timeout=30,
            )


if __name__ == '__main__':
    unittest.main()
