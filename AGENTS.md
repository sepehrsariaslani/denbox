# Denbox project instructions

## Shared worktree and conversation coordination

- Before editing, read `DENBOX_PROJECT_CONTEXT.md`, `README.md`, `git status --short`, and the relevant current diff.
- This repository is shared by multiple Denbox conversations. Treat existing modifications and untracked files as active work: inspect them, preserve them, and avoid resets, cleanups, or whole-file replacements.
- When another conversation changes a file during a build, copy the current `Sources` and `Resources` to a temporary snapshot, compare hashes before and after copying, and build that snapshot. Report which snapshot was built; do not describe an old snapshot as the current worktree build.
- Update `DENBOX_PROJECT_CONTEXT.md` after product decisions or significant changes. Keep installed-app state separate from current-worktree state, and record what was actually built, installed, launched, or verified.
- Codex chat transcripts are not available through the current tools. Record decisions and handoffs in `DENBOX_PROJECT_CONTEXT.md` so other conversations can continue from the shared repository.

## Product and data boundaries

- Keep Denbox Mac-first and Persian by default; preserve English selection and original film, series, person, and provider names.
- Keep viewing history, personal ratings, My List, and preferences local unless Sepehr explicitly chooses a sync service.
- Keep API credentials in Keychain. Never copy credentials, private media URLs, or personal viewing data into source, logs, screenshots, or project notes.
- Preserve the existing SQLite and Keychain identities while evolving the Simba-to-Denbox app.

## Build and verification

- Do not run tests unless Sepehr asks for tests or verification. Do not claim runtime behavior from a successful compile.
- For compile checks, build a temporary, hash-checked snapshot by default; do not overwrite `dist` or the installed app as a side effect of validation.
- Check `git diff --check` and validate `Resources/fa.lproj/Localizable.strings` after editing them.
