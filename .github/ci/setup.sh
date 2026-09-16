#!/usr/bin/env bash
set -euo pipefail
# the live stack is go-built. ubuntu-latest ships go on PATH, and GOTOOLCHAIN=auto
# fetches the newer toolchain the harness module asks for.
case "$MACH_CI_LEG" in
  x86_64-linux)
    go version
    test/live/harness/start.sh
    ;;
esac
