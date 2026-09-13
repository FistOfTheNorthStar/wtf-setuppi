#!/usr/bin/env bash
#
# tests/lint.sh — shellcheck the scripts. Exits 127 if shellcheck is missing,
# so run.sh can report a skip instead of a failure.
#
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

command -v shellcheck >/dev/null 2>&1 || exit 127

# The suite's helper file is sourced, not executed; -x lets shellcheck follow
# the sources it can resolve.
shellcheck --shell=bash --external-sources \
  "$ROOT/wt" "$DIR/run.sh" "$DIR/lint.sh" "$DIR/helpers.sh" "$DIR"/*.test.sh
