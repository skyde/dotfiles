# Automation / Agents

This repo is designed to be run **interactively** (`init`, `apply`, `update`).  
If you automate (e.g., CI, devcontainer, or a provisioning tool), follow these guidelines:

- Run in **dry-run** first (`./apply.sh --no`) and log output.
- Adopt rather than overwrite on long‑lived machines (`stow --adopt`).
- Pin major tool versions in your package manager where reproducibility matters.
- Keep `packages.txt` minimal; layer project‑specific configs elsewhere.
