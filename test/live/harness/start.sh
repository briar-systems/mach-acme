#!/bin/sh
# start the live acme conformance stack: pebble, its challenge test server, and
# the plain-http front end. every process is local and bound to loopback.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
tools="$root/.tools"
bin="$tools/gopath/bin"
run="$tools/run"
mkdir -p "$run"

"$0.stop" 2>/dev/null || true

# challtestsrv answers pebble's http-01, dns-01, and tls-alpn-01 validation and
# exposes a plain-http management api the mach challenge provider drives.
"$bin/pebble-challtestsrv" \
    -http01 ":5002" -tlsalpn01 ":5001" -https01 "" \
    -dnsserver ":8053" -doh "" -management ":8055" \
    >"$run/challtestsrv.log" 2>&1 &
echo $! >"$run/challtestsrv.pid"

# PEBBLE_VA_NOSLEEP removes the randomized validation delay so ordering in the
# tests is deterministic. PEBBLE_WFE_NONCEREJECT=0 disables pebble's default 5%
# random badNonce injection; the badNonce path has its own dedicated fixtures.
cd "$tools"
PEBBLE_VA_NOSLEEP=1 PEBBLE_WFE_NONCEREJECT=0 \
    "$bin/pebble" -config "$tools/test/config/pebble-config.json" \
    -dnsserver 127.0.0.1:8053 \
    >"$run/pebble.log" 2>&1 &
echo $! >"$run/pebble.pid"

"$bin/acme-proxy" -listen 127.0.0.1:14001 -upstream 127.0.0.1:14000 \
    >"$run/proxy.log" 2>&1 &
echo $! >"$run/proxy.pid"

i=0
while [ "$i" -lt 100 ]; do
    if [ "$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:14001/dir 2>/dev/null)" = "200" ]; then
        echo "live acme stack ready on http://127.0.0.1:14001/dir"
        exit 0
    fi
    i=$((i + 1))
    sleep 0.1
done
echo "live acme stack failed to become ready" >&2
exit 1
