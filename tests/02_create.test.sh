# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# Creating worktrees: naming, prefixes, base refs, stdout discipline.

test_create_makes_prefixed_dir_and_bare_branch() {
  run wt create "add search"
  assert_ok
  local name; name="$(name_n 1 add-search)"
  assert_dir "$TEST_TMP/host/wt-$name"
  assert_branch_exists "$name"
  assert_no_file "$TEST_TMP/host/$name"
}

test_create_prints_only_the_path_on_stdout() {
  run wt create "add search"
  assert_ok
  # Regression: `git worktree add` writes "HEAD is now at ..." to stdout.
  assert_eq "$stdout" "$TEST_TMP/host/wt-$(name_n 1 add-search)" "stdout"
}

test_sequence_number_increments() {
  wt create one >/dev/null 2>&1
  wt create two >/dev/null 2>&1
  run wt create three
  assert_contains "$stdout" "wt-$(name_n 3 three)"
}

test_slugify_normalizes_input() {
  run wt create "Add   Search!!"
  assert_contains "$stdout" "wt-$(name_n 1 add-search)"
}

test_raw_uses_the_name_verbatim() {
  run wt create my-experiment --raw
  assert_ok
  assert_dir "$TEST_TMP/host/wt-my-experiment"
  assert_branch_exists "my-experiment"
}

test_create_from_another_branch() {
  base_git branch feature-base main
  base_git push -q origin feature-base
  run wt create derived --from feature-base
  assert_ok
}

test_create_from_unknown_branch_fails() {
  run wt create derived --from nope
  assert_fails
  assert_contains "$stderr" "not found locally or on origin"
}

test_existing_branch_is_checked_out() {
  base_git branch reuse-me main
  run wt create reuse-me --raw
  assert_ok
  assert_contains "$stderr" "already exists; checking it out"
}

test_duplicate_path_is_refused() {
  wt create dup --raw >/dev/null 2>&1
  run wt create dup --raw
  assert_fails
  assert_contains "$stderr" "Path already exists"
}

test_unknown_flag_is_refused() {
  run wt create thing --bogus
  assert_fails
  assert_contains "$stderr" "Unknown flag"
}

test_empty_dir_prefix_creates_unprefixed_dirs() {
  run wtenv WT_DIR_PREFIX= -- create plain
  assert_ok
  assert_dir "$TEST_TMP/host/$(name_n 1 plain)"
}
