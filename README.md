# mach-acme

`mach-acme` defines reusable ACME client contracts above `mach-http` and `mach-tls`. Account keys, protocol state, challenge presentation, certificate storage, and renewal policy remain separate so applications can choose their own durable storage and deployment integrations.

The current repository is a contract scaffold. It does not claim to create accounts, finalize orders, answer challenges, or renew certificates until the HTTP and TLS client lifecycles and an audited signing provider exist.

## Boundaries

- `client` owns directory configuration and injected HTTP and TLS clients.
- `jose` keeps account key ownership and JWS signing behind caller-owned bounded buffers.
- `nonce` separates replay nonce persistence from protocol retries.
- `identifier` is the shared DNS and IP identifier model.
- `account` models account identity and credentials.
- `order` models identifiers, authorizations, finalization, and order state.
- `challenge` separates HTTP-01 and DNS-01 presentation from ACME protocol polling.
- `certificate` owns issued chain metadata and private key references.
- `storage` defines transactional account and certificate persistence.
- `renewal` decides when a certificate is due and delegates time and execution policy.
- `renewal_info` accepts authority-provided renewal windows.
- `external_account` defines external account binding.
- `key_change` defines transactional account key rollover.
- `problem` preserves ACME problem documents as structured failures.

## Local dependencies

The manifest uses local path dependencies for `mach-std`, `mach-http`, and `mach-tls`. Build outputs are written to `../.mach-out/acme/`, outside the repository.

## Status

This scaffold is not a functional ACME client. `mach-http` does not yet execute client requests and `mach-tls` does not yet perform handshakes. This repository deliberately contains no private key generation, JOSE signing, nonce retry, challenge polling, certificate installation, or background scheduler implementation.
