# VS Code multi-file Git diffs from the terminal

The `gl_vsc_diff` helper opens GitLens' multi-file diff editor from the shell by
launching a `vscode://` deep link. Use it when you want a single, scrollable
view of every file that differs between two commits or branches without leaving
your terminal.

## Requirements

1. [Visual Studio Code 1.86 or newer][1] (ships the multi-file diff editor).
2. [GitLens][2] installed in VS Code.
3. Your operating system must be able to handle `vscode://` URLs (`xdg-open`,
   `open`, or `code --open-url`). VS Code documents this URL support.[3]

## Capture the GitLens `repoId` once per repository

GitLens identifies repositories with an opaque `repoId`. Discover it once and
store it in Git config:

1. In VS Code open **GitLens › Search & Compare**, create any comparison, then
   **Share → Copy Link to Comparison**. The copied URL contains `/r/<repoId>/`.
   ([GitLens release notes][4])
2. Inside the Git repository run:

   ```bash
   git config gitlens.repoId "<repoId from the copied link>"
   ```

   The setting is saved inside `.git/config` so it stays local to that clone.
   You can override it per invocation with `--repo-id` or per session by
   exporting `GITLENS_REPO_ID`.

## Usage

```bash
gl_vsc_diff [OPTIONS] <BASE> <HEAD> [REPO]
```

- `BASE` and `HEAD` are any Git refs (`main`, `feature/xyz`, commit SHAs, etc.).
- `REPO` defaults to the current repository root (or the current directory when
  not inside a Git repository).
- `BASE...HEAD` (three-dot) is the default range; add `--two-dot` for
  `BASE..HEAD` semantics.
- Override the repo ID with `--repo-id <value>` when you do not want to rely on
  Git config or an environment variable.

Examples:

```bash
gl_vsc_diff origin/main HEAD             # diff current branch vs. main
gl_vsc_diff abc1234 def5678 ~/src/app     # compare two commits in another repo
gl_vsc_diff -2 main feature/login         # force two-dot semantics
```

The script URL-encodes refs and repository paths before opening the GitLens
comparison at:

```
vscode://eamodio.gitlens/r/<repoId>/compare/<BASE>...<HEAD>?path=<repo>
```

VS Code hands the URL to GitLens, which renders the multi-file diff in a single
editor tab. ([GitLens release notes][4]) ([VS Code January 2024 update][1])

## Troubleshooting tips

- If nothing happens, confirm `gl_vsc_diff --help` lists the launch order. You
  might need to ensure either `xdg-open`, `open`, `code`, or `powershell.exe` is
  on your `PATH`.
- When GitLens opens multiple diff tabs instead of the combined view, update VS
  Code to 1.86+ where the multi-file diff editor is enabled by default.[1]
- For repos where you cannot modify `.git/config`, pass `--repo-id` directly.

[1]: https://code.visualstudio.com/updates/v1_86 "VS Code January 2024 (v1.86)"
[2]: https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens "GitLens — Git supercharged"
[3]: https://code.visualstudio.com/docs/configure/command-line "VS Code command-line docs"
[4]: https://help.gitkraken.com/gitlens/gitlens-release-notes-current/ "GitLens release notes"
