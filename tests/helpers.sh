# tests/helpers.sh — fixtures and assertions for the wt suite.
#
# Sourced by run.sh inside each test's own subshell, which runs with `set -e`,
# so a failing assertion aborts that test and nothing else.

TODAY="$(date +%d-%m-%Y)"
T_OUT="$TEST_TMP/.stdout"
T_ERR="$TEST_TMP/.stderr"

# ---- running wt -----------------------------------------------------------

# Call the script under test.
wt() { "$WT_BIN" "$@"; }

# Call it with extra environment variables:  wtenv WT_DIR_PREFIX=x -- config
# (plain `env VAR=1 wt ...` cannot work: wt is a shell function, not a binary.)
wtenv() {
  local -a envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  env "${envs[@]}" "$WT_BIN" "$@"
}

# Run a command, capturing its streams instead of failing the test:
# sets $status, $stdout, $stderr.
# shellcheck disable=SC2034  # status/stdout/stderr are read by the test files
run() {
  status=0
  "$@" >"$T_OUT" 2>"$T_ERR" </dev/null || status=$?
  stdout="$(cat "$T_OUT")"
  stderr="$(cat "$T_ERR")"
}

# Same, but with a terminal-less stdin closed off explicitly for clarity.
run_tty_less() { run "$@"; }

# ---- fixtures -------------------------------------------------------------

# A bare "remote", a "base" clone with one commit, and a "host" directory with
# wt.yml. Leaves you in host. Called automatically before every test.
#
# The git repos are built once by run.sh and copied per test — a git
# init/clone/commit/push per test dominated the suite's runtime. The copy has
# to be re-pointed at *this* test's remote, or every test would share one.
fixture() {
  cp -R "$FIXTURE_TEMPLATE/remote" "$TEST_TMP/remote"
  cp -R "$FIXTURE_TEMPLATE/base" "$TEST_TMP/base"
  git -C "$TEST_TMP/base" remote set-url origin "$TEST_TMP/remote"
  mkdir -p "$TEST_TMP/host"
  cd "$TEST_TMP/host" || exit 1
  config <<'YML'
base_repo: ../base
worktree_root: .
dir_prefix: "wt-"
YML
}

# Build the template the fixtures are copied from (run.sh calls this once).
build_fixture_template() {
  local dir="$1"
  mkdir -p "$dir"
  git init -q --bare "$dir/remote"
  git clone -q "$dir/remote" "$dir/base" 2>/dev/null
  git -C "$dir/base" config user.email test@example.com
  git -C "$dir/base" config user.name "wt tests"
  echo hello > "$dir/base/file.txt"
  printf '.env\n.venv/\n' > "$dir/base/.gitignore"
  git -C "$dir/base" add -A
  git -C "$dir/base" commit -qm initial
  git -C "$dir/base" branch -M main
  git -C "$dir/base" push -q -u origin main
}

# Replace wt.yml with what is on stdin.
config() { cat > "$TEST_TMP/host/wt.yml"; }

# Append lines to wt.yml.
config_add() { cat >> "$TEST_TMP/host/wt.yml"; }

base_git() { git -C "$TEST_TMP/base" "$@"; }

# Make worktree_root a directory inside the base repo instead of beside it.
fixture_root_inside_repo() {
  mkdir -p "$TEST_TMP/base/trees"
  cd "$TEST_TMP/base/trees" || exit 1
  cat > wt.yml <<'YML'
base_repo: ..
worktree_root: .
dir_prefix: "wt-"
YML
  export WT_CONFIG="$PWD/wt.yml"
}

# The auto-generated name for the Nth worktree created today.
name_n() { printf '%s-%s-%s' "$TODAY" "$1" "$2"; }

# ---- assertions -----------------------------------------------------------

fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }

assert_eq() {
  [ "$1" = "$2" ] || fail "${3:-value}: expected '$2', got '$1'"
}
assert_ne() {
  [ "$1" != "$2" ] || fail "${3:-value}: expected something other than '$2'"
}
assert_contains() {
  case "$1" in *"$2"*) return 0 ;; esac
  fail "expected to contain '$2', got: $1"
}
assert_not_contains() {
  case "$1" in *"$2"*) fail "expected NOT to contain '$2', got: $1" ;; esac
  return 0
}
assert_status() { assert_eq "$status" "$1" "exit status (stderr: $stderr)"; }
assert_ok() { assert_status 0; }
assert_fails() { [ "$status" -ne 0 ] || fail "expected a non-zero exit, got 0"; }
assert_empty() { [ -z "$1" ] || fail "${2:-value}: expected empty, got '$1'"; }
assert_file() { [ -f "$1" ] || fail "no such file: $1"; }
assert_dir() { [ -d "$1" ] || fail "no such directory: $1"; }
assert_no_file() { [ ! -e "$1" ] || fail "expected not to exist: $1"; }
assert_symlink_to() {
  [ -L "$1" ] || fail "not a symlink: $1"
  assert_eq "$(readlink "$1")" "$2" "symlink target"
}
assert_branch_exists() {
  base_git show-ref --verify --quiet "refs/heads/$1" || fail "branch missing: $1"
}
assert_branch_gone() {
  base_git show-ref --verify --quiet "refs/heads/$1" && fail "branch still exists: $1"
  return 0
}
# Count occurrences of a substring in a string.
count_of() { printf '%s' "$1" | grep -c -- "$2" || true; }
