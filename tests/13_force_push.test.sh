# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr.
# shellcheck disable=SC2154
# push --force-with-lease: overwrite the remote branch after a rebase, without
# ever throwing away a push that came from somewhere else.

remote_head() { git -C "$TEST_TMP/remote" rev-parse "refs/heads/$1"; }

# main moves on the remote, so that rebasing a pushed branch rewrites it.
advance_main() {
  git clone -q "$TEST_TMP/remote" "$TEST_TMP/other" 2>/dev/null
  git -C "$TEST_TMP/other" config user.email other@example.com
  git -C "$TEST_TMP/other" config user.name other
  echo upstream > "$TEST_TMP/other/upstream.txt"
  git -C "$TEST_TMP/other" add -A
  git -C "$TEST_TMP/other" commit -qm upstream
  git -C "$TEST_TMP/other" push -q origin main
}

# A pushed worktree with one commit, rebased onto a main that has moved on.
# Sets $p (path) and $n (name).
pushed_and_rebased() {
  n="$(name_n 1 one)"
  p="$(wt create one "$@" 2>/dev/null)"
  echo work > "$p/w.txt"
  wt commit "$n" -m work --push >/dev/null 2>&1
  advance_main
  run wt rebase "$n"
  assert_ok
}

test_plain_push_after_a_rebase_is_rejected_with_a_hint() {
  pushed_and_rebased
  assert_contains "$stderr" "wt push $n --force-with-lease"
  run wt push "$n"
  assert_fails
  assert_contains "$stderr" "re-run with --force-with-lease"
}

test_force_with_lease_pushes_a_rebased_branch() {
  pushed_and_rebased
  run wt push "$n" --force-with-lease
  assert_ok
  assert_eq "$(remote_head "$n")" "$(git -C "$p" rev-parse HEAD)" "remote head"
}

test_force_with_lease_follows_the_issue_name() {
  pushed_and_rebased --issue 12
  run wt push "$n" --force-with-lease
  assert_ok
  assert_eq "$(remote_head "#12-one")" "$(git -C "$p" rev-parse HEAD)" "remote head"
}

test_commit_push_accepts_force_with_lease() {
  pushed_and_rebased
  echo more > "$p/more.txt"
  run wt commit "$n" -m more --push --force-with-lease
  assert_ok
  assert_eq "$(remote_head "$n")" "$(git -C "$p" rev-parse HEAD)" "remote head"
}

# Someone else pushed to the branch and we never fetched it: the lease is stale.
test_force_with_lease_keeps_an_unseen_push() {
  pushed_and_rebased
  git -C "$TEST_TMP/other" fetch -q origin
  git -C "$TEST_TMP/other" checkout -q -b theirs "origin/$n"
  echo theirs > "$TEST_TMP/other/theirs.txt"
  git -C "$TEST_TMP/other" add -A
  git -C "$TEST_TMP/other" commit -qm theirs
  git -C "$TEST_TMP/other" push -q origin "theirs:$n"
  local theirs; theirs="$(remote_head "$n")"
  run wt push "$n" --force-with-lease
  assert_fails
  assert_eq "$(remote_head "$n")" "$theirs" "remote head"
}

# Same, but a fetch (any wt create/rebase does one) has already updated the
# remote-tracking ref, so the lease alone would pass.
test_force_with_lease_keeps_a_fetched_but_unmerged_push() {
  pushed_and_rebased
  git -C "$TEST_TMP/other" fetch -q origin
  git -C "$TEST_TMP/other" checkout -q -b theirs "origin/$n"
  echo theirs > "$TEST_TMP/other/theirs.txt"
  git -C "$TEST_TMP/other" add -A
  git -C "$TEST_TMP/other" commit -qm theirs
  git -C "$TEST_TMP/other" push -q origin "theirs:$n"
  local theirs; theirs="$(remote_head "$n")"
  git -C "$p" fetch -q origin
  run wt push "$n" --force-with-lease
  assert_fails
  assert_contains "$stderr" "never part of"
  assert_eq "$(remote_head "$n")" "$theirs" "remote head"
}

test_force_with_lease_on_a_first_push_is_a_plain_push() {
  wt create one >/dev/null 2>&1
  run wt push "$(name_n 1 one)" --force-with-lease
  assert_ok
  git -C "$TEST_TMP/remote" show-ref --verify --quiet "refs/heads/$(name_n 1 one)" \
    || fail "branch was not pushed"
}

test_permanent_branches_are_never_force_pushed() {
  base_git branch production
  base_git push -q origin production
  config_add <<'YML'
permanent:
  - production
YML
  wt create production --raw >/dev/null 2>&1
  run wt push production --force-with-lease
  assert_fails
  assert_contains "$stderr" "never force-pushed"
}

test_rebase_gives_no_push_hint_for_an_unpushed_branch() {
  wt create one >/dev/null 2>&1
  advance_main
  run wt rebase "$(name_n 1 one)"
  assert_ok
  case "$stderr" in *force-with-lease*) fail "hint shown for an unpushed branch" ;; esac
}

test_commit_force_with_lease_without_push_is_refused() {
  wt create one >/dev/null 2>&1
  run wt commit "$(name_n 1 one)" --force-with-lease
  assert_fails
  assert_contains "$stderr" "use it with --push"
}
