Dot Hooks Layout

This repo uses a generic `./dot` CLI that discovers and runs hook scripts.
Hooks are organized under `scripts/<platform>/<subcommand>/` and run in
sorted order (prefix with numbers to control sequencing, e.g., `10-*.sh`).

Platforms
- `common/` — runs everywhere
- `unix/` — runs on macOS and Linux
- `darwin/` — macOS only
- `linux/` — Linux only
- `windows/` — Windows (PowerShell .ps1)

Subcommands
- `apply/` — perform installs/config linking
- `restow/` — re-apply links (or re-run apply on Windows)
- `delete/` — remove links (or no-op on Windows)
- `diff/` — preview changes (implemented by apply hooks honoring DOT_DRYRUN)
- `test/` — smoke/unit tests hooks

Environment passed to hooks
- `DOT_CMD` — subcommand (apply, restow, delete, update, diff, test)
- `DOT_OS` — darwin | linux | windows
- `DOT_REPO` — absolute path to repo root
- `DOT_TARGET` — target home directory (defaults to `$HOME` / `$env:USERPROFILE`)
- `DOT_DRYRUN` — `1` when `--dry-run` or `dot diff` is used, empty otherwise

Authoring Hooks
- Shell hooks must be executable and should log succinct status.
- Respect `DOT_DRYRUN` to avoid making changes during previews.
- Keep hooks idempotent and repo-agnostic orchestration in `./dot` only.
