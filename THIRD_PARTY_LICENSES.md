# Third-party notices

## fx-autoconfig

Omazen vendors the program loader and profile runtime from [MrOtherGuy/fx-autoconfig](https://github.com/MrOtherGuy/fx-autoconfig) at commit [`dfdab5684faffc112b76ccb1d8cab7f75da0102c`](https://github.com/MrOtherGuy/fx-autoconfig/tree/dfdab5684faffc112b76ccb1d8cab7f75da0102c), whose `boot.sys.mjs` identifies itself as version `0.10.16`.

These files are distributed under the Mozilla Public License 2.0. The unmodified upstream license is at [vendor/fx-autoconfig/LICENSE](vendor/fx-autoconfig/LICENSE), and file-level provenance and checksums are at [vendor/fx-autoconfig/UPSTREAM.md](vendor/fx-autoconfig/UPSTREAM.md).

The vendored files remain physically separate from Omazen's MIT-licensed bridge, actor, CSS and Bash code.

## zen-wabi

[zen-wabi](https://github.com/parazeeknova/zen-wabi) was studied as an MIT-licensed architectural precedent. Omazen does not bundle it, depend on it, or copy its bridge/actor implementation. The relevant ideas—polling an atomically replaced palette, using a privileged bridge, and broadcasting through a `JSWindowActor`—were independently reimplemented with a smaller contract and no Matugen, Boost, Quickshell or external-dotfiles dependency.

No zen-wabi license text is required for the Omazen distribution because no zen-wabi source is included; its authorship and influence are recorded here and in the research report.

