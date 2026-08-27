# Omazen CLI v1.4.1 contract

These SHA-256 manifests preserve the observable CLI behavior of the Bash
implementation at commit `ec1f907`, immediately before it was removed.

The contract tests normalize nondeterministic paths, timestamps, and process
identifiers before hashing stdout, stderr, exit status, and generated files.
To inspect a deliberate contract update, run the relevant test with
`OMAZEN_UPDATE_CONTRACT_MANIFEST=1`; never replace these manifests solely from
the Rust implementation under test.
