# Rust dependency and license record

The Phase 1 `omazen-cli` package has no third-party Cargo dependencies. Its
committed lockfile contains only the local package. Palette parsing, canonical
serialization, path resolution, private directory creation and atomic rename
use the Rust standard library.

The compiler is pinned to Rust 1.98.0. Rust standard-library components are
distributed under the Apache-2.0 and MIT licenses; those toolchain components
are build inputs and the dynamically linked system C runtime remains supplied
by the supported Omarchy system. Revisit this record before accepting every new
Cargo dependency and add its purpose, exact locked version and license.
