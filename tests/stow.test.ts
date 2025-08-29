import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { spawnSync } from 'child_process';
import { describe, it, expect } from 'vitest';

const REPO_ROOT = path.resolve(__dirname, '..');
const STOW_ROOT = path.join(REPO_ROOT, 'stow');
const IGNORE_FILES = new Set(['.DS_Store']);

const isMac = () => process.platform === 'darwin';
const isLinux = () => process.platform === 'linux';

type OSSkip = { linux?: string[]; darwin?: string[] };
let osSkip: OSSkip = {
  linux: ['macos', 'hammerspoon', 'vscode-macos'],
  darwin: ['vscode-linux']
};
try {
  const p = path.join(__dirname, 'os-skip.json');
  if (fs.existsSync(p)) {
    const overrides = JSON.parse(fs.readFileSync(p, 'utf8')) as OSSkip;
    osSkip = { ...osSkip, ...overrides };
  }
} catch {
  // ignore
}

function allPackages(): string[] {
  if (!fs.existsSync(STOW_ROOT)) return [];
  return fs
    .readdirSync(STOW_ROOT, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
}

function packagesForCurrentOS(): string[] {
  const pkgs = allPackages();
  const skip = isLinux()
    ? new Set(osSkip.linux ?? [])
    : isMac()
    ? new Set(osSkip.darwin ?? [])
    : new Set(pkgs);
  return pkgs.filter((p) => !skip.has(p));
}

function ensureDirs(...dirs: string[]) {
  for (const d of dirs) fs.mkdirSync(d, { recursive: true });
}

function walkFiles(dir: string): string[] {
  const out: string[] = [];
  const stack = [dir];
  while (stack.length) {
    const cur = stack.pop()!;
    for (const e of fs.readdirSync(cur, { withFileTypes: true })) {
      const p = path.join(cur, e.name);
      if (e.isDirectory()) stack.push(p);
      else if (e.isFile() && !IGNORE_FILES.has(e.name)) out.push(p);
    }
  }
  return out;
}

function targetForSource(src: string, pkgDir: string, home: string): string {
  const rel = path.relative(pkgDir, src);
  return path.join(home, rel);
}

function run(cmd: string, args: string[], cwd: string) {
  const res = spawnSync(cmd, args, { cwd, encoding: 'utf8' });
  if (res.error) throw res.error;
  return res;
}

function stowFlags(): string[] {
  const raw = (process.env.STOW_FLAGS ?? '').trim();
  return raw ? raw.split(/\s+/) : [];
}

function stowPackage(home: string, pkg: string, extra: string[] = []) {
  const args = ['-d', STOW_ROOT, '-t', home, ...stowFlags(), ...extra, '-S', pkg];
  const res = run('stow', args, REPO_ROOT);
  if (res.status !== 0) {
    throw new Error(`stow failed for ${pkg}\ncmd: stow ${args.join(' ')}\nstdout:\n${res.stdout}\nstderr:\n${res.stderr}`);
  }
  return res;
}

function unstowPackage(home: string, pkg: string) {
  const args = ['-d', STOW_ROOT, '-t', home, '-D', pkg];
  const res = run('stow', args, REPO_ROOT);
  if (res.status !== 0) {
    throw new Error(`unstow failed for ${pkg}\ncmd: stow ${args.join(' ')}\nstdout:\n${res.stdout}\nstderr:\n${res.stderr}`);
  }
  return res;
}

describe('GNU Stow dotfiles', () => {
  it('has stow installed', () => {
    const res = run('stow', ['--version'], REPO_ROOT);
    expect(res.status).toBe(0);
  });

  for (const pkg of packagesForCurrentOS()) {
    it(`maps files correctly: ${pkg}`, () => {
      const home = fs.mkdtempSync(path.join(os.tmpdir(), 'dotfiles-home-'));

      // Pre-create common dirs; reduces stow noise & matches typical targets
      ensureDirs(
        home,
        path.join(home, '.config'),
        path.join(home, '.local', 'share'),
        path.join(home, '.cache'),
        ...(isMac()
          ? [
              path.join(home, 'Library'),
              path.join(home, 'Library', 'Application Support')
            ]
          : [])
      );

      stowPackage(home, pkg);

      const pkgDir = path.join(STOW_ROOT, pkg);
      const srcFiles = walkFiles(pkgDir);

      // Every file in the package tree should be reachable via the target path
      for (const src of srcFiles) {
        const tgt = targetForSource(src, pkgDir, home);
        if (!fs.existsSync(tgt)) {
          throw new Error(`Missing target: ${tgt} (from ${src})`);
        }
        const realTgt = fs.realpathSync(tgt);
        const realSrc = fs.realpathSync(src);
        expect(realTgt).toBe(realSrc);
      }

      // Idempotency: dry-run should plan no changes
      const dry = run(
        'stow',
        ['-n', '-v', '-d', STOW_ROOT, '-t', home, ...stowFlags(), '-S', pkg],
        REPO_ROOT
      );
      expect(dry.status).toBe(0);
      const hasPlannedOps = /(LINK:|UNLINK:|MOVE:|REMOVE:|CONFLICT:)/.test(
        dry.stdout
      );
      expect(hasPlannedOps).toBe(false);

      // Unstow should remove created links
      unstowPackage(home, pkg);
      for (const src of srcFiles) {
        const tgt = targetForSource(src, pkgDir, home);
        expect(fs.existsSync(tgt)).toBe(false);
      }
    });
  }
});

