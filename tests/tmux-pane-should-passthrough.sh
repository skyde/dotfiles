#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/tmux-pane-should-passthrough"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tmux-pane-passthrough.XXXXXX")"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/ps" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${TMUX_TEST_PS_OUTPUT:-}"
SH
chmod +x "$tmp/bin/ps"

no_tr_bin="$tmp/no-tr-bin"
mkdir -p "$no_tr_bin"
ln -s "$(command -v bash)" "$no_tr_bin/bash"

assert_success() {
  local name="$1"
  shift

  if "$@"; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s\n' "$name" >&2
    return 1
  fi
}

assert_failure() {
  local name="$1"
  shift

  if "$@"; then
    printf 'not ok - %s\n' "$name" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_success "direct nvim command passes through" "$helper" nvim /dev/ttys001
assert_success "direct nvim.exe command passes through" "$helper" nvim.exe /dev/ttys001
assert_success "direct Windows path nvim.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\tools\nvim.exe README.md' ""
assert_success "direct uppercase Windows path nvim.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\tools\NVIM.EXE README.md' ""
assert_success "direct UNC Windows path nvim.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" '\\server\share\nvim.exe README.md' ""
assert_success "direct slash UNC Windows path nvim.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" '//server/share/nvim.exe README.md' ""
assert_success "direct vi command passes through" "$helper" vi /dev/ttys001
assert_success "direct vim.basic command passes through" "$helper" /usr/bin/vim.basic /dev/ttys001
assert_success "direct helix command passes through" "$helper" /opt/homebrew/bin/hx /dev/ttys001
assert_success "direct nano command passes through" "$helper" /usr/bin/nano /dev/ttys001
assert_success "direct micro command passes through" "$helper" /opt/homebrew/bin/micro /dev/ttys001
assert_success "direct terminal emacs command passes through" "$helper" /opt/homebrew/bin/emacs /dev/ttys001
assert_success "direct terminal emacsclient command passes through" "$helper" /opt/homebrew/bin/emacsclient /dev/ttys001
assert_success "direct kak command passes through" "$helper" /opt/homebrew/bin/kak /dev/ttys001
assert_success "direct kakoune command passes through" "$helper" /opt/homebrew/bin/kakoune /dev/ttys001
assert_success "direct less pager command passes through" "$helper" /usr/bin/less /dev/ttys001
assert_success "direct man pager command passes through" "$helper" /usr/bin/man /dev/ttys001
assert_success "direct delta pager command passes through" "$helper" /opt/homebrew/bin/delta /dev/ttys001
assert_success "direct path yazi command passes through" "$helper" /opt/homebrew/bin/yazi /dev/ttys001
assert_success "direct path ssh.exe command passes through without ps" env PATH=/usr/bin:/bin "$helper" /usr/bin/ssh.exe ""
assert_success "direct Windows path ssh.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\tools\ssh.exe devbox' ""
assert_success "direct uppercase Windows path ssh.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\tools\SSH.EXE devbox' ""
assert_success "direct UNC Windows path ssh.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" '\\server\share\ssh.exe devbox' ""
assert_success "direct slash UNC Windows path ssh.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" '//server/share/ssh.exe devbox' ""
assert_success "direct nested tmux command passes through" "$helper" /opt/homebrew/bin/tmux /dev/ttys001
assert_success "direct screen command passes through" "$helper" /usr/bin/screen /dev/ttys001
assert_success "direct zellij command passes through" "$helper" /opt/homebrew/bin/zellij /dev/ttys001
assert_success "direct codex command passes through" "$helper" /opt/homebrew/bin/codex /dev/ttys001
assert_success "direct aider command passes through" "$helper" /opt/homebrew/bin/aider /dev/ttys001
assert_success "direct ssh command passes through without ps" env PATH=/usr/bin:/bin "$helper" ssh ""
assert_success "direct ssh remote shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh devbox" ""
assert_success "direct ssh RequestTTY auto remote shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRequestTTY=auto devbox" ""
assert_failure "direct ssh RequestTTY no remote shell command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRequestTTY=no devbox" ""
assert_success "direct ssh forced tty remote nvim passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -t devbox nvim README.md" ""
assert_success "direct ssh no-tty then forced tty remote nvim passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -Tt devbox nvim README.md" ""
assert_success "direct ssh RequestTTY remote nvim passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRequestTTY=yes devbox nvim README.md" ""
assert_success "direct ssh proxy command option still passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -o ProxyCommand='ssh -W %h:%p bastion' devbox" ""
assert_failure "direct ssh RemoteCommand nvim without tty does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRemoteCommand='nvim README.md' devbox" ""
assert_success "direct ssh RequestTTY RemoteCommand nvim passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRequestTTY=yes -oRemoteCommand='nvim README.md' devbox" ""
assert_success "direct ssh forced tty RemoteCommand nvim passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -tt -o RemoteCommand='nvim README.md' devbox" ""
assert_failure "direct ssh forced tty RemoteCommand one-shot does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -t -oRemoteCommand='echo nvim' devbox" ""
assert_success "direct ssh RemoteCommand none remote shell passes through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRemoteCommand=none devbox" ""
assert_failure "direct ssh remote one-shot command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh devbox echo nvim" ""
assert_failure "direct ssh RequestTTY remote one-shot command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRequestTTY=yes devbox echo nvim" ""
assert_failure "direct ssh RequestTTY auto remote nvim does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -oRequestTTY=auto devbox nvim README.md" ""
assert_failure "direct ssh forced tty then no-tty remote nvim does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -tT devbox nvim README.md" ""
assert_failure "direct ssh tunnel command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -N -L 8080:localhost:80 devbox" ""
assert_failure "direct slash UNC Windows path ssh tunnel does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "//server/share/ssh.exe -N -L 8080:localhost:80 devbox" ""
assert_failure "direct ssh stdio forwarding command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -W db:5432 bastion" ""
assert_failure "direct ssh no-pty command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -T git@github.com" ""
assert_failure "direct ssh control command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "ssh -O check devbox" ""
assert_success "paste key direct nvim command passes through" "$helper" --paste-key nvim /dev/ttys001
assert_success "paste key direct vim command passes through" "$helper" --paste-key vim /dev/ttys001
assert_success "paste key direct nested tmux command passes through" "$helper" --paste-key tmux /dev/ttys001
assert_failure "paste key direct nano command uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key nano ""
assert_failure "paste key direct micro command uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key micro ""
assert_failure "paste key direct emacs command uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key emacs ""
assert_failure "paste key direct ssh command uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key ssh ""
assert_failure "paste key direct ssh remote shell uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "ssh devbox" ""
assert_failure "paste key direct kitten ssh uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "kitten ssh devbox" ""
assert_failure "paste key direct mosh client uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key mosh-client ""
assert_failure "paste key direct delta pager uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key delta ""
assert_success "paste key direct docker exec nvim passes through" env PATH=/usr/bin:/bin "$helper" --paste-key "docker exec -it app nvim README.md" ""
assert_failure "paste key direct docker exec ssh uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "docker exec -it app ssh devbox" ""
assert_failure "paste key direct docker attach uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "docker attach app" ""
assert_failure "paste key direct docker start attach uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "docker start -ai app" ""
assert_failure "paste key direct podman attach uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "podman attach app" ""
assert_success "paste key direct kubectl exec nvim passes through" env PATH=/usr/bin:/bin "$helper" --paste-key "kubectl exec -it pod/app -- nvim README.md" ""
assert_failure "paste key direct kubectl exec ssh uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "kubectl exec -it pod/app -- ssh devbox" ""
assert_failure "paste key direct kubectl attach uses tmux paste" env PATH=/usr/bin:/bin "$helper" --paste-key "kubectl attach -it pod/app -c api" ""
assert_success "direct mosh client command passes through without ps" env PATH=/usr/bin:/bin "$helper" mosh-client ""
assert_success "direct autossh command passes through without ps" env PATH=/usr/bin:/bin "$helper" autossh ""
assert_success "direct autossh remote shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "autossh -M 0 devbox" ""
assert_failure "direct autossh tunnel command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "autossh -M 0 -N -L 8080:localhost:80 devbox" ""
assert_success "direct ipython command passes through without ps" env PATH=/usr/bin:/bin "$helper" ipython ""
assert_success "direct python repl command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "python3" ""
assert_success "direct python interactive script passes through without ps" env PATH=/usr/bin:/bin "$helper" "python3 -i app.py" ""
assert_success "direct python pdb module passes through without ps" env PATH=/usr/bin:/bin "$helper" "python3 -m pdb app.py" ""
assert_success "direct python mixed-case IPython module passes through without ps" env PATH=/usr/bin:/bin "$helper" "python3 -m IPython" ""
assert_success "direct python mixed-case module passes through without tr" env PATH="$no_tr_bin" "$helper" "python3 -m IPython" ""
assert_success "direct python compact mixed-case module passes through without ps" env PATH=/usr/bin:/bin "$helper" "python3 -mIPython" ""
assert_failure "direct python compact noninteractive module does not pass through" env PATH=/usr/bin:/bin "$helper" "python3 -mhttp.server" ""
assert_success "direct python compact interactive command string passes through" env PATH=/usr/bin:/bin "$helper" "python3 -ic 'print(\"nvim\")'" ""
assert_failure "direct python script command line does not pass through" env PATH=/usr/bin:/bin "$helper" "python3 app.py" ""
assert_failure "direct python noninteractive module does not pass through" env PATH=/usr/bin:/bin "$helper" "python3 -m http.server" ""
assert_failure "direct python command string does not pass through" env PATH=/usr/bin:/bin "$helper" "python3 -c 'print(\"nvim\")'" ""
assert_failure "direct python compact command string does not pass through" env PATH=/usr/bin:/bin "$helper" "python3 -cprint(\"nvim\")" ""
assert_failure "direct python config utility does not pass through" env PATH=/usr/bin:/bin "$helper" "python3-config --includes" ""
assert_success "direct node repl command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "node" ""
assert_success "direct node interactive script command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "node -i app.js" ""
assert_success "direct node preload repl command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "node -r ts-node/register" ""
assert_success "direct node inspect command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "node inspect app.js" ""
assert_success "direct nodejs repl command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "nodejs --interactive" ""
assert_success "direct node compact preload repl command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "node -rinteractive" ""
assert_success "direct node compact interactive eval command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "node -ie 'console.log(\"nvim\")'" ""
assert_failure "direct node script command line does not pass through" env PATH=/usr/bin:/bin "$helper" "node app.js" ""
assert_failure "direct node eval command line does not pass through" env PATH=/usr/bin:/bin "$helper" "node -e 'console.log(\"nvim\")'" ""
assert_failure "direct node print command line does not pass through" env PATH=/usr/bin:/bin "$helper" "node -p 'process.version'" ""
assert_failure "direct node compact eval command line does not pass through" env PATH=/usr/bin:/bin "$helper" "node -econsole.info(\"nvim\")" ""
assert_failure "direct node compact print command line does not pass through" env PATH=/usr/bin:/bin "$helper" "node -pprocess.version" ""
assert_failure "direct node compact preload script command line does not pass through" env PATH=/usr/bin:/bin "$helper" "node -rinteractive app.js" ""
assert_failure "direct node test runner does not pass through" env PATH=/usr/bin:/bin "$helper" "node --test" ""
assert_failure "direct node inspector script does not pass through" env PATH=/usr/bin:/bin "$helper" "node --inspect-brk app.js" ""
assert_success "direct deno repl command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "deno repl" ""
assert_success "direct bare deno command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "deno" ""
assert_success "direct deno global option before repl passes through without ps" env PATH=/usr/bin:/bin "$helper" "deno --config deno.json repl" ""
assert_failure "direct deno run command line does not pass through" env PATH=/usr/bin:/bin "$helper" "deno run app.ts" ""
assert_failure "direct deno global option before run does not pass through" env PATH=/usr/bin:/bin "$helper" "deno --config deno.json run app.ts" ""
assert_failure "direct deno eval command line does not pass through" env PATH=/usr/bin:/bin "$helper" "deno eval 'console.log(1)'" ""
assert_failure "direct deno version command line does not pass through" env PATH=/usr/bin:/bin "$helper" "deno --version" ""
assert_success "direct bun repl command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "bun repl" ""
assert_failure "direct bare bun command line does not pass through" env PATH=/usr/bin:/bin "$helper" "bun" ""
assert_failure "direct bun run command line does not pass through" env PATH=/usr/bin:/bin "$helper" "bun run app.ts" ""
assert_success "direct php interactive command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "php -a" ""
assert_success "direct php long interactive command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "php --interactive" ""
assert_success "direct php define option before interactive passes through without ps" env PATH=/usr/bin:/bin "$helper" "php -d memory_limit=-1 -a" ""
assert_success "direct php ini option before interactive passes through without ps" env PATH=/usr/bin:/bin "$helper" "php -c php.ini --interactive" ""
assert_failure "direct php run command line does not pass through" env PATH=/usr/bin:/bin "$helper" "php -r 'echo 1;'" ""
assert_failure "direct php define option before run does not pass through" env PATH=/usr/bin:/bin "$helper" "php -d memory_limit=-1 -r 'echo 1;'" ""
assert_failure "direct php script command line does not pass through" env PATH=/usr/bin:/bin "$helper" "php app.php" ""
assert_failure "direct php ini option before script does not pass through" env PATH=/usr/bin:/bin "$helper" "php -c php.ini app.php" ""
assert_success "direct irb command passes through without ps" env PATH=/usr/bin:/bin "$helper" "irb" ""
assert_success "direct pry command passes through without ps" env PATH=/usr/bin:/bin "$helper" "pry" ""
assert_success "direct rdbg command passes through without ps" env PATH=/usr/bin:/bin "$helper" "rdbg app.rb" ""
assert_success "direct rails console command passes through without ps" env PATH=/usr/bin:/bin "$helper" "rails console" ""
assert_success "direct rails dbconsole command passes through without ps" env PATH=/usr/bin:/bin "$helper" "rails dbconsole" ""
assert_failure "direct rails runner command does not pass through" env PATH=/usr/bin:/bin "$helper" "rails runner 'puts 1'" ""
assert_failure "direct rails console help does not pass through" env PATH=/usr/bin:/bin "$helper" "rails console --help" ""
assert_success "direct bundle exec pry command passes through without ps" env PATH=/usr/bin:/bin "$helper" "bundle exec pry" ""
assert_success "direct bundler versioned exec irb command passes through without ps" env PATH=/usr/bin:/bin "$helper" "bundler _2.5.0_ exec -- irb" ""
assert_success "direct bundle exec rails console command passes through without ps" env PATH=/usr/bin:/bin "$helper" "bundle exec rails console" ""
assert_failure "direct bundle exec echoing pry does not pass through" env PATH=/usr/bin:/bin "$helper" "bundle exec echo pry" ""
assert_success "direct ruby -S irb command passes through without ps" env PATH=/usr/bin:/bin "$helper" "ruby -S irb" ""
assert_success "direct ruby -S rails console command passes through without ps" env PATH=/usr/bin:/bin "$helper" "ruby -I lib -S rails console" ""
assert_success "direct ruby bin rails console command passes through without ps" env PATH=/usr/bin:/bin "$helper" "ruby bin/rails console" ""
assert_failure "direct ruby script command does not pass through" env PATH=/usr/bin:/bin "$helper" "ruby app.rb" ""
assert_failure "direct ruby eval command does not pass through" env PATH=/usr/bin:/bin "$helper" "ruby -e 'puts 1'" ""
assert_failure "direct ruby rails runner command does not pass through" env PATH=/usr/bin:/bin "$helper" "ruby bin/rails runner 'puts 1'" ""
assert_success "direct gdb command passes through without ps" env PATH=/usr/bin:/bin "$helper" "gdb ./app" ""
assert_success "direct lldb command passes through without ps" env PATH=/usr/bin:/bin "$helper" "lldb ./app" ""
assert_success "direct rr replay command passes through without ps" env PATH=/usr/bin:/bin "$helper" "rr replay" ""
assert_success "direct ghci command passes through without ps" env PATH=/usr/bin:/bin "$helper" "ghci Main.hs" ""
assert_success "direct iex command passes through without ps" env PATH=/usr/bin:/bin "$helper" "iex -S mix" ""
assert_success "direct erl command passes through without ps" env PATH=/usr/bin:/bin "$helper" "erl" ""
assert_success "direct utop command passes through without ps" env PATH=/usr/bin:/bin "$helper" "utop" ""
assert_success "direct jshell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "jshell" ""
assert_success "direct radian command passes through without ps" env PATH=/usr/bin:/bin "$helper" "radian" ""
assert_success "direct phpdbg command passes through without ps" env PATH=/usr/bin:/bin "$helper" "phpdbg -qrr app.php" ""
assert_success "direct psql shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "psql postgres" ""
assert_failure "direct psql command option does not pass through" env PATH=/usr/bin:/bin "$helper" "psql postgres -c 'select 1'" ""
assert_failure "direct psql attached command option does not pass through" env PATH=/usr/bin:/bin "$helper" "psql postgres -cselect" ""
assert_failure "direct psql file option does not pass through" env PATH=/usr/bin:/bin "$helper" "psql -f schema.sql" ""
assert_failure "direct psql attached file option does not pass through" env PATH=/usr/bin:/bin "$helper" "psql -fschema.sql" ""
assert_success "direct mysql shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "mysql app" ""
assert_failure "direct mysql execute option does not pass through" env PATH=/usr/bin:/bin "$helper" "mysql app -e 'select 1'" ""
assert_failure "direct mysql attached execute option does not pass through" env PATH=/usr/bin:/bin "$helper" "mysql app -eselect" ""
assert_success "direct mariadb shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "mariadb app" ""
assert_failure "direct mariadb execute option does not pass through" env PATH=/usr/bin:/bin "$helper" "mariadb --execute='select 1' app" ""
assert_success "direct sqlite3 shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "sqlite3 app.db" ""
assert_failure "direct sqlite3 sql one-liner does not pass through" env PATH=/usr/bin:/bin "$helper" "sqlite3 app.db 'select 1'" ""
assert_success "direct duckdb shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "duckdb analytics.duckdb" ""
assert_failure "direct duckdb command option does not pass through" env PATH=/usr/bin:/bin "$helper" "duckdb -c 'select 1'" ""
assert_failure "direct duckdb attached command option does not pass through" env PATH=/usr/bin:/bin "$helper" "duckdb -cselect" ""
assert_success "direct redis-cli shell command passes through without ps" env PATH=/usr/bin:/bin "$helper" "redis-cli -h localhost -p 6379" ""
assert_failure "direct redis-cli command does not pass through" env PATH=/usr/bin:/bin "$helper" "redis-cli -h localhost ping" ""
assert_failure "direct redis-cli help does not pass through" env PATH=/usr/bin:/bin "$helper" "redis-cli --help" ""
assert_success "direct lua repl command passes through without ps" env PATH=/usr/bin:/bin "$helper" "lua" ""
assert_success "direct lua interactive script passes through without ps" env PATH=/usr/bin:/bin "$helper" "lua -i app.lua" ""
assert_success "direct lua module preload repl passes through without ps" env PATH=/usr/bin:/bin "$helper" "lua -l socket" ""
assert_failure "direct lua script does not pass through" env PATH=/usr/bin:/bin "$helper" "lua app.lua" ""
assert_failure "direct lua eval does not pass through" env PATH=/usr/bin:/bin "$helper" "lua -e 'print(1)'" ""
assert_failure "direct lua attached eval does not pass through" env PATH=/usr/bin:/bin "$helper" "lua -eprint(1)" ""
assert_success "direct luajit repl command passes through without ps" env PATH=/usr/bin:/bin "$helper" "luajit -l ffi" ""
assert_failure "direct luajit script does not pass through" env PATH=/usr/bin:/bin "$helper" "luajit app.lua" ""
assert_failure "direct luajit attached eval does not pass through" env PATH=/usr/bin:/bin "$helper" "luajit -eprint(1)" ""
assert_success "direct julia repl command passes through without ps" env PATH=/usr/bin:/bin "$helper" "julia --project=." ""
assert_success "direct julia interactive script passes through without ps" env PATH=/usr/bin:/bin "$helper" "julia -i app.jl" ""
assert_failure "direct julia script does not pass through" env PATH=/usr/bin:/bin "$helper" "julia app.jl" ""
assert_failure "direct julia eval does not pass through" env PATH=/usr/bin:/bin "$helper" "julia -e 'println(1)'" ""
assert_failure "direct julia attached eval does not pass through" env PATH=/usr/bin:/bin "$helper" "julia -eprintln(1)" ""
assert_success "direct R repl command passes through without ps" env PATH=/usr/bin:/bin "$helper" "R --vanilla" ""
assert_success "direct Windows R.exe repl command passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\tools\R.EXE --vanilla' ""
assert_failure "direct R eval does not pass through" env PATH=/usr/bin:/bin "$helper" "R -e 'print(1)'" ""
assert_failure "direct R attached eval does not pass through" env PATH=/usr/bin:/bin "$helper" "R -eprint(1)" ""
assert_failure "direct R CMD does not pass through" env PATH=/usr/bin:/bin "$helper" "R CMD BATCH app.R" ""
assert_success "direct sshpass ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "sshpass -p secret ssh devbox" ""
assert_failure "direct sshpass ssh tunnel command does not pass through without ps" env PATH=/usr/bin:/bin "$helper" "sshpass -p secret ssh -N -L 8080:localhost:80 devbox" ""
assert_failure "direct sshpass non-tui command line does not pass through" env PATH=/usr/bin:/bin "$helper" "sshpass -p secret echo ssh devbox" ""
assert_success "direct kitten ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kitten ssh devbox" ""
assert_success "direct env ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "env TERM=xterm-256color ssh devbox" ""
assert_success "direct env chdir mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "env --chdir=/tmp mosh devbox" ""
assert_success "direct env split-string ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "env -S 'ssh devbox'" ""
assert_failure "direct env split-string echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "env -S 'echo ssh' ssh devbox" ""
assert_success "direct assignment ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "FOO=bar ssh devbox" ""
assert_success "direct arch nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "arch -x86_64 nvim README.md" ""
assert_success "direct arch ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "arch -arm64 ssh devbox" ""
assert_failure "direct arch echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "arch -x86_64 echo nvim README.md" ""
assert_success "direct Windows cmd ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\Windows\System32\cmd.exe /c ssh devbox' ""
assert_success "direct uppercase Windows cmd ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\Windows\System32\CMD.EXE /C SSH.EXE devbox' ""
assert_success "direct Windows cmd nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\Windows\System32\cmd.exe /s /c "nvim README.md"' ""
assert_success "direct Windows cmd uppercase command option passes through without tr" env PATH="$no_tr_bin" "$helper" 'C:\Windows\System32\cmd.exe /C ssh devbox' ""
assert_failure "direct Windows cmd echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" 'C:\Windows\System32\cmd.exe /k "echo ssh devbox"' ""
assert_failure "direct Windows cmd shell does not pass through without ps" env PATH=/usr/bin:/bin "$helper" 'C:\Windows\System32\cmd.exe' ""
assert_success "direct sudo ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "sudo -u root ssh devbox" ""
assert_success "direct sudo long option mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" 'sudo --prompt="password please" --user=root mosh devbox' ""
assert_success "direct sudo compact login user ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "sudo -iu root ssh devbox" ""
assert_success "direct sudo compact short user t ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "sudo -ut ssh devbox" ""
assert_success "direct sudo compact short user group-letter ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "sudo -ug ssh devbox" ""
assert_success "direct sudo compact short user type-letter ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "sudo -uT ssh devbox" ""
assert_success "direct sudo attached user ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "sudo -uroot ssh devbox" ""
assert_success "direct doas ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "doas -u root ssh devbox" ""
assert_success "direct doas config mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "doas -C /tmp/doas.conf mosh devbox" ""
assert_success "direct nice htop command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "nice -n 5 htop" ""
assert_success "direct stdbuf compact option nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "stdbuf -oL nvim README.md" ""
assert_success "direct stdbuf separated option ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "stdbuf -o L ssh devbox" ""
assert_success "direct unbuffer ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "unbuffer ssh devbox" ""
assert_success "direct rlwrap ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "rlwrap ssh devbox" ""
assert_success "direct rlwrap completion file nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "rlwrap -f completions.txt nvim README.md" ""
assert_success "direct setsid nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "setsid -w nvim README.md" ""
assert_success "direct winpty nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "winpty nvim README.md" ""
assert_success "direct winpty.exe nvim.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "winpty.exe nvim.exe README.md" ""
assert_success "direct script command string ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "script -q -c 'ssh devbox' /dev/null" ""
assert_success "direct script logfile nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "script -q /dev/null nvim README.md" ""
assert_success "direct time ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "time ssh devbox" ""
assert_success "direct bsd time nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "/usr/bin/time -p nvim README.md" ""
assert_success "direct gnu time mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "gtime -f '%E' -o timing.log mosh devbox" ""
assert_success "direct shell ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'ssh devbox'" ""
assert_success "direct shell time ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'time ssh devbox'" ""
assert_success "direct dash ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "dash -c 'ssh devbox'" ""
assert_success "direct powershell ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pwsh -NoProfile -Command 'ssh devbox'" ""
assert_success "direct powershell command option passes through without tr" env PATH="$no_tr_bin" "$helper" "pwsh -NoProfile -Command 'ssh devbox'" ""
assert_success "direct shell setup ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'cd /tmp && ssh devbox'" ""
assert_success "direct shell setup failure handler then ssh passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'cd /tmp || exit; ssh devbox'" ""
assert_success "direct shell sourced nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "zsh -ic 'source ~/.zshrc; nvim README.md'" ""
assert_success "direct shell clear then nvim passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'clear; nvim README.md'" ""
assert_success "direct shell printf then ssh passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'printf \"opening\\n\"; ssh devbox'" ""
assert_success "direct shell echo then mosh passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'echo opening; mosh devbox'" ""
assert_success "direct shell trap then ssh passes through without ps" env PATH=/usr/bin:/bin "$helper" "bash -lc 'trap \"printf cleanup\" EXIT; ssh devbox'" ""
assert_success "direct nested env shell ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "env FOO='two words' bash -lc 'ssh devbox'" ""
assert_success "direct env kitten ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "env TERM=xterm-kitty kitten ssh devbox" ""
assert_success "direct poetry run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "poetry run ssh devbox" ""
assert_success "direct poetry run separator ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "poetry run -- ssh devbox" ""
assert_success "direct poetry global directory nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "poetry -C ./app run nvim README.md" ""
assert_success "direct poetry global project ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "poetry --project=./app run ssh devbox" ""
assert_success "direct pipenv run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pipenv run ssh devbox" ""
assert_success "direct pipenv global python nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pipenv --python 3.12 run nvim README.md" ""
assert_success "direct pipx run spec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pipx run --spec neovim nvim README.md" ""
assert_success "direct hatch run env nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "hatch run test:nvim README.md" ""
assert_success "direct hatch matrix ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "hatch run +py=3.12 -version=9000 ssh devbox" ""
assert_success "direct hatch env run nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "hatch env run -e test nvim README.md" ""
assert_success "direct uv run nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uv run -- nvim README.md" ""
assert_success "direct uv run options nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uv run --with ruff --env-file .env -- nvim README.md" ""
assert_success "direct uv run inline option ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uv run --with=ruff --python 3.12 ssh devbox" ""
assert_success "direct uv global project nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uv --project ./app run --with-requirements requirements.txt nvim README.md" ""
assert_success "direct uvx nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uvx nvim README.md" ""
assert_success "direct uvx from nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uvx --from neovim nvim README.md" ""
assert_success "direct uvx python ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uvx --python 3.12 ssh devbox" ""
assert_success "direct uvx flag options nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uvx --managed-python --no-build nvim README.md" ""
assert_success "direct uv tool run nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uv tool run --from neovim nvim README.md" ""
assert_success "direct uv global directory tool run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uv --directory ./app tool run ssh devbox" ""
assert_success "direct uv tool option color run nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "uv tool --color never run nvim README.md" ""
assert_success "direct pixi run nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pixi run nvim README.md" ""
assert_success "direct pixi run separator ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pixi run -- ssh devbox" ""
assert_success "direct pixi run environment ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pixi run -e cuda ssh devbox" ""
assert_success "direct pixi global manifest nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pixi --manifest-path ./pixi.toml run nvim README.md" ""
assert_success "direct npx nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "npx --yes nvim README.md" ""
assert_success "direct npm exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "npm exec -- ssh devbox" ""
assert_success "direct npm exec call ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "npm exec -c 'ssh devbox'" ""
assert_success "direct npm x package nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "npm x --package=neovim -- nvim README.md" ""
assert_success "direct pnpm exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pnpm exec nvim README.md" ""
assert_success "direct pnpm global dir ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pnpm --dir ./app exec ssh devbox" ""
assert_success "direct pnpm shell-mode nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pnpm exec -c 'nvim README.md'" ""
assert_success "direct pnpm dlx package lazygit command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pnpm dlx --package lazygit lazygit" ""
assert_success "direct pnx package nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pnx --package neovim nvim README.md" ""
assert_success "direct pnpx package ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "pnpx --package openssh ssh devbox" ""
assert_success "direct yarn dlx package nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "yarn dlx --package=neovim nvim README.md" ""
assert_success "direct yarn exec ssh shell command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "yarn exec 'ssh devbox'" ""
assert_success "direct yarn exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "yarn exec nvim README.md" ""
assert_success "direct yarnpkg dlx package nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "yarnpkg dlx --package=neovim nvim README.md" ""
assert_success "direct bunx nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "bunx --bun nvim README.md" ""
assert_success "direct bun x package lazygit command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "bun x --package lazygit lazygit" ""
assert_success "direct corepack yarn dlx nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "corepack yarn dlx --package=neovim nvim README.md" ""
assert_success "direct corepack yarn versioned exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "corepack yarn@4.1.0 exec 'ssh devbox'" ""
assert_success "direct corepack pnpm exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "corepack pnpm exec ssh devbox" ""
assert_success "direct corepack npx nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "corepack npx --yes nvim README.md" ""
assert_success "direct corepack pnx lazygit command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "corepack pnx --package lazygit lazygit" ""
assert_success "direct npx.cmd nvim.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "npx.cmd --yes nvim.exe README.md" ""
assert_success "direct uppercase npx.cmd nvim.exe command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "NPX.CMD --yes NVIM.EXE README.md" ""
assert_success "direct direnv exec mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "direnv exec . mosh devbox" ""
assert_success "direct direnv exec separator nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "direnv exec . -- nvim README.md" ""
assert_success "direct asdf exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "asdf exec nvim README.md" ""
assert_success "direct asdf exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "asdf exec ssh devbox" ""
assert_success "direct mise exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "mise exec -- ssh devbox" ""
assert_success "direct mise alias nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "mise x -- nvim README.md" ""
assert_success "direct rtx exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "rtx exec -- ssh devbox" ""
assert_success "direct rtx alias nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "rtx x -- nvim README.md" ""
assert_success "direct nix develop ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "nix develop -c ssh devbox" ""
assert_success "direct nix develop attached command ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "nix develop --command=ssh devbox" ""
assert_success "direct nix develop attached command ssh without args passes through without ps" env PATH=/usr/bin:/bin "$helper" "nix develop --command=ssh" ""
assert_success "direct nix shell mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "nix shell .#openssh -c mosh devbox" ""
assert_success "direct nix shell attached command mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "nix shell .#openssh --command=mosh devbox" ""
assert_success "direct nix run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "nix run .#openssh -- ssh devbox" ""
assert_success "direct devcontainer exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "devcontainer exec --workspace-folder . nvim README.md" ""
assert_success "direct devcontainer exec shell nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "devcontainer exec --workspace-folder . --remote-env TERM=xterm-256color bash -lc 'nvim README.md'" ""
assert_success "direct docker exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker exec -it app nvim README.md" ""
assert_success "direct docker exec shell nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker exec --user root app bash -lc 'nvim README.md'" ""
assert_success "direct docker global context exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker --context prod exec app nvim README.md" ""
assert_success "direct docker attach command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker attach app" ""
assert_success "direct docker attach explicit stdin command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker attach --no-stdin=false app" ""
assert_success "direct docker container attach command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker container attach app" ""
assert_success "direct docker start attach interactive command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker start -ai app" ""
assert_success "direct docker container start attach interactive command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker container start --attach --interactive app" ""
assert_success "direct docker run nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker run --rm -it -e TERM=xterm-256color ubuntu nvim README.md" ""
assert_success "direct docker global host run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker --host=unix:///tmp/docker.sock run --rm -it ubuntu ssh devbox" ""
assert_success "direct docker run shell nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker run --rm --workdir /src ubuntu bash -lc 'nvim README.md'" ""
assert_success "direct docker run nvim entrypoint passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker run --rm --entrypoint nvim ubuntu README.md" ""
assert_success "direct docker run shell entrypoint passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker run --rm --entrypoint sh ubuntu -lc 'nvim README.md'" ""
assert_success "direct docker compose exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker compose exec -it app nvim README.md" ""
assert_success "direct docker global context compose exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker --context prod compose exec app nvim README.md" ""
assert_success "direct docker compose exec shell nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker compose -f compose.dev.yml --project-name demo exec app bash -lc 'nvim README.md'" ""
assert_success "direct docker compose run nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker compose run --rm --service-ports app nvim README.md" ""
assert_success "direct docker compose run shell nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker compose --profile dev run -e TERM=xterm-256color app bash -lc 'nvim README.md'" ""
assert_success "direct docker compose run nvim entrypoint passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker compose run --entrypoint=nvim app README.md" ""
assert_success "direct docker compose run shell entrypoint passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker compose run --entrypoint sh app -lc 'nvim README.md'" ""
assert_success "direct docker-compose exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker-compose exec app ssh devbox" ""
assert_success "direct docker-compose run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "docker-compose run --rm app ssh devbox" ""
assert_success "direct podman container exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman container exec -it app ssh devbox" ""
assert_success "direct podman global connection container exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman --connection prod container exec app ssh devbox" ""
assert_success "direct podman attach command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman attach app" ""
assert_success "direct podman start attach interactive command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman start -ai app" ""
assert_success "direct podman run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman run --rm -it fedora ssh devbox" ""
assert_success "direct podman global remote run ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman --remote run --rm -it fedora ssh devbox" ""
assert_success "direct podman run nvim entrypoint passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman run --rm --entrypoint nvim fedora README.md" ""
assert_success "direct podman compose exec mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman compose exec app mosh devbox" ""
assert_success "direct podman global url compose exec mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman --url ssh://devbox compose exec app mosh devbox" ""
assert_success "direct podman compose run mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman compose run --rm app mosh devbox" ""
assert_success "direct podman compose run nvim entrypoint passes through without ps" env PATH=/usr/bin:/bin "$helper" "podman compose run --entrypoint nvim app README.md" ""
assert_success "direct kubectl exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl exec -it deploy/app -c api -- nvim README.md" ""
assert_success "direct kubectl exec nvim without separator passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl exec -it deploy/app -c api nvim README.md" ""
assert_success "direct kubectl exec with namespace option passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl exec -n dev pod/app --container api nvim README.md" ""
assert_success "direct kubectl global namespace exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl -n dev exec pod/app -- nvim README.md" ""
assert_success "direct kubectl global context exec shell ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl --context=prod -n dev exec pod/app -- sh -c 'ssh devbox'" ""
assert_success "direct kubectl global short verbosity exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl -v 6 exec pod/app -- nvim README.md" ""
assert_success "direct kubectl global long verbosity exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl --v 6 exec pod/app -- ssh devbox" ""
assert_success "direct kubectl global client cert exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl --client-certificate cert.pem --client-key key.pem exec pod/app -- nvim README.md" ""
assert_success "direct kubectl global basic auth exec ssh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl --username alice --password example exec pod/app -- ssh devbox" ""
assert_success "direct kubectl global logging exec nvim command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl --log-flush-frequency 5s --vmodule kubelet=6 exec pod/app -- nvim README.md" ""
assert_success "direct kubectl attach stdin tty command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl attach -it pod/app -c api" ""
assert_success "direct kubectl attach compact container stdin tty passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl attach -it pod/app -capi" ""
assert_success "direct kubectl global namespace attach stdin command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "kubectl -n dev attach --stdin pod/app -c api" ""
assert_success "direct oc exec shell mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "oc exec pod/app -- sh -c 'mosh devbox'" ""
assert_success "direct oc global namespace exec mosh command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "oc --namespace dev exec pod/app -- mosh devbox" ""
assert_success "direct oc attach stdin tty command line passes through without ps" env PATH=/usr/bin:/bin "$helper" "oc attach -it pod/app -c api" ""
assert_failure "direct kitten image command line does not pass through" env PATH=/usr/bin:/bin "$helper" "kitten icat image.png" ""
assert_failure "direct env without command does not pass through" env PATH=/usr/bin:/bin "$helper" "env -u TERM VAR" ""
assert_failure "direct sudo shell without TUI does not pass through" env PATH=/usr/bin:/bin "$helper" "sudo -u root zsh" ""
assert_failure "direct sudo compact login user echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "sudo -iu root echo ssh devbox" ""
assert_failure "direct doas echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "doas -u root echo ssh devbox" ""
assert_failure "direct stdbuf echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "stdbuf -oL echo nvim README.md" ""
assert_failure "direct unbuffer echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "unbuffer echo ssh devbox" ""
assert_failure "direct rlwrap echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "rlwrap echo ssh devbox" ""
assert_failure "direct setsid echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "setsid echo nvim README.md" ""
assert_failure "direct winpty echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "winpty echo nvim README.md" ""
assert_failure "direct winpty.exe echoing nvim.exe does not pass through" env PATH=/usr/bin:/bin "$helper" "winpty.exe echo nvim.exe README.md" ""
assert_failure "direct script command string echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "script -q -c 'echo ssh devbox' /dev/null" ""
assert_failure "direct script logfile echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "script -q /dev/null echo ssh devbox" ""
assert_failure "direct time echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "time echo ssh devbox" ""
assert_failure "direct gnu time echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "gtime -f '%E' echo nvim README.md" ""
assert_failure "direct shell echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "bash -lc 'echo ssh devbox'" ""
assert_failure "direct shell time echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "bash -lc 'time echo ssh devbox'" ""
assert_failure "direct shell printf echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "bash -lc 'printf ssh; echo done'" ""
assert_failure "direct shell trap body mentioning ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "bash -lc 'trap \"ssh devbox\" EXIT; echo done'" ""
assert_failure "direct powershell echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "pwsh -NoProfile -Command 'echo ssh devbox'" ""
assert_failure "direct powershell single-dash option value named ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "pwsh -configurationName ssh" ""
assert_failure "direct shell setup echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "bash -lc 'cd /tmp && echo ssh devbox'" ""
assert_failure "direct shell setup fallback echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "bash -lc 'cd /tmp || echo ssh devbox'" ""
assert_failure "direct poetry echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "poetry run echo ssh devbox" ""
assert_failure "direct poetry global directory echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "poetry -C ./app run echo ssh devbox" ""
assert_failure "direct pipenv echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "pipenv run echo ssh devbox" ""
assert_failure "direct pipx run echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "pipx run --spec cowsay echo nvim README.md" ""
assert_failure "direct hatch run echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "hatch run test:echo nvim README.md" ""
assert_failure "direct hatch env run echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "hatch env run -e test echo ssh devbox" ""
assert_failure "direct uv run option echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "uv run --with ruff echo nvim README.md" ""
assert_failure "direct uv module run does not pass through" env PATH=/usr/bin:/bin "$helper" "uv run -m http.server" ""
assert_failure "direct uvx echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "uvx --from cowsay echo nvim README.md" ""
assert_failure "direct uvx help does not pass through" env PATH=/usr/bin:/bin "$helper" "uvx --help nvim README.md" ""
assert_failure "direct uv tool list does not pass through" env PATH=/usr/bin:/bin "$helper" "uv tool list nvim README.md" ""
assert_failure "direct pixi run echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "pixi run echo nvim README.md" ""
assert_failure "direct pixi dry-run does not pass through" env PATH=/usr/bin:/bin "$helper" "pixi run --dry-run nvim README.md" ""
assert_failure "direct pixi global version does not pass through" env PATH=/usr/bin:/bin "$helper" "pixi --version run nvim README.md" ""
assert_failure "direct npx echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "npx --yes echo nvim README.md" ""
assert_failure "direct npm exec call echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "npm exec -c 'echo ssh devbox'" ""
assert_failure "direct pnpm exec echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "pnpm exec echo nvim README.md" ""
assert_failure "direct pnpm shell-mode echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "pnpm exec -c 'echo ssh devbox'" ""
assert_failure "direct pnpx echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "pnpx --package cowsay echo ssh devbox" ""
assert_failure "direct yarn dlx echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "yarn dlx echo nvim README.md" ""
assert_failure "direct yarn exec echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "yarn exec 'echo ssh devbox'" ""
assert_failure "direct yarnpkg dlx echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "yarnpkg dlx echo nvim README.md" ""
assert_failure "direct bunx echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "bunx echo nvim README.md" ""
assert_failure "direct bun x package echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "bun x --package cowsay echo ssh devbox" ""
assert_failure "direct corepack utility command does not pass through" env PATH=/usr/bin:/bin "$helper" "corepack use pnpm@10 nvim README.md" ""
assert_failure "direct corepack yarn echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "corepack yarn dlx echo nvim README.md" ""
assert_failure "direct corepack pnpm shell-mode echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "corepack pnpm exec -c 'echo ssh devbox'" ""
assert_failure "direct direnv echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "direnv exec . echo ssh devbox" ""
assert_failure "direct asdf exec echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "asdf exec echo nvim README.md" ""
assert_failure "direct mise without command separator does not pass through" env PATH=/usr/bin:/bin "$helper" "mise exec echo ssh devbox" ""
assert_failure "direct rtx without command separator does not pass through" env PATH=/usr/bin:/bin "$helper" "rtx exec echo ssh devbox" ""
assert_failure "direct nix echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "nix develop -c echo ssh devbox" ""
assert_failure "direct nix attached echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "nix develop --command=echo ssh devbox" ""
assert_failure "direct devcontainer exec shell echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "devcontainer exec --workspace-folder . bash -lc 'echo nvim README.md'" ""
assert_failure "direct devcontainer up nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "devcontainer up --workspace-folder . nvim README.md" ""
assert_failure "direct docker exec shell echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "docker exec app bash -lc 'echo nvim README.md'" ""
assert_failure "direct docker attach without stdin does not pass through" env PATH=/usr/bin:/bin "$helper" "docker attach --no-stdin app" ""
assert_success "direct docker attach uppercase false passes without tr" env PATH="$no_tr_bin" "$helper" "docker attach --no-stdin=FALSE app" ""
assert_failure "direct docker start attach without interactive does not pass through" env PATH=/usr/bin:/bin "$helper" "docker start -a app" ""
assert_failure "direct docker start explicit false attach does not pass through" env PATH=/usr/bin:/bin "$helper" "docker start --attach=false --interactive app" ""
assert_failure "direct docker run shell echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "docker run --rm ubuntu bash -lc 'echo nvim README.md'" ""
assert_failure "direct docker run echo entrypoint does not pass through" env PATH=/usr/bin:/bin "$helper" "docker run --rm --entrypoint echo ubuntu ssh devbox" ""
assert_failure "direct docker run without command does not pass through" env PATH=/usr/bin:/bin "$helper" "docker run --rm -it ubuntu" ""
assert_failure "direct docker global context non-exec does not pass through" env PATH=/usr/bin:/bin "$helper" "docker --context prod ps nvim" ""
assert_failure "direct docker global help does not pass through" env PATH=/usr/bin:/bin "$helper" "docker --help exec app nvim README.md" ""
assert_failure "direct docker compose exec shell echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "docker compose exec app bash -lc 'echo nvim README.md'" ""
assert_failure "direct docker compose run echoing nvim does not pass through" env PATH=/usr/bin:/bin "$helper" "docker compose run app bash -lc 'echo nvim README.md'" ""
assert_failure "direct docker compose run echo entrypoint does not pass through" env PATH=/usr/bin:/bin "$helper" "docker compose run --entrypoint echo app ssh devbox" ""
assert_failure "direct docker compose run without command does not pass through" env PATH=/usr/bin:/bin "$helper" "docker compose run app" ""
assert_failure "direct podman run echo entrypoint does not pass through" env PATH=/usr/bin:/bin "$helper" "podman run --rm --entrypoint echo fedora ssh devbox" ""
assert_failure "direct podman attach without stdin does not pass through" env PATH=/usr/bin:/bin "$helper" "podman attach --no-stdin app" ""
assert_failure "direct podman start attach without interactive does not pass through" env PATH=/usr/bin:/bin "$helper" "podman start -a app" ""
assert_failure "direct podman global version does not pass through" env PATH=/usr/bin:/bin "$helper" "podman --version run fedora ssh devbox" ""
assert_failure "direct podman compose run echo entrypoint does not pass through" env PATH=/usr/bin:/bin "$helper" "podman compose run --entrypoint echo app ssh devbox" ""
assert_failure "direct kubectl exec echoing ssh does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl exec pod/app -- echo ssh devbox" ""
assert_failure "direct kubectl exec echoing ssh without separator does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl exec pod/app echo ssh devbox" ""
assert_failure "direct kubectl attach without stdin does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl attach pod/app -c api" ""
assert_failure "direct kubectl attach compact container without stdin does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl attach pod/app -capi" ""
assert_failure "direct kubectl attach compact namespace without stdin does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl attach -nprod pod/app -capi" ""
assert_failure "direct kubectl attach explicit false stdin does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl attach --stdin=false pod/app -c api" ""
assert_failure "direct kubectl global namespace non-exec does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl -n dev get pods nvim" ""
assert_failure "direct kubectl global verbosity non-exec does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl -v 6 get pods nvim" ""
assert_failure "direct kubectl global client cert non-exec does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl --client-certificate cert.pem get pods nvim" ""
assert_failure "direct kubectl global help does not pass through" env PATH=/usr/bin:/bin "$helper" "kubectl --help exec pod/app -- nvim README.md" ""
assert_success "bare python current command with repl ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/python3 /usr/bin/python3' "$helper" python3 /dev/ttys001
assert_failure "bare python current command with script ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/python3 /usr/bin/python3 app.py' "$helper" python3 /dev/ttys001
assert_success "bare node current command with repl ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/node /usr/bin/node' "$helper" node /dev/ttys001
assert_failure "bare node current command with script ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/node /usr/bin/node app.js' "$helper" node /dev/ttys001
assert_success "bare deno current command with repl ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/deno /usr/bin/deno repl' "$helper" deno /dev/ttys001
assert_failure "bare deno current command with run ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/deno /usr/bin/deno run app.ts' "$helper" deno /dev/ttys001
assert_success "bare deno current command with global option repl ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/deno /usr/bin/deno --config deno.json repl' "$helper" deno /dev/ttys001
assert_failure "bare deno current command with global option run ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/deno /usr/bin/deno --config deno.json run app.ts' "$helper" deno /dev/ttys001
assert_success "bare php current command with interactive ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/php /usr/bin/php -a' "$helper" php /dev/ttys001
assert_failure "bare php current command with script ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/php /usr/bin/php app.php' "$helper" php /dev/ttys001
assert_success "bare php current command with define interactive ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/php /usr/bin/php -d memory_limit=-1 -a' "$helper" php /dev/ttys001
assert_failure "bare php current command with define run ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/php /usr/bin/php -d memory_limit=-1 -r '\''echo 1;'\''' "$helper" php /dev/ttys001
assert_success "bare ruby current command with irb ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/ruby /usr/bin/ruby -S irb' "$helper" ruby /dev/ttys001
assert_success "bare ruby current command with rails console ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/ruby /usr/bin/ruby bin/rails console' "$helper" ruby /dev/ttys001
assert_failure "bare ruby current command with script ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/ruby /usr/bin/ruby app.rb' "$helper" ruby /dev/ttys001
assert_success "bare rails current command with console ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/local/bin/rails /usr/local/bin/rails console' "$helper" rails /dev/ttys001
assert_failure "bare rails current command with runner ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/local/bin/rails /usr/local/bin/rails runner '\''puts 1'\''' "$helper" rails /dev/ttys001
assert_success "bare bundle current command with pry ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/local/bin/bundle /usr/local/bin/bundle exec pry' "$helper" bundle /dev/ttys001
assert_failure "bare bundle current command with echo ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/local/bin/bundle /usr/local/bin/bundle exec echo pry' "$helper" bundle /dev/ttys001
assert_success "bare psql current command with shell ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/psql /usr/bin/psql postgres' "$helper" psql /dev/ttys001
assert_failure "bare psql current command with one-shot ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/psql /usr/bin/psql postgres -c '\''select 1'\''' "$helper" psql /dev/ttys001
assert_failure "bare psql current command with attached one-shot ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/psql /usr/bin/psql postgres -cselect' "$helper" psql /dev/ttys001
assert_success "bare sqlite3 current command with database ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/sqlite3 /usr/bin/sqlite3 app.db' "$helper" sqlite3 /dev/ttys001
assert_failure "bare sqlite3 current command with sql ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/sqlite3 /usr/bin/sqlite3 app.db '\''select 1'\''' "$helper" sqlite3 /dev/ttys001
assert_success "bare lua current command with repl ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/lua /usr/bin/lua' "$helper" lua /dev/ttys001
assert_failure "bare lua current command with script ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/lua /usr/bin/lua app.lua' "$helper" lua /dev/ttys001
assert_failure "bare lua current command with attached eval ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/lua /usr/bin/lua -eprint(1)' "$helper" lua /dev/ttys001
assert_success "bare R current command with repl ps args passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/R /usr/bin/R --vanilla' "$helper" R /dev/ttys001
assert_failure "bare R current command with eval ps args does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/R /usr/bin/R -e '\''print(1)'\''' "$helper" R /dev/ttys001
assert_failure "plain shell without child TUI does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT='S+ /bin/zsh' "$helper" zsh /dev/ttys001
assert_success "shell with foreground nvim child passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/nvim' "$helper" zsh /dev/ttys001
assert_success "paste key shell with foreground nvim child passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/nvim' "$helper" --paste-key zsh /dev/ttys001
assert_success "shell with foreground Windows ssh.exe child passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ C:\\tools\\ssh.exe C:\\tools\\ssh.exe devbox' "$helper" zsh /dev/ttys001
assert_failure "paste key shell with foreground Windows ssh.exe child uses tmux paste" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ C:\\tools\\ssh.exe C:\\tools\\ssh.exe devbox' "$helper" --paste-key zsh /dev/ttys001
assert_success "foreground env ssh command line passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/env /usr/bin/env TERM=xterm-256color ssh devbox' "$helper" zsh /dev/ttys001
assert_failure "paste key foreground env ssh command line uses tmux paste" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/env /usr/bin/env TERM=xterm-256color ssh devbox' "$helper" --paste-key zsh /dev/ttys001
assert_failure "foreground env split-string echoing ssh does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/env /usr/bin/env -S '\''echo ssh'\'' ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground arch nvim command line passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/arch /usr/bin/arch -x86_64 nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "foreground arch echoing nvim does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/arch /usr/bin/arch -x86_64 echo nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground shell ssh command line passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /bin/bash /bin/bash -lc '\''ssh devbox'\''' "$helper" zsh /dev/ttys001
assert_failure "foreground shell echoing ssh does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /bin/bash /bin/bash -lc '\''echo ssh devbox'\''' "$helper" zsh /dev/ttys001
assert_success "foreground ssh RequestTTY auto remote shell child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRequestTTY=auto devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh RequestTTY no remote shell child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRequestTTY=no devbox' "$helper" zsh /dev/ttys001
assert_success "foreground ssh forced tty remote nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -t devbox nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground ssh no-tty then forced tty remote nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -Tt devbox nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground ssh RequestTTY remote nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRequestTTY=yes devbox nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh RemoteCommand nvim without tty child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRemoteCommand=\'nvim README.md\' devbox' "$helper" zsh /dev/ttys001
assert_success "foreground ssh RequestTTY RemoteCommand nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRequestTTY=yes -oRemoteCommand=\'nvim README.md\' devbox' "$helper" zsh /dev/ttys001
assert_success "foreground ssh forced tty RemoteCommand nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -tt -o RemoteCommand=\'nvim README.md\' devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh forced tty RemoteCommand one-shot child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -t -oRemoteCommand=\'echo nvim\' devbox' "$helper" zsh /dev/ttys001
assert_success "foreground ssh RemoteCommand none child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRemoteCommand=none devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh remote one-shot child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh devbox echo nvim' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh RequestTTY remote one-shot child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRequestTTY=yes devbox echo nvim' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh RequestTTY auto remote nvim child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -oRequestTTY=auto devbox nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh forced tty then no-tty remote nvim child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -tT devbox nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh tunnel child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -N -L 8080:localhost:80 devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground ssh no-pty child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ssh /usr/bin/ssh -T git@github.com' "$helper" zsh /dev/ttys001
assert_failure "foreground autossh tunnel child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/autossh /usr/bin/autossh -M 0 -N -L 8080:localhost:80 devbox' "$helper" zsh /dev/ttys001
assert_success "foreground time nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/time /usr/bin/time -p nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "foreground time echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/time /usr/bin/time -p echo nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground stdbuf nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/stdbuf /usr/bin/stdbuf -oL nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground script ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/script /usr/bin/script -q -c '\''ssh devbox'\'' /dev/null' "$helper" zsh /dev/ttys001
assert_failure "foreground script echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/script /usr/bin/script -q -c '\''echo ssh devbox'\'' /dev/null' "$helper" zsh /dev/ttys001
assert_success "sudo with foreground ssh child passes through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /usr/bin/sudo\nS+ /usr/bin/ssh' "$helper" sudo /dev/ttys001
assert_success "foreground lazygit child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/bash\nS+ /opt/homebrew/bin/lazygit' "$helper" bash /dev/ttys001
assert_success "foreground vim.basic child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/bash\nS+ /usr/bin/vim.basic' "$helper" bash /dev/ttys001
assert_success "foreground helix child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/hx' "$helper" zsh /dev/ttys001
assert_success "foreground nano child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /usr/bin/nano /tmp/message.txt' "$helper" zsh /dev/ttys001
assert_success "foreground micro child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/micro /tmp/message.txt' "$helper" zsh /dev/ttys001
assert_success "foreground terminal emacs child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/emacs -nw /tmp/message.txt' "$helper" zsh /dev/ttys001
assert_success "foreground kakoune child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/kak /tmp/message.txt' "$helper" zsh /dev/ttys001
assert_success "foreground less child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /usr/bin/less' "$helper" zsh /dev/ttys001
assert_success "foreground delta child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/delta /opt/homebrew/bin/delta README.md' "$helper" zsh /dev/ttys001
assert_success "foreground nested tmux child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/tmux' "$helper" zsh /dev/ttys001
assert_success "foreground screen child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /usr/bin/screen' "$helper" zsh /dev/ttys001
assert_success "foreground zellij child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/zellij' "$helper" zsh /dev/ttys001
assert_success "foreground codex child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/codex' "$helper" zsh /dev/ttys001
assert_success "foreground mosh client child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/mosh-client' "$helper" zsh /dev/ttys001
assert_success "foreground ghci child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/ghci /opt/homebrew/bin/ghci Main.hs' "$helper" zsh /dev/ttys001
assert_success "foreground iex child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS+ /opt/homebrew/bin/iex /opt/homebrew/bin/iex -S mix' "$helper" zsh /dev/ttys001
assert_success "foreground python pdb child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/python3 /usr/bin/python3 -m pdb app.py' "$helper" zsh /dev/ttys001
assert_failure "foreground python script child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/python3 /usr/bin/python3 app.py' "$helper" zsh /dev/ttys001
assert_success "foreground node repl child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/node /usr/bin/node' "$helper" zsh /dev/ttys001
assert_success "foreground node inspect child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/node /usr/bin/node inspect app.js' "$helper" zsh /dev/ttys001
assert_failure "foreground node script child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/node /usr/bin/node app.js' "$helper" zsh /dev/ttys001
assert_success "foreground deno repl child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/deno /usr/bin/deno repl' "$helper" zsh /dev/ttys001
assert_failure "foreground deno run child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/deno /usr/bin/deno run app.ts' "$helper" zsh /dev/ttys001
assert_success "foreground php interactive child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/php /usr/bin/php -a' "$helper" zsh /dev/ttys001
assert_failure "foreground php script child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/php /usr/bin/php app.php' "$helper" zsh /dev/ttys001
assert_success "foreground ruby rails console child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ruby /usr/bin/ruby bin/rails console' "$helper" zsh /dev/ttys001
assert_failure "foreground ruby script child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/bin/ruby /usr/bin/ruby app.rb' "$helper" zsh /dev/ttys001
assert_success "foreground bundle exec pry child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/bundle /usr/local/bin/bundle exec pry' "$helper" zsh /dev/ttys001
assert_failure "foreground bundle exec echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/bundle /usr/local/bin/bundle exec echo pry' "$helper" zsh /dev/ttys001
assert_success "foreground rails console child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/rails /usr/local/bin/rails console' "$helper" zsh /dev/ttys001
assert_failure "foreground rails runner child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/rails /usr/local/bin/rails runner '\''puts 1'\''' "$helper" zsh /dev/ttys001
assert_success "foreground kitten ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kitten /opt/homebrew/bin/kitten ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground kitty kitten ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /Applications/kitty.app/Contents/MacOS/kitty /Applications/kitty.app/Contents/MacOS/kitty +kitten ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground devcontainer exec nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/devcontainer /opt/homebrew/bin/devcontainer exec --workspace-folder . nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground docker exec nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker exec -it app nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground docker global context exec nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker --context prod exec app nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground docker attach child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker attach app' "$helper" zsh /dev/ttys001
assert_failure "paste key foreground docker attach child uses tmux paste" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker attach app' "$helper" --paste-key zsh /dev/ttys001
assert_success "foreground docker attach explicit stdin child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker attach --no-stdin=false app' "$helper" zsh /dev/ttys001
assert_success "foreground docker start attach interactive child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker start -ai app' "$helper" zsh /dev/ttys001
assert_failure "paste key foreground docker start attach child uses tmux paste" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker start -ai app' "$helper" --paste-key zsh /dev/ttys001
assert_success "foreground docker run nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker run --rm -it ubuntu nvim README.md' "$helper" zsh /dev/ttys001
assert_success "paste key foreground docker run nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker run --rm -it ubuntu nvim README.md' "$helper" --paste-key zsh /dev/ttys001
assert_success "foreground docker run nvim entrypoint child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker run --rm --entrypoint nvim ubuntu README.md' "$helper" zsh /dev/ttys001
assert_success "foreground docker compose exec nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker compose exec app nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground docker global context compose exec nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker --context prod compose exec app nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground docker compose run nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker compose run --rm app nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground podman run nvim entrypoint child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/podman /usr/local/bin/podman run --rm --entrypoint nvim fedora README.md' "$helper" zsh /dev/ttys001
assert_success "foreground podman global connection run ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/podman /usr/local/bin/podman --connection prod run --rm fedora ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground podman attach child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/podman /usr/local/bin/podman attach app' "$helper" zsh /dev/ttys001
assert_success "foreground podman start attach interactive child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/podman /usr/local/bin/podman start -ai app' "$helper" zsh /dev/ttys001
assert_success "foreground kubectl exec nvim without separator child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl exec -it pod/app -c api nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground kubectl global namespace exec nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl -n dev exec pod/app -- nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground kubectl global verbosity exec nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl -v 6 exec pod/app -- nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground kubectl global basic auth exec ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl --username alice --password example exec pod/app -- ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground kubectl attach stdin child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl attach -it pod/app -c api' "$helper" zsh /dev/ttys001
assert_failure "paste key foreground kubectl attach stdin child uses tmux paste" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl attach -it pod/app -c api' "$helper" --paste-key zsh /dev/ttys001
assert_success "foreground oc attach stdin child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/oc /opt/homebrew/bin/oc attach --stdin pod/app -c api' "$helper" zsh /dev/ttys001
assert_failure "paste key foreground oc attach stdin child uses tmux paste" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/oc /opt/homebrew/bin/oc attach --stdin pod/app -c api' "$helper" --paste-key zsh /dev/ttys001
assert_success "foreground npx nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/npx /opt/homebrew/bin/npx --yes nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground pnpm exec ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/pnpm /opt/homebrew/bin/pnpm --dir ./app exec ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground yarn dlx nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/yarn /opt/homebrew/bin/yarn dlx --package=neovim nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground bunx ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/bunx /opt/homebrew/bin/bunx --bun ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground corepack yarn dlx nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/corepack /opt/homebrew/bin/corepack yarn dlx --package=neovim nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground corepack pnpm exec ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/corepack /opt/homebrew/bin/corepack pnpm exec ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground pipx run nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/pipx /opt/homebrew/bin/pipx run --spec neovim nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground uvx nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/uvx /opt/homebrew/bin/uvx --from neovim nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground uv tool run ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/uv /opt/homebrew/bin/uv tool run --python 3.12 ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground uvx flag options nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/uvx /opt/homebrew/bin/uvx --managed-python --no-build nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground hatch run ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/hatch /opt/homebrew/bin/hatch run +py=3.12 -version=9000 ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground nix attached command ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /nix/var/nix/profiles/default/bin/nix /nix/var/nix/profiles/default/bin/nix develop --command=ssh devbox' "$helper" zsh /dev/ttys001
assert_success "foreground pixi run nvim child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/pixi /opt/homebrew/bin/pixi run nvim README.md' "$helper" zsh /dev/ttys001
assert_success "foreground pixi run environment ssh child passes through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/pixi /opt/homebrew/bin/pixi run -e cuda ssh devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground pixi run echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/pixi /opt/homebrew/bin/pixi run echo nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "foreground pixi dry-run child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/pixi /opt/homebrew/bin/pixi run --dry-run nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "foreground kitten image child does not pass through" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kitten /opt/homebrew/bin/kitten icat image.png' "$helper" zsh /dev/ttys001
assert_failure "foreground devcontainer exec echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/devcontainer /opt/homebrew/bin/devcontainer exec --workspace-folder . bash -lc '\''echo nvim README.md'\''' "$helper" zsh /dev/ttys001
assert_failure "foreground docker exec echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker exec app bash -lc '\''echo nvim README.md'\''' "$helper" zsh /dev/ttys001
assert_failure "foreground docker global context non-exec child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker --context prod ps nvim' "$helper" zsh /dev/ttys001
assert_failure "foreground docker attach without stdin child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker attach --no-stdin app' "$helper" zsh /dev/ttys001
assert_failure "foreground docker start attach without interactive child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker start -a app' "$helper" zsh /dev/ttys001
assert_failure "foreground docker start explicit false attach child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker start --attach=false --interactive app' "$helper" zsh /dev/ttys001
assert_failure "foreground docker run echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker run ubuntu bash -lc '\''echo nvim README.md'\''' "$helper" zsh /dev/ttys001
assert_failure "foreground docker run echo entrypoint child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker run --rm --entrypoint echo ubuntu ssh devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground docker compose exec echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker compose exec app bash -lc '\''echo nvim README.md'\''' "$helper" zsh /dev/ttys001
assert_failure "foreground docker compose run echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/docker /usr/local/bin/docker compose run app bash -lc '\''echo nvim README.md'\''' "$helper" zsh /dev/ttys001
assert_failure "foreground podman run echo entrypoint child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/podman /usr/local/bin/podman run --rm --entrypoint echo fedora ssh devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground podman attach without stdin child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /usr/local/bin/podman /usr/local/bin/podman attach --no-stdin app' "$helper" zsh /dev/ttys001
assert_failure "foreground kubectl exec echo without separator child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl exec pod/app echo ssh devbox' "$helper" zsh /dev/ttys001
assert_failure "foreground kubectl attach without stdin child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl attach pod/app -c api' "$helper" zsh /dev/ttys001
assert_failure "foreground kubectl attach explicit false stdin child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl attach --stdin=false pod/app -c api' "$helper" zsh /dev/ttys001
assert_failure "foreground kubectl global namespace non-exec child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl -n dev get pods nvim' "$helper" zsh /dev/ttys001
assert_failure "foreground kubectl global verbosity non-exec child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl -v 6 get pods nvim' "$helper" zsh /dev/ttys001
assert_failure "foreground kubectl global client cert non-exec child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/kubectl /opt/homebrew/bin/kubectl --client-certificate cert.pem get pods nvim' "$helper" zsh /dev/ttys001
assert_failure "foreground npx echo child does not pass through behind shell" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh /bin/zsh\nS+ /opt/homebrew/bin/npx /opt/homebrew/bin/npx --yes echo nvim README.md' "$helper" zsh /dev/ttys001
assert_failure "stopped nvim child is ignored" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nT+ /opt/homebrew/bin/nvim' "$helper" zsh /dev/ttys001
assert_failure "zombie ssh child is ignored" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nZ+ /usr/bin/ssh' "$helper" zsh /dev/ttys001
assert_failure "background ssh is ignored when another foreground process exists" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S+ /bin/zsh\nS /usr/bin/ssh' "$helper" zsh /dev/ttys001
assert_success "systems without foreground markers can still detect child TUI" \
  env PATH="$tmp/bin:/usr/bin:/bin" TMUX_TEST_PS_OUTPUT=$'S /bin/zsh\nS /usr/bin/mosh' "$helper" zsh /dev/ttys001
