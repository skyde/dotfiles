# CI / CD

This repo uses GitHub Actions to validate **fresh installs**, **code quality**, **edge cases**, and **performance** across macOS, Linux, and Windows.

## Workflows

1) **comprehensive-test.yml** — Main testing pipeline  
   - **Triggers:** push to main/develop, PRs, manual, weekly schedule  
   - **Matrix:** Ubuntu (latest, 20.04), macOS (latest, 12), Windows (latest)  
   - **Phases:** repository checks → dependency install (git, stow) → script runs (init/apply/update) → link verification → security & compliance

2) **script-validation.yml** — Code quality  
   - **ShellCheck** for `.sh`, PowerShell syntax validation for `.ps1`  
   - Ensures parity between shell and PowerShell variants  
   - Verifies README/docs match script behaviors where applicable

3) **edge-case-testing.yml** — Stress & edge cases  
   - Pre‑existing files & `--adopt` flow  
   - Offline runs, rapid install/uninstall cycles  
   - Concurrent operations and recovery from broken links

4) **performance-monitoring.yml** — Speed & resource use  
   - Track apply time, memory/IO, and regressions (e.g., via `hyperfine`)  
   - Thresholds enforce steady performance

## Coverage

- **Platforms:** Linux (Ubuntu 20.04 + latest), macOS (12 + latest), Windows (latest)  
- **Scripts:** `init.*`, `apply.*`, `update.*` (shell & PowerShell)  
- **Packages:** common (shell, devtools, nvim, Code, kitty, lf) + macOS (hammerspoon) + Windows (Documents, vsvim, visual_studio, kinesis-advantage2, savant-elite2)

## Quality gates & thresholds

- All platform jobs pass
- ShellCheck / PowerShell parse pass
- No secrets or unsafe permissions detected
- README/docs synced with actual package counts/flags
- Performance within defined thresholds

## Local equivalents

```bash
shellcheck *.sh
AUTO_INSTALL=0 ./init.sh
./apply.sh --no
./apply.sh --restow
./apply.sh --delete
```

Use `gh workflow run` to trigger workflows on-demand.
