# Release checklist

Use this checklist from a clean `main` worktree for the local `1.3.2` release
candidate.

## Automated gate

```bash
tests/release-gate.sh
```

The gate installs the pinned analyzers, runs static analysis, validates the
release consistency and palette contrast, exercises the disposable lifecycle,
renders the visual smoke fixture with Zen, and checks repository whitespace. On
a Wayland session with Hyprland and ImageMagick it also boots a disposable real
Zen profile to
capture Settings and browser chrome, exercise palette changes plus
disable/enable, and compare the captures with tolerance. It must pass before
deployment; headless environments retain the deterministic fixture check and
skip only the compositor-backed extension.

The CI visual job downloads the fixed Zen release used by the test, verifies its
SHA-256 before extraction, and then checks the embedded application version.

## Local deployment gate

1. Close Zen normally.
2. Run `./install.sh` from the release commit.
3. Reopen Zen once so fx-autoconfig loads the new bridge and shared module.
4. Run `omazen doctor` and `omazen doctor --json`; require zero failures and
   zero warnings in both reports. Save the JSON report for the test record:
   `omazen doctor --json > /tmp/omazen-1.3.2-doctor.json`.
5. Confirm `bridge.log` contains `BRIDGE_LOADED version=1.3.2`, a successful
   `PALETTE_APPLIED`, and no current error.
6. Exercise dark/light theme changes, disable/enable, Settings, a common dialog,
   Library, Passwords, Print and Developer Tools without destructive actions.
7. Confirm the normal update created one timestamped application backup.

Do not publish the tag if any live gate fails. The staged installer leaves the
active application unchanged when pre-activation setup fails; the previous
successful application copy is retained as the timestamped backup after an
activated update.

## Publication gate

After the live validation report is updated and committed, derive and create
the tag from `VERSION`, then push both the commit and the derived tag:

```bash
RELEASE_TAG=$(tests/create-release-tag.sh)
git push origin main "$RELEASE_TAG"
```

The `Release` GitHub Actions workflow validates the tag against `VERSION`, runs
the complete CI gate, extracts the matching changelog section, and creates the
GitHub release only after every check passes. It can also be dispatched manually
for an existing version tag.
