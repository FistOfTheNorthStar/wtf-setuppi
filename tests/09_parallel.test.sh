# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# Parallel use: the create lock, and shared files under concurrent writes.

test_concurrent_creates_do_not_collide() {
  local i
  for i in 1 2 3 4 5; do
    ( wt create "task $i" > "$TEST_TMP/out.$i" 2>/dev/null ) &
  done
  wait
  local paths distinct
  paths="$(cat "$TEST_TMP"/out.* | sort)"
  distinct="$(printf '%s\n' "$paths" | sort -u | wc -l | tr -d ' ')"
  assert_eq "$distinct" "5" "distinct worktree paths"
}

test_concurrent_creates_allocate_distinct_indices() {
  local i
  for i in 1 2 3 4; do
    ( wt create "task $i" >/dev/null 2>&1 ) &
  done
  wait
  local dupes
  dupes="$(base_git config --get-all wt.worktree-index | awk '{print $2}' | sort -n | uniq -d)"
  assert_empty "$dupes" "duplicate indices"
}

test_concurrent_creates_preserve_user_lines_in_shared_files() {
  # Regression: the lock was released before the read-modify-write of
  # .git/info/exclude and .gitignore, so parallel runs could truncate them.
  printf '# user line\n' > "$TEST_TMP/base/.git/info/exclude"
  config <<'YML'
base_repo: ../base
worktree_root: .
copy:
  - .env
YML
  printf 'X=1\n' > "$TEST_TMP/base/.env"
  local i
  for i in 1 2 3 4; do
    ( wt create "task $i" >/dev/null 2>&1 ) &
  done
  wait
  assert_contains "$(cat "$TEST_TMP/base/.git/info/exclude")" "# user line"
}

test_a_stale_lock_times_out_with_a_useful_message() {
  local common="$TEST_TMP/base/.git"
  mkdir -p "$common/wt.lock"
  run wtenv WT_LOCK_TIMEOUT=1 -- create blocked
  assert_fails
  assert_contains "$stderr" "wt.lock"
  rmdir "$common/wt.lock"
}
