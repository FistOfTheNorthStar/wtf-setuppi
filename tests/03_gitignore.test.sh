# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# The generated .gitignore rule.

test_rule_is_written_into_the_containing_repo() {
  fixture_root_inside_repo
  run wt gitignore
  assert_ok
  local gi="$TEST_TMP/base/.gitignore"
  assert_contains "$(cat "$gi")" "/trees/wt-*/"
}

test_rule_is_anchored_at_the_repo_root() {
  fixture_root_inside_repo
  wt gitignore >/dev/null 2>&1
  # A lookalike directory elsewhere must not be ignored.
  mkdir -p "$TEST_TMP/base/elsewhere/wt-decoy"
  touch "$TEST_TMP/base/elsewhere/wt-decoy/f"
  run git -C "$TEST_TMP/base" check-ignore -q elsewhere/wt-decoy
  assert_fails
}

test_user_lines_are_preserved() {
  fixture_root_inside_repo
  printf '# mine\n*.log\n' > "$TEST_TMP/base/.gitignore"
  wt gitignore >/dev/null 2>&1
  local gi; gi="$(cat "$TEST_TMP/base/.gitignore")"
  assert_contains "$gi" "# mine"
  assert_contains "$gi" "*.log"
}

test_changing_dir_prefix_rewrites_not_duplicates() {
  fixture_root_inside_repo
  wt gitignore >/dev/null 2>&1
  WT_DIR_PREFIX=tree_ wt gitignore >/dev/null 2>&1
  local gi; gi="$(cat "$TEST_TMP/base/.gitignore")"
  assert_contains "$gi" "/trees/tree_*/"
  assert_not_contains "$gi" "/trees/wt-*/"
  assert_eq "$(count_of "$gi" '>>> wt worktrees')" "1" "managed block count"
}

test_check_reports_drift_and_exits_nonzero() {
  fixture_root_inside_repo
  run wtenv WT_DIR_PREFIX=tree_ -- gitignore --check
  assert_status 1
  assert_contains "$stderr" "out of date"
}

test_check_is_clean_when_up_to_date() {
  fixture_root_inside_repo
  wt gitignore >/dev/null 2>&1
  run wt gitignore --check
  assert_ok
}

test_empty_prefix_removes_the_block_instead_of_ignoring_everything() {
  fixture_root_inside_repo
  wt gitignore >/dev/null 2>&1
  run wtenv WT_DIR_PREFIX= -- gitignore
  assert_ok
  local gi; gi="$(cat "$TEST_TMP/base/.gitignore")"
  assert_not_contains "$gi" "wt worktrees"
  assert_not_contains "$gi" "/*/"
}

test_manage_gitignore_false_leaves_the_file_alone() {
  fixture_root_inside_repo
  printf '# mine\n' > "$TEST_TMP/base/.gitignore"
  run wtenv WT_MANAGE_GITIGNORE=false -- gitignore
  assert_ok
  assert_eq "$(cat "$TEST_TMP/base/.gitignore")" "# mine" "gitignore"
}

test_root_outside_a_repo_is_reported_not_fatal() {
  run wt gitignore
  assert_ok
  assert_contains "$stderr" "not inside a git repository"
}

test_active_link_is_ignored_too() {
  fixture_root_inside_repo
  printf 'active_link: ./current\n' >> wt.yml
  wt gitignore >/dev/null 2>&1
  assert_contains "$(cat "$TEST_TMP/base/.gitignore")" "/trees/current"
}
