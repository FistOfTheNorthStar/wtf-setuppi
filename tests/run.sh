#!/usr/bin/env bash
#
# tests/run.sh — the wt test suite. No dependencies beyond bash and git.
#
#   ./tests/run.sh              run everything (and shellcheck, if installed)
#   ./tests/run.sh create       run only tests whose name matches "create"
#   ./tests/run.sh -j1          run serially (default: one job per CPU)
#   ./tests/run.sh --no-lint    skip the shellcheck step
#
# Each test runs in its own subshell with `set -e`, against its own throwaway
# git repos under $TMPDIR. Nothing touches the repo you are working in, and
# tests share no state, so they can run in parallel.
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WT_BIN="${WT_BIN:-$DIR/../wt}"
[ -x "$WT_BIN" ] || { printf 'not executable: %s\n' "$WT_BIN" >&2; exit 1; }

# Keep git hermetic: no user config, no prompts, no colors anywhere.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0
export NO_COLOR=1
unset WT_CONFIG WT_BASE_REPO WT_WORKTREE_ROOT WT_DIR_PREFIX WT_MAIN_BRANCH \
      WT_REMOTE WT_DATE_FORMAT WT_COMMIT_PREFIX WT_PORT_BASE_CFG WT_PORT_STRIDE \
      WT_POST_CREATE WT_PRE_ACTIVATE WT_POST_ACTIVATE WT_ACTIVE_LINK \
      WT_MANAGE_GITIGNORE WT_COPY WT_LINK WT_LOCK_TIMEOUT 2>/dev/null || true

default_jobs() {
  local n
  n="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
  [ "$n" -gt 8 ] && n=8
  printf '%s' "$n"
}

lint=1
filter=""
jobs_max="$(default_jobs)"
for arg in "$@"; do
  case "$arg" in
    --no-lint) lint=0 ;;
    -j*)       jobs_max="${arg#-j}" ;;
    -*) printf 'unknown flag: %s\n' "$arg" >&2; exit 1 ;;
    *) filter="$arg" ;;
  esac
done
case "$jobs_max" in ''|*[!0-9]*|0) printf 'bad job count\n' >&2; exit 1 ;; esac

red=''; grn=''; ylw=''; rst=''
if [ -t 1 ]; then red=$'\033[31m'; grn=$'\033[32m'; ylw=$'\033[33m'; rst=$'\033[0m'; fi

tmpdir_root="${TMPDIR:-/tmp}"; tmpdir_root="${tmpdir_root%/}"
WORK="$(mktemp -d "$tmpdir_root/wt-suite.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# One template fixture, copied per test (a git init/clone/commit per test was
# pure overhead). See helpers.sh.
export FIXTURE_TEMPLATE="$WORK/template"
# shellcheck source=helpers.sh
TEST_TMP="$WORK" . "$DIR/helpers.sh"
build_fixture_template "$FIXTURE_TEMPLATE"

# Run one test: writes "<status> <name>" to a result file and its output to a log.
run_test() {
  local file="$1" fn="$2" name="$3" slot="$4"
  local tmp log
  tmp="$(mktemp -d "$tmpdir_root/wt-test.XXXXXX")"
  log="$WORK/$slot.log"
  if (
      set -e
      export TEST_TMP="$tmp"
      # shellcheck source=helpers.sh
      . "$DIR/helpers.sh"
      # shellcheck source=/dev/null
      . "$file"
      fixture
      "$fn"
     ) >"$log" 2>&1 </dev/null; then
    printf 'ok %s\n' "$name" > "$WORK/$slot.result"
  else
    printf 'fail %s\n' "$name" > "$WORK/$slot.result"
  fi
  rm -rf "$tmp"
}

started=$SECONDS
slot=0
declare -a pending=()
for file in "$DIR"/*.test.sh; do
  [ -e "$file" ] || continue
  suite="$(basename "$file" .test.sh)"
  while IFS= read -r fn; do
    name="$suite/${fn#test_}"
    if [ -n "$filter" ]; then
      case "$name" in *"$filter"*) ;; *) continue ;; esac
    fi
    slot=$((slot + 1))
    pending+=("$slot")
    if [ "$jobs_max" -le 1 ]; then
      run_test "$file" "$fn" "$name" "$slot"
    else
      # Throttle to jobs_max concurrent tests (portable to bash 3.2: no wait -n).
      while [ "$(jobs -rp | wc -l)" -ge "$jobs_max" ]; do sleep 0.05; done
      run_test "$file" "$fn" "$name" "$slot" &
    fi
  done < <(grep -oE '^test_[A-Za-z0-9_]+' "$file" | sort -u)
done
wait

if [ "${#pending[@]}" -eq 0 ]; then
  printf 'no tests matched %s\n' "${filter:-(everything)}" >&2
  exit 1
fi

n=0; passed=0; failed=0
declare -a failures=()
for slot in "${pending[@]}"; do
  [ -f "$WORK/$slot.result" ] || continue
  read -r verdict name < "$WORK/$slot.result"
  n=$((n + 1))
  if [ "$verdict" = ok ]; then
    passed=$((passed + 1))
    printf '%sok%s   %s\n' "$grn" "$rst" "$name"
  else
    failed=$((failed + 1))
    failures+=("$name")
    printf '%sFAIL%s %s\n' "$red" "$rst" "$name"
    sed 's/^/       /' "$WORK/$slot.log"
  fi
done

printf '\n%d test(s): %d passed, %d failed  (%ds, -j%s)\n' \
  "$n" "$passed" "$failed" "$((SECONDS - started))" "$jobs_max"
if [ "$failed" -gt 0 ]; then
  printf '%sfailed:%s %s\n' "$red" "$rst" "${failures[*]}"
fi

lint_status=0
if [ "$lint" -eq 1 ] && [ -z "$filter" ]; then
  printf '\n'
  "$DIR/lint.sh" || lint_status=$?
  if [ "$lint_status" -eq 127 ]; then
    printf '%sskip%s shellcheck is not installed (brew install shellcheck)\n' "$ylw" "$rst"
    lint_status=0
  elif [ "$lint_status" -eq 0 ]; then
    printf '%sok%s   shellcheck\n' "$grn" "$rst"
  fi
fi

[ "$failed" -eq 0 ] && [ "$lint_status" -eq 0 ]
