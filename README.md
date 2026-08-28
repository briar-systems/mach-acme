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

- `mach-std` v0.33.0
- `mach-http` v0.4.1
- `mach-crypto` v0.6.0

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

The harness runs `pebble`, its challenge test server, and a plain-HTTP front
end on loopback. `mach-acme` emits typed HTTPS wire requests and TLS
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
