# Rust dependency and license record

The Phase 1 `sync` implementation had no third-party dependencies. Phase 4 adds
`sha2 0.10.9` to calculate ownership-manifest hashes without invoking an
external executable. Its locked dependency graph is:

| Package | Version | License |
|---|---|---|
| `sha2` | 0.10.9 | MIT OR Apache-2.0 |
| `digest` | 0.10.7 | MIT OR Apache-2.0 |
| `block-buffer` | 0.10.4 | MIT OR Apache-2.0 |
| `crypto-common` | 0.1.7 | MIT OR Apache-2.0 |
| `generic-array` | 0.14.7 | MIT |
| `typenum` | 1.20.1 | MIT OR Apache-2.0 |
| `cpufeatures` | 0.2.17 | MIT OR Apache-2.0 |
| `cfg-if` | 1.0.4 | MIT OR Apache-2.0 |
| `libc` | 0.2.189 | MIT OR Apache-2.0 |
| `version_check` | 0.9.5 | MIT/Apache-2.0 |

All are compatible permissive licenses. Palette parsing, canonical
serialization, path resolution, private directory creation and atomic rename
continue to use the Rust standard library.

The compiler is pinned to Rust 1.98.0. Rust standard-library components are
distributed under the Apache-2.0 and MIT licenses; those toolchain components
are build inputs and the dynamically linked system C runtime remains supplied
by the supported Omarchy system. Revisit this record before accepting every new
Cargo dependency and add its purpose, exact locked version and license.
