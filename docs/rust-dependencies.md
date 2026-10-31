# Rust dependency and license record

The Phase 1 `sync` implementation had no third-party dependencies. Phase 4
introduced `sha2` to calculate ownership-manifest hashes without invoking an
external executable. The current implementation uses `sha2 0.11.1`; its locked
dependency graph is:

| Package | Version | License |
|---|---|---|
| `sha2` | 0.11.1 | MIT OR Apache-2.0 |
| `digest` | 0.11.3 | MIT OR Apache-2.0 |
| `block-buffer` | 0.12.1 | MIT OR Apache-2.0 |
| `crypto-common` | 0.2.2 | MIT OR Apache-2.0 |
| `hybrid-array` | 0.4.15 | MIT OR Apache-2.0 |
| `typenum` | 1.20.1 | MIT OR Apache-2.0 |
| `cpufeatures` | 0.3.1 | MIT OR Apache-2.0 |
| `cfg-if` | 1.0.5 | MIT OR Apache-2.0 |
| `libc` | 0.2.191 | MIT OR Apache-2.0 |
| `const-oid` | 0.10.2 | Apache-2.0 OR MIT |

The `0.11` migration replaces `generic-array` with `hybrid-array` for
fixed-size cryptographic buffers and removes `version_check`. `const-oid` is
pulled in by `digest` for algorithm object identifiers. `sha2 0.11.1` requires
Rust 1.88, below the project's pinned 1.99.1 compiler. The hash result is now
formatted byte by byte as lowercase hexadecimal because the new array type
does not implement `LowerHex`. Known SHA-256 vectors and lifecycle integrity
checks cover the persisted hash format.

All are compatible permissive licenses. Palette parsing, canonical
serialization, path resolution, private directory creation and atomic rename
continue to use the Rust standard library.

The compiler is pinned to Rust 1.99.1. Rust standard-library components are
distributed under the Apache-2.0 and MIT licenses; those toolchain components
are build inputs and the dynamically linked system C runtime remains supplied
by the supported Omarchy system. Revisit this record before accepting every new
Cargo dependency and add its purpose, exact locked version and license.
