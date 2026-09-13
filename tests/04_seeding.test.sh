# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# copy: / link: seeding of ignored files.

seeding_config() {
  config <<'YML'
base_repo: ../base
worktree_root: .
dir_prefix: "wt-"
copy:
  - .env
link:
  - .venv
YML
}

test_copy_and_link_are_seeded() {
  printf 'SECRET=1\n' > "$TEST_TMP/base/.env"
  mkdir -p "$TEST_TMP/base/.venv/bin"
  seeding_config
  local p; p="$(wt create seeded 2>/dev/null)"
  assert_file "$p/.env"
  assert_eq "$(cat "$p/.env")" "SECRET=1" ".env contents"
  assert_symlink_to "$p/.venv" "$TEST_TMP/base/.venv"
}

test_copied_file_is_independent_of_the_base() {
  printf 'A=1\n' > "$TEST_TMP/base/.env"
  seeding_config
  local p; p="$(wt create seeded 2>/dev/null)"
  printf 'A=2\n' > "$p/.env"
  assert_eq "$(cat "$TEST_TMP/base/.env")" "A=1" "base .env untouched"
}

test_missing_sources_are_skipped_with_a_warning() {
  seeding_config
  run wt create seeded
  assert_ok
  assert_contains "$stderr" "skipping '.env'"
  assert_contains "$stderr" "skipping '.venv'"
}

test_nested_copy_paths_create_parents() {
  mkdir -p "$TEST_TMP/base/.claude"
  printf '{}\n' > "$TEST_TMP/base/.claude/settings.local.json"
  config <<'YML'
base_repo: ../base
worktree_root: .
copy:
  - .claude/settings.local.json
YML
  local p; p="$(wt create nested 2>/dev/null)"
  assert_file "$p/.claude/settings.local.json"
}

test_tracked_files_are_never_clobbered() {
  # file.txt is tracked in the fixture; listing it in copy: must not overwrite.
  printf 'BASE VERSION\n' > "$TEST_TMP/base/file.txt"
  config <<'YML'
base_repo: ../base
worktree_root: .
copy:
  - file.txt
YML
  local p; p="$(wt create tracked 2>/dev/null)"
  assert_eq "$(cat "$p/file.txt")" "hello" "checked-out file wins"
}

test_seeded_files_do_not_dirty_the_worktree() {
  printf 'SECRET=1\n' > "$TEST_TMP/base/.env"
  mkdir -p "$TEST_TMP/base/.venv"
  seeding_config
  local p; p="$(wt create seeded 2>/dev/null)"
  run git -C "$p" status --porcelain --untracked-files=all
  assert_empty "$stdout" "worktree status"
}

test_exclude_block_lands_in_the_shared_exclude() {
  printf 'SECRET=1\n' > "$TEST_TMP/base/.env"
  seeding_config
  wt create seeded >/dev/null 2>&1
  local ex; ex="$(cat "$TEST_TMP/base/.git/info/exclude")"
  assert_contains "$ex" "/.wt.env"
  assert_contains "$ex" "/.env"
}

test_env_var_lists_override_yml() {
  printf 'SECRET=1\n' > "$TEST_TMP/base/.env"
  local p; p="$(wtenv WT_COPY=".env" -- create envlist 2>/dev/null)"
  assert_file "$p/.env"
}
