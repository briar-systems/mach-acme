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

## Replay nonce ownership

A `nonce.Pool` owns copies of available nonces. The supplied memory implementation
uses fixed caller storage and rejects empty, oversized, non-base64url, duplicate,
and over-capacity values. Its `Memory`, slot array, and complete declared byte
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
