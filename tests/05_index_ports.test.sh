# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# Per-worktree index, ports, .wt.env and post_create.

ports_config() {
  config <<'YML'
base_repo: ../base
worktree_root: .
dir_prefix: "wt-"
port_base: 8000
port_stride: 10
YML
}

test_indices_start_at_one_and_increment() {
  ports_config
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  run wt list --json
  assert_contains "$stdout" '"index": 1'
  assert_contains "$stdout" '"index": 2'
}

test_ports_derive_from_index() {
  ports_config
  wt create one >/dev/null 2>&1
  run wt list --json
  assert_contains "$stdout" '"port_base": 8010'
}

test_wt_env_is_written() {
  ports_config
  local p; p="$(wt create one 2>/dev/null)"
  assert_file "$p/.wt.env"
  local env_file; env_file="$(cat "$p/.wt.env")"
  assert_contains "$env_file" 'WT_INDEX="1"'
  assert_contains "$env_file" 'WT_PORT_BASE="8010"'
}

test_wt_env_survives_quotes_and_dollars_in_names() {
  # Regression: unescaped values silently produced a wrong WT_PATH.
  local p; p="$(wt create 'we"ird$name' --raw 2>/dev/null)"
  # shellcheck source=/dev/null
  ( set -e; . "$p/.wt.env"; [ "$WT_PATH" = "$p" ] ) \
    || fail ".wt.env did not source back to the right path"
}

test_index_is_freed_and_reused_after_delete() {
  ports_config
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  wt delete "$(name_n 1 one)" >/dev/null 2>&1
  wt create three >/dev/null 2>&1
  run wt list --json
  # index 1 was freed by the delete and handed to "three"
  assert_eq "$(count_of "$stdout" '"index": 1')" "1" "index 1 in use once"
}

test_index_is_stable_across_runs() {
  ports_config
  wt create one >/dev/null 2>&1
  local first second
  first="$(wt list --json | grep -o '"index": [0-9]*')"
  second="$(wt list --json | grep -o '"index": [0-9]*')"
  assert_eq "$first" "$second" "index stability"
}

test_post_create_runs_with_the_environment() {
  config <<'YML'
base_repo: ../base
worktree_root: .
port_base: 8000
post_create: 'printf "%s|%s|%s" "$WT_NAME" "$WT_INDEX" "$WT_PORT_BASE" > hook.txt'
YML
  local p; p="$(wt create hooked 2>/dev/null)"
  assert_eq "$(cat "$p/hook.txt")" "$(name_n 1 hooked)|1|8010" "hook environment"
}

test_post_create_failure_is_reported_but_keeps_the_worktree() {
  config <<'YML'
base_repo: ../base
worktree_root: .
post_create: 'exit 7'
YML
  run wt create hooked
  assert_status 7
  assert_contains "$stderr" "post_create failed"
  assert_dir "$TEST_TMP/host/wt-$(name_n 1 hooked)"
}

test_no_hook_skips_post_create() {
  config <<'YML'
base_repo: ../base
worktree_root: .
post_create: 'touch should-not-exist'
YML
  local p; p="$(wt create hooked --no-hook 2>/dev/null)"
  assert_no_file "$p/should-not-exist"
}

test_open_passes_the_worktree_path_to_open_with() {
  config_add <<'YML'
open_with: 'printf "%s" > opened.txt'
YML
  run wt create opened --open
  assert_status 0
  assert_eq "$(cat "$stdout/opened.txt")" "$stdout" "open_with argument"
}

test_open_runs_after_post_create() {
  config_add <<'YML'
post_create: 'touch provisioned'
open_with: 'test -f provisioned && touch opened; true'
YML
  local p; p="$(wt create opened --open 2>/dev/null)"
  assert_file "$p/opened"
}

test_open_failure_only_warns() {
  config_add <<'YML'
open_with: 'no-such-editor-for-wt-tests'
YML
  run wt create opened --open
  assert_status 0
  assert_contains "$stderr" "open_with failed"
  assert_dir "$stdout"
}

test_create_does_not_open_without_the_flag() {
  config_add <<'YML'
open_with: 'touch should-not-exist; true'
YML
  local p; p="$(wt create opened 2>/dev/null)"
  assert_no_file "$p/should-not-exist"
}

test_open_without_open_with_is_refused() {
  run wt create opened --open
  assert_status 1
  assert_contains "$stderr" "--open needs open_with"
  assert_no_file "$TEST_TMP/host/wt-$(name_n 1 opened)"
}

test_open_command_opens_an_existing_worktree() {
  config_add <<'YML'
open_with: 'printf "%s" > opened.txt'
YML
  local p; p="$(wt create opened 2>/dev/null)"
  assert_no_file "$p/opened.txt"
  run wt open "$(name_n 1 opened)"
  assert_status 0
  assert_eq "$(cat "$p/opened.txt")" "$p" "open_with argument"
}

test_open_command_fails_when_open_with_fails() {
  config_add <<'YML'
open_with: 'no-such-editor-for-wt-tests'
YML
  wt create opened >/dev/null 2>&1
  run wt open "$(name_n 1 opened)"
  assert_status 1
  assert_contains "$stderr" "open_with failed"
}

test_open_command_without_open_with_is_refused() {
  wt create opened >/dev/null 2>&1
  run wt open "$(name_n 1 opened)"
  assert_status 1
  assert_contains "$stderr" "open needs open_with"
}

test_open_command_rejects_an_unknown_worktree() {
  run wtenv WT_OPEN_WITH=true -- open nope
  assert_status 1
  assert_contains "$stderr" "No worktree at"
}

test_open_with_env_overrides_and_shows_in_config() {
  run wt config
  assert_contains "$stdout" "open_with   : (disabled)"
  run wtenv WT_OPEN_WITH=code -- config
  assert_contains "$stdout" "open_with   : code"
}

test_ports_are_absent_when_port_base_is_unset() {
  wt create one >/dev/null 2>&1
  run wt list --json
  assert_contains "$stdout" '"port_base": null'
}
