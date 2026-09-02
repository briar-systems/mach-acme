# mach-acme

`mach-acme` provides lightweight, bounded ACME protocol components for Mach. The
directory, JOSE, replay-nonce, signed-request, account lifecycle, and structured
problem foundations are implemented. Order, challenge, certificate, and renewal
contracts remain separate so applications can choose their storage and deployment
systems.

The library does not pretend to be a network client. It produces typed HTTP
requests and accepts typed HTTP responses. A future `mach-http` client transport
will execute those requests without changing the ACME state machine or key
ownership contract.

## Implemented

- strict bounded ACME directory discovery with all RFC 8555 endpoints and metadata
- canonical EC, OKP, and RSA JWK encoding and RFC 7638 SHA-256 thumbprints
- canonical flattened JWS with ES256, EdDSA, and PS256 account keys
- nonce-bearing outer JWS and nonce-free nested JWS for key rollover
- separate public signer metadata and caller-owned private keys
- caller-provided entropy for RSA-PSS with ownership predicates, post-callback
  validation, transactional output, and explicit salt zeroization
- bounded one-use replay nonce storage with deterministic newest-first selection
  and reserve, commit, and release transactions
- immutable nonce callback descriptors, public ranges, and opaque secret-owner
  domains with fail-closed result, alias, reentrancy, and state validation
- signed-request state and bounded per-request `badNonce` recovery
- exact URL, payload, `kid`, signer thumbprint, and prepared-body binding with
  timeout and response bounds on every wire request
- structured local, HTTP, and ACME problem causes
- bounded structured ACME subproblems for multi-identifier failures
- caller-owned JSON scratch, output storage, signing work, and wire buffers
- strict numeric grammar and an explicit duplicate-key comparison-work bound
- bounded account creation, lookup, contact replacement, terms agreement,
  deactivation, and strict account response decoding
- deterministic HS256 and HS384 external account binding with exact secret-key
  ownership, bounded MAC keys, and provenance-carrying output operations
- nested account key rollover for ES256, EdDSA, and PS256 credentials
- durable credential prepare, commit, abort, and recovery with explicit conflict,
  failure, and unknown outcomes
- serialized storage-provider callbacks with alias, reentrancy, descriptor,
  readiness, input-binding, and result validation
- explicit wildcard and IP identifier policy with strict RFC 1123 name syntax,
  IP literal parsing, and case-insensitive identifier comparison
- bounded `newOrder` encoding, POST-as-GET retrieval, and strict order and
  authorization decoding with embedded RFC 7807 failures
- challenge selection and the RFC 8555 wildcard challenge rule
- Retry-After-aware order polling with an absolute deadline, bounded
  exponential backoff, an attempt ceiling, cancellation, and terminal statuses
- RFC 8555 key authorization derived from the account key, with HTTP-01 paths,
  DNS-01 record names and digests, and the RFC 8737 TLS-ALPN-01 digest and
  `acmeIdentifier` extension value
- exactly-once challenge presentation and cleanup across success, failure,
  timeout, and cancellation, with a same-thread reentrancy guard
- bounded, injectable DNS propagation policy requiring consecutive
  confirmations
- RFC 2986 certification requests with subjectAltName DNS and IP entries,
  built without ever holding the certificate key
- strict X.509 decoding of subjectAltName and the validity window, and
  verification of an issued certificate against the requested identifiers
- PEM chain decoding, RFC 8288 alternate-chain links, order finalization,
  certificate download, and revocation with CRL reasons
- transactional certificate and private-key replacement over the same durable
  gate, tokens, and one-active-transaction rule as account credentials
- file-backed durable state: versioned, checksummed documents replaced
  atomically with owner-only permissions, and a store that survives restart,
  reports corruption, and refuses a stale writer
- ARI certificate identifiers, renewal-information windows, and a renewal
  scheduler with randomized selection, bounded retry, clock-skew handling,
  observable transitions, and cancellation

## Protocol boundary

The transport-independent path is:

1. Create `client.discovery_request` with the configured limits and execute the returned GET.
2. Convert the transport result to `client.Response` and call
   `client.parse_directory`.
3. Execute `client.nonce_request` when no replay nonce is available.
4. Initialize a `client.SignedRequest` with `client.begin_signed`.
5. Call `client.prepare_signed`, which reserves a stored nonce, writes a JWS, and
   commits the nonce only when the exact wire body is ready.
6. Execute the POST described by `client.signed_wire`. Its body is the exact output accepted by `prepare_signed`.
7. Deliver the response to `client.accept_signed_response` and follow its action.

`ACTION_RETRY_SIGNED` means the server supplied a fresh nonce. `ACTION_ACQUIRE_NONCE`
means the caller must execute the directory's HEAD request, then pass the result to
`client.accept_nonce_response`. Neither action hides I/O or retries inside a signing
callback. Recovery nonces are copied into the exact `SignedRequest` that received
them, so concurrent requests cannot exchange retry credentials through the shared
nonce pool.

See [the protocol contract](doc/protocol.md) for lifetimes, failure rules, and
buffer requirements.

## Dependencies

The repository pins exact released Git tags:

- `mach-std` v0.34.0
- `mach-http` v0.7.5
- `mach-crypto` v0.8.1

Build output uses Mach's repository-local `out/` path. Run the root tests and the
protocol vector project with:

```text
mach test . --profile debug
mach test . --profile release
mach test test/protocol --profile debug
mach test test/protocol --profile release
```

`test/live` is a conformance suite that drives a real ACME authority rather
than a fixture. Start the local stack first, then run it:

```text
test/live/harness/start.sh
mach test test/live --profile debug
mach test test/live --profile release
test/live/harness/start.sh.stop
```

`start.sh` builds the stack's binaries on first use, so a clean checkout needs
only Go on the path. The harness runs `pebble`, its challenge test server, and
a plain-HTTP front end on loopback. `mach-acme` emits typed HTTPS wire requests and TLS
termination belongs to `mach-tls`, so the front end terminates TLS while every
ACME byte, URL, status, and header passes through unchanged.

## Account lifecycle

`account.encode` creates each RFC 8555 account payload. `account.begin` selects
JWK authentication for creation and lookup and account URL authentication for
updates. `account.parse` validates a successful account representation into
caller-owned text and contact storage. Encoding measures the complete bounded
request before writing directly to caller output, so every admitted 64-contact,
4096-byte-per-contact request is representable. Contact values use strict URI
syntax, including complete percent escapes and constrained `mailto` addresses.
`storage.begin_save` stages the first account credential or a same-generation
account metadata update through the durable transaction boundary.

`external_account.encode` creates the nested flattened JWS required by a CA's
external account binding policy. A binding selects HS256 or HS384 and carries a
bounded secret-qualified key whose owner pointer must be that exact key pointer.
The returned operation binds the encoded bytes, algorithm, account-key
thumbprint, and `newAccount` URL. `account.encode` accepts that operation, not
untrusted JSON, and `account.begin` binds the outer request to the same signer.

Key rollover starts with `key_change.prepare`. It durably stages the replacement
through `storage.Manager`, signs the inner JWS with the new key, and returns the
nested payload for an outer request signed by the old account key.
`key_change.begin_outer` consumes that exact prepared replacement through the
provider-owned storage gate before it creates the old-key request. An accepted
response commits the staged credential. A rejected response aborts it. An
ambiguous transport outcome retains the pending credential so `storage.recover`
can reconcile the server's active key after restart. `key_change.resolve` accepts
only a recovered next-generation key replacement and commits or aborts its exact
transaction.

## Remaining scope

Network execution waits on the production `mach-http` client lifecycle. Order and
authorization progression, challenge polling, finalization, certificate
installation, and renewal scheduling are tracked as later ACME layers. The
current protocol boundary is shaped so those layers add request payloads and
response decoders without changing signing, nonce, account, or transport
ownership.

## Orders and authorizations

`order.encode` writes a bounded `newOrder` payload from a caller-owned
identifier array. Admission is an explicit `identifier.Policy` rather than a
library default, so a deployment that cannot answer DNS-01 never silently
orders a wildcard, and RFC 8738 IP identifiers stay opt-in. DNS names use
strict RFC 1123 syntax, wildcards are only a leftmost `*.` label, and duplicate
identifiers are rejected before the order is created because they make the
returned authorization list ambiguous.

`order.begin_new` submits the order under the account `kid`. `order.begin_fetch`
is the RFC 8555 POST-as-GET read used for order polling and authorization
retrieval. `order.parse` accepts the 201 creation response with its `Location`
and the 200 poll response against a known order URL, and requires the
certificate URL to appear exactly when the order is `valid`.
`order.parse_authorization` decodes the identifier, wildcard flag, expiry, and
bounded challenge list. A challenge type this build does not implement is
retained with a zero kind so selection can skip it without failing the whole
authorization. An embedded `error` object is copied into caller storage, so a
partial failure survives the response that carried it.

`order.select_challenge` and `order.challenge_admissible` are pure decisions
over an already parsed authorization. RFC 8555 section 7.1.3 admits only DNS-01
for a wildcard authorization, and that rule is stated here rather than left to
each caller.

Polling is a decision function, not a loop. The caller owns the clock and
supplies a monotonic reading, the authority's Retry-After, and the current
status. `order.poll_next` honours Retry-After when it exceeds the local
backoff floor, clamps every wait to the policy ceiling, refuses a wait that
would pass the absolute deadline rather than truncating it, stops at an
attempt ceiling, and reports cancellation and terminal statuses distinctly.
Backoff doubles from the floor and saturates, so a long poll can never produce
an unbounded or overflowing wait.

## Challenges

`challenge.key_authorization` derives the RFC 8555 section 8.1 value from the
account key itself rather than accepting a thumbprint from the caller, so a
challenge can never be answered with a key the account does not hold. From that
one value the library produces the HTTP-01 path and body, the DNS-01 record
name and `base64url(SHA-256(keyAuthorization))` value, and the RFC 8737
TLS-ALPN-01 digest and `acmeIdentifier` extension octet string. A wildcard
order is validated against its base domain, so a DNS-01 record name never
carries the wildcard label.

`challenge.Attempt` owns one presentation through one provider. Cleanup is owed
exactly when presentation succeeded: a provider that declined the challenge is
never asked to present, and a presentation that failed owes nothing.
`challenge.finish` is the single exit for success, failure, timeout, and
cancellation, so every path retires the provider's state once and only once.
Calling it again is accepted and does not reach the provider a second time. The
presentation and cleanup call counters are public, so exactly-once is observed
rather than inferred. A provider that re-enters its own attempt from inside a
callback is refused before it can move the attempt's state.

Waiting for a published record to become observable is a caller policy.
`challenge.Probe` is an injectable observation callback, so a deployment
supplies a resolver and a test supplies a deterministic answer. Confirmations
must be consecutive, so a record that appears and then disappears restarts the
count rather than proceeding. The wait is bounded by the shared poll policy.

`acme.poll` holds the one bounded wait policy that orders, challenges, and
renewal share. It is status agnostic: callers reduce their own status to
`reached` and `terminal` and keep their own vocabulary.

## Certificates

`certificate.encode_csr` produces a complete RFC 2986 certification request.
The library owns the DER encoding, which is the error-prone half, and never
owns the key: the caller's signer receives the exact certification request info
bytes and returns a signature. The signer's context is a plain pointer, so
secret memory cannot be laundered through it. The returned signature's shape is
validated against the algorithm it claims, and the request info is re-encoded
and compared after signing, so a signer that disturbed its input cannot publish
a request.

`certificate.parse_certificate` decodes only what an ACME decision depends on:
the subjectAltName entries and the validity window. `verify_issued` parses the
leaf and requires it to cover exactly the requested identifiers. A certificate
that omits a requested name, or carries one that was not ordered, is refused —
before anything reaches durable storage. Chain bodies are decoded from PEM into
caller storage, so a retained certificate never points at a response buffer.

`certificate.parse_alternates` reads RFC 8288 `Link` headers and retains only
`rel="alternate"` targets, copying each into caller storage so it outlives the
response fields.

Certificate and private-key replacement runs through the same durable manager
as account credentials. `storage.RecordKind` is the axis durable state grows
along: both kinds share the gate, the monotonic token sequence, the
one-active-transaction rule, and callback serialization, and differ only in the
staged payload and its ownership rules. A store declares which record kinds it
holds; one that declares no certificate callbacks refuses certificate
transactions rather than half-supporting them.

## Durable files

Every durable record is one self-describing document: a magic, a schema
version, the record kind, the payload length, and a SHA-256 of the payload.
`file_store.write_document` replaces a document atomically — the replacement is
written to a sibling temporary, flushed, closed, renamed, and the parent
directory is flushed — so a reader sees either the previous committed document
or the complete new one, and a write that fails leaves the previous one exactly
as it was. Durable ACME state includes account keys, so files are created
owner-only and their directories owner-only.

`read_document` validates the magic, the schema version, the record kind, the
declared length, and the payload digest before publishing any payload. A
truncated, corrupt, foreign, or future-versioned document is reported, never
partly believed. `needs_migration` reports a document written by an older
schema so a caller migrates deliberately.

`file_store.Store` implements the durable store contract for both transactional
record kinds over one document each. It persists the transaction token before
handing it out, so the sequence stays monotonic across a restart even if
nothing is staged against it, and it enforces the expected generation durably,
so a writer working from a stale read is refused rather than overwriting a
newer record. A staged record that was never committed is recovered as pending
with the committed record untouched — which is what an interrupted process
looks like on the next run.

The private key is never written. The store persists public credential
material and one opaque key identity, and the application's secret provider
maps that identity back to its key material.

`file_store.copy_document` is backup and restore: the source is fully validated
before anything is written, so a backup cannot capture a corrupt document and a
restore cannot install one.

## Renewal

`renewal_info` implements draft-ietf-acme-ari. `certificate_id` builds the
identifier from the certificate's own authority key identifier and serial
number, `request_url` joins it to the directory's `renewalInfo` base, and
`parse` validates the suggested window before retaining it. The window is
advice, not an instruction: one that is inverted, unparseable, or absent leaves
the caller on its own policy.

`renewal` owns no clock, no timer, and no randomness. Every decision is a pure
function of the caller's supplied reading, the certificate's own lifetime, the
authority's advice, and an injected random source, so a deployment and a test
see identical behaviour.

The authority's window wins when it is usable, because it is the only party
that knows about a mass revocation, and it is still clamped to the
certificate's own lifetime so a wild suggestion cannot schedule a renewal after
expiry. Without usable advice, renewal is planned a policy lead before expiry
and spread with jitter so a fleet does not renew in lockstep.

Urgency comes from the certificate's lifetime rather than only the planned
instant, so a certificate inside its renewal lead is due even if the clock
drifted. A schedule that is backing off is excluded from that shortcut, which
is what keeps an expiring certificate that keeps failing from retrying without
pause. Retries back off within a ceiling and count against a fixed budget, and
a clock that moved backwards past the tolerated skew is replanned rather than
fired. Every state change is reported to an observer, and cancellation is
terminal.

`select_next` picks the certificate closest to expiry among those actually
ready, so expiring certificates get priority without a backing-off one being
selected before its delay elapses.

## Record literals

A record literal leaves every field it does not name holding the previous stack
frame's contents rather than zero, which covers `T{}` as well as any partial
form (briar-systems/mach#3108). Clearing a record that holds callbacks or
pointers with a literal therefore does not clear it.

Name every field of every literal. A record containing an array cannot satisfy
that, because an array field cannot be named in a literal at all, so those are
built by declaring `var value: T;` — which does zero the whole record including
its arrays — and assigning each field. `nonce.no_pool` and `client.no_limits`
return a value cleared by declaration, and `client.release` copies from them
rather than assigning a literal.

`briar-systems/mach-tls` carries `tools/partial_literal_sweep.py`, which
enumerates any literal that breaks the rule; it reports zero for this
repository.
