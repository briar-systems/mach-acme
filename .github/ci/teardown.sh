#!/usr/bin/env bash
set -euo pipefail
case "$MACH_CI_LEG" in
  x86_64-linux) test/live/harness/start.sh.stop ;;
esac
