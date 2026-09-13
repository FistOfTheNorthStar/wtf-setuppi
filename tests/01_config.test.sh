# shellcheck shell=bash
# Sourced by tests/run.sh after helpers.sh, in the same shell: run() assigns
# $status/$stdout/$stderr, and single-quoted hook bodies must stay unexpanded.
# shellcheck disable=SC2154,SC2016
# Config parsing: defaults, overrides, lists, block scalars, validation.

test_defaults_are_applied() {
  run wt config
  assert_ok
  assert_contains "$stdout" "main_branch : main"
  assert_contains "$stdout" "remote      : origin"
  assert_contains "$stdout" "dir_prefix  : wt-"
  assert_contains "$stdout" "port_stride : 10"
  assert_contains "$stdout" "port_base   : (disabled)"
}

test_env_overrides_yml() {
  run wtenv WT_MAIN_BRANCH=trunk WT_DIR_PREFIX=tree_ -- config
  assert_ok
  assert_contains "$stdout" "main_branch : trunk"
  assert_contains "$stdout" "dir_prefix  : tree_"
}

test_missing_config_is_a_clear_error() {
  rm -f wt.yml
  cd "$TEST_TMP" || exit 1
  run wt config
  assert_fails
  assert_contains "$stderr" "cp wt.yml.example wt.yml"
}

test_inline_comments_and_quotes_are_stripped() {
  config <<'YML'
base_repo: ../base      # trailing comment
worktree_root: .
dir_prefix: "wt-"       # quoted value
commit_prefix: 'draft'
YML
  run wt config
  assert_ok
  assert_contains "$stdout" "dir_prefix  : wt-"
  assert_contains "$stdout" "commit_prefix: draft"
  assert_not_contains "$stdout" "trailing comment"
}

test_block_scalar_hooks_are_read() {
  config <<'YML'
base_repo: ../base
worktree_root: .
post_create: |
  echo one
  echo two
YML
  run wt config
  assert_ok
  assert_contains "$stdout" "echo one"
  assert_contains "$stdout" "echo two"
}

test_folded_block_scalar_joins_lines() {
  config <<'YML'
base_repo: ../base
worktree_root: .
post_create: >
  echo one
  echo two
YML
  run wt config
  assert_contains "$stdout" "echo one echo two"
}

test_yaml_lists_are_read() {
  config <<'YML'
base_repo: ../base
worktree_root: .
copy:
  - .env
  - .claude/settings.local.json
link:
  - .venv
YML
  run wt config
  assert_contains "$stdout" "copy        : .env .claude/settings.local.json"
  assert_contains "$stdout" "link        : .venv"
}

test_bad_dir_prefix_is_rejected() {
  run wtenv WT_DIR_PREFIX=a/b -- config
  assert_fails
  assert_contains "$stderr" "must not contain"
}

test_bad_port_base_is_rejected() {
  run wtenv WT_PORT_BASE_CFG=abc -- config
  assert_fails
  assert_contains "$stderr" "port_base must be a number"
}

test_bad_manage_gitignore_is_rejected() {
  run wtenv WT_MANAGE_GITIGNORE=maybe -- config
  assert_fails
  assert_contains "$stderr" "must be true or false"
}

test_missing_base_repo_is_rejected() {
  config <<'YML'
worktree_root: .
YML
  run wt config
  assert_fails
  assert_contains "$stderr" "'base_repo' is required"
}

test_help_needs_no_config() {
  rm -f wt.yml
  cd "$TEST_TMP" || exit 1
  run wt help
  assert_ok
  assert_contains "$stdout" "wt create"
  assert_contains "$stdout" "wt activate"
}
