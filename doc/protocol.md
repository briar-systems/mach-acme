# ACME protocol contract

This document defines the ownership and failure rules for directory discovery and
signed ACME requests. The protocol layer does not own sockets, connections, clocks,
or account private-key storage.

## Directory discovery

`client.discovery_request` produces a replay-safe GET description. The caller
executes it through a transport and passes a bounded `client.Response` to
`client.parse_directory`.

Parsing requires HTTP 200, a strict UTF-8 JSON object, unique decoded member names,
and HTTPS URLs for `newNonce`, `newAccount`, and `newOrder`. Optional `newAuthz`,
`revokeCert`, `keyChange`, `renewalInfo`, terms, website, CAA identities, and the
external-account requirement are retained. Unknown members are ignored as RFC 8555
requires.

The caller supplies JSON scratch, text storage, and a CAA view array. Successful
views point into the caller's text storage. Any parse, type, limit, or capacity
failure leaves the output record and text storage unchanged.

## Account keys and JWS

`jose.Signer` contains public key material and bounded output dimensions only.
Private keys are passed separately as `jose.PrivateKey` for each signing operation.
This keeps durable key ownership with the application or its secret provider.

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

RSA-PSS asks the supplied entropy provider for exactly 32 secret bytes. An absent or
failing provider returns `ENTROPY_UNAVAILABLE`. Salt storage is zeroed before and
after the provider and after signing. Signing work and final output must not overlap.
Capacity, key, entropy, or encoding failure leaves the final output unchanged.

## Replay nonce ownership

A `nonce.Pool` owns copies of available nonces. The supplied memory implementation
uses fixed caller storage and rejects empty, oversized, non-base64url, duplicate,
and over-capacity values.

Taking a nonce copies it to caller storage and then wipes and retires its slot. The
newest available nonce is selected. A small destination does not consume or modify
the stored nonce. Clearing the pool wipes every slot.

`client.prepare_signed` consumes a nonce before signing. Once handed to a signing
attempt, that nonce is never returned to the pool, including when local signing
fails. This conservative ownership rule prevents accidental replay across callers.

Every successful ACME response may contribute one `Replay-Nonce`. Duplicate header
fields are rejected. A `badNonce` response first discards all stale nonces, then
stores its fresh response nonce when present. If absent, the state machine requests
a HEAD acquisition. Retry count is bounded by `Limits.max_bad_nonce_retries`.
Exhaustion retains the last structured ACME and HTTP cause while returning
`RETRY_LIMIT`.

## Signed-request state

`SignedRequest` transitions are explicit:

- `REQUEST_READY` or `REQUEST_RETRY` can be prepared
- preparation without a nonce enters `REQUEST_NEEDS_NONCE`
- successful preparation enters `REQUEST_AWAITING`
- a successful response enters `REQUEST_COMPLETE`
- a recoverable `badNonce` enters `REQUEST_RETRY` or `REQUEST_NEEDS_NONCE`
- any terminal protocol or transport-response failure enters `REQUEST_FAILED`

The caller must not replay a POST body after an ambiguous transport failure. The
wire description marks signed POSTs as not replay safe. Higher account and order
layers decide whether a new ACME request is valid after consulting their operation
state.

## Bounds and lifetimes

`client.Limits` bounds request bodies, response bodies, problem bodies, URL and
nonce lengths, JSON scratch, JSON depth, JSON values, JSON key lengths, CAA entries,
retry count, and the transport timeout policy value. The caller's actual buffers may
set tighter bounds.

Response bodies and fields need only remain alive for the accepting call, except
that `Error.http.body` retains the supplied view. Directory and parsed problem views
point into their explicit storage records. A JWS output remains caller-owned. Work
storage contains public canonical and signature bytes and can be reused after the
operation returns.

## Error mapping

Local errors retain a domain and stable code. Rejected non-ACME responses retain
status, body, retry delay, and retryability. Valid ACME problem documents additionally
retain type, title, detail, instance, and problem status. Malformed or oversized
problem documents retain the original HTTP cause while reporting the precise parse
or capacity code. The exact RFC badNonce URN maps to `BAD_NONCE`.

## Validation sources

The protocol test project includes the RFC 7638 RSA thumbprint example, the RFC 8032
Ed25519 signing vector, RFC 8555 protected-header material, an independently
generated OpenSSL RSA-PSS key fixture, hostile JSON and nonce cases, and a captured
Let's Encrypt staging directory response. The staging fixture keeps routine tests
deterministic. Live execution belongs to the future transport integration suite.
