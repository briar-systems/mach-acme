# Changelog

## [Unreleased]

## [0.4.2] - 2026-09-17

### Changed
- Dependencies: mach-http v0.11.0 (#74).

## [0.4.1] - 2026-09-17

### Changed
- Dependencies: mach-crypto v0.12.0, which has faster X25519 and Ed25519 (#70).
- Releases are published by the shared release workflow when a `v*` tag is pushed. It checks the tag, version and changelog, runs the full CI tier, then publishes the GitHub release (#68).

## [0.4.0] - 2026-09-17

### Changed
- Dependencies: mach-std v4.0.1, mach-crypto v0.11.0, mach-http v0.10.0. Building now needs mach 5.2.0 or later, and a consumer that declares its own std must be on v4.0.1 (#64).
- The README's dependency list matches the pins again.

## [0.3.0] - 2026-09-16

### Security
- Durable state files and directories are now owner-only on Windows too. Before this they took the inherited default permissions, because mach-std did not enforce file modes there (#57, briar-systems/mach-std#703).

### Changed
- Dependencies: mach-std v3.2.0, mach-crypto v0.10.1, mach-http v0.9.0. A consumer that declares its own std must be on v3.2.0.
- CI runs the shared family pipeline from briar-systems/.github, with the live ACME suite as a subproject and a single `gate` check (#53).

## [0.2.1] - 2026-09-15

### Fixed
- Concurrent requests on one client no longer fail about 3% of the time as a mutated protocol state. The nonce provider ownership check hashed the client's own callback lock word, which other threads change (#51).

### Changed
- Dependencies: mach-crypto v0.9.1, mach-http v0.8.2.
- The protocol tests are part of the root test set (#48).

## [0.2.0] - 2026-09-13

### Changed
- Migrated to mach 5.0 and mach-std 2.0.0.
- Dependencies: mach-crypto v0.9.0, mach-http v0.8.0.

## [0.1.9] - 2026-09-05

### Changed

- Dependencies: mach-http v0.7.6, mach-crypto v0.8.2.
- The record-literal section no longer points at `mach-tls`'s partial literal
  sweep. That script is removed: enumerating the violations was a workaround
  for briar-systems/mach#3108, which is being fixed in the compiler. The rule
  itself is unchanged and still stated here.

### Added

- GitHub Actions CI: every pull request builds the library, runs the suite and the protocol vector project in both profiles, brings up the live ACME stack and runs the live suite against it, and verifies IR across all six targets.

## [0.1.8] - 2026-09-02

### Changed

- `mach-http` advances to `v0.7.5`, adopting the HTTP/3 DATA frame fix so
  every consumer in hedge's graph shares one release.

## [0.1.7] - 2026-09-02

### Changed

- `mach-http` advances to `v0.7.4`, adopting the HTTP/3 teardown fix so
  every consumer in hedge's graph shares one release.

## [0.1.6] - 2026-09-01

### Changed

- `mach-std` advances to `v0.34.0`, `mach-http` to `v0.7.3`, and `mach-crypto`
  to `v0.8.1`, aligning on the released typed secret-storage stack.

## [0.1.5] - 2026-09-01

### Changed

- Pinned `mach-http` to `v0.7.2` across the root, protocol, and live
  conformance dependency graphs, with all exact locks agreeing on the
  released HTTP teardown contracts.

## [0.1.4] - 2026-08-31

### Changed

- Pinned `mach-crypto` to `v0.7.0`.
- Refreshed exact dependency locks for the root, protocol, and live
  projects.

## [0.1.3] - 2026-08-31

### Changed

- Updated the `mach-http` dependency to `v0.7.0`.
- Tracked exact dependency locks for the root, protocol, and live
  integration projects.

## [0.1.2] - 2026-08-29

### Fixed

- Replaced the remaining empty and partial record literals. `client.release`
  cleared `client.nonces` with `nonce.Pool{}`, an eleven-field record with
  nine pointers and eight callbacks. That and `Limits` now come from
  constructors that clear by declaration, and the remaining sites that
  carry digests and thumbprints in arrays now clear through a
  `var`-and-assign branch.

### Changed

- Refreshed `test/protocol`'s dependency lock, which pinned `mach-http`
  v0.4.1 while the library resolves v0.5.0 transitively.

## [0.1.1] - 2026-08-28

### Changed

- Aligned the `mach-http` dependency to `v0.5.0` so a consumer can depend
  on this library alongside the rest of the stack. No functional change,
  since mach-acme does not construct HTTP/3 connections.

## [0.1.0] - 2026-08-28

### Added

- A complete ACME client: directory discovery and signed requests, account
  lifecycle with external account binding and key rollover, orders with
  authorizations and bounded polling, HTTP-01, DNS-01, and TLS-ALPN-01
  challenge presentation, CSR generation with issuance, alternate chain
  selection and revocation, durable transactional state, and ARI-aware
  renewal scheduling.
- Key authorization following RFC 8555 section 8.1, DNS-01 using the
  `_acme-challenge.` label with the SHA-256 digest, and TLS-ALPN-01
  carrying the `acmeIdentifier` extension under OID 1.3.6.1.5.5.7.1.31 per
  RFC 8737 section 3.

### Changed

- Pinned `mach-std` to `v0.33.0`, `mach-http` to `v0.4.1`, and `mach-crypto`
  to `v0.6.0`.
