# wt — a generic git-worktree manager

A small, repo-agnostic script to create, rebase, commit, and delete git
worktrees, keeping the base branch up to date automatically. All settings live
in a `wt.yml` file, so the same script works for any repo.

## Layout

```
Projects/
├── shallowflaws/        ← the base repo (stays on latest main)
└── wt-shallowflaws/
    ├── wt               ← the script
    ├── wt.yml           ← configuration (points at ../shallowflaws)
    ├── wt.yml.example   ← template to copy for other repos
    ├── .gitignore       ← ignores `wt-*/`
    ├── tests/           ← the test suite (`./tests/run.sh`)
    ├── README.md        ← this file
    └── wt-<name>/       ← each worktree you create lives here
        └── .wt.env      ← its name, index and port range
```

Worktree **directories** carry a prefix (`wt-` by default) so a single
`.gitignore` line keeps them all out of git. The **branch** name is never
prefixed — see [Directory prefix](#directory-prefix).

## Setup

The script ships without a `wt.yml` — create one from the template and fill in
your repo:

```bash
cp wt.yml.example wt.yml
$EDITOR wt.yml
```

At minimum, point **`base_repo`** at the repo you want worktrees of (a path
relative to `wt.yml`, or an absolute one). The rest have working defaults:

| Key | Fill in | Default |
|---|---|---|
| `base_repo` | **Required** — path to the main repo, e.g. `../shallowflaws` | — |
| `worktree_root` | Where worktrees are created; `.` means next to `wt.yml` | `.` |
| `dir_prefix` | Prefix for worktree directories, so `wt-*/` can be gitignored | `wt-` |
| `manage_gitignore` | Whether `wt` maintains the ignore rule for you | `true` |
| `main_branch` | The base branch, if it isn't `main` (e.g. `master`) | `main` |
| `remote` | The remote to fetch/push, if it isn't `origin` | `origin` |
| `date_format` | `strftime` format for the date in auto-named branches | `%d-%m-%Y` |
| `commit_prefix` | Prefix for `wt commit`'s default message | `wip` |
| `copy` / `link` | Ignored files each worktree needs (`.env`, `.venv`) — see [Parallel worktrees](#parallel-worktrees-and-agents) | — |
| `port_base` / `port_stride` | Give each worktree its own port range | off / `10` |
| `post_create` | Command to run in a freshly created worktree | — |
| `active_link` | Stable path pointing at the active worktree — see [Activating](#activating-a-worktree) | — |
| `pre_activate` / `post_activate` | Commands run around a switch (stop / start the server) | — |

Then check that it resolved the way you expect, and create your first worktree:

```bash
./wt config
./wt create "my first branch"
```

`wt config` prints absolute paths, so it will tell you immediately if
`base_repo` points somewhere wrong. Keep `wt.yml.example` around as the
template — copy it again for another repo.

## Configuration

All settings come from `wt.yml`. The script searches for it in this order:

1. `$WT_CONFIG` — an explicit path
2. `wt.yml` next to the script
3. `wt.yml` in the current directory, then walking up parents

Paths are resolved relative to the config file (absolute paths are left as-is).

```yaml
base_repo: ../shallowflaws     # the main repo, kept on latest main
worktree_root: .               # where worktrees are created
dir_prefix: "wt-"              # prefix for worktree directories (not branches)
manage_gitignore: true         # keep the dir_prefix rule in .gitignore up to date
main_branch: main              # base branch, always pulled to latest
remote: origin                 # git remote to fetch/push
date_format: "%d-%m-%Y"        # date prefix for auto-named branches (strftime)
commit_prefix: wip             # default `wt commit` message prefix

port_base: 8000                # worktree N gets ports 8000 + N*port_stride
port_stride: 10
post_create: pipenv install    # run inside each new worktree
copy:                          # seeded per worktree (ignored files git won't bring)
  - .env
  - .claude/settings.local.json
link:                          # shared with the base repo via symlink
  - .venv
```

Every key can also be overridden per-run by its matching env var:
`WT_BASE_REPO`, `WT_WORKTREE_ROOT`, `WT_DIR_PREFIX`, `WT_MANAGE_GITIGNORE`,
`WT_MAIN_BRANCH`, `WT_REMOTE`, `WT_DATE_FORMAT`, `WT_COMMIT_PREFIX`,
`WT_PORT_BASE_CFG`, `WT_PORT_STRIDE`, `WT_POST_CREATE`, `WT_ACTIVE_LINK`,
`WT_PRE_ACTIVATE`, `WT_POST_ACTIVATE`, and `WT_COPY` / `WT_LINK`
(space-separated). Run `./wt config` to print the resolved settings.

The three command keys (`post_create`, `pre_activate`, `post_activate`) accept a
YAML block scalar, so a multi-line hook doesn't have to be crammed onto one line:

```yaml
post_activate: |
  cd "$WT_ACTIVE_LINK"
  docker compose up -d
```

**Using it for another repo:** drop the `wt` script in a directory next to that
repo and run through [Setup](#setup) again with a fresh copy of
`wt.yml.example`. One `wt` script per repo, each with its own `wt.yml` — or keep
a single script and point `$WT_CONFIG` at whichever `wt.yml` you want.

## Usage

Run from inside `wt-shallowflaws/`:

```bash
./wt <command> [args]
```

| Command | What it does |
|---|---|
| `./wt create <slug>` | Fetch origin, fast-forward `main`, then create a worktree in **`wt-DD-MM-YYYY-N-<slug>/`** on a new branch **`DD-MM-YYYY-N-<slug>`** off **latest main**. |
| `./wt create <slug> --from <branch>` | Same, but branch off `<branch>` (local or `origin/<branch>`) instead of `main`. |
| `./wt create <name> --raw` | Skip auto-naming and use `<name>` verbatim as the branch/worktree name. |
| `./wt rebase <name>` | Update `main`, then rebase the worktree's branch onto **latest `origin/main`**. |
| `./wt rebase <name> --onto <branch>` | Rebase onto another branch instead of `main`. |
| `./wt commit <name>` | Stage **all** changes in the worktree and commit with a generic message (`wip: DD-MM-YYYY HH:MM`). |
| `./wt commit <name> -m "msg"` | Same, but with your own commit message. |
| `./wt commit <name> --push` | Commit, then `git push -u origin HEAD` (creates the remote branch on first push). |
| `./wt delete <name>` | Remove the worktree and delete its branch (only if fully merged). |
| `./wt delete <name> --force` | Also discard uncommitted changes in the worktree. |
| `./wt delete <name> --keep-branch` | Remove the worktree but keep the branch. |
| `./wt clean --merged` | Remove every worktree whose branch is merged into `main` (asks first). |
| `./wt clean --gone` | Same, for branches whose remote was deleted — catches squash-merged PRs. |
| `./wt clean --merged --dry-run` | List what would be removed. Add `--yes` to skip the prompt. |
| `./wt activate <name>` | Make it the active worktree: run `pre_activate`, repoint `active_link`, run `post_activate`. |
| `./wt create <slug> --activate` | Create and activate in one step. |
| `./wt active` | Print the active worktree's name (`--path` for its path). |
| `./wt path <name>` | Print a worktree's path: `cd "$(./wt path 10-09-2026-1-add-search)"`. |
| `./wt exec <name> -- <cmd>` | Run a command inside one worktree, with its `WT_*` environment. |
| `./wt each -- <cmd>` | Run a command inside every worktree (`--keep-going` to not stop at the first failure). |
| `./wt list --json` | Same as `list`, as JSON — for scripts and orchestrators. |
| `./wt config` | Print the resolved configuration (which `wt.yml`, paths, etc). |
| `./wt update` | Just fetch origin and fast-forward `main` in the base repo. |
| `./wt list` | List worktrees with index, ports, dirty flag and ahead/behind `main`. |
| `./wt gitignore` | Rewrite the managed `.gitignore` block to match `dir_prefix`. |
| `./wt gitignore --check` | Report whether it is up to date; exits non-zero if not (for CI / hooks). |
| `./wt help` | Show usage. |

## Naming

`create` names branches/worktrees using the repo convention
**`DD-MM-YYYY-N-slug`** (e.g. `10-09-2026-1-add-search`):

- **`DD-MM-YYYY`** — today's date.
- **`N`** — the next unused sequence number for today (looks at existing
  branches *and* worktree dirs, so gaps from deletions don't reuse a number).
- **`slug`** — your text, lowercased with non-alphanumerics collapsed to dashes
  (`"Add Search!"` → `add-search`).

Pass `--raw` to bypass this and name the branch exactly what you type.

## Directory prefix

Worktrees are created at **`<worktree_root>/<dir_prefix><name>`**, with
`dir_prefix` defaulting to **`wt-`**. The prefix applies to the *directory only*
— the branch keeps the bare name — so one ignore rule covers every worktree.

### The ignore rule is generated

`.gitignore` has no variables, so `wt` derives the rule from `dir_prefix` and
maintains it for you, in a marked block in the `.gitignore` of whichever repo
contains `worktree_root`:

```gitignore
# >>> wt worktrees (managed by wt — edits below are overwritten) >>>
# Generated from dir_prefix in wt.yml. Re-run: wt gitignore
/wt-*/
# <<< wt worktrees <<<
```

The block is rewritten on every `./wt create`, and on demand with
`./wt gitignore` — so changing `dir_prefix` in `wt.yml` updates the rule instead
of leaving a stale one behind. Everything outside the markers is left alone, and
the rule is anchored to `worktree_root`'s path within the repo (`/trees/wt-*/`
if the root is a `trees/` subdirectory), so it can't ignore lookalike
directories elsewhere.

Two cases worth knowing:

- **`dir_prefix: ""`** — no rule can be generated (`/*/` would ignore every
  directory in the repo), so `wt` removes the block and warns instead.
- **`worktree_root` outside any repo** — nothing to ignore; `wt` says so and
  moves on.

Set `manage_gitignore: false` if you would rather write the rule yourself. To
make sure the rule stays current in CI or a pre-commit hook:

```bash
./wt gitignore --check    # non-zero exit if .gitignore doesn't match dir_prefix
```

Commands take the **bare name** (= the branch name) and add the prefix for you:

```bash
./wt create "add search"                # → wt-10-09-2026-1-add-search/  (branch: 10-09-2026-1-add-search)
./wt commit 10-09-2026-1-add-search     # bare name
./wt commit wt-10-09-2026-1-add-search  # the directory name works too (shell tab-completion)
```

Set your own prefix, or turn prefixing off, in `wt.yml`:

```yaml
dir_prefix: "tree_"    # → tree_10-09-2026-1-add-search/
dir_prefix: ""         # → 10-09-2026-1-add-search/   (old behavior, nothing to ignore)
```

Worktree directories created before this existed (unprefixed) are still found
by `commit` / `rebase` / `delete`, and still count toward the daily sequence
number — nothing to rename.

## Parallel worktrees (and agents)

Worktrees are cheap, so it is tempting to run several at once — by hand, or with
one coding agent per branch. Four things make that actually work.

### Each worktree is usable the moment it exists

A fresh worktree contains only what git tracks. Everything ignored — `.env`,
`.venv/`, `node_modules/`, `.claude/settings.local.json` — is missing, so the
app can't boot and an agent re-asks for permissions it was already granted.
`copy:` and `link:` fix that:

```yaml
copy:                            # a private copy per worktree
  - .env
  - .claude/settings.local.json
link:                            # one shared copy, symlinked
  - .venv
  - node_modules
```

Copy what a worktree should be able to diverge on; link what is large and
shared. **A linked dependency directory is shared state** — `npm install` in one
worktree changes it for all of them. If the branches disagree about
dependencies, copy instead, or install in `post_create`.

Sources are relative to `base_repo`. Missing ones are skipped with a warning
(no `.venv` yet is fine), and nothing git checked out is ever overwritten.

### Each worktree has an index, and can have its own ports

Every worktree is assigned the lowest free integer, kept in the base repo's git
config so it survives everything but `delete` (which frees it for reuse). Set
`port_base`, and each one also gets a private range:

```yaml
port_base: 8000
port_stride: 10       # worktree 1 -> 8010, worktree 2 -> 8020, ...
```

Both are written to `.wt.env` in the worktree, and exported to `post_create`,
`exec` and `each`:

```bash
WT_NAME="10-09-2026-1-add-search"
WT_INDEX="1"
WT_PORT_BASE="8010"
WT_PATH="/Users/you/Projects/wt-shallowflaws/wt-10-09-2026-1-add-search"
WT_BASE_REPO="/Users/you/Projects/shallowflaws"
```

Read it as a dotenv file, `source` it, or have `post_create` splice the ports
into the worktree's own `.env`. Note that `wt` only *allocates* the numbers —
making the app listen on them is the project's job.

> One caveat for the `shallowflaws` stack: its `docker-compose.yml` binds fixed
> host ports (5432, 6380, 1025, 8025, 9000/9001, 80/443), so a second `docker
> compose up` fails to bind. The workable shape is one shared infrastructure
> stack from the base repo plus per-worktree *application* ports — and, if you
> want each worktree reachable over HTTPS, a Caddy site per index
> (`wt1.localhost` → `8010`) instead of a single `localhost` block.

### `post_create` provisions it

Runs inside the new worktree with all of the above set:

```yaml
post_create: 'pipenv install --dev && createdb "app_wt$WT_INDEX"'
```

A failure is reported and leaves the worktree in place; `wt create` exits
non-zero so a supervisor notices. Skip it for one run with `--no-hook`.

### Concurrent `create` is safe

`create` takes a lock on the base repo for the part that allocates a sequence
number, an index and a directory, so ten agents starting at once get ten
distinct worktrees instead of colliding on `10-09-2026-1-…`. The lock is only
held around that allocation — the fetch happens outside it.

### Output is scriptable

Diagnostics go to **stderr**, data to **stdout**, and colors switch off when
stdout isn't a terminal (or `NO_COLOR` is set). So:

```bash
path=$(./wt create "add search")           # stdout is exactly the path
cd "$(./wt path 10-09-2026-1-add-search)"
./wt list --json | jq -r '.[] | select(.dirty) | .name'
./wt each --keep-going -- pytest -q        # non-zero exit if any worktree fails
```

`./wt list --json` gives an orchestrator the whole picture:

```json
[
  {"name": "10-09-2026-1-add-search", "path": "/…/wt-10-09-2026-1-add-search",
   "branch": "10-09-2026-1-add-search", "index": 1, "port_base": 8010,
   "dirty": false, "ahead": 2, "behind": 0, "head": "b5bd2ad",
   "subject": "add search endpoint"}
]
```

### Cleaning up

Agent workflows generate a lot of dead worktrees:

```bash
./wt clean --merged --gone --dry-run   # see what would go
./wt clean --merged --gone --yes       # remove it
```

`--merged` catches branches merged into `main`; `--gone` catches branches whose
remote was deleted, which is how a squash-merged PR looks locally. Worktrees
with uncommitted changes are always skipped and reported. On a terminal `clean`
lists what it will remove and asks for confirmation; with no terminal (a script,
CI, an agent) it refuses to proceed unless you pass `--yes`.

### One file wt writes outside the worktrees

`.wt.env` would otherwise show up as untracked in every worktree, so `wt` adds a
managed block to the base repo's `.git/info/exclude` (git has no per-worktree
exclude file). It is local, never committed, and lists `.wt.env` plus your
`copy:`/`link:` entries — the latter because a linked directory arrives as a
*symlink*, which a trailing-slash pattern like `.venv/` no longer matches.

## Activating a worktree

`wt activate <name>` makes one worktree *the* current one:

```bash
./wt activate 10-09-2026-1-add-search
./wt active           # -> 10-09-2026-1-add-search
./wt active --path    # -> /Users/you/Projects/wt-shallowflaws/wt-10-09-2026-1-add-search
./wt list             # the active one is marked with *
```

It does three things, in order: runs **`pre_activate`**, repoints
**`active_link`** at the worktree, runs **`post_activate`**. A failing
`pre_activate` aborts the switch — nothing is repointed — so a hook can refuse
to hand over (pending migrations, a dirty database) by exiting non-zero.

### What "the running server picks it up" actually means

Be clear-eyed about this: **a process that is already running cannot be moved to
different code by flipping a symlink.** It resolved its paths at startup, and
`uvicorn --reload` / Vite watch the *resolved* directory, so they will not
notice. Anything that claims otherwise is restarting something.

There are two shapes that do work, and `wt` supports both through the hooks:

**1. One server, restarted onto the new tree.** `active_link` gives you a fixed
path to start from, and the hooks stop and start the process:

```yaml
active_link: ./current
pre_activate: |
  if [ -n "$WT_PREVIOUS_PATH" ] && [ -f "$WT_PREVIOUS_PATH/server.pid" ]; then
    kill "$(cat "$WT_PREVIOUS_PATH/server.pid")" 2>/dev/null || true
    rm -f "$WT_PREVIOUS_PATH/server.pid"
  fi
  alembic upgrade head
post_activate: |
  cd "$WT_ACTIVE_LINK"
  pipenv run dev & echo $! > "$WT_PATH/server.pid"
```

Now the port stays the same and `./wt activate <other>` swaps what is being
served. (Careful with the PID: backgrounding a `cd x && cmd` *list* gives you
the subshell's PID, not the server's, and killing it leaves the old process
holding the port. Background the command itself, as above.)

**2. Every worktree keeps running; the proxy switches.** This is the better fit
for `shallowflaws`, which already has Caddy in front. Each worktree has its own
`WT_PORT_BASE`, so its servers can all stay up; activating only rewrites which
upstream `https://localhost` points at, and `caddy reload` applies it gracefully
without dropping connections:

```yaml
post_activate: |
  printf 'reverse_proxy 127.0.0.1:%s\n' "$WT_PORT_BASE" > "$WT_BASE_REPO/docker/caddy/active.conf"
  docker compose -f "$WT_BASE_REPO/docker/docker-compose.yml" exec -w /etc/caddy caddy caddy reload
```

with the Caddyfile importing that snippet. Here nothing restarts at all — the
next request simply lands on the newly active worktree. Keeping a per-index
hostname (`wt2.localhost` → `8020`) alongside means every worktree stays
reachable while one of them owns the canonical URL.

### Hook environment

Both hooks run **inside the incoming worktree** and receive its `WT_NAME`,
`WT_BRANCH`, `WT_PATH`, `WT_INDEX`, `WT_PORT_BASE`, `WT_BASE_REPO` and
`WT_MAIN_BRANCH`, plus:

| Variable | Meaning |
|---|---|
| `WT_PREVIOUS_NAME` | The worktree being deactivated (empty on the first activation) |
| `WT_PREVIOUS_PATH` | Its path, so `pre_activate` can stop its server |
| `WT_ACTIVE_LINK` | The stable path — during `pre_activate` it still points at the old worktree, during `post_activate` at the new one |

`--no-hook` skips both, for when you only want the link moved.

### Notes

- `active_link` is a symlink `wt` maintains; it is added to the managed
  `.gitignore` block automatically.
- If the path exists and is *not* a symlink, `wt` refuses to touch it.
- Deleting the active worktree clears the marker and removes the dangling link.
  Its server is **not** stopped, though — and if the PID file lived inside that
  worktree it is gone too, leaving an orphan holding the port. Keep the PID
  outside the tree (`"$WT_BASE_REPO/.wt-server-$WT_INDEX.pid"`), or have
  `pre_activate` kill by port (`lsof -ti :8000 | xargs -r kill`) so a stale
  process can never outlive the worktree that started it.
- Activating the worktree that is already active re-runs both hooks — a
  convenient "restart the server" that needs no separate command.

## Examples

```bash
# New feature — becomes e.g. 10-09-2026-1-add-search
./wt create "add search"

# Second one today — becomes 10-09-2026-2-fix-tests
./wt create fix-tests

# Branch off an existing branch instead of main
./wt create hotfix --from 15-07-2026-1-fix-tests

# Exact name, no date/number prefix
./wt create experiment-xyz --raw

# Bring a worktree up to date with main
./wt rebase 10-09-2026-1-add-search

# Done — remove the worktree and its (merged) branch
./wt delete 10-09-2026-1-add-search
```

Driving several at once:

```bash
# Fan out three tasks; each returns its path on stdout
for task in "add search" "fix flaky tests" "bump deps"; do
  ./wt create "$task"
done

# What is in flight?
./wt list

# Run the suite everywhere, don't stop at the first red one
./wt each --keep-going -- pytest -q

# Anything with uncommitted work?
./wt list --json | jq -r '.[] | select(.dirty) | .name'

# Reap what has landed
./wt clean --merged --gone --dry-run

# Point the dev server at one of them, then swap
./wt activate 10-09-2026-1-add-search
./wt activate 10-09-2026-2-fix-flaky-tests
```

## Behavior notes

- **`main` is always refreshed** before create/rebase: fetches with `--prune`
  and **fast-forwards only** — a diverged local `main` fails loudly instead of
  merging silently.
- **Dirty base repo is respected**: if `main` has uncommitted changes, the
  fast-forward is skipped with a warning rather than clobbering your work.
- **New branch name = worktree directory name**, minus `dir_prefix`. If a
  branch with that name already exists, it is checked out instead of erroring.
- **Rebase refuses on uncommitted changes**, and on conflict prints the exact
  `git rebase --continue` / `--abort` commands to run.
- **Delete only removes merged branches** automatically; an unmerged branch is
  kept and the `git branch -D` command to force-delete it is printed.
- **Indices are recycled.** Deleting worktree 2 frees index 2 (and ports 8020+)
  for the next `create` — stable while a worktree lives, not unique forever.
- **`each` stops at the first failure** unless you pass `--keep-going`, and
  exits non-zero if any worktree failed.
- **A failing `pre_activate` cancels the switch**; a failing `post_activate`
  does not (the worktree is already active), it just warns and exits non-zero.

## Tests

```bash
./tests/run.sh                # everything, in parallel, plus shellcheck
./tests/run.sh activate       # only tests whose name matches "activate"
./tests/run.sh -j1            # serially, when a failure is hard to read
./tests/run.sh --no-lint      # skip shellcheck
```

104 tests, ~15s. No dependencies beyond bash and git — no bats, no npm.

Each test runs in its own subshell with `set -e` (so the first failed assertion
ends that test) against its own throwaway git repos under `$TMPDIR`: a bare
"remote", a "base" clone, and a "host" directory holding `wt.yml`. Nothing
touches the repo you are working in, `git` runs with `GIT_CONFIG_GLOBAL` and
`GIT_CONFIG_SYSTEM` pointed at `/dev/null`, and every `WT_*` variable is unset
first, so your shell environment can't change the result. The suite also runs a
*copy* of `wt` from that temp directory, so the real `wt.yml` next to the script
is never picked up (the script prefers that file over the one in `$PWD`). Because tests share
nothing, the runner runs one per CPU by default.

### Writing one

Add a `test_*` function to any `tests/*.test.sh` file. The runner finds it by
name and calls `fixture` for you first, leaving you in the host directory:

```bash
test_create_makes_prefixed_dir_and_bare_branch() {
  run wt create "add search"           # captures $status, $stdout, $stderr
  assert_ok
  local name; name="$(name_n 1 add-search)"
  assert_dir "$TEST_TMP/host/wt-$name"
  assert_branch_exists "$name"
}
```

`tests/helpers.sh` has the vocabulary: `wt`, `wtenv VAR=x -- args`, `run`,
`config <<YML`, `base_git`, `name_n <n> <slug>`, and `assert_eq` /
`assert_contains` / `assert_status` / `assert_symlink_to` /
`assert_branch_gone` and friends. Two things to know:

- `wt` is a shell function, so `env VAR=1 wt …` can't work — use
  `wtenv VAR=1 -- …`.
- Names contain today's date, so build them with `name_n 1 add-search`, never
  by hardcoding.

### What is covered

Config parsing, naming and prefixes, the generated `.gitignore`, seeding,
indices and ports, `post_create`, activation and its hooks, `list`/`path`/
`exec`/`each`, `delete`/`clean`/`rebase`/`commit`, concurrent `create`, and
awkward layouts (paths with spaces, symlinked roots, legacy unprefixed
directories). Every bug found while building `wt` has a regression test — each
is commented with the failure it locks down, so the reason it exists survives.

### shellcheck

`tests/lint.sh` runs it over `wt` and the suite; `run.sh` calls it at the end
and reports a **skip** rather than a failure when it isn't installed:

```bash
brew install shellcheck
```

Both are clean at default settings. The few suppressions in `wt` are local, with
a comment giving the reason (deliberate word-splitting on `WT_COPY`, a `$` that
is a regex anchor rather than an expansion). `.shellcheckrc` only teaches it
where to find sourced files.

## Optional: call `wt` from anywhere

Add an alias to your `~/.zshrc`:

```bash
alias wt='/Users/kaarlekulvik/Projects/wt-shallowflaws/wt'
```

Then `wt create ...` works from any directory.
