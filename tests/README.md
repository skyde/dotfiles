Running tests

- Prereqs: Node 18+, GNU Stow installed (Unix).
- From repo root:
  - cd tests
  - npm install
  - npm test

Or simply run from the repo root:

- ./dot test

Notes

- The suite stows into a temporary HOME, asserts mappings, checks idempotency, then unstows.
- On Windows, Stow is not used. dot.ps1 test runs a VS Code smoke check via scripts/bootstrap.ps1 -OnlyVSCode.

