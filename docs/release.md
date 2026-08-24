# Release checklist

Use this checklist from a clean `main` worktree. Replace `1.1.0` when preparing a
later release.

## Automated gate

```bash
tests/syntax.sh
tests/test.sh
tests/visual-smoke.sh
git diff --check
```

Require the release-consistency check to report the same version as `VERSION`
and all tests to pass before deployment.

## Local deployment gate

1. Close Zen normally.
2. Run `./install.sh` from the release commit.
3. Reopen Zen once so fx-autoconfig loads the new bridge and shared module.
4. Run `omazen doctor` and require zero failures and zero warnings.
5. Confirm `bridge.log` contains `BRIDGE_LOADED version=1.1.0`, a successful
   `PALETTE_APPLIED`, and no current error.
6. Exercise dark/light theme changes, disable/enable, Settings, a common dialog,
   Library, Passwords, Print and Developer Tools without destructive actions.
7. Confirm the normal update created one timestamped application backup.

Do not publish the tag if any live gate fails. The staged installer leaves the
active application unchanged when pre-activation setup fails; the previous
successful application copy is retained as the timestamped backup after an
activated update.

## Publication gate

After the live validation report is updated and committed:

```bash
git tag -a v1.1.0 -m "Omazen 1.1.0"
git push origin main
git push origin v1.1.0
```

Create the GitHub release from the `1.1.0` changelog section. Verify the tag and
release point to the same validated commit.
