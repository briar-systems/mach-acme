# mach-acme

`mach-acme` provides lightweight, bounded ACME protocol components for Mach. The
directory, JOSE, replay-nonce, signed-request, and structured problem foundations
are implemented. Account, order, challenge, certificate, and renewal contracts
remain separate so applications can choose their storage and deployment systems.

The library does not pretend to be a network client. It produces typed HTTP
requests and accepts typed HTTP responses. A future `mach-http` client transport
will execute those requests without changing the ACME state machine or key
ownership contract.

## Implemented

- strict bounded ACME directory discovery with all RFC 8555 endpoints and metadata
- canonical EC, OKP, and RSA JWK encoding and RFC 7638 SHA-256 thumbprints
- canonical flattened JWS with ES256, EdDSA, and PS256 account keys
- separate public signer metadata and caller-owned private keys
- caller-provided entropy for RSA-PSS with explicit salt zeroization
- bounded one-use replay nonce storage with deterministic newest-first selection
- signed-request state and bounded `badNonce` recovery
- structured local, HTTP, and ACME problem causes
- caller-owned JSON scratch, output storage, signing work, and wire buffers

## Protocol boundary

The transport-independent path is:

1. Create `client.discovery_request` and execute the returned GET.
2. Convert the transport result to `client.Response` and call
   `client.parse_directory`.
3. Execute `client.nonce_request` when no replay nonce is available.
4. Initialize a `client.SignedRequest` with `client.begin_signed`.
5. Call `client.prepare_signed`, which consumes one stored nonce and writes a JWS.
6. Execute the POST described by `client.signed_wire`.
7. Deliver the response to `client.accept_signed_response` and follow its action.

`ACTION_RETRY_SIGNED` means the server supplied a fresh nonce. `ACTION_ACQUIRE_NONCE`
means the caller must execute the directory's HEAD request, then pass the result to
`client.accept_nonce_response`. Neither action hides I/O or retries inside a signing
callback.

See [the protocol contract](doc/protocol.md) for lifetimes, failure rules, and
buffer requirements.

## Dependencies

The repository pins exact released Git tags:

- `mach-std` v0.29.0
- `mach-http` v0.3.0
- `mach-crypto` v0.4.0

Build output uses Mach's repository-local `out/` path. Run the root tests and the
protocol vector project with:

```text
mach test . --profile debug
mach test test/protocol --profile debug
mach test test/protocol --profile release
```

## Remaining scope

Network execution waits on the production `mach-http` client lifecycle. Account
registration, external account binding, order and authorization progression,
challenge polling, finalization, certificate installation, key rollover, and
renewal scheduling are tracked as later ACME layers. The current protocol boundary
is shaped so those layers add request payloads and response decoders without
changing signing, nonce, or transport ownership.
