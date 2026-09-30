# Changelog

## [Unreleased]

## [0.14.1] - 2026-09-30

### Fixed
- Builds on mach 6.8. The all-ones and near-all-ones addresses in the memory-range, nonce and protocol tests are cast to a pointer through `usize`, where mach 6.8 refuses an unsuffixed literal past `i64` with `const.out_of_range`. What the tests check is unchanged.

## [0.14.0] - 2026-09-28

### Added
- A fuzz lane in `test/fuzz`, on the same driver as mach-tls's, with boundaries over every parser of server input: `json`, `url`, `directory`, `problem`, `replay-nonce`, `account`, `order`, `authorization`, `chain`, `certificate`, `alternates` and `renewal-info`, and a checked-in corpus. `mach build test/fuzz` runs on every pull request and the replay runs on the heavy tier. It found nothing, so the library is unchanged (#115).

### Changed
- **Breaking.** Dependencies: mach-std `^9.4` at v9.4.1, mach-crypto `^0.26` at v0.26.0 and mach-http `^0.25` at v0.25.1 (were `^9.3`, `^0.25` and v0.25.0). Resolution is flat, so a consumer must move to the new std and crypto with it. std 9.4.1 maps a guard page below every linux thread stack, crypto 0.26 lets the system allocators own the only secret wipe and zeroing, and http 0.25.1 is fixes only. The fuzz and live subprojects pin the three by tag.
- **Breaking.** Requires mach 6.5 (`mach = "^6.5"`), since http 0.25.1 does, and CI seeds mach v6.5.0. The 6.5 formatter is applied.

### Fixed
- The storage conformance and file-store tests claim a unique temp path per run, so parallel runs no longer race on fixed `/tmp` paths (#117).

## [0.13.0] - 2026-09-27

### Changed
- **Breaking.** Dependencies: mach-std `^9.3` at v9.3.0, mach-crypto `^0.25` at v0.25.0 and mach-http `^0.25` at v0.25.0 (were `^9.0`, `^0.24` and `^0.24`). Resolution is flat, so a consumer must move to the new std, crypto and http with it. http 0.25 adds a lingering server close and breaks only `h1.connection.Config` literals, and crypto 0.25 adds public secret-tag HMAC, and mach-acme builds no `Config` literal, so nothing it uses changes. The live conformance subproject pins the three by tag, and its suite passes against pebble (#132).

## [0.12.0] - 2026-09-27

### Changed
- **Breaking.** The challenge and certificate seams take a typed context instead of `ptr`, so an embedder can hand mach-acme a record that holds secret storage, which cannot erase to `ptr` (#126). `challenge.Provider[C]` carries `ctx: *C` and its callbacks take `*C`, and `Providers[C]`, `Attempt[C]`, `provider_valid`, `attempt_init`, `supports`, `begin`, `presented` and `finish` are generic over it. `Attempt.owner` is `*Attempt[C]` instead of `ptr`. `certificate.CsrSigner[C]` carries `ctx: *C` with `sign: fun(*C, *u8, usize, *u8, usize) usize`, the call is `encode_csr[C]`, and `certificate.PrivateKey[C]` and `Issued[C]` take the same typed `ctx`. `challenge.SupportsFun`, `PresentFun`, `CleanupFun` and `certificate.SignFun` are removed, since mach has no generic `def`. `jose.PrivateKey.secret_owner` and `Presentation.ctx` stay `ptr`, as identity and token only, and a welded owner names itself with the address of one of its public fields. `attempt_init` and `attempt_ready` no longer check the attempt's byte range, since a welded attempt cannot be measured as bytes, and keep the nil and typed self-pointer checks. The unit and live suites run the seams over welded contexts, and README and `doc/protocol.md` document the typed seams.
- **Breaking.** Dependencies: mach-http `^0.24` at v0.24.0 (was `^0.23` at v0.23.0). Resolution is flat, so a consumer must move to http 0.24 with it. http 0.24 adds the server tunnel and the response and tunnel timeouts and breaks only `server.Handler` literals, and mach-acme reaches http only through `core.field`, `core.method` and `core.status`, so nothing it uses changes. The live conformance subproject pins http v0.24.0 by tag, and its suite passes against pebble (#128).

## [0.11.0] - 2026-09-27

### Changed
- **Breaking.** Dependencies: mach-http `^0.23` at v0.23.0 (was `^0.21` at v0.21.0). Resolution is flat, so a consumer must move to http 0.23 with it. http 0.22 and 0.23 add the server runner in `http.server.server`, make `h1.connection.config_valid` public and stop a closing h1 engine from parsing input, and mach-acme reaches http only through `core.field`, `core.method` and `core.status`, so nothing it uses changes. The live conformance subproject pins http v0.23.0 by tag, and its suite passes against pebble (#122).
- Three unused imports in `acme.json`, `acme.account` and `acme.file_store` are gone, so the library builds without warnings on mach 6.3 (#122).

### Fixed
- Each live conformance test registers its own random account key. The tests shared one fixed key, and two concurrent first registrations of it raced inside pebble and failed one test with a 500 on a fresh authority, which is every CI run (#120).

## [0.10.0] - 2026-09-26

### Changed
- **Breaking.** mach-acme builds on mach 6: `mach.toml` requires mach `^6` (was `^5.12`), and the dependencies move to mach-std `^9.0` (v9.0.0, was `^8.0` at v8.0.0), mach-crypto `^0.24` (v0.24.0, was `^0.22` at v0.22.0) and mach-http `^0.21` (v0.21.0, was `^0.20` at v0.20.0). Resolution is flat, so a consumer must move to mach 6, std 9, crypto 0.24 and http 0.21 with it. The public surface of mach-acme is unchanged. CI seeds mach v6.0.0, and the live conformance subproject pins std v9.0.0, crypto v0.24.0 and http v0.21.0 by tag (#114).
- Every test is named by identifier (`test subject__case`), as mach 6 requires. Test-only helpers are marked `#[testing]`, as are the thread and atomic imports only the tests in `src/nonce.mach` use, so ordinary builds omit them. `test/selections/verify.sh` reads the identifier form and matches the qualified names `mach test --list` prints (#114).
- The suite is pruned to mach's test policy, from 70 tests to 64 (61 to 56 under `src`, 9 to 8 in `test/live`). A trivial constructor check in `acme.problem`, pins on fixed problems in `acme.json`, `acme.nonce` and the account payloads, and a live smoke test that every other live test repeats are gone. The unique checks of the protocol nonce test (an invalid value and a short output) fold into `acme.nonce#take__newest_exactly_once`. Every hostile-input and parser corpus stays (#114).

## [0.9.0] - 2026-09-25

### Changed
- **Breaking.** Dependencies: mach-http `^0.20` at v0.20.0 (was `^0.19` at v0.19.0). Resolution is flat, so a consumer must move to http 0.20 with it. http 0.20 adds `EVENT_REQUEST_REJECTED` to the server h1 engine, a query check in the router and `core.target`, and mach-acme reaches http only through `core.field`, `core.method` and `core.status`, so nothing it uses changes. The live conformance subproject pins http v0.20.0 by tag, and its suite passes against pebble (#110).

## [0.8.1] - 2026-09-25

### Changed

- The library entry moved from `src/lib.mach` to `src/lib/acme.mach` and the tests entry from `src/test/tests.mach` to `src/lib/tests.mach`, the family layout for artifact entries (briar-systems/.github#107). A bare `use acme;` still binds the library entry, and every other module path is unchanged. The entry module itself is now `acme.lib.acme`, so an import that named `acme.lib` directly names that path or uses `use acme;` instead (#106).

## [0.8.0] - 2026-09-25

### Changed
- **Breaking.** Dependencies: mach-std `^8.0` (v8.0.0, was `^7.0` at v7.0.2), mach-crypto `^0.22` (v0.22.0, was `^0.20` at v0.20.0), mach-http `^0.19` (v0.19.0, was `^0.18` at v0.18.0), and mach `^5.12` (was `^5.9`), which std 8 requires. Resolution is flat, so a consumer must move to std 8.x and mach 5.12 with it. Rebuild anything that links std rather than recompiling against the new sources, as std's release notes say. std 8 adds the typed secret view and grows `buffers.SecretSource`, and mach-acme uses neither. crypto 0.21 and 0.22 change AES and AES-GCM, which mach-acme does not reach, and http 0.19 changes only h2. The only source change is the layout mach 5.12's formatter requires in `src/test/protocol.mach` (#101).
- The protocol vectors in `src/test/protocol.mach` run under `mach test . --lib tests`. mach 5.12 tests only the selected artifact's closure (briar-systems/mach#3813), so `mach test .` alone now collects the 15 tests the library reaches and not the other 46. The test-only `[artifact.tests]` reaches them, and `[artifact.acme]` is marked `default = true`, so `mach build .`, `--all-targets` and a consumer's `use acme` still select the library alone. `test/selections/verify.sh` fails when a test declared under `src` is collected by neither selection on some target, and CI runs it on the primary leg (#101).
- CI seeds mach v5.12.0 until the family pin moves (briar-systems/.github#103), and runs the `tests` selection on every leg. The live conformance subproject pins std v8.0.0, crypto v0.22.0 and http v0.19.0 by tag (#101).

### Fixed
- README: "Remaining scope" is removed, because everything it listed as a later layer is implemented. The README now says the library leaves transport to its host, that `test/live` issues a certificate end to end against a real authority, and that hedge provides a production transport. The dependency list names the resolved releases, std v7.0.2, http v0.18.0 and crypto v0.20.0 (#100).

## [0.7.1] - 2026-09-23

### Changed
- Dependencies: mach-http `^0.18` (v0.18.0), so mach-acme resolves alongside a project that needs http 0.18. http 0.18 adds `h2.connection.pending_work` and fixes a frame dropped at end of stream, and mach-acme reaches http only through `core.field`, `core.method` and `core.status`. The live conformance subproject pins http v0.18.0 by tag (#96).

## [0.7.0] - 2026-09-22

### Changed
- **Breaking.** Dependencies: mach-std `^7.0` (v7.0.2), mach-crypto `^0.20` (v0.20.0), mach-http `^0.17` (v0.17.0), selected by version range with the resolved release committed as a gitlink. A consumer must be on std 7.x. None of the std 7 migration items reach mach-acme: it calls no `io.runtime.make`, stores no `data.toml.Value`, and builds no `allocator.page`, `testing` or `arena` (its only allocator construction is `allocator.fixed` in the protocol tests). crypto 0.19 and 0.20 rewrite the P-256, RSA and Poly1305 arithmetic on 64-bit limbs with unchanged signatures and key acceptance, and the JOSE signing paths here exercise them unchanged. http 0.16 and 0.17 change only the exchange engines, retry policy and HTTP/3 surfaces, and mach-acme reaches http only through `core.field`, `core.method` and `core.status`. `mach = "^5.9"` is unchanged (#92).
- The live conformance subproject pins std v7.0.2, crypto v0.20.0 and http v0.17.0 by tag (#92).

## [0.6.0] - 2026-09-19

### Changed
- **Breaking.** Dependencies: mach-std `^6.0` (v6.0.0), mach-crypto `^0.18` (v0.18.0), mach-http `^0.15` (v0.15.0), selected by version range with the resolved release committed as a gitlink, and `mach.toml` now requires mach `^5.9`. A consumer must be on std 6.x. None of the std 6 migration tables reach mach-acme: it uses no `sort`, `heap`, `map`, `set` or `buffers` account, and its only `std.crypto.ct` call is `zeroize`. crypto's SHA-2 now runs on std's hardware-dispatched states, and `hash.Sha256` stays opaque to the callers here. http 0.15's public surface is unchanged and mach-acme uses only `http.core` (#88).
- CI asks the family workflow for `dit: required`, because mach-crypto 0.17 and later link a secret multiply that needs FEAT_DIT on aarch64 (#88).
- The live conformance subproject pins std, crypto and http by tag itself, because a path dependency carries no pin for a dependency it selects by version (#88).

## [0.5.0] - 2026-09-17

### Changed
- **Breaking.** Dependencies: mach-std v5.3.0, mach-crypto v0.13.2, mach-http v0.12.0, and `mach.toml` now requires mach `^5.3`. A consumer must be on std 5.x as well. mach-acme itself consumes no std completions and uses only `http.core`, so the std 5.3 completion contract and the http 0.12 engine changes do not reach it (#80).
- **Breaking.** Poll deadlines and readings are monotonic `std.chrono.time.Instant` values instead of bare `i64` nanoseconds: `poll.begin` takes `deadline: time.Instant`, `poll.next` and `order.poll_next` take `now: time.Instant`, and so do `challenge.propagation_begin` and `challenge.propagation_next`. A wall-clock `time.Time` no longer type-checks as a deadline. The renewal schedule keeps its wall-clock unix seconds, because certificate validity is compared against the outside world (#80).
- **Breaking.** `poll.next` accounts for the caller's observation before cancellation. An observation that reached the target is `READY`, and a failed one is `TERMINAL`, even after `poll.cancel`. `CANCELLED` is returned only for an observation that made no progress. The old order, which checked cancellation first, could tell a caller to abandon a finalized order that was already `valid`. The next run would then issue again and spend a duplicate-certificate slot. `poll.Decision` gains `cancelled`, which reports that the poll had been cancelled even when a `READY` or `TERMINAL` decision outranked it (#80).

### Changed
- The copyright is now held by Briar Systems LLC (#78).

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
