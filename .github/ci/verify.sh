#!/usr/bin/env bash
set -euo pipefail
# the selections guard lists every target, so one leg is the whole signal
case "$MACH_CI_LEG" in
  x86_64-linux) bash test/selections/verify.sh "$MACH_COMPILER" ;;
esac
