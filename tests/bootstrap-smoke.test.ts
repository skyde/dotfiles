import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { spawnSync } from 'child_process';
import { describe, it, expect } from 'vitest';

const REPO_ROOT = path.resolve(__dirname, '..');
const BOOTSTRAP = path.join(REPO_ROOT, 'scripts', 'bootstrap.sh');

function run(cmd: string, args: string[], opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {}) {
  const res = spawnSync(cmd, args, {
    cwd: opts.cwd ?? REPO_ROOT,
    env: { ...process.env, ...(opts.env ?? {}) },
    encoding: 'utf8'
  });
  return res;
}

describe('bootstrap.sh smoke', () => {
  it('runs in DRY mode with temp HOME', () => {
    if (process.platform === 'win32') return; // not applicable
    expect(fs.existsSync(BOOTSTRAP)).toBe(true);

    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-home-'));
    // Common dirs
    for (const d of [home, path.join(home, '.config'), path.join(home, '.local', 'share')]) {
      fs.mkdirSync(d, { recursive: true });
    }

    const original = fs.readFileSync(BOOTSTRAP, 'utf8');
    // Insert stubs for heavy operations and dry-run stow before `main "$@"`
    const marker = '\nmain "$@"';
    const stub = `
ensure_stow() { return 0; }
install_neovim_and_lazyvim() { return 0; }
install_helix() { return 0; }
install_ohmyzsh() { return 0; }
install_lazygit() { return 0; }
install_ripgrep() { return 0; }
install_bat() { return 0; }
install_kitty() { return 0; }
install_wezterm() { return 0; }
install_fonts() { return 0; }
rebuild_bat_cache() { return 0; }
ensure_shell_rc() { return 0; }
ensure_git_editor() { return 0; }
disable_charge_chime_macos() { return 0; }
stow_pkg() { local pkg="$1"; stow -n -v --no-folding -d "$here/stow" -t "$HOME" -S "$pkg"; }
`;
    const idx = original.lastIndexOf(marker);
    expect(idx).toBeGreaterThan(0);
    const modified = original.slice(0, idx) + '\n' + stub + original.slice(idx);

    const tmpScript = path.join(REPO_ROOT, 'tests', 'bootstrap-smoke.sh');
    fs.writeFileSync(tmpScript, modified, { mode: 0o755 });

    const res = run('bash', [tmpScript], { env: { HOME: home } });
    if (res.status !== 0) {
      throw new Error(`bootstrap.sh smoke failed\ncode: ${res.status}\nstdout:\n${res.stdout}\nstderr:\n${res.stderr}`);
    }
    expect(res.stdout).toContain('Bootstrap complete');
  });
});
