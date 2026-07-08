# playwright/headless/profile

**Intentionally empty placeholder.**

The `headless` mode uses `browser.isolated: true` (see [../config.json](../config.json) and [../../README.md](../../README.md) row #4). Under isolated mode, Playwright creates a fresh in-memory temp profile per session and wipes it on close. **Nothing on disk is ever used by headless.**

This folder exists only for visual symmetry with the four mode subfolders — `persistent` is the one mode that uses a real on-disk profile at [../../persistent/profile/](../../persistent/profile/); the other three (`headless`, `interactive`, `tracing`) are all ephemeral and would otherwise have no `profile/` at all.

## If you see files here

Something is wrong. Verify:
- [../config.json](../config.json) still contains `"isolated": true` under `browser`.
- The launcher [../../launch.ps1](../../launch.ps1) is invoking `npx ... --config playwright/headless/config.json`.

If both look right and files still appear, check whether `@playwright/mcp` was updated upstream and isolated semantics changed — diff against the [settings table](../../README.md#settings).
