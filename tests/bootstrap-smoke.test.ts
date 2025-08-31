import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { spawnSync } from 'child_process';
import { describe, it, expect } from 'vitest';

const REPO_ROOT = path.resolve(__dirname, '..');
const DOT = path.join(REPO_ROOT, 'dot');

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
    expect(fs.existsSync(DOT)).toBe(true);

    const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-home-'));
    for (const d of [home, path.join(home, '.config'), path.join(home, '.local', 'share')]) {
      fs.mkdirSync(d, { recursive: true });
    }

    const res = run('bash', [DOT, 'diff'], { env: { HOME: home } });
    if (res.status !== 0) {
      throw new Error(`dot diff smoke failed\ncode: ${res.status}\nstdout:\n${res.stdout}\nstderr:\n${res.stderr}`);
    }
    // Look for stow planning output to confirm hooks ran
    expect(res.stdout).toContain('[stow] os=');
  });
});
