# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# Awkward paths and legacy layouts.

test_worktree_root_with_spaces() {
  # Regression: delete parsed `git worktree list` with $2 and left the branch.
  local host="$TEST_TMP/my projects/host"
  mkdir -p "$host"
  cd "$host" || exit 1
  cat > wt.yml <<YML
base_repo: $TEST_TMP/base
worktree_root: .
dir_prefix: "wt-"
YML
  run wt create spaced
  assert_ok
  assert_dir "$host/wt-$(name_n 1 spaced)"
  run wt delete "$(name_n 1 spaced)"
  assert_ok
  assert_contains "$stderr" "Branch '$(name_n 1 spaced)' deleted"
  assert_branch_gone "$(name_n 1 spaced)"
}

test_worktree_root_reached_through_a_symlink() {
  mkdir -p "$TEST_TMP/real"
  ln -s "$TEST_TMP/real" "$TEST_TMP/link"
  cd "$TEST_TMP/link" || exit 1
  cat > wt.yml <<YML
base_repo: $TEST_TMP/base
worktree_root: .
dir_prefix: "wt-"
YML
  run wt create linked
  assert_ok
  run wt delete "$(name_n 1 linked)"
  assert_ok
  assert_branch_gone "$(name_n 1 linked)"
}

test_legacy_unprefixed_directories_are_still_found() {
  # Created before dir_prefix existed: no prefix on disk.
  base_git worktree add -q --no-track -b legacy "$TEST_TMP/host/legacy" origin/main
  run wt path legacy
  assert_eq "$stdout" "$TEST_TMP/host/legacy" "legacy path"
  run wt delete legacy
  assert_ok
  assert_branch_gone legacy
}

test_legacy_directories_count_toward_the_sequence_number() {
  base_git worktree add -q --no-track -b "$(name_n 7 old)" "$TEST_TMP/host/$(name_n 7 old)" origin/main
  run wt create next
  assert_contains "$stdout" "wt-$(name_n 8 next)"
}
