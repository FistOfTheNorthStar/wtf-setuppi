# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr.
# shellcheck disable=SC2154
# Issue numbers: the local branch keeps its <date>-N-<slug> name, the branch on
# the remote is named after the issue.

remote_has() { git -C "$TEST_TMP/remote" show-ref --verify --quiet "refs/heads/$1"; }

test_create_with_issue_pushes_under_the_issue_name() {
  local p; p="$(wt create "add search" --issue 12345 2>/dev/null)"
  echo work > "$p/w.txt"
  run wt commit "$(name_n 1 add-search)" -m work --push
  assert_ok
  remote_has "#12345-add-search" || fail "issue-named branch was not pushed"
  remote_has "$(name_n 1 add-search)" && fail "local name was pushed too"
  assert_branch_exists "$(name_n 1 add-search)"
  assert_eq "$(git -C "$p" rev-parse --abbrev-ref '@{upstream}')" "origin/#12345-add-search" "upstream"
}

test_issue_can_be_given_at_push_time_with_a_hash() {
  local p; p="$(wt create one 2>/dev/null)"
  echo work > "$p/w.txt"
  wt commit "$(name_n 1 one)" -m work >/dev/null 2>&1
  run wt push "$(name_n 1 one)" --issue '#77'
  assert_ok
  remote_has "#77-one" || fail "issue-named branch was not pushed"
}

test_issue_is_remembered_for_later_pushes() {
  local p; p="$(wt create one --issue 5 2>/dev/null)"
  wt push "$(name_n 1 one)" >/dev/null 2>&1
  echo more > "$p/more.txt"
  run wt commit "$(name_n 1 one)" -m more --push
  assert_ok
  assert_eq "$(git -C "$TEST_TMP/remote" log -1 --pretty=%s "#5-one")" more "remote head"
}

test_push_without_an_issue_keeps_the_branch_name() {
  wt create one >/dev/null 2>&1
  run wt push "$(name_n 1 one)"
  assert_ok
  remote_has "$(name_n 1 one)" || fail "branch was not pushed"
}

test_remote_branch_format_is_configurable() {
  config_add <<'YML'
remote_branch: "app#{issue}-{slug}"
YML
  wt create one --issue 9 >/dev/null 2>&1
  run wt push "$(name_n 1 one)"
  assert_ok
  remote_has "app#9-one" || fail "formatted branch was not pushed"
}

test_name_placeholder_and_raw_branches() {
  wt create experiment --raw >/dev/null 2>&1
  run wtenv 'WT_REMOTE_BRANCH={issue}/{name}' -- push experiment --issue 3
  assert_ok
  remote_has "3/experiment" || fail "raw branch was not pushed under the issue"
}

test_slug_is_recovered_for_branches_without_a_recorded_one() {
  wt create one >/dev/null 2>&1
  base_git config --unset "branch.$(name_n 1 one).wtslug"
  run wt push "$(name_n 1 one)" --issue 8
  assert_ok
  remote_has "#8-one" || fail "slug was not derived from the branch name"
}

test_changing_the_issue_warns_about_the_old_remote_branch() {
  wt create one --issue 1 >/dev/null 2>&1
  wt push "$(name_n 1 one)" >/dev/null 2>&1
  run wt push "$(name_n 1 one)" --issue 2
  assert_ok
  assert_contains "$stderr" "push origin --delete '#1-one'"
  remote_has "#2-one" || fail "new issue-named branch was not pushed"
}

test_clean_gone_follows_the_issue_named_upstream() {
  wt create one --issue 4 >/dev/null 2>&1
  wt push "$(name_n 1 one)" >/dev/null 2>&1
  git -C "$TEST_TMP/remote" branch -D "#4-one" >/dev/null 2>&1
  run wt clean --gone --dry-run
  assert_ok
  assert_contains "$stdout" "upstream gone"
}

test_bad_issue_is_refused() {
  run wt create one --issue abc
  assert_fails
  assert_contains "$stderr" "Issue must be a number"
  assert_no_file "$TEST_TMP/host/wt-$(name_n 1 one)"
}

test_commit_issue_without_push_is_refused() {
  wt create one >/dev/null 2>&1
  run wt commit "$(name_n 1 one)" --issue 5
  assert_fails
  assert_contains "$stderr" "use it with --push"
}

test_remote_branch_without_issue_placeholder_is_refused() {
  run wtenv 'WT_REMOTE_BRANCH={slug}' -- config
  assert_fails
  assert_contains "$stderr" "must contain {issue}"
}

test_config_shows_remote_branch() {
  run wt config
  assert_ok
  assert_contains "$stdout" "remote_branch: #{issue}-{slug}"
}
