# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# delete / clean / rebase / commit.

test_delete_removes_worktree_and_branch() {
  wt create one >/dev/null 2>&1
  run wt delete "$(name_n 1 one)"
  assert_ok
  assert_no_file "$TEST_TMP/host/wt-$(name_n 1 one)"
  assert_branch_gone "$(name_n 1 one)"
}

test_delete_keeps_the_branch_on_request() {
  wt create one >/dev/null 2>&1
  run wt delete "$(name_n 1 one)" --keep-branch
  assert_ok
  assert_branch_exists "$(name_n 1 one)"
}

test_delete_refuses_a_dirty_worktree_without_force() {
  local p; p="$(wt create one 2>/dev/null)"
  echo dirt > "$p/dirty.txt"
  run wt delete "$(name_n 1 one)"
  assert_fails
  assert_dir "$p"
}

test_delete_force_discards_changes() {
  local p; p="$(wt create one 2>/dev/null)"
  echo dirt > "$p/dirty.txt"
  run wt delete "$(name_n 1 one)" --force
  assert_ok
  assert_no_file "$p"
}

test_delete_of_a_missing_worktree_is_a_clear_error() {
  # Regression: reported "has changes, re-run with --force", and --force then
  # died with a raw git fatal.
  run wt delete nope
  assert_fails
  assert_contains "$stderr" "No worktree at"
  run wt delete nope --force
  assert_fails
  assert_contains "$stderr" "No worktree at"
}

test_delete_keeps_an_unmerged_branch_and_says_so() {
  local p; p="$(wt create one 2>/dev/null)"
  echo work > "$p/w.txt"
  wt commit "$(name_n 1 one)" -m work >/dev/null 2>&1
  run wt delete "$(name_n 1 one)"
  assert_ok
  assert_contains "$stderr" "not fully merged"
  assert_branch_exists "$(name_n 1 one)"
}

test_delete_prints_nothing_on_stdout() {
  wt create one >/dev/null 2>&1
  run wt delete "$(name_n 1 one)"
  assert_empty "$stdout" "delete stdout"
}

test_clean_needs_a_selector() {
  run wt clean
  assert_fails
  assert_contains "$stderr" "Say what to clean"
}

test_clean_merged_lists_and_removes() {
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  run wt clean --merged --dry-run
  assert_ok
  assert_contains "$stdout" "$(name_n 1 one)"
  assert_dir "$TEST_TMP/host/wt-$(name_n 1 one)"
  run wt clean --merged --yes
  assert_ok
  assert_no_file "$TEST_TMP/host/wt-$(name_n 1 one)"
  assert_no_file "$TEST_TMP/host/wt-$(name_n 2 two)"
}

test_clean_skips_dirty_worktrees() {
  local p; p="$(wt create one 2>/dev/null)"
  echo dirt > "$p/dirty.txt"
  run wt clean --merged --yes
  assert_contains "$stderr" "uncommitted changes"
  assert_dir "$p"
}

test_clean_keeps_unmerged_work() {
  local p; p="$(wt create one 2>/dev/null)"
  echo work > "$p/w.txt"
  wt commit "$(name_n 1 one)" -m work >/dev/null 2>&1
  run wt clean --merged --yes
  assert_dir "$p"
}

test_clean_gone_catches_a_deleted_upstream() {
  local p; p="$(wt create one 2>/dev/null)"
  echo work > "$p/w.txt"
  wt commit "$(name_n 1 one)" -m work --push >/dev/null 2>&1
  git -C "$TEST_TMP/remote" branch -D "$(name_n 1 one)" >/dev/null 2>&1
  run wt clean --gone --dry-run
  assert_ok
  assert_contains "$stdout" "upstream gone"
}

test_clean_refuses_without_a_terminal_or_yes() {
  wt create one >/dev/null 2>&1
  run wt clean --merged
  assert_fails
  assert_contains "$stderr" "without a terminal"
}

test_clean_reports_nothing_to_do_cleanly() {
  run wt clean --merged --yes
  assert_ok
  assert_contains "$stderr" "Nothing to clean."
  assert_not_contains "$stderr" "0 skipped"
}

test_commit_and_push_set_upstream() {
  local p; p="$(wt create one 2>/dev/null)"
  echo work > "$p/w.txt"
  run wt commit "$(name_n 1 one)" -m "my message" --push
  assert_ok
  assert_eq "$(git -C "$p" log -1 --pretty=%s)" "my message" "commit subject"
  git -C "$TEST_TMP/remote" show-ref --verify --quiet "refs/heads/$(name_n 1 one)" \
    || fail "branch was not pushed"
}

test_commit_on_a_clean_tree_warns() {
  wt create one >/dev/null 2>&1
  run wt commit "$(name_n 1 one)"
  assert_ok
  assert_contains "$stderr" "Nothing to commit"
}

test_rebase_onto_a_missing_target_is_a_clear_error() {
  # Regression: any failure was reported as "Rebase hit conflicts".
  wt create one >/dev/null 2>&1
  run wt rebase "$(name_n 1 one)" --onto no-such-branch
  assert_fails
  assert_contains "$stderr" "not found locally or on origin"
  assert_not_contains "$stderr" "hit conflicts"
}

test_rebase_refuses_a_dirty_worktree() {
  local p; p="$(wt create one 2>/dev/null)"
  echo dirt > "$p/dirty.txt"
  run wt rebase "$(name_n 1 one)"
  assert_fails
  assert_contains "$stderr" "uncommitted changes"
}

test_rebase_moves_the_branch_onto_new_main() {
  local p; p="$(wt create one 2>/dev/null)"
  echo work > "$p/w.txt"
  wt commit "$(name_n 1 one)" -m work >/dev/null 2>&1
  # advance main on the remote
  echo more > "$TEST_TMP/base/file.txt"
  base_git commit -qam "main moves on"
  base_git push -q origin main
  run wt rebase "$(name_n 1 one)"
  assert_ok
  assert_contains "$(git -C "$p" log --pretty=%s)" "main moves on"
}
