# ACME protocol contract

This document defines the ownership and failure rules for directory discovery and
signed ACME requests. The protocol layer does not own sockets, connections, clocks,
or account private-key storage.

## Directory discovery

`client.discovery_request` validates the bootstrap URL and produces a
replay-safe GET description. The caller executes it through a transport and
passes a bounded `client.Response` to `client.parse_directory`.

Every successful `WireRequest` carries the configured timeout and maximum
response body size. A constructor failure is retained in `WireRequest.error` and
must not be sent. URLs are bounded HTTPS absolute URIs without fragments,
userinfo, controls, malformed percent escapes, or non-ASCII wire bytes. The HTTPS
scheme is matched case insensitively and accepted URL bytes are retained exactly.
This narrow local check will be replaced by the shared client URL and authority
policy from `mach-http` issue 11 when transport integration lands.

Parsing requires HTTP 200, a strict UTF-8 JSON object, unique decoded member names,
and HTTPS URLs for `newNonce`, `newAccount`, and `newOrder`. Optional `newAuthz`,
`revokeCert`, `keyChange`, `renewalInfo`, terms, website, CAA identities, and the
external-account requirement are retained. Unknown members are ignored as RFC 8555
requires.

The caller supplies JSON scratch, text storage, and a CAA view array. Successful
views point into the caller's text storage. Any parse, type, limit, or capacity
failure leaves the output record and text storage unchanged.

All declared byte and item ranges must be mathematically representable. JSON
input, response bodies and fields, scratch, text storage, item arrays, and output
records must not overlap where parsing writes through either view. Alias failures
are rejected before output storage is changed.

## Account keys and JWS

`jose.Signer` contains public key material and bounded output dimensions only.
Private keys are passed separately as `jose.PrivateKey` for each signing operation.
Each private key also carries a non-null opaque `secret_owner` identity. This keeps
durable key ownership with the application or its secret provider without
declassifying a secret-qualified address.

Supported account algorithms are:

- `ES256`, using an uncompressed P-256 public key and a 32-byte private scalar
- `EDDSA`, using an Ed25519 public key and a 32-byte private seed
- `PS256`, using a bounded RSA public/private key and caller-provided entropy

Public/private pairs are validated before signing. P-256 and Ed25519 public points
receive strict cryptographic validation. RSA modulus and exponent constraints are
checked before use.

JWK members use RFC 7638 lexicographic order. Protected headers use the fixed order
`alg`, then `jwk` or `kid`, then `nonce`, then `url`. Base64url values are unpadded.
The flattened JWS object uses the fixed order `protected`, `payload`, `signature`.

RSA-PSS asks the supplied entropy provider for exactly 32 secret bytes. Callers
construct this boundary with `jose.entropy_provider` or `jose.no_entropy`. A
provider supplies public and secret ownership predicates plus a post-callback
validation function. Those callbacks and their contexts remain valid and
immutable for the operation. Any declared overlap with the message, output,
public key, protocol state, or salt destination fails before entropy is requested.
The private RSA exponent is included in the secret ownership checks. The message
and bound ACME inputs are checked again after the callback. An absent
or failing provider returns `ENTROPY_UNAVAILABLE`. A provider that changes an
input or fails post-callback validation returns `INVALID_INPUT` before final
output is published. Salt storage is zeroed before and after the provider and
after signing. Signing work and final output
must not overlap each other, the payload, protected header views, or public key
storage. JWK, thumbprint, and signature outputs must not overlap their public
inputs. Secret-qualified key storage cannot alias public mutable buffers in
well-typed Mach code. Capacity, key, entropy, alias, or encoding failure leaves
the final output unchanged.

Outer ACME requests explicitly include a nonce. The same encoder can omit it for
the nested JWS required by account key rollover. A protected header cannot both
select a JWK and retain a `kid`.

## Account lifecycle

`account.encode` writes complete bounded payloads for account creation, existing
account lookup, contact replacement, terms agreement, and deactivation. Creation
may embed a successful `external_account.Operation`. Raw external-binding JSON is
not accepted. The returned `account.Operation` binds the exact output view and
SHA-256 payload digest, so it cannot authorize changed bytes. Contact values must
be nonempty ASCII URI values. A `mailto` contact contains exactly one address and
cannot contain a second address, header fields, or a fragment. Output is published
only after the complete payload has been validated and encoded. The output cannot
overlap the contact view array, contact bytes, or external binding bytes.

`account.begin` accepts the matching successful `account.Operation` and exact
signer, uses the directory `newAccount` URL and a JWK for creation and lookup, and
rejects an action, payload, external-binding identity, or signer mismatch. Updates
require the same account URL as request endpoint and protected `kid`.
`account.parse` accepts HTTP 200 or 201 and requires a strict account object with
a known status, bounded contacts, and an HTTPS orders URL. JSON scratch, response
storage, contact views, output, response fields, response body, and the retained
account URL are range-checked and disjoint. Creation requires exactly one HTTPS
`Location` field and copies it into account storage. Existing-account responses
retain the caller's known account URL. Other parsed views point into caller-owned
storage. Creation, contact update, and terms agreement require a `valid` account.
Deactivation requires `deactivated`. Lookup may recover any defined account
status. Validation and capacity failures do not publish an account or change text
storage.

External account bindings are encoded internally rather than delegated to an
unverifiable callback. `external_account.Binding` selects HS256 or HS384 and
carries a secret-qualified MAC key bounded by `MAX_MAC_KEY_BYTES`. Its
`secret_owner` is a secret-qualified pointer and must equal the exact MAC-key
pointer. The
protected header binds `alg`, `kid`, and the exact `newAccount` URL. Its payload is
the canonical JWK of the new account key. Work and output storage cannot overlap
each other, public key bytes, the key ID, or URL. HMAC tag-capacity failures map to
`OUTPUT_TOO_SMALL`, not a signing failure. Final output is transactional. The
returned operation binds the output digest, MAC algorithm, URL digest, and account
key thumbprint for the enclosing account request.

## Durable credentials and key rollover

`account.Credentials` binds an account representation, public signer, opaque
private-key owner, and nonzero generation. The opaque identity allows a secret
provider to retain every supported private-key shape without exposing a public
pointer to secret storage.

`storage.Manager` wraps an application durable store. Each store supplies a
`storage.Gate` inside its provider context. All managers for that store share the
gate, so callback serialization and the one-active-transaction rule hold across
manager instances. Managers are location-bound and copying one invalidates the
copy. A replacement transaction
checks the expected credential generation, stages the complete next credential,
then commits or aborts by an exact provider token and credential digest. The
manager admits one active transaction and rejects forged, stale, or reused writes.
Commit and abort distinguish `STORAGE_CONFLICT`, `STORAGE_FAILED`, and
`STORAGE_UNKNOWN`. `storage.recover` returns the durable current credential and
any pending replacement, registers that exact transaction in a fresh manager, and
allows restart and ambiguous wire outcomes to be reconciled without guessing
which key is active. `storage.resume` converts a validated pending snapshot to the
exact write accepted by the remaining lifecycle operation. Same-generation saves
may commit while staged or recovered. Next-generation replacements may commit
only after a wire attempt or explicit recovered-replacement authorization.

`storage.begin_save` uses expected generation zero for the first account record
and the current generation for contact, terms, status, or other account metadata
updates. `storage.begin_replace` is reserved for key changes and requires the next
generation while preserving the exact account representation. An interrupted
initial save is recoverable as a pending generation-one credential even though no
current record exists yet.

Each `storage.Store` declares the complete representable provider context through
`context_anchor` and `context_size`, with both `ctx` and the zero-initialized
`gate` located inside that range. The first manager permanently binds the gate to
the complete callback descriptor. The
provider must classify that complete range as owned and must never classify the
manager, caller outputs, rollover work, or rollover output as owned. Transaction
tokens are nonzero, globally monotonic for the lifetime of the durable store, and
persist across commits, aborts, and process restarts. A successful `begin` creates
an active transaction. `abort` must accept it before or after staging. Only
`SUCCESS` proves rollback. Any other status leaves recovery responsible for the
transaction.

Every store callback is serialized through the provider's shared gate.
Same-thread reentrancy is rejected before a
nested callback can run. The callback descriptor is snapshotted, so direct
mutation cannot redirect a later validation or cleanup call. Readiness, opaque
secret ownership classification, exact credential descriptors and digests,
transaction shape, and load output shape are checked around callbacks. The store
must own every returned public credential range and recognize its opaque secret
owner, but it may not own the manager, caller's output record, or transient load
record. Ownership and readiness callbacks must not mutate returned snapshot
metadata or child descriptors.

`key_change.prepare` durably stages the candidate before publishing any rollover
payload. It encodes the RFC 8555 inner payload containing the account URL and old
JWK, then signs a nonce-free nested JWS with the new ES256, EdDSA, or PS256 key.
The prepared value binds the exact nested JWS bytes, both endpoint URLs, both old
and replacement key thumbprints, the complete replacement credential, and the
credential generation. Identical old and replacement keys are rejected.
`key_change.begin_outer` takes the storage manager, consumes the exact staged
replacement, submits that object under the old account `kid`, and binds the outer
request to the old signer. A local client-begin failure returns the replacement to
the staged state. Accepted responses commit, rejected responses
abort, and ambiguous outcomes retain the pending transaction for explicit
recovery. Work and output are proven disjoint from the complete store context and
manager before and after staging. A local encoding or signing failure requests an
abort before any nested JWS is published. If rollback is not proven successful,
the exact transaction remains recoverable.

The conformance suite includes an atomic filesystem-backed account store. It
verifies restart recovery, persisted monotonic transaction tokens, exact pending
writes, and rejection of truncated durable records without publishing a partially
modified recovery output.

## Orders and authorizations

`order.encode` measures the complete bounded `newOrder` payload before writing
to caller output, so every admitted request is representable. Identifier
admission is an explicit `identifier.Policy`. Wildcards are admitted because
RFC 8555 defines them; IP identifiers are not, because RFC 8738 support is
optional and many authorities reject them. A wildcard is only a leftmost `*.`
label over a valid RFC 1123 name. Duplicate identifiers are rejected before the
order is created, because the returned authorization list would be ambiguous.
Timestamps are bounded RFC 3339 instants. Output cannot overlap the identifier
array, identifier bytes, or the timestamp views.

`order.begin_new` binds the exact payload digest and submits under the account
`kid`. `order.begin_fetch` is the POST-as-GET read: an empty payload
authenticates a read of an order or authorization and requires an account URL.

`order.parse` accepts HTTP 201 with exactly one HTTPS `Location`, or HTTP 200
against a caller-supplied known order URL. It requires a known order status, a
nonempty identifier array, an authorization array, and an HTTPS finalize URL.
The certificate URL must be present exactly when the order is `valid`. Parsed
identifiers are re-validated against the caller's policy, so an authority that
echoes a wildcard a deployment forbade is rejected rather than accepted.

`order.parse_authorization` requires a known authorization status, an
identifier object, and a bounded nonempty challenge array. The authority names
the base domain and flags the wildcard separately, so the identifier is
validated without the wildcard label. A challenge whose type this build does
not implement is retained with a zero kind and is simply not selectable; it
does not fail the authorization. Tokens are validated as bounded base64url for
every implemented challenge type.

An embedded RFC 7807 `error` object on an order or a challenge is bounded and
copied into caller text storage, so a partial failure survives the response
that carried it. A value that decodes cleanly but does not fit the caller's
storage is a capacity failure, not a malformed document, and the two are
reported with distinct codes. JSON scratch, text storage, item arrays, output
records, the known resource URL, and the response body and fields are
range-checked and pairwise disjoint. Any parse, type, limit, policy, or
capacity failure leaves the caller's output record unchanged.

## Order polling

Polling is a decision, not a loop. The library owns no clock and no timer.
`order.poll_next` receives the current status, the target status, the
authority's Retry-After in seconds, and a caller-supplied monotonic reading,
and returns exactly one of wait, ready, terminal, deadline, cancelled, or
limit.

Retry-After is honoured when it exceeds the local backoff floor, and every wait
is clamped to the policy ceiling, so a hostile or mistaken advisory cannot
produce an unbounded wait. Backoff doubles from the floor and saturates at the
ceiling without overflowing. A wait that would pass the absolute deadline is
refused rather than truncated, and the attempt counter is not advanced by a
decision that produced no wait. Cancellation is checked before any status
interpretation. A terminal status that is not the target is reported distinctly
from reaching the target, so an order that went `invalid` is never mistaken for
success.

## Challenges

`challenge.key_authorization` computes the RFC 8555 section 8.1 value by
deriving the account key's RFC 7638 thumbprint internally. The caller supplies
the challenge and the signer, never a thumbprint, so a challenge cannot be
answered with a key the account does not hold. Output cannot overlap the token
or the public key, and a capacity failure publishes nothing.

Derived data is exact and bounded:

- HTTP-01: the `/.well-known/acme-challenge/<token>` path, with the key
  authorization as the response body
- DNS-01: the `_acme-challenge.<base domain>` record name and the
  `base64url(SHA-256(keyAuthorization))` value. A wildcard order is validated
  against its base domain, so the record name never carries the wildcard label.
- TLS-ALPN-01: the RFC 8737 section 3 `SHA-256(keyAuthorization)` digest and the
  DER `OCTET STRING` that carries it as the `acmeIdentifier` extension value.
  The caller builds the self-signed certificate and marks that extension
  critical.

Every key authorization is re-validated before it is used as digest input, so a
malformed value never reaches a hash or a provider.

`challenge.Attempt` binds one presentation to one provider and one location.
Cleanup is owed exactly when presentation succeeded. A provider that declines
the challenge through `supports` is never asked to present. A presentation that
returned a failure owes no cleanup, because a provider that could not publish
is responsible for its own partial state.

`challenge.finish` is the single exit for success, failure, timeout, and
cancellation. It invokes cleanup exactly once and is idempotent afterwards: a
repeated call is accepted and does not reach the provider again. A cleanup that
fails reports that failure and is still never repeated, so a provider cannot be
asked to withdraw the same state twice. The presentation and cleanup call
counters are public so exactly-once is observed rather than inferred. Provider
callbacks are serialized and same-thread reentrancy is rejected before a nested
callback can move the attempt.

`challenge.begin_respond` submits the RFC 8555 section 7.5.1 empty JSON object
to the challenge URL under the account `kid`, and rejects any other payload.

## DNS propagation

Observing a published record is a caller policy, not a library timer.
`challenge.Probe` carries an injectable observation callback, so a deployment
supplies a resolver and a test supplies a deterministic answer. Each
`propagation_next` performs exactly one observation. Confirmations must be
consecutive: a record that appears and then disappears restarts the count
rather than proceeding. The wait is bounded by the shared poll policy's attempt
ceiling, delay ceiling, and absolute deadline, and cancellation is honoured
before any observation is made.

## Bounded waiting

`acme.poll` holds the single wait policy that orders, challenges, and renewal
share, so the three can never drift apart. It is status agnostic: callers
reduce their own vocabulary to `reached` and `terminal`.

Retry-After is honoured when it exceeds the local backoff floor, and every wait
is clamped to the policy ceiling, so a hostile or mistaken advisory cannot
produce an unbounded wait. Backoff doubles from the floor and saturates without
overflowing. A wait that would pass the absolute deadline is refused rather
than truncated, and a decision that produced no wait does not advance the
attempt counter. Cancellation is checked before any status interpretation, and
a terminal status that is not the target is reported distinctly from reaching
the target.

## Certificate requests

`certificate.encode_csr` writes a complete RFC 2986 certification request. The
subject is an empty `Name`, because an ACME certificate is identified entirely
by its subjectAltName entries. DNS identifiers are written as `dNSName` and IP
identifiers as `iPAddress` with the address packed to four or sixteen octets.
Entries appear in the caller's identifier order.

The DER writer fills its buffer from the end toward the front, so wrapping a
finished child is a prepend and no length needs a second measuring pass.
Lengths use the minimal form, and a length that cannot be represented fails
rather than truncating.

The library never holds the certificate key. The caller's `SignFun` receives
the exact certification request info bytes and returns a signature. Its context
is a plain pointer, so secret memory cannot reach it. After signing, the
request info is re-encoded and compared, so a signer that disturbed its input
publishes nothing. The returned signature is validated against the shape its
algorithm names: the RFC 3279 DER sequence of two positive integers for ECDSA,
sixty-four octets for Ed25519, and one modulus-sized block for RSA. Work and
output storage must be disjoint from each other and from the public key.

## Issued certificates

`certificate.parse_certificate` uses a strict forward DER reader that rejects
high-tag-number form, indefinite length, and non-minimal lengths. It decodes
only the fields an ACME decision depends on: the subjectAltName entries and the
validity window. Times are RFC 5280 `UTCTime` through 2049 and
`GeneralizedTime` after, both zulu with seconds present. A certificate carrying
more than one subjectAltName is rejected. General names other than `dNSName`
and `iPAddress` are ignored, because no ACME identifier can produce them.

`certificate.verify_issued` parses the leaf and requires it to cover exactly
the requested identifiers. DNS names compare case insensitively; an IP
identifier's text is packed and compared against the certificate's raw octets.
A certificate that omits a requested name, or carries a name that was not
ordered, is refused. Callers run this before anything is written to durable
storage, so a mismatched certificate never becomes the stored one.

`certificate.parse_chain` decodes an `application/pem-certificate-chain` body
into caller storage. Content outside a PEM block, an unterminated block, an
empty block, and a body that does not fit the caller's storage all fail without
publishing a chain. Decoded certificates point into caller storage, never into
the response.

`certificate.parse_alternates` reads RFC 8288 `Link` headers and retains only
`rel="alternate"` targets. Each is validated as an HTTPS URL and copied into
caller storage, so an alternate outlives the response fields it came from.

`encode_finalize` and `encode_revoke` write the RFC 8555 section 7.4 and 7.6
payloads exactly, with base64url and no padding. Revocation admits only the CRL
reasons ACME defines. `begin_revoke` selects the account `kid` or the
certificate key's JWK, which is the only way to revoke when the account that
ordered the certificate is gone.

## Durable record kinds

`storage.RecordKind` is the axis durable state grows along. Account credentials
and certificates share the gate, the monotonic token sequence, the
one-active-transaction rule, callback serialization, and same-thread reentrancy
rejection. They differ only in the staged payload and its ownership rules, so
adding a record kind does not rebuild the transaction layer.

A `storage.Store` declares which record kinds it holds. Certificate callbacks
are either both present or both absent; a half-declared record kind is a
configuration error. A store that declares none refuses certificate
transactions rather than half-supporting them.

`begin_replace_certificate` checks the expected generation, so a concurrent
renewal cannot overwrite a newer record. The staged record's digest binds the
storage key, certificate URL, complete chain bytes, chain length, private-key
owner identity, every identifier, the validity window, and the generation, so a
record changed between staging and commit is detected as a conflict. A
transaction the store opened but could not stage stays recoverable rather than
being silently dropped. `recover_certificate` returns the durable record and
any pending replacement and registers that exact transaction in a fresh
manager; `resume_certificate` converts it to the exact write commit will
accept.

## Durable documents

Every durable record is one self-describing document. The header carries a
magic, a schema version, the record kind, a reserved field, the payload length,
and a SHA-256 of the payload. A reader validates all of them before publishing
any payload, so a truncated, corrupt, foreign, or future-versioned document is
reported rather than partly believed. A document written by an older schema is
readable and reported through `needs_migration`, so migration is deliberate
rather than a reader guessing at a layout.

`write_document` replaces atomically: the replacement is written to a sibling
temporary, flushed, closed, and renamed, and the parent directory is flushed
after. A reader therefore sees either the previous committed document or the
complete new one. A write that fails at any point before the rename leaves the
previous document exactly as it was, which is the path an exhausted disk also
takes. Files are created owner-only and their directories owner-only, because
durable ACME state includes account keys.

`copy_document` validates the source completely before writing the
destination, so a backup cannot capture a corrupt document and a restore cannot
install one.

## The file-backed store

`file_store.Store` implements the durable store contract for both transactional
record kinds, holding one document per kind. The document records the committed
record, any pending replacement, and the transaction that staged it, so a
restart sees exactly what was in flight.

The transaction token is persisted before it is handed out, so the sequence
stays globally monotonic across a restart even if nothing is ever staged
against that token. The expected generation is enforced durably: `begin`
compares it against what is committed under that key and returns `CONFLICT` on
a mismatch, so a writer working from a stale read is refused rather than
overwriting a newer record. That check is what makes two writers over one store
safe, and it holds across manager instances, threads, and processes.

A staged record is copied into the store's own slots so it survives a restart.
The caller's own bytes are adopted for the life of the transaction, so the
manager's ownership checks can be answered truthfully while the durable copy is
what actually persists.

The private key is never written to disk. The store persists public credential
material and one opaque key identity, and the application's secret provider maps
that identity back to its key material. A store's declared ceilings on URLs,
contacts, keys, chains, and identifiers are refusals, not truncations: what is
written is always what can be read back.

## Renewal information

`renewal_info.certificate_id` builds the draft-ietf-acme-ari identifier from
the certificate's own authority key identifier and serial number, base64url and
unpadded, over the exact DER octets. `request_url` joins it to the directory's
`renewalInfo` base without doubling a trailing slash and re-validates the
result as an HTTPS URL. The request is an unauthenticated GET.

`renewal_info.parse` requires HTTP 200 and a suggested window whose start and
end are RFC 3339 instants, accepting a fractional second and a numeric offset,
and requires the window to end after it starts. Any Retry-After the authority
sent is retained alongside it. A window that is inverted, unparseable, or
absent is reported rather than retained, so the caller falls back to its own
policy instead of acting on advice that was never understood.

## Renewal scheduling

The scheduler owns no clock, no timer, and no randomness. Every decision is a
pure function of the caller's supplied wall-clock reading, the certificate's
lifetime, the authority's advice, and an injected random source. Randomness is
injected rather than drawn, so a fleet spreads its renewals while a test stays
deterministic.

The authority's window wins when it is usable, because it is the only party
that knows about a mass revocation, and a time is drawn uniformly within it.
The window is still clamped to the certificate's own `notBefore` and
`notAfter`, so a wild suggestion cannot schedule a renewal after expiry or
before the certificate exists. Without usable advice the target is a policy
lead before expiry, spread by jitter, and never at or after expiry.

Scheduling state is derived entirely from the durable certificate record and
the policy, so a restart replans to a schedule of the same shape rather than
needing its own durable copy.

Urgency comes from the certificate's own lifetime, not only from the instant
that was planned, so a certificate inside its renewal lead is due even if the
clock drifted back a little. A schedule that is backing off is excluded from
that shortcut; otherwise an expiring certificate that kept failing would retry
without pause, which is exactly the unbounded loop the contract forbids.

A failed attempt backs off by doubling within a ceiling, adds jitter without
passing that ceiling, and counts against a fixed attempt budget. Exhausting the
budget is terminal, so a prolonged outage produces a bounded number of widely
spaced attempts. A clock that moved backwards further than the tolerated skew
is not evidence that a renewal is due: the schedule is replanned from the new
reading rather than firing, so a corrected clock cannot cause a renewal storm.

Every state change is reported to an observer with the previous and current
state, the attempt count, the next run, and the cause. Cancellation is
terminal and cannot be undone or replanned.

`select_next` picks the certificate closest to expiry among those actually
ready. A schedule that is backing off is not ready until its delay elapses, so
urgency cannot turn into a spin, and the most urgent certificate regains
priority once its backoff passes.

## Replay nonce ownership

A `nonce.Pool` owns copies of available nonces. The supplied memory implementation
uses fixed caller storage and rejects empty, oversized, non-base64url, duplicate,
and over-capacity values. Duplicate detection covers every live available or
reserved nonce, including while another thread holds a reservation. Its `Memory`,
slot array, and complete declared byte
store must be mathematically representable and pairwise disjoint. Put inputs and
reservation outputs cannot alias any of those regions. Alias and range failures occur
before a nonce is copied, consumed, or wiped.

The memory implementation serializes put, reserve, commit, release, and clear
operations with its
embedded mutex. Initialization and release require exclusive ownership. Release
wipes the complete declared backing store and makes existing pool handles fail
readiness validation before the storage can be initialized again. Sequence
exhaustion fails closed until the pool is cleared.

Reserving a nonce copies the newest available value to caller storage and marks its
slot unavailable to other reservations. Commit wipes and retires exactly that
reservation. Release makes exactly that reservation available again with its
original ordering. Invalid, repeated, or foreign transaction tokens fail without
changing another slot. A small destination does not reserve or modify the stored
nonce. Clearing the pool wipes available and reserved slots and invalidates their
tokens without reusing their transaction identities. `nonce.take` is a convenience
operation that reserves and immediately commits through the same contract.

`Client` copies the `Pool` callback descriptor during initialization. The source
descriptor therefore need not remain alive, but its `ctx` and the storage behind
that context must remain valid until client release. The descriptor includes an
immutable ownership predicate for every byte range owned by the provider. The
descriptor also includes `owns_secret(ctx, owner)`. It accepts the opaque owner
identity carried by a private key, so providers can declare arbitrary secret
ownership domains without receiving or declassifying secret addresses. The
predicates, callback pointers, dimensions, owned regions, ownership domains, and
their backing state
must not change until release. Client state, request state, signing inputs, work,
output, callback inputs, and callback outputs are checked against that predicate
before the corresponding callback boundary. Callback pointers, dimensions, and
readiness are checked at initialization and every callback boundary. A reservation
is accepted only when it has a nonzero token, identifies the exact supplied output
buffer, has a bounded nonzero base64url length, and is internally consistent with
its error and `found` fields. Readiness, ownership, reserve, commit, release, put,
and clear callbacks must not mutate the bound `Client` or `SignedRequest`.
`Client.callback_owner` rejects same-thread reentrant client operations before they
can change protocol state and serializes callback boundaries across threads.
Post-callback validation still rejects direct mutation. Such
mutation fails closed and is never overwritten by the protocol layer.

`client.prepare_signed` reserves a normal pool nonce before signing. A local
signing or capacity failure releases it, so an attempt that produced no wire body
does not destroy a credential. Successful signing commits the reservation before
the output view is published. A commit or release failure terminalizes the request,
publishes no body, and wipes any encoded prefix after a failed commit. A nonce reserved for a
specific `badNonce` recovery stays attached to that request across local signing
failure because no wire request was emitted. It never becomes available to a
different request.

Every successful ACME response may contribute one `Replay-Nonce`. A `badNonce`
response first discards all stale shared nonces, then copies its fresh response
nonce into the exact `SignedRequest` that received the response. Clearing the
shared pool does not disturb recovery nonces already reserved by other requests.
If absent, the state machine requests a HEAD acquisition and binds that response's
nonce to the waiting request. Retry count is bounded by
`Limits.max_bad_nonce_retries`.
Exhaustion retains the last structured ACME and HTTP cause while returning
`RETRY_LIMIT`.

Invalid or repeated response nonce fields are ignored as RFC 8555 requires.
Optional fresh nonces are also ignored when the bounded pool is already full.
The completed POST result is never converted into a failure merely because an
additional nonce could not be retained.

## Signed-request state

`SignedRequest` transitions are explicit:

- `REQUEST_READY` or `REQUEST_RETRY` can be prepared
- preparation without a nonce enters `REQUEST_NEEDS_NONCE`
- successful preparation enters `REQUEST_AWAITING`
- a successful response enters `REQUEST_COMPLETE`
- a recoverable `badNonce` enters `REQUEST_RETRY` or `REQUEST_NEEDS_NONCE`
- any terminal protocol or transport-response failure enters `REQUEST_FAILED`

Each request is bound to the exact initialized `Client` generation that began it.
Foreign clients, double initialization, and requests retained across client release
and reinitialization fail before consuming a nonce, exposing a wire body, or
accepting a response.

`begin_signed` records SHA-256 bindings for the exact URL, payload, and `kid`
bytes. The caller retains their storage but grants the request immutable access
through completion or failure. Preparation checks the bindings before and after
nonce and entropy callbacks. `signed_wire` checks them again, so changing any
borrowed input before preparation or after a body is prepared fails closed. The
transport URL can never diverge from the URL protected by the JWS.

`begin_signed_bound` additionally records the exact signer thumbprint. Account
and key-rollover request constructors use this path. `prepare_signed` rejects a
different signer before consuming a nonce and checks the thumbprint again after
signing callbacks before publishing a body.

Both signed-response and nonce-response acceptance check those bindings before
parsing or invoking a provider. Once a final signed response is admitted, every
terminal shape, alias, parse, provider, or policy failure clears the retained wire
body and enters `REQUEST_FAILED`. A failed response callback can therefore never
leave a replayable POST body behind.

The caller must not replay a POST body after an ambiguous transport failure. The
prepared request retains the exact output view accepted by signing. `signed_wire`
does not accept a replacement body and clears that view when the response is
accepted. The wire description marks signed POSTs as not replay safe. Higher account and order
layers decide whether a new ACME request is valid after consulting their operation
state.

## Bounds and lifetimes

`client.Limits` bounds request bodies, response bodies, problem bodies, URL and
nonce lengths, JSON scratch, JSON depth, JSON values, JSON key lengths, CAA entries,
duplicate-key comparison work, problem subproblems, response header fields, retry count, and the transport
timeout policy value. The caller's actual buffers may set tighter bounds.

`max_request_bytes` bounds the complete flattened JWS body, not only its raw
payload. `prepare_signed` narrows the output capacity to that policy before the
transactional encoder runs. The body view retained by `SignedRequest` remains
valid only while the caller keeps the accepted output buffer alive and unchanged.
Signing buffers and parser storage must also be disjoint from `Client`,
`SignedRequest`, and nonce-pool state. Invalid aliases fail before a stored nonce
is consumed or an awaiting request loses its exact prepared body.

JSON number grammar is checked before the pinned tree parser is entered. Leading
zeroes, truncated fractions or exponents, and integer parts outside the parser's
signed 64-bit accumulation range are rejected. `max_json_key_comparisons` bounds
decoded duplicate-member detection independently of byte and value limits, so a
large object cannot turn a bounded response into unbounded quadratic work.
Range-size output records and JSON object records are themselves checked as full
representable ranges before write or dereference, including at the maximum address.

Response bodies and fields need only remain alive for the accepting call, except
that `Error.http.body` retains the supplied view. Directory and parsed problem views
point into their explicit storage records. A JWS output remains caller-owned. Work
storage contains public canonical and signature bytes and can be reused after the
operation returns.

Malformed or oversized body views are never retained in `Error.http.body`. Their
status and retry delay remain available, but the rejected view is replaced with an
empty view so callers cannot accidentally dereference out-of-policy memory.

## Error mapping

Local errors retain a domain and stable code. Rejected non-ACME responses retain
status, body, retry delay, and retryability. Valid ACME problem documents additionally
retain type, title, detail, instance, problem status, and bounded structured
subproblems with their identifiers. Malformed or oversized problem documents
retain the original HTTP cause while reporting the precise parse or capacity
code. The exact RFC badNonce URN maps to `BAD_NONCE`.

## Validation sources

The protocol test project includes the RFC 7638 RSA thumbprint example, the RFC 8032
Ed25519 signing vector, RFC 8555 protected-header material, an independently
generated OpenSSL RSA-PSS key fixture, hostile JSON and nonce cases, and a captured
Let's Encrypt staging directory response. The staging fixture keeps routine tests
deterministic. Live execution belongs to the future transport integration suite.
