# the fuzz lane

`corpus/<boundary>/` holds the retained inputs for every untrusted-input entry
point of the library. Each directory pairs with a row of the registry in
`src/boundaries.mach`, which names the harness that answers it:

| boundary | entry point |
|---|---|
| `json` | `json.parse`, the bounded tree every response document is read through |
| `url` | `client.url_valid`, the https grammar every url the authority names is held to |
| `directory` | `client.parse_directory` |
| `problem` | `client.accept_signed_response` on an error response, which reads its problem document |
| `replay-nonce` | the `Replay-Nonce` field, through `client.accept_nonce_response` and `client.accept_signed_response` |
| `account` | `account.parse` for a creation, a contact update and a deactivation |
| `order` | `order.parse` for a creation and a poll |
| `authorization` | `order.parse_authorization`, with its challenges |
| `chain` | `certificate.parse_chain`, then every leaf reader over each certificate it decodes |
| `certificate` | `certificate.parse_certificate`, `certificate.renewal_id_parts` and `renewal_info.certificate_id` |
| `alternates` | `certificate.parse_alternates`, one `Link` field value per line |
| `renewal-info` | `renewal_info.parse` |

A document boundary's input is the response body. The harness frames it in the
response a real exchange delivers: the status the parser expects, a
`Location` field where a creation carries one, and for `problem` a signed
request awaiting its answer and a fresh `Replay-Nonce`. A field boundary's
input is the field value, and a value the field layer refuses never reaches the
reader, so it is answered as refused there.

The durable document reader in `file_store` is not a boundary: it reads the
library's own files, and refuses any payload whose digest does not match
before it parses anything.

## Answers

An input is answered when its entry point parses it or refuses it with a typed
error, and every view the parse publishes lies inside the storage it was copied
to, or inside the input for the der readers. A harness also checks what its
parser promises: a refused response writes nothing to the caller's record, an
accepted url is an https url of printable bytes, every url a resource names
passes that grammar, an accepted tree stays within the depth and value limits
it was held to, an order names a certificate exactly when it is valid, an
identifier satisfies the policy it was parsed under, a challenge of a known
type carries a valid token, a badNonce problem retries with the nonce its
response carried, a nonce is bound or pooled exactly when it is a valid nonce
and is the bytes sent, a chain is decoded certificate after certificate into
its storage, and a renewal identifier is the unpadded base64url of the key
identifier and serial joined by a dot. Breaking any of these is a finding.

Each input is copied so that it ends on the last byte before an unreadable page
(`std.allocator.testing`), so a parser that reads one byte past its input
faults on the spot. A crash is a finding. So is a hang: every walk a harness
drives is bounded by its input's length, and the replay runs under a timeout.

## Running it

From the repository root:

```sh
mach dep pull test/fuzz
mach build test/fuzz
test/fuzz/out/linux-x86_64/debug/bin/fuzz replay
test/fuzz/out/linux-x86_64/debug/bin/fuzz one <boundary> <file>
test/fuzz/out/linux-x86_64/debug/bin/fuzz mutate <boundary|all> <runs> <seed> [--retain]
```

`replay` answers every retained input and fails on a finding, on an empty
boundary directory, or on a directory no boundary answers. CI replays it in both
profiles on the heavy tier: a pull request into `main`, or a dispatch with
`heavy: fuzz` or `heavy: all`. `mach build test/fuzz` runs on every pull request
so the lane cannot rot.

`mutate` is the on-demand search. It draws from a boundary's corpus, applies one
to three structural mutations (flip a bit, set a byte, truncate, extend, swap,
zero a run) from one seeded generator, and answers the result, so a seed and a
run count replay exactly. A finding is written to
`test/fuzz/out/findings/<boundary>/`. With `--retain`, an input whose outcome
the corpus does not hold yet is minimized, by cutting ever smaller chunks while
the outcome holds, and written to its boundary's directory as `m-<outcome>.bin`.

An outcome is what the parse answered: its error kind and code, and for an
accepted input the shape it took (which optional fields are present, the
statuses and identifier kinds it names, how many list entries, bucketed). This
is not code coverage. There is no coverage instrumentation for Mach, so two
inputs that reach different code with the same answer count as one.

## The corpus

The named files are valid seeds, each accepted by its parser: the response
bodies, field values and certificate the unit suite decodes, a directory in
the shape of pebble's, and a chain, root, intermediate and leaf generated for
the lane, the leaf with dns, wildcard and ipv6 names. The `m-*` files were
retained by `fuzz mutate all 20000 1 --retain`.

To retain a new input by hand, put the file in its boundary's directory. When a
finding is fixed, retain the input that found it, so the replay keeps it fixed.
