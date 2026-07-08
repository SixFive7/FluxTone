# playwright/interactive/profile

**Intentionally empty placeholder.**

The `interactive` mode uses `browser.isolated: true` (see [../config.json](../config.json) and [../../README.md](../../README.md) row #4). Under isolated mode, Playwright creates a fresh in-memory temp profile per session and wipes it on close — that's the whole point of this mode. **Credentials entered in the visible browser do not persist on disk and never end up in this folder.**

This folder exists only for visual symmetry with the four mode subfolders — `persistent` is the one mode that uses a real on-disk profile at [../../persistent/profile/](../../persistent/profile/); the other three (`headless`, `interactive`, `tracing`) are all ephemeral and would otherwise have no `profile/` at all.

## If you see files here

Something is wrong. The whole privacy guarantee of interactive mode (no credential persistence) depends on `isolated: true` being effective. Verify:
- [../config.json](../config.json) still contains `"isolated": true` under `browser`.
- The launcher [../../launch.ps1](../../launch.ps1) is invoking `npx ... --config playwright/interactive/config.json`.

If you find unexpected state here, treat it as a potential security concern — wipe the folder and investigate before reusing this mode for credential workflows.
