# Changelog

## [Unreleased]

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
