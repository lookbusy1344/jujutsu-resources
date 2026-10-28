---
name: jj-version-control
description: Essentials for driving Jujutsu (jj) version control non-interactively — mental model, everyday commands, bookmarks, undo, and the GitHub PR workflow. Use whenever a repo is jj-managed (jj root succeeds) or the user asks about jj/Jujutsu commands.
---

# Jujutsu (jj) essentials

Condensed from `references/jj-reference.md` (jj v0.46.0), the full reference. Read it for: revsets,
change-vs-commit IDs, `GIT_DIR`/work-tree env for colocated repos, reftable migration, anonymous
branches, history reorganising (`squash --into`, `absorb`, split), conflict resolution, tags,
stacked PRs, keeping a PR current with main.

## Detecting jj vs plain git

`jj --ignore-working-copy root` (no snapshot). Success: jj repo, probably colocated (`.jj` + real
`.git`) — use jj, not mutating `git`. Failure: plain git.

## Mental model

- **No staging area.** The working copy is a commit (`@`). Every jj command snapshots pending edits
  into `@` first.
- **Change ID** (`qpvuntsm`) is stable across rewrites; **commit ID** (hex) changes on every
  amend/rebase/describe. Use change IDs in scripts, commit IDs to pin a version.
- `@` = working copy, `@-` = its parent, `x-`/`x+` = parent/child of x.
- History editing is normal: no `--force`, and `jj undo` exists.
- Conflicts never block a command; they are recorded in commits and resolved later.
- Everything is recoverable via the operation log.

## Rules for scripts/agents

- Pass `-m "msg"` to `describe`/`commit`/`squash`; never rely on an editor.
- Use `--no-pager`, or scope history-changing commands with `-r`.
- Do not bypass immutability with `--ignore-immutable` routinely.
- Do not run mutating `git` concurrently with jj in a colocated repo (import/export races).
- `git status` shows ` M` but `jj st` is clean and `git diff` is empty: stale Git index cache. Fix:
  `git read-tree HEAD && git update-index -q --refresh`.
- On error: `jj op log`, then `jj undo`. Do not hand-repair the graph.

## Snapshots

Nearly every jj command snapshots `@` first, including `jj log` and `jj op log`. Sequential
snapshots are harmless. Two at once record concurrent operations that rewrite `@` and leave a
divergent change.

- Mutating commands (`describe`, `commit`, `new`, `squash`, `rebase`, `git push`) snapshot on their
  own. Do not run `jj st` before them.
- Run `jj st` once at the start of a task and once to review a batch of edits, not every turn or
  between file writes. Read files directly when that answers the question.
- History/operation reads (`log`, `show <committed-rev>`, `op log`, `evolog`, `bookmark list`): pass
  `--ignore-working-copy`. Output reflects the last snapshot. Never use it with `st` or `diff` of
  `@` (hides unsaved edits) or with mutating commands (leaves the working copy stale).
- Never issue jj commands in parallel tool calls. One snapshotting command at a time per checkout
  (without `jj workspace add` there is one checkout).
- Subagents in this checkout run jj only with `--ignore-working-copy`; the parent snapshots.
- Background tools (watchman triggers, editor integrations, dashboards polling `jj log`) also
  snapshot and race with the agent unless they pass `--ignore-working-copy`.

## Revsets

Used with `-r`. Full set algebra and more patterns in the reference.

- `x::y` is the connected span from x to y, both included. `x..y` is `::y ~ ::x` (what y adds over
  x). They differ at merges. To discard a branch off `common`, use `n1::tip` or `common+::tip`;
  `common::tip` includes `common`, and `::tip` has no lower bound.
- Precedence: `&` and infix `~` share a level, so parenthesise mixes. `(a | b)..` means
  `a.. & b..`.
- `description(x)` and `author(x)` match exactly and descriptions keep a trailing newline, so
  `description("mid")` is a silent empty set. Use `substring:` or `glob:`.
- Not valid: `local_bookmarks()` (use `bookmarks()`), `conflict()` (use `conflicts()`), `obslog()`
  (use `jj evolog -r`).

| Revset | Yields |
|--------|--------|
| `trunk()..@` | unlanded work |
| `remote_bookmarks()..bookmarks()` | local commits a push would send |
| `heads(all())` / `visible_heads()` | every visible tip, including anonymous |
| `reachable(@, mutable())` | whole mutable stack around `@` |
| `ancestors(@, 5)` | `@` plus four generations back |
| `conflicts()` / `divergent()` | conflicted / divergent changes |
| `mutable() & mine()` | your rewritable commits |
| `fork_point(a \| b)` | last commit a and b share |
| `roots(x::y)` | first commit(s) of a span |

## Setup

```bash
jj git init                     # adopt existing repo in cwd; colocated by default
jj git clone <url> [dir]        # colocated by default
jj bookmark track main@origin   # remote bookmarks are imported but not auto-tracked
```

With `reftable` ref format, `jj git init` reports success but imports nothing (`jj st` shows every
file added). Check `git rev-parse --show-ref-format`; if needed run
`git refs migrate --ref-format=files` first.

## Everyday commands

```bash
jj st                        # snapshot + status
jj log                       # mutable revisions + context
jj log -r 'trunk()..@'       # unlanded work
jj diff [-r <rev>]           # default @
jj show <rev>                # description + diff

jj describe -m "msg"         # set message on @
jj new                       # new empty change on @
jj new <rev1> <rev2> ...     # merge (no `jj merge`)
jj commit -m "msg"           # describe @ + new

jj squash                    # move @ into @- (fixup)
jj squash --into <change-id> # move @ into any ancestor
jj squash <path>...          # only these paths
jj absorb                    # distribute @'s hunks into the ancestors that last touched those lines
                             # (good for PR review fixes)

jj edit <rev>                # make <rev> the working copy
jj abandon <rev>             # drop a change, rebase descendants onto its parent
jj rebase -s <src> -o <dest> # move src + descendants
jj rebase -b <branch> -o <dest>
```

No `jj add` and no amend: editing files while `@` is a change amends it.

## Bookmarks

No "current branch": bookmarks are named pointers that move only when told to.

```bash
jj bookmark list
jj bookmark create <name> [-r <rev>]
jj bookmark set <name> -r <rev>      # create or move
jj bookmark track <name>@<remote>
jj bookmark delete <name>            # pushed as a remote deletion
```

`set`/`move` refuse backward/sideways moves without `-B`/`--allow-backwards`.

### Bookmark divergence (`name@git`, `name@origin`)

Colocated bookmarks have three positions: jj, the git-ref mirror `name@git`, and each
`name@origin`. A ref moved outside jj yields a conflicted bookmark (`name??` in `jj log`, two
targets in `jj bookmark list`). Causes:

- **Raw git ref mutations** (`git branch -f`, `commit`, `checkout -b`, `push`, `merge`, `rebase`).
  Move with `jj bookmark set`, publish with `jj git push`. `git fetch` is fine.
- **Fetch onto a locally-moved bookmark** that someone else also moved on the remote. Fetch before
  moving a shared bookmark, or rebase onto the fetched position before pushing.
- **Concurrent jj in one workspace**: divergent changes strand the bookmark (see Snapshots).

Fix: pick the intended target and point every position at it.

```bash
jj bookmark list <name>
jj bookmark set <name> -r <intended> [-B]
jj git fetch                  # reconcile a conflicted @origin first
jj git push -b <name>
```

A stale `name@git` with the jj bookmark already correct clears on the next snapshot or
`jj git export`. Never hand-edit `.git/refs`.

## Remotes / GitHub

```bash
jj git fetch
jj git push                         # tracked bookmarks; force-with-lease is automatic
jj git push -b <bookmark>
jj git push --dry-run -b <bookmark>
```

If a `pmain` alias exists (see Aliases), `jj pmain` moves `main` to `@-` and pushes. Push only with
explicit permission.

No `jj pull`: fetch, then rebase your bookmark onto the remote.

PR loop:

```bash
jj git fetch
jj new main@origin
# edit, jj commit -m "..."
jj bookmark create my-feature -r @-     # tip is @-; @ is the empty working commit
jj git push -b my-feature
gh pr create --head my-feature --fill

# review fixes
jj absorb
jj git push -b my-feature

# after merge
jj git fetch
jj bookmark delete my-feature
jj git push --deleted
```

`jj git push` refuses commits with no description, with conflicts, or marked private.

## Pre-commit / pre-push checks

jj runs no git hooks. Manual substitutes:

```bash
jj fix -s 'trunk()..@'                                    # formatters (stdin to stdout)
jj run -r 'trunk()..@' --ignore-changes -j 4 -- <check>   # check each change in isolation
```

- `jj fix` rewrites content and cannot reject a change. Report-only tools (clippy, tests) belong in
  `jj run --ignore-changes`, which exits non-zero if any revision fails.
- Each `jj run` revision gets its own checkout with a cold build cache. Prefer fast checks
  (`cargo check`, unit tests).
- To gate a push, chain checks in an alias via `jj util exec` or a task-runner recipe and call that
  instead of `jj git push`.

See `references/jj-reference.md` ("Running formatters — jj fix", "Run commands across revisions").

## Undo / recovery

```bash
jj undo / jj redo            # repeatable
jj op log                    # timeline of repo states
jj op show <op-id>
jj op restore <op-id>        # new operation matching an earlier state
```

`undo`/`redo` refuse an operation from another workspace; pass `--allow-cross-workspace` or use
`jj op revert <op-id>`.

Prefer these over manual graph surgery.

## Aliases

An alias runs exactly one jj subcommand; there is no chaining. To chain, use `jj util exec`:

```toml
[aliases]
pmain = ["util", "exec", "--", "sh", "-c", "jj bookmark set main -r @- && jj git push --bookmark main"]
```

Config: `~/.config/jj/config.toml`; edit with `jj config edit --user` or
`jj config set --user <key> <value>`.
