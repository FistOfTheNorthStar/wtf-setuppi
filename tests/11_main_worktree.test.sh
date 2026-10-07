# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr.
# shellcheck disable=SC2154
# main in a worktree of its own, with the base repo detached.

# Push a new commit to <branch> on the remote from a separate clone, so the
# base repo and the worktrees only see it after a fetch.
advance_remote() {
  local clone="$TEST_TMP/pusher"
  [ -d "$clone" ] || git clone -q "$TEST_TMP/remote" "$clone" 2>/dev/null
  git -C "$clone" fetch -q origin
  git -C "$clone" checkout -q -B "$1" "origin/$1"
  echo "$2" > "$clone/$2.txt"
  git -C "$clone" add -A
  git -C "$clone" -c user.email=t@e -c user.name=t commit -qm "$2"
  git -C "$clone" push -q origin "$1"
}

test_create_main_while_base_is_on_it_explains_how_to_detach() {
  run wt create main --raw
  assert_fails
  assert_contains "$stderr" "switch --detach"
  assert_no_file "$TEST_TMP/host/wt-main"
}

test_main_gets_a_worktree_once_the_base_is_detached() {
  base_git switch -q --detach
  run wt create main --raw
  assert_ok
  assert_eq "$(git -C "$TEST_TMP/host/wt-main" rev-parse --abbrev-ref HEAD)" main "branch"
}

test_update_fast_forwards_a_main_worktree_in_place() {
  base_git switch -q --detach
  wt create main --raw >/dev/null 2>&1
  advance_remote main m1
  run wt update
  assert_ok
  assert_file "$TEST_TMP/host/wt-main/m1.txt"
}

test_update_leaves_other_branches_alone() {
  base_git branch production
  base_git push -q origin production
  wt create production --raw >/dev/null 2>&1
  advance_remote production p1
  run wt update
  assert_ok
  assert_no_file "$TEST_TMP/host/wt-production/p1.txt"
}

test_delete_removes_a_main_worktree_but_keeps_the_branch() {
  base_git switch -q --detach
  wt create main --raw >/dev/null 2>&1
  run wt delete main
  assert_ok
  assert_no_file "$TEST_TMP/host/wt-main"
  assert_branch_exists main
}

test_clean_never_removes_a_main_worktree() {
  base_git switch -q --detach
  wt create main --raw >/dev/null 2>&1
  wt create one >/dev/null 2>&1
  run wt clean --merged --yes
  assert_ok
  assert_dir "$TEST_TMP/host/wt-main"
  assert_no_file "$TEST_TMP/host/wt-$(name_n 1 one)"
}
