import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { spawnSync } from 'child_process';
import { describe, it, expect } from 'vitest';

const REPO_ROOT = path.resolve(__dirname, '..');
const DOT = path.join(REPO_ROOT, 'dot');

function run(cmd: string, args: string[], env: Record<string,string> = {}) {
  const res = spawnSync(cmd, args, { cwd: REPO_ROOT, env: { ...process.env, ...env }, encoding: 'utf8' });
  if (res.error) throw res.error;
  return res;
}

describe('dot hook runner', () => {
  it('selects platform hooks in order', () => {
    if (process.platform === 'win32') return; // windows uses dot.ps1
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dot-hooks-'));
    const mk = (p: string, content: string) => {
      const file = path.join(tmp, p);
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.writeFileSync(file, content, { mode: 0o755 });
    };
    // common -> unix -> darwin/linux
    mk('common/apply/10-a.sh', '#!/usr/bin/env bash\necho [HOOK] common-10');
    mk('unix/apply/20-b.sh',   '#!/usr/bin/env bash\necho [HOOK] unix-20');
    const plat = process.platform === 'darwin' ? 'darwin' : 'linux';
    mk(`${plat}/apply/30-c.sh`, '#!/usr/bin/env bash\necho [HOOK] plat-30');

    const res = run('bash', [DOT, 'apply', '--dry-run'], { DOT_HOOKS: tmp });
    expect(res.status).toBe(0);
    const out = res.stdout;
    const i1 = out.indexOf('[HOOK] common-10');
    const i2 = out.indexOf('[HOOK] unix-20');
    const i3 = out.indexOf('[HOOK] plat-30');
    expect(i1).toBeGreaterThan(-1);
    expect(i2).toBeGreaterThan(i1);
    expect(i3).toBeGreaterThan(i2);
  });
});

