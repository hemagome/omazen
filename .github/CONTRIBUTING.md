# Contributing to Omazen

Thank you for considering a contribution. Omazen installs privileged browser
code, so changes should be small, explainable, and validated against the
security and compatibility boundaries documented in the repository.

## Before you start

- Read the [README](../README.md), [security model](../docs/security.md), and
  [compatibility contract](../docs/compatibility.md).
- Search existing issues and pull requests before opening a new one.
- For a security vulnerability, do not open a public issue. Contact the
  repository maintainers privately through GitHub instead.
- Keep changes focused. Please open a separate pull request for unrelated work.

## Development environment

Omazen's CLI is implemented in Rust while its rollback dispatcher and theme
hook remain shell; Gecko integration remains JavaScript and CSS. Rust 1.98.0 is
required for the Rust gates. The supported runtime and fully validated
compatibility target are documented in the README and compatibility guide.

To run the local checks on Linux x86-64:

```bash
tests/install-linters.sh /tmp/omazen-linters
PATH=/tmp/omazen-linters:$PATH tests/lint.sh
tests/syntax.sh
tests/rust.sh
tests/test.sh
```

The rendered-pixel smoke test also requires a usable Zen binary:

```bash
tests/visual-smoke.sh
```

Before submitting a release-related change, run the complete gate:

```bash
tests/release-gate.sh
```

Do not include passwords, tokens, browsing data, private profile contents, or
machine-specific secrets in issues, logs, screenshots, or commits.

## Making changes

- Preserve the supported scope: Omarchy Quattro with the native
  `zen-browser-bin` package.
- Keep privileged code narrowly scoped and preserve the existing allowlists,
  validation rules, fixed paths, ownership checks, and bounded logging.
- Do not add runtime downloads, remote code execution, local servers, or new
  page-exposed APIs without first documenting and reviewing the security impact.
- Update documentation, compatibility notes, tests, and the changelog when the
  behavior or support contract changes.
- Modify the canonical `zen/Omazen/omazen-chrome.css` and
  `zen/Omazen/omazen-content.css` sources. Do not add versioned stylesheet
  copies to the repository; installation derives their cache-busting names
  from `VERSION`.
- Use clear commit messages that describe the change and its reason.

## Pull requests

Describe the problem, the approach, the supported environment, and the checks
you ran. Include screenshots only when a visual change is relevant, and redact
any sensitive information. Pull requests should be ready for review, limited in
scope, and responsive to feedback.

CI must pass before a change is merged. Maintainers may ask for additional
validation against the supported Zen build or for updates to the relevant
documentation.

## Questions

Use GitHub Discussions for general questions and support. Use an issue for a
reproducible bug or a focused feature proposal, following the repository issue
templates.
