# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# activate / active: the stable link and its hooks.

activate_config() {
  config <<'YML'
base_repo: ../base
worktree_root: .
dir_prefix: "wt-"
active_link: ./current
YML
}

test_activate_points_the_link_and_records_the_marker() {
  activate_config
  local p; p="$(wt create one 2>/dev/null)"
  run wt activate "$(name_n 1 one)"
  assert_ok
  assert_symlink_to "$TEST_TMP/host/current" "$p"
  assert_eq "$(wt active)" "$(name_n 1 one)" "active name"
}

test_switching_repoints_the_link() {
  # Regression: `mv` followed the symlink and moved the new link *inside* the
  # old worktree, leaving the switch silently ineffective.
  activate_config
  wt create one >/dev/null 2>&1
  local second; second="$(wt create two 2>/dev/null)"
  wt activate "$(name_n 1 one)" >/dev/null 2>&1
  wt activate "$(name_n 2 two)" >/dev/null 2>&1
  assert_symlink_to "$TEST_TMP/host/current" "$second"
  assert_no_file "$TEST_TMP/host/wt-$(name_n 1 one)/current"
}

test_active_path_prints_the_path() {
  activate_config
  local p; p="$(wt create one 2>/dev/null)"
  wt activate "$(name_n 1 one)" >/dev/null 2>&1
  run wt active --path
  assert_eq "$stdout" "$p" "active --path"
}

test_active_without_one_is_an_error() {
  activate_config
  run wt active
  assert_fails
  assert_contains "$stderr" "No active worktree"
}

test_hooks_run_in_order_with_previous_pointers() {
  config <<'YML'
base_repo: ../base
worktree_root: .
active_link: ./current
pre_activate: 'printf "pre:%s:%s\n" "$WT_NAME" "$WT_PREVIOUS_NAME" >> "$WT_BASE_REPO/trace"'
post_activate: 'printf "post:%s:%s\n" "$WT_NAME" "$WT_PREVIOUS_NAME" >> "$WT_BASE_REPO/trace"'
YML
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  wt activate "$(name_n 1 one)" >/dev/null 2>&1
  wt activate "$(name_n 2 two)" >/dev/null 2>&1
  local trace; trace="$(cat "$TEST_TMP/base/trace")"
  assert_contains "$trace" "pre:$(name_n 1 one):"
  assert_contains "$trace" "post:$(name_n 1 one):"
  assert_contains "$trace" "pre:$(name_n 2 two):$(name_n 1 one)"
}

test_failing_pre_activate_aborts_the_switch() {
  activate_config
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  wt activate "$(name_n 1 one)" >/dev/null 2>&1
  run wtenv WT_PRE_ACTIVATE='exit 3' -- activate "$(name_n 2 two)"
  assert_fails
  assert_contains "$stderr" "not switching"
  assert_eq "$(wt active)" "$(name_n 1 one)" "active is unchanged"
  assert_symlink_to "$TEST_TMP/host/current" "$TEST_TMP/host/wt-$(name_n 1 one)"
}

test_failing_post_activate_still_switches() {
  activate_config
  wt create one >/dev/null 2>&1
  run wtenv WT_POST_ACTIVATE='exit 4' -- activate "$(name_n 1 one)"
  assert_fails
  assert_eq "$(wt active)" "$(name_n 1 one)" "switch happened anyway"
}

test_refuses_to_replace_a_real_directory() {
  activate_config
  mkdir -p "$TEST_TMP/host/current"
  wt create one >/dev/null 2>&1
  run wt activate "$(name_n 1 one)"
  assert_fails
  assert_contains "$stderr" "not a symlink"
}

test_deleting_the_active_worktree_clears_it() {
  activate_config
  wt create one >/dev/null 2>&1
  wt activate "$(name_n 1 one)" >/dev/null 2>&1
  run wt delete "$(name_n 1 one)"
  assert_ok
  assert_contains "$stderr" "nothing is active now"
  assert_no_file "$TEST_TMP/host/current"
}

test_create_activate_does_both() {
  activate_config
  run wt create one --activate
  assert_ok
  assert_eq "$(wt active)" "$(name_n 1 one)" "active after create --activate"
}

test_activate_works_without_a_link() {
  wt create one >/dev/null 2>&1
  run wt activate "$(name_n 1 one)"
  assert_ok
  assert_eq "$(wt active)" "$(name_n 1 one)" "marker without a link"
}
