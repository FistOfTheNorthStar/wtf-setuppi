# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# list / path / exec / each — the orchestration surface.

test_list_shows_status_columns() {
  wt create one >/dev/null 2>&1
  run wt list
  assert_ok
  assert_contains "$stdout" "NAME"
  assert_contains "$stdout" "$(name_n 1 one)"
}

test_list_marks_the_active_worktree() {
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  wt activate "$(name_n 2 two)" >/dev/null 2>&1
  run wt list --json
  assert_contains "$stdout" "\"name\": \"$(name_n 2 two)\", \"path\""
  assert_eq "$(count_of "$stdout" '"active": true')" "1" "exactly one active"
}

test_list_json_reports_dirty_and_ahead() {
  local p; p="$(wt create one 2>/dev/null)"
  echo change > "$p/new.txt"
  run wt list --json
  assert_contains "$stdout" '"dirty": true'
  wt commit "$(name_n 1 one)" -m "work" >/dev/null 2>&1
  run wt list --json
  assert_contains "$stdout" '"dirty": false'
  assert_contains "$stdout" '"ahead": 1'
}

test_list_json_escapes_quotes_in_subjects() {
  local p; p="$(wt create one 2>/dev/null)"
  echo change > "$p/new.txt"
  wt commit "$(name_n 1 one)" -m 'a "quoted" subject' >/dev/null 2>&1
  run wt list --json
  assert_contains "$stdout" '\"quoted\"'
}

test_path_prints_the_directory() {
  local p; p="$(wt create one 2>/dev/null)"
  run wt path "$(name_n 1 one)"
  assert_eq "$stdout" "$p" "path"
}

test_path_accepts_the_prefixed_directory_name() {
  local p; p="$(wt create one 2>/dev/null)"
  run wt path "wt-$(name_n 1 one)"
  assert_eq "$stdout" "$p" "path from dir name"
}

test_path_of_a_missing_worktree_fails() {
  run wt path nope
  assert_fails
  assert_contains "$stderr" "No worktree at"
}

test_exec_runs_with_the_worktree_environment() {
  wt create one >/dev/null 2>&1
  run wt exec "$(name_n 1 one)" -- sh -c 'printf "%s|%s" "$WT_NAME" "${PWD##*/}"'
  assert_eq "$stdout" "$(name_n 1 one)|wt-$(name_n 1 one)" "exec env and cwd"
}

test_exec_needs_a_command() {
  wt create one >/dev/null 2>&1
  run wt exec "$(name_n 1 one)"
  assert_fails
  assert_contains "$stderr" "Nothing to run"
}

test_exec_propagates_the_exit_status() {
  wt create one >/dev/null 2>&1
  run wt exec "$(name_n 1 one)" -- sh -c 'exit 5'
  assert_status 5
}

test_each_visits_every_worktree() {
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  wt create three >/dev/null 2>&1
  run wt each -- sh -c 'echo visited'
  assert_ok
  assert_eq "$(count_of "$stdout" visited)" "3" "worktrees visited"
}

test_each_does_not_lose_worktrees_to_a_stdin_reading_command() {
  # Regression: the loop read the worktree list on stdin, so `cat` (or any
  # interactive command) swallowed the rest of the list and the run silently
  # covered only the first worktree.
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  wt create three >/dev/null 2>&1
  run wt each -- sh -c 'cat > /dev/null; echo visited'
  assert_ok
  assert_eq "$(count_of "$stdout" visited)" "3" "worktrees visited with a stdin reader"
}

test_each_stops_at_the_first_failure() {
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  run wt each -- false
  assert_fails
  assert_contains "$stderr" "Stopping"
}

test_each_keep_going_runs_all_and_summarizes() {
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  run wt each --keep-going -- false
  assert_fails
  assert_contains "$stderr" "2 of 2 worktree(s) failed"
}

test_each_with_no_worktrees_is_not_an_error() {
  run wt each -- true
  assert_ok
  assert_contains "$stderr" "No worktrees under"
}
