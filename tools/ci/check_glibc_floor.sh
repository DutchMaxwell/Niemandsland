#!/usr/bin/env bash
# Prints the highest GLIBC_x.y symbol version a shared library needs; exit 1 if it is above the max.
# Usage: check_glibc_floor.sh <lib.so> [max=2.35]
set -euo pipefail
LIB="${1:?usage: check_glibc_floor.sh <lib.so> [max=2.35]}"
MAX="${2:-2.35}"
NEED=$(objdump -T "$LIB" | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/^GLIBC_//' | sort -uV | tail -n1)
NEED="${NEED:-0}"
echo "$LIB needs GLIBC_${NEED} (allowed: GLIBC_${MAX})"
if [ "$(printf '%s\n%s\n' "$NEED" "$MAX" | sort -V | tail -n1)" != "$MAX" ]; then
  echo "::error::$LIB needs GLIBC_${NEED}, above the GLIBC_${MAX} floor - build on an older runner image"
  exit 1
fi
