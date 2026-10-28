# Jujutsu (jj) — Reference for Agents and Humans

**Validated:** 2026-10-08 · **jj version:** v0.46.0 · docs: `jj-vcs.dev/latest`

Guide to driving `jj` non-interactively. Assumes git familiarity.

## Repository layouts

1. **Colocated (default)** — `.jj` and a real `.git` share one working tree. jj imports/exports git
   state on every command, so `git`, `gh`, IDEs and CI see a normal git repo. `jj git init` and
   `jj git clone` produce this in v0.45.
2. **Non-colocated** — only `.jj`; the git store sits in `.jj/repo/store/git`. Same Git backend
   (push/fetch identical), but external git tools cannot see it. Opt in with `--no-colocate` or
   `git.colocate = false`.

v0.45 has no native-storage `jj init`; `jj git init` is the supported initializer.

This guide targets colocation. Costs: import/export on each command (slow only with very many refs),
and mutating Git commands can create states jj cannot model. Prefer jj for mutations; never run
mutating `git` and `jj` concurrently.

### When to use non-colocation

Choose it to fence git off: with no top-level `.git`, no stray `git commit` from an editor, hook or
agent habit can move a branch behind jj's back. Also useful for huge ref counts or tooling confused
by a visible `.git`. For GitHub work with `gh`, colocation usually wins.

Point git tools at the store (`jj git root` prints its path):

```bash
GIT_DIR=$(jj git root) gh pr list                   # gh and ref/metadata-only git
GIT_DIR=$(jj git root) git log --oneline
GIT_DIR=$(jj git root) GIT_WORK_TREE=$(jj workspace root) git status   # needs the work tree
```

Do not leave these exported in a session that also runs mutating jj commands; that restores the
two-writer race. Read-only use is safe.

Convert an existing repo:

```bash
jj git colocation status
jj git colocation enable      # expose the Git store as a top-level .git
jj git colocation disable     # move it behind .jj
```

## Mental model

- **The working copy is a commit.** No staging area, no `git add`. Almost every command first
  snapshots changed files into `@`. Until then, fresh edits exist only on disk.
- **Change IDs are stable across rewrites; commit IDs identify exact versions.**
- **Editing history is normal.** Rewriting a commit rebases its descendants. No `--force`; use
  `jj undo`.
- **Conflicts are first-class.** Merges/rebases never stop; conflicts are recorded in commits and
  resolved later.
- **The operation log records everything** (`jj op log`, `undo`/`redo`, `op revert`, `op restore`).

`@` is the revset symbol for the working-copy commit, not a change ID; it moves on `jj new`,
`jj commit` and `jj edit`. Capture the full change ID when a durable identifier is needed.
`@-` = parent of `@`; `foo-` / `foo+` = parent / child of `foo`.

## Rules for agents and scripts

- Disable the pager: `--no-pager` or `[ui] paginate = "never"`.
- Avoid editors: pass `-m` to `describe`/`commit`; use paths or explicit revisions instead of
  `split`/`squash -i`. Two non-interactive forms still open an editor: `jj split <paths>` (one
  session for both descriptions; pass `-m`) and `jj squash` when source and destination both have descriptions (pass `-m`, or `-u` to
  keep the destination's).
- Name logical work by full change ID; commit hashes change on rewrite.
- Give history-changing commands an explicit revset. Prefer `jj rebase -r/-s/-b ... -o ...` over
  the implicit branch containing `@`.
- For parseable output use `--no-graph -T <template>` and predicates such as `conflicts()` or
  `empty()`, not rendered status text.
- Mutating commands snapshot on their own; do not run `jj st` before them. Run `jj st` once at the
  start of a task and once to review a batch of edits. Pass `--ignore-working-copy` to history and
  operation reads (`log`, `show <committed-rev>`, `op log`, `evolog`, `bookmark list`); they then
  reflect the last snapshot. Never use it with `st`/`diff` of `@` (hides unsaved edits) or with
  mutating commands (working copy goes stale).
- Detect a jj repo with `jj --ignore-working-copy root` (no snapshot).
- Never issue jj commands in parallel tool calls: concurrent snapshots each rewrite `@` and leave a
  divergent change. Subagents sharing the checkout use `--ignore-working-copy` only. Background
  tools (watchman trigger, editor integrations, dashboards) race the same way unless they pass it.
- Do not routinely bypass immutability with `--ignore-immutable`.
- On error, inspect `jj op log` and prefer `jj undo` over manual graph repair.
- `-R <path>` targets another repo; `--at-op <op>` inspects a past operation without changing state.

## Change IDs versus commit IDs

- A **change** is the logical unit of work across rewrites; its **change ID** is lowercase letters
  (`qpvuntsm`).
- A **commit** is one immutable version of a change; its **commit ID** is hex (`d5e03cfa`).

Rewriting creates a new commit and hides the old one: same change ID, new commit ID. Editing,
describing, rebasing, conflict resolution, signing and automatic descendant rebasing all do this.
Descendants keep their change IDs but get new commit IDs.

Use a **change ID** for "the current version of this logical change" (`edit`, `squash`, `rebase`,
bookmarks, automation). Use the full ID in durable scripts; short prefixes can become ambiguous.
Use a **commit ID** for one exact version: recovering a hidden snapshot from `jj evolog`, comparing
before/after, Git/GitHub interop, disambiguating divergence. Git sees only commits, which is why
rewriting a pushed change moves the remote bookmark to a new hash.

```bash
jj log --no-graph -r @ -T '"change_id=" ++ change_id ++ "\ncommit_id=" ++ commit_id ++ "\n"'
jj evolog -r <change-id>      # every stored version of one change
```

### Divergent changes

A **divergent change** has several visible commits for one change ID (shown `(divergent)`). Ordinary
rewrites do not cause it. It appears when two processes rewrite the same change, or when something
makes a hidden predecessor visible again (a bookmark, working copy, visible or fetched descendant).
Moving and pushing a bookmark does not abandon an old line that is still visible; it stays as an
anonymous head.

jj disambiguates sides with a **change offset**: `abc/0`, `abc/1`. A bare divergent change ID is an
error; the hint offers offsets or `change_id(abc)` (all sides). Offsets are sorted by commit ID per
change and recomputed per operation, so they **renumber** as sides are rewritten or abandoned. Fine
for a one-shot (`jj abandon 'abc/1'`); for multi-step cleanup, resolve each to a commit ID first.

Offsets are also numbered independently per change: `root/0` and `tip/0` need not lie on the same
line. A mismatched `root/N::tip/M` silently yields an empty or wrong range, and abandoning it hits
the wrong commits. Check the range before destroying anything: `jj log -r '<root>/N::<tip>/M'`.

Diagnose first:

```bash
jj log -r 'divergent()'                      # both versions of every divergent change
jj log -r 'heads(divergent())' --no-graph    # tip of each divergent line
jj log -r 'heads(all())'                     # includes unbookmarked heads
jj bookmark list --all-remotes               # which line refs retain
jj log --no-graph -r 'fork_point(<tip-a-id> | <tip-b-id>)'               # last shared commit
jj log --no-graph -r 'roots(<fork-id>..(<tip-a-id> | <tip-b-id>))'       # first commit per side
jj log -r '<old-root-id>::<old-tip-id> & (bookmarks() | remote_bookmarks())'  # must be empty
jj log -r 'children(<old-tip-id>)'           # anything based on the old tip
```

If the old line is an unwanted unpublished stack with no refs or descendants, abandon its complete
inclusive range and verify:

```bash
jj abandon '<old-root-commit-id>::<old-tip-commit-id>'
jj log -r 'divergent()'; jj status
```

Abandoning only the old tip is not enough: its parent becomes the next anonymous head and the rest
stays divergent. If the old line has a bookmark, descendants or published work, move or rebase those
first. A replacement change gets a new change ID; stability covers rewrite lineage only.

### `jj converge` (v0.45)

Replaces the divergent commits of a change with one new commit, rebases descendants onto it and
repoints local bookmarks. It groups revisions in `--revision` (default alias `revsets.converge`,
`mutable() & divergent()`) by change ID.

```bash
jj converge                       # every mutable divergent change
jj converge -r 'divergent()'      # chosen revset
jj converge --no-interactive      # warn and exit non-zero instead of prompting (for scripts)
```

Heuristics pick tree, description, parents and author. When inconclusive (commonly differing
descriptions) jj prompts; give the sides a matching description first for unattended runs. The
result may carry file conflicts. Review with `jj op show -p` and `jj evolog`; `jj undo` to revert.
Commits sharing the change ID outside the revset remain. Use the manual abandon steps above to keep
one side's commits instead of synthesizing a new one.

Change IDs travel in a header on the Git commit, so they survive plain `git clone`. Anything that
makes a new commit hash (`git rebase`, GitHub squash-merge) loses them.

## Anonymous branches

Anonymous branching is the normal jj model for local work. A branch needs no name to stay visible or
safe. Bookmarks add a stable handle and are required for Git remote workflows, not for keeping
commits.

```bash
jj new trunk() -m "feat: first idea"
jj new trunk() -m "feat: second idea"    # sibling: anonymous branch from the same parent

jj log -r 'visible_heads()'              # every visible head
jj log -r 'reachable(@, mutable())'      # mutable stack connected to @
```

An **anonymous head** is a visible commit with no visible descendants. Find it in `jj log`, then
`jj edit <change-id>` or `jj new <change-id>`. It is hidden only by `jj abandon` or a superseding
rewrite.

A visible head is never garbage-collected: GC preserves everything reachable from visible heads. No
bookmark, tag or reflog is needed (unlike Git). Only *hidden* commits (abandoned changes, rewritten
predecessors) depend on the op log and are subject to GC.

Create bookmarks where names matter: publishing, PRs, sharing a handle, long-lived landmarks. Do not
advance a bookmark after every local commit to imitate Git's current branch.

## Setup

```bash
jj git init                 # colocated by default: .jj + real .git
jj git init --no-colocate   # git store hidden in .jj
jj git clone <url> [dir]    # also colocated by default
jj git clone --no-colocate <url>

jj config set --user user.name "Name"
jj config set --user user.email "me@example.com"
```

`--colocate` is a no-op in v0.45. Flip the default with `git.colocate = false`.

### Git reftable incompatibility (v0.45)

jj does not import refs from a Git repo using `reftable` ref storage. Signature: `jj git init
--colocate` reports success but imports no bookmarks; `@` sits on `root()` and `jj st` shows every
file as added. The refs stay in `.git`; jj cannot see them.

```bash
git rev-parse --show-ref-format             # prints files or reftable
git clone --ref-format=files <url> [dir]    # prevent reftable on a new clone
git refs migrate --ref-format=files         # migrate an existing clone before jj init
jj git init --colocate
```

If jj was already initialized against reftable, move the new `.jj` aside, migrate or re-clone, then
init again. Do not mistake the all-files-added change for imported history.

**Identity:** `user.name`/`user.email` apply only to future commits. Set them before the first real
change, or fix an existing commit with `jj metaedit --update-author -r <rev>`.

**Operation identity** is separate. `jj op log` and `jj evolog` record `operation.username` /
`operation.hostname` (default: OS account and hostname, not `[user]`), including automatic
snapshots. Anonymizing `[user]` does not hide them:

```bash
jj config set --user operation.username "Name"
jj config set --user operation.hostname "some-host"
```

Applies only to operations created afterward.

### Repairing commit metadata

`jj metaedit` changes metadata without touching content; it creates new commit IDs and rebases
descendants.

```bash
jj metaedit -r <rev> --author 'Name <me@example.com>'
jj metaedit -r <rev> --update-author              # use configured identity
jj metaedit -r <rev> --update-author-timestamp
jj metaedit -r <rev> --update-change-id           # breaks rewrite lineage; rarely appropriate
```

## Inspecting

```bash
jj st                       # snapshot, then status
jj log                      # mutable revisions + limited immutable context; ~ = elided
jj log -r ::                # complete visible history
jj log -r '::@'             # ancestors of @
jj log -r 'main..@'         # commits on @ not on main
jj show <rev>               # description + diff
jj diff [-r <rev>]          # default @; --git, --stat, -s
jj diff --from A --to B
jj interdiff --from A --to B # compare the patch of A with the patch of B
jj evolog [-r <rev>]        # evolution of one change (was `jj obslog`, still aliased)
jj evolog -p -r <rev>       # patch between successive versions
jj op log                   # operation history
```

Bare `jj log` uses the `revsets.log` config, so imported Git history often shows as an
`(elided revisions)` / `~` node. Use `-r ::` for everything, `-r <revset>` to narrow, `--no-graph`
for scripts, `-T <template>` for output.

### Three logs

- **`jj log`** — the commit graph.
- **`jj op log`** — operation history: each entry is a full repo state (commits, bookmarks, `@`) plus
  the `args:` that produced it. The timeline `jj undo`/`jj op restore` walk.
- **`jj evolog -r <change>`** — every commit ID one change ID has pointed at. Entries read
  `<change>/1`, `/2`, … (steps back), mostly `(hidden)`, each naming the producing operation.

## Making changes

Two idioms; pick one.

```bash
# describe-then-new
jj describe -m "feat: thing"    # message on @
jj new                          # fresh empty change on top

# commit = describe @ + new
jj commit -m "feat: thing"
jj commit -i -m "feat: thing"   # select changes; rest stays in the new @
```

In a colocated repo, completed work left in `@` can show as staged/unstaged in Git tools. Finish
with `jj new` or use `jj commit`. See [Colocated repos — interop rules](#colocated-repos--interop-rules).

```bash
jj new <rev>                    # new change on <rev>
jj new A B                      # merge: parents A and B
jj new <rev> --no-edit          # create child without moving the working copy
jj new --insert-before <rev>    # (-B) insert before rev, rebase rev onto the new change
jj new --insert-after <rev>     # (-A) insert after rev, rebase its children onto it
jj describe -m "msg" [-r <rev>]
jj edit <rev>                   # resume editing an old change
jj abandon <rev>                # drop; descendants rebase onto its parent
```

No "amend": editing files while `@` is a change amends it. To amend an older commit, `jj edit <rev>`
or edit in `@` and `jj squash` down.

### Squash workflow — described change plus scratch child

Describe an empty feature change, make an undescribed scratch child, and move accepted work from the
child into the feature:

```bash
jj new trunk() -m "feat(api): add rate limiting"
jj new                                  # scratch child (@)
# ...edit and test...
jj squash src/rate_limiter.rs           # move selected paths into @-
jj squash -i                            # choose hunks (human use)
jj squash                               # move the rest into @-
```

This gives index-like separation without staging. After a full squash jj abandons the emptied source
and creates a fresh empty change. For unattended agents use filesets or an explicit destination:
`jj squash --into <feature-change-id> <paths>...`.

The alternative is the **edit workflow** (`jj edit`, `next --edit`, `prev --edit`). Both give the
same graph; choose per task.

### Navigating a stack

`next`/`prev` move relative to `@` and by default create a new empty `@` at the destination. `--edit`
edits the destination directly.

```bash
jj next [N] [--edit]
jj prev [N] [--edit]
jj next --conflict --edit       # jump to next conflicted descendant (same for prev)
```

With several children, name the target with `jj edit <rev>`. `ui.movement.edit` changes the default.
Same model as Sapling's `sl prev`/`sl next`.

## Reorganizing history

```bash
jj squash                       # @ into @-
jj squash -r <rev>              # <rev> into its parent
jj squash --into <rev>          # @ into any ancestor
jj squash -i                    # pick hunks
jj squash <path>...

jj split                        # interactive hunk selection
jj split <path>... -m "msg"     # listed paths go to the first change; without -m the editor opens
jj split --parallel <path>...   # siblings instead of parent + child

jj rebase -s <src> -o <dest>    # src + descendants
jj rebase -b <branch> -o <dest> # whole branch
jj rebase -r <rev> -o <dest>    # single revision
jj rebase -r <rev> -o A -o B    # multiple parents (merge)
jj rebase -r <rev> -A A -B B    # insert after A and before B

jj absorb                       # distribute @ hunks into the ancestors that last touched those lines
jj absorb -t <revset>           # restrict destinations (default mutable()); the rest stays in @
jj absorb <path>...
jj absorb -i                    # human use

jj duplicate <rev> -o <dest>
jj restore [--from <rev>] <path>...
jj restore -i
jj diffedit -r <rev>            # edit a commit's diff without checking it out
jj parallelize <revset>         # sequential revisions to siblings
jj simplify-parents -r <revset> # remove redundant parent edges
jj arrange <revset>             # interactive reorder/squash/split (human use)
```

`jj squash -i` moves selected hunks from `@` into `@-` (or `--into <rev>`). With descriptions on both
source and destination, even non-interactive `squash` opens the editor: pass `-m` or `-u`. An
undescribed source never prompts.

`jj absorb` moves only hunks attributable to a single ancestor. Unattributable hunks, or those
outside `-t`, stay in `@` for a manual `jj squash --into`.

`--onto`/`-o` is the current spelling for a new parent; `--destination`/`-d` is still accepted.
`--insert-after`/`-A` and `--insert-before`/`-B` work on `new`, `rebase`, `duplicate`, `split` (and
experimentally `squash`).

### Abandon versus revert

`abandon` removes unpublished changes from visible history. `revert` makes a new inverse change, for
shared or immutable history.

```bash
jj abandon <revset>
jj revert -r <bad-rev> -o @            # inverse on top of @
jj revert -r <bad-rev> -A <after-rev>
```

`jj abandon` **deletes** bookmarks on the abandoned commits; a deleted tracked bookmark propagates as
a remote deletion on the next push. `--retain-bookmarks` moves them to the parent instead.

**Discarding an anonymous branch** (`common` is the base, `n1..n10` the branch): anchor both ends.

```bash
jj abandon 'n1::n10'         # the branch, nothing else
jj abandon 'common+::n10'    # same, knowing only the base
```

`jj abandon ::n10` has no left bound: it walks to the root and abandons everything reachable.

Recovery uses the operation log: `jj undo` or `jj op restore <op-id>`. Abandoned commits stay
reachable until GC. See [Undo / operation log](#undo--operation-log).

`jj restore --changes-in <rev>` applies a revision's inverse into an existing destination (default
the working copy); prefer `revert` when the inverse should be its own reviewable change.
`jj restore` takes `--into` (alias `--to`) and `--from`; `-c/--changes-in <rev>` = `--into <rev>
--from <rev>-`. Bare `jj restore` restores `@` from its parents, leaving an empty change with
metadata intact.

### `--restore-descendants`

Rewriting an ancestor normally reapplies each descendant's diff onto the new parent, which can
conflict. `--restore-descendants` preserves descendants' file content instead:

```bash
jj restore --restore-descendants --into <ancestor> --from <ancestor>- <path>...
```

Example: removing line `b` from `mid` with a plain restore conflicts with `top`, which added `c`
after `b`. With the flag, `top` keeps `a\nb\nc` conflict-free and owns `b`.

### Work against several branches at once

An integration change merges several PR heads so code and tests see their combination without
making the PRs depend on each other:

```bash
jj new pr-a pr-b pr-c -m "integration: test PRs together"
jj new                         # keep integration empty; edit in a child
# ...fix against the combined tree...
jj absorb
jj op show -p                  # what absorb changed
```

The integration change is local scaffolding; never move a PR bookmark onto it. `absorb` moves only
hunks attributable to mutable ancestors; use `jj squash --into <change>` or `jj split` for the rest.
When upstream moves:

```bash
jj git fetch
jj rebase -s 'roots(trunk()..integration)' -o trunk()
```

`integration` is a bookmark or change ID. The old `all:roots(...)` prefix is invalid in v0.45.

## Bookmarks

No "current branch". Bookmarks do **not** move as you commit; advance them explicitly.

```bash
jj bookmark list
jj bookmark create <name> [-r <rev>]   # default @
jj bookmark set <name> -r <rev>        # create or move
jj bookmark move <name> --to <rev>     # move only
jj bookmark advance --to <rev>         # advance the closest eligible bookmark(s)
jj bookmark delete <name>              # propagates as remote deletion on next push
jj bookmark forget <name>              # local only; leaves the remote alone
jj bookmark rename <old> <new>
jj bookmark track <name>@<remote>
jj bookmark untrack <name>@<remote>
```

`set` and `move` refuse backward/sideways moves without `-B`/`--allow-backwards`. Resolving a
*conflicted* bookmark is the exception: `jj bookmark set name -r <rev>` accepts any side.

Typical flow: work on a stack, `jj bookmark set mybranch -r @-`, push.

**Adopt a remote branch:** fetch makes untracked remote bookmarks visible without local ones. Track
it to create the local bookmark and join future sync:

```bash
jj git fetch
jj bookmark list --all-remotes
jj bookmark track feature@origin
jj new feature                    # new work on top; or `jj edit feature` to amend the tip
```

Tracking is sync policy, not ancestry. A tracked remote bookmark joins fetch/push reconciliation
with its same-named local bookmark; an untracked one is visible as `<name>@<remote>` but controls
nothing. Use `delete` to remove the remote ref, `forget` to drop only local bookkeeping.

## Tags

v0.45 creates and moves lightweight Git-compatible tags. Tags make their ancestors immutable by
default; moving a tag needs `--allow-move`.

```bash
jj tag list
jj tag set v1.2.3 -r <rev> [--allow-move]
jj tag delete v1.2.3                    # deletion pushed later
jj tag track v1.2.3@origin
jj tag untrack v1.2.3@origin
jj git push -t v1.2.3
```

jj reads annotated tags but creates only lightweight ones; make annotated or signed releases through
the hosting service.

## Git remotes

```bash
jj git fetch [--remote origin]
jj git push                     # tracked bookmarks/tags in remote_bookmarks(remote=<remote>)..@
jj git push -b <bookmark>       # new bookmarks push automatically
jj git push -t <tag>
jj git push --all               # all bookmarks and tags, including new
jj git push --tracked
jj git push --deleted           # pending deletions
jj git push -c <rev>            # auto-named bookmark (push-<changeid>) + push
jj git push --named name=<rev>  # named bookmark + push
jj git push --dry-run -b <bookmark>
jj git remote add|list|set-url|rename|remove    # remove also forgets that remote's bookmarks
jj git import / jj git export   # manual sync .jj <-> .git (automatic when colocated)
```

Git remotes receive named refs, so an anonymous change needs a bookmark (`-c` / `--named` can create
one during the push). Non-fast-forward updates use force-with-lease semantics: jj updates the remote
only if its ref still matches the last fetch. If the remote moved independently, fetch and resolve
divergence rather than bypassing this.

The push remote comes from `--remote`, `git.push`, or jj's remote-name fallback, not per bookmark.
One push can target several remotes (v0.46): repeat `--remote`, or set `git.push` to a string
pattern or an array of patterns. `--remote` also takes patterns. `revsets.git-push` sets the
default revisions a bare `jj git push` considers.

## GitHub / PR workflow

Colocated repos work with `gh`, CI and editors directly. Non-colocated:
`GIT_DIR=$(jj git root) gh pr list`.

### Worked example

```bash
# 1. start from current main
jj git fetch
jj new main@origin

# 2. build
jj commit -m "feat(api): add rate limiter"
jj commit -m "test(api): cover rate limiter"
# @ is now an empty change above the two commits

# 3. push and open the PR
jj bookmark create rate-limiter -r @-    # tip is the last real commit
jj git push --dry-run -b rate-limiter
jj git push -b rate-limiter
gh pr create --head rate-limiter --fill

# 4. address review: amend the right commit, not a new fixup
jj absorb                                # or: jj squash --into <change-id>
jj git push -b rate-limiter              # force-update is automatic

# 5. keep up with main
jj git fetch
jj rebase -b rate-limiter -o main@origin # conflicts land in commits, don't block
jj git push -b rate-limiter

# 6. merge on GitHub (--squash, --merge or --rebase per repo policy), then clean up
gh pr merge rate-limiter --squash
jj git fetch
jj bookmark delete rate-limiter
jj git push --deleted                    # if GitHub did not delete the remote branch
jj new main@origin
```

Push the bookmark at `@-`; `@` is the empty working commit. Prefer `absorb` to "address review"
commits. There is no `pull`: fetch, then rebase onto the fetched remote.

### Stacked pull requests

A stack is a sequence of changes with one bookmark per review boundary; the bookmarks exist because
GitHub needs named heads.

```bash
jj new main@origin -m "feat(api): add request context"     # A
jj new -m "feat(api): add request logging"                 # B on A
jj new                                                     # empty @ above the stack

jj bookmark create pr-request-context -r @--
jj bookmark create pr-request-logging -r @-
jj git push -b pr-request-context -b pr-request-logging

gh pr create --head pr-request-context --base main --fill
gh pr create --head pr-request-logging --base pr-request-context --fill
```

For longer stacks, name every PR tip explicitly. Editing an earlier change rebases its descendants
and their bookmarks follow. Push every affected bookmark after `edit`, `squash`, `absorb` or
`rebase`:

```bash
jj absorb
jj git push -b pr-request-context -b pr-request-logging
```

When a lower PR lands, fetch, rebase the rest onto trunk, and retarget the next PR's base if
needed. After a **squash-merge**, the landed commits rebase onto trunk as empty duplicates;
`jj rebase --skip-emptied` abandons commits that become empty during the rebase (those already empty
are kept). Do not use the many-parent integration workflow for stacked PRs; they have ancestry
between them.

## Gerrit workflow

Gerrit's `Change-Id:` trailer groups pushed versions into patch sets; `jj gerrit upload` adds a
missing trailer derived from the jj change ID.

```bash
jj gerrit upload -r 'trunk()..@' --remote-branch main --dry-run
jj gerrit upload -r 'trunk()..@' --remote-branch main
jj gerrit upload -r <revset> --remote-branch main --reviewer reviewer@example.com --topic api-cleanup --wip
```

Dry-run a broad revset first: upload may rewrite commits to add trailers. Later rewrites of the same
changes become new patch sets via the stable trailer.

## Merging

No `jj merge` (removed in 0.14). A merge is a commit with several parents:

```bash
jj new featureA featureB              # empty merge, editable in the working copy
jj new main featureA featureB         # octopus: any number of parents
jj new featureA featureB --no-edit
```

The merge starts empty; its tree is the merge of the parents' trees. Conflicting parents give a
conflicted merge that still succeeds. To fold work together linearly, rebase instead
(`jj rebase -r/-s/-b ... -o <dest>`).

## Conflicts

```bash
jj st                           # conflicted files
jj log                          # conflicted commits marked
jj resolve --list [-r <rev>]    # list conflicted paths without launching a tool
jj resolve [<path>]             # launch merge tool
jj resolve --tool <tool> <path>
```

Or edit the markers directly; jj detects resolution at the next snapshot. Because conflicts live in
commits, a common pattern is `jj new <conflicted>`, fix the markers, `jj squash` the fix back. You
can also `jj undo` the operation that caused them.

### Reading conflict markers

Default `ui.conflict-marker-style = "diff"`: a snapshot plus diffs to apply.

```text
<<<<<<< conflict 1 of 1
%%%%%%% diff from: nnvwlypy 552936ce "base"
\\\\\\\        to: koxtvtoo 74889680 "side1"
-b
+B1
+++++++ yukklzsq 16907fe0 "side2"
B2
>>>>>>> conflict 1 of 1 ends
```

Marker lines name revisions as `change_id commit_id "description"`.

- `<<<<<<<` / `>>>>>>>` delimit the conflict.
- `%%%%%%%` starts a diff to apply; `diff from:` is the base, `\\\\\\\ to:` the other side, then the
  `-`/`+` hunk. Many-sided conflicts have several.
- `+++++++` starts a materialized snapshot: one side's full content.

jj picks one side as the snapshot and renders the rest as diffs, so a diff section can precede it.
To resolve by hand, replace the whole marked region with the final content, remove every marker,
then `jj st` or `jj resolve --list` to verify.

```toml
[ui]
conflict-marker-style = "diff" # or "snapshot", "git"
```

**`"snapshot"`** shows every side in full, base included: first side `+++++++`, base `-------`,
each further side `+++++++`.

```text
<<<<<<< conflict 1 of 1
+++++++ mrsvuzly 01ab8030 "sideA"
grapefruit
------- xysurrto d0094fc3 "base"
banana
+++++++ npnwxqqt b3376c01 "sideB"
lemon
>>>>>>> conflict 1 of 1 ends
```

**`"git"`** is diff3, two-sided only: `<<<<<<<` first side, `|||||||` base, `=======` second side,
`>>>>>>>` end.

```text
<<<<<<< mrsvuzly 01ab8030 "sideA"
grapefruit
||||||| xysurrto d0094fc3 "base"
banana
=======
lemon
>>>>>>> npnwxqqt b3376c01 "sideB"
```

A file keeps the style it was materialized with until jj next updates that path; a config change
leaves existing conflicts alone.

### Many-sided conflicts

An N-parent merge touching the same lines gives an N-sided conflict (N added terms, N−1 base terms),
labelled `N-sided conflict` in `jj st` and `jj resolve --list`. In `"diff"` style one side is the
`+++++++` snapshot and the rest are `%%%%%%%` diffs from base:

```text
<<<<<<< conflict 1 of 1
%%%%%%% diff from: pmtrousv 057f0b88 "base"
\\\\\\\        to: owlylqsy f25bb0a8 "sideA"
-banana
+fruit_A
%%%%%%% diff from: pmtrousv 057f0b88 "base"
\\\\\\\        to: unukksnk bb524e09 "sideB"
-banana
+fruit_B
+++++++ uulovtlt 73cf8d8f "sideC"
fruit_C
>>>>>>> conflict 1 of 1 ends
```

`"snapshot"` lists each side in full with the base repeated between them. `"git"` cannot represent
more than two sides, so jj silently falls back to `"snapshot"` for that file. Independent regions in
one file are numbered `conflict 1 of n`, `2 of n`, …

Resolving an earlier conflicted change rebases descendants; those that only inherited the conflict
may turn clean, genuine ones remain. Check with `jj log -r '<resolved-change>::'` and
`jj log -r 'conflicts()'`.

## Undo / operation log

```bash
jj undo                         # undo the last non-undo operation; repeat to walk back
jj redo
jj op log
jj op revert <op-id>            # invert one operation, keeping later work
jj op restore <op-id>           # new operation whose state matches an earlier point
jj op show <op-id>              # metadata + commit diff
jj op diff --from <a> --to <b>
```

Almost anything is reversible; prefer `jj undo` to reconstructing state by hand.

`jj undo` takes no operation ID; repeated `undo`/`redo` behaves like an editor's stack. Since
v0.46 `undo`/`redo` refuse an operation performed in another workspace; pass
`--allow-cross-workspace`, or `jj op revert <op-id>` for a specific operation.
`op restore` does **not** delete the intervening history.

**Worked recovery — a bad rebase.** If it was the last action, `jj undo`. Otherwise:

```bash
jj op log --no-graph -T 'id.short() ++ " " ++ description ++ "\n"'
jj op show 3c4563216e59         # confirm it is the rebase op
jj op revert 3c4563216e59       # inverse; later work remains
```

To restore wholesale: `jj op restore <op-before-the-mess>`. Later operations stay in `jj op log`.
To make them garbage-collectable too:

```bash
jj op restore <op-before-the-mess>
jj op abandon '<op-before-the-mess>..@-'
```

Inspect `jj op log` first. Operation ranges are not commit revsets, and abandoning them removes
recovery paths once GC runs. `jj op log` itself is a safe read.

### Speculative operations

`--no-integrate-operation` runs a command and prints the resulting operation ID without making it
the op-log head or updating the working copy. Inspect with `--at-op`, then integrate or drop:

```bash
op=$(jj --no-integrate-operation rebase -b feature -o main@origin)
jj --at-op "$op" log -r 'main@origin..feature'
jj op integrate "$op"
```

This isolates jj state only, not external effects: `jj git push --no-integrate-operation` still
pushes. Use `jj git push --dry-run` to preview.

## Auto working-copy snapshots

Nearly every command first snapshots edits by rewriting `@` with the same change ID and a new commit
ID. The old version is hidden but kept until GC. Take the commit ID from `jj evolog`:

```bash
jj show <commit-id>                          # inspect a hidden snapshot
jj restore --from <commit-id> <path>...      # pull files back into @
jj new <commit-id>                           # revive the snapshot as a fresh change
jj edit <commit-id>                          # resume that exact version
jj op diff --from <prev-op> --to <snapshot-op>
```

Explicit control:

```bash
jj st                           # snapshot, then status
jj util snapshot                # snapshot only
jj --ignore-working-copy log    # no snapshot/update; state as of the last snapshot
```

`jj root` does not snapshot; `jj log` and `jj op log` do. For wholesale loss prefer `jj undo` or
`jj op restore`. Snapshots are not backups: `jj util gc` reclaims hidden commits after the grace
period.

## Maintenance — jj util gc

Nothing runs automatically; the op log and object store grow until pruned by hand.

```bash
jj op abandon ..<old-op-id>     # mark old operations obsolete
jj util gc                      # backend GC; in colocated repos also runs `git gc`
jj util gc --expire now         # skip the default 2-week grace period
```

`gc` reclaims only objects that are obsolete, unreferenced by any surviving operation **and** older
than `--expire`. Hidden commits stay referenced by the operations that produced them, so
`gc --expire now` alone does nothing to the op log: run `jj op abandon` first.

There is no date filter for operations. `jj op log` has no `-r`; `jj op abandon` accepts only
operation-graph symbols (op-ID prefixes, `@`, `@-`, `..` ranges). `before("1 day ago")` fails with
`Operation ID "before(...)" is not a valid hexadecimal prefix`. `--expire` accepts only `"now"` in
0.45.

### Wiping the operation log

Closest to `git reflog expire --expire=now --all && git gc --prune=now`:

```bash
jj op abandon '..@-'      # every operation before the current one
jj util gc --expire now
```

- **Preserved:** the visible commit graph (everything reachable from a bookmark or the working
  copy, with descriptions, content, change IDs), bookmark positions, `jj st`.
- **Removed:** the op log (nothing for `undo`/`op restore` to walk back to) and every commit reachable
  only through it: pre-rebase versions, earlier `@` snapshots, abandoned changes. You lose a
  bookmark's *prior* positions; current positions are untouched.

Destructive and irreversible, no `--dry-run`, no confirmation. Inspect `jj op log` first.

### Integrity checks — no `jj fsck`

In a colocated repo `git fsck` covers the object store. For jj-specific state:

```bash
jj op log --limit 3     # walks op history; fails fast on a corrupt op store
jj debug reindex        # rebuilds the commit index; errors on inconsistency, doubles as repair
jj debug index          # index stats
jj debug object <id>    # inspect one operation/view object
jj debug working-copy   # compare working-copy state file with what jj expects
jj debug local-working-copy
```

None is a full content check; a clean `reindex` plus a clean `op log` walk is the practical signal.

### Other `jj util` subcommands

```bash
jj util backend name      # "git" (clean check before assuming Git interop)
jj util config-schema     # JSON schema (draft-04) for the TOML config
jj util exec -- <cmd> ... # run an external command; basis for multi-command aliases
jj util diff <a> <b>      # diff two files on disk with jj's diff formats (v0.46)
jj util completion <shell>
jj util install-man-pages <dir>
jj util markdown-help     # full CLI help as Markdown
```

## Revsets

Used with `-r`.

| Expr | Meaning |
|------|---------|
| `@` | working-copy commit |
| `x-` / `x+` | parents / children (repeatable: `x--`, `@++`) |
| `::x` / `x::` | ancestors / descendants of x (inclusive) |
| `x..y` | ancestors of y that are not ancestors of x |
| `x \| y`, `x & y`, `x ~ y`, `~x` | union, intersection, difference, complement |
| `all()`, `none()`, `root()` | literal sets |
| `heads(x)`, `roots(x)` | tips / roots of a set |
| `visible_heads()` | all visible heads, including anonymous |
| `bookmarks()`, `tags()`, `remote_bookmarks()` | by ref |
| `tracked_remote_bookmarks()`, `untracked_remote_bookmarks()` | by tracking state |
| `description(pat)`, `author(pat)`, `files(pat)` | content/metadata |
| `mine()`, `empty()`, `merges()`, `conflicts()` | predicates |
| `immutable()`, `mutable()` | rewrite-protected / rewritable |
| `reachable(src, domain)` | commits connected to `src` without leaving `domain` |
| `fork_point(x)`, `merge_point(x)` | fork / merge points for a set |
| `trunk()` | main/master/trunk bookmark, resolved at init; `root()` if none |
| `latest(x, n)` | n most recent |
| `ancestors(x, depth)` / `descendants(x, depth)` | depth-limited `::x` / `x::` |

**String-pattern gotcha:** `description(x)`, `author(x)` etc. default to **exact** match, and a
description keeps its trailing newline, so `description("mid")` matches nothing for a commit
described "mid". Use `description(substring:"mid")`, `description(glob:'mid*')` or `"mid\n"`. A bare
quoted string is a silent empty set, which quietly no-ops revset-driven commands such as
`jj absorb -t`.

### Composing revsets

Every expression is a set; operators nest freely (`heads(mutable() & mine())`).

| Form | Meaning | Endpoints |
|------|---------|-----------|
| `::x` | ancestors of x | includes x |
| `x::` | descendants of x | includes x |
| `x::y` | descendants of x **and** ancestors of y (DAG range) | includes both |
| `..x` | `root()..x` | includes x |
| `x..` | `x..visible_heads()` | excludes x |
| `x..y` | ancestors of y not ancestors of x | includes y, excludes x |

**`::` and `..` differ.** `x::y` is connectivity: commits on a path from x to y. `x..y` is set
difference `::y ~ ::x`. They coincide on a linear chain and part at merges:

```bash
# common → n1 → … → n10, n5 merges in external commit x (not descended from common)
jj log -r 'common..n10'      # includes x
jj log -r 'common+::n10'     # excludes x
```

Use `x::y` for "the connected sub-DAG between two points" (discarding a branch, rebasing a span); use
`x..y` for "what y adds over x" (review ranges, `trunk()..@`). Since `::` includes both endpoints,
abandoning a branch must exclude the base: `n1::tip` or `common+::tip`, never `common::tip`.

**Precedence**, tightest first: `f(x)` → postfix `-`/`+` → pattern `p:x` → range `::`/`..` → unary
`~x` → `&` and infix `~` (**same level**, left-associative) → `|`. So `x ~ y & z` is `(x ~ y) & z`.
Parenthesise when mixing `&` and `~`. Also, `..` does not distribute over `|` on its left:
`(a | b)..` means `a.. & b..`.

```bash
jj log -r 'trunk()..@ & mine() & ~empty()'
jj log -r 'latest(heads(trunk()..@ & mine()), 1)'
```

| Revset | Yields |
|--------|--------|
| `trunk()..@` | unlanded work (review range) |
| `@ & empty()` | is the working copy empty (empty set = no) |
| `heads(all())` | every visible tip |
| `::@ & bookmarks()` | nearest bookmarks behind you |
| `roots(x::y)` | first commit(s) of a span; the base to rebase onto |
| `fork_point(a \| b)` | last commit a and b share |
| `x:: & ~x::y` | descendants of x not on the way to y |
| `mutable() & mine() & description(glob:'wip*')` | your rewritable WIP |
| `trunk()..@ ~ ::pushed_bookmark` | local commits not yet behind the pushed ref |
| `trunk()::bookmarks()` | span from trunk to every local bookmark tip |
| `trunk()::@` | span from trunk to the working copy |
| `remote_bookmarks()..bookmarks()` | local commits behind no remote bookmark (what a push sends) |
| `ancestors(@, 5)` | `@` plus four generations back (depth counts x itself) |
| `roots(ancestors(conflicts()))::conflicts()` | minimal sub-DAG from earliest conflict origin to the conflicts |
| `latest(bookmarks(), 5)` | five most recent bookmark tips |

`reachable(src, domain)` ignores edge direction: `reachable(@, mutable())` is the whole mutable
stack around `@`, ancestors and descendants, where `::@` / `@::` give one direction each.

`ancestors(x)` with no depth equals `::x`; `ancestors(@, 1)` is `@`. `descendants(x, depth)` is the
forward counterpart.

**Local vs remote bookmarks.** `bookmarks()` returns local targets; `remote_bookmarks()` returns
remote-tracking tips (`@git` excluded; pass `remote="git"` or `remote="*"` to include). After you
push and then advance locally, local sits at the new tip while the remote stays at the pushed commit
(`feature@origin`; `jj log` marks the local side `feature*`).

```bash
jj log -r 'remote_bookmarks()..bookmarks()'                # what a push would send
jj log -r 'fork_point(bookmarks() | remote_bookmarks())'   # shared base
jj log -r 'fork_point(bookmarks() | remote_bookmarks())::(bookmarks() | remote_bookmarks())'  # how they diverge
```

For all named work above trunk use `trunk()::(bookmarks() | remote_bookmarks())`.

**Span from a predicate:** `roots(ancestors(P))::P` is the minimal connected sub-DAG from where P's
lineage begins down to P. With `P = conflicts()` it is where resolution starts.

**Not valid in v0.45** (unknown functions are parse errors, not empty sets):

- `local_bookmarks()` — `bookmarks()` is already local; remote forms are `remote_bookmarks()`,
  `tracked_remote_bookmarks()`, `untracked_remote_bookmarks()`.
- `conflict()` — it is `conflicts()` (likewise `merges()`, `tags()`).
- `obslog(@)` / `evolog(@)` — no such revset. Use the command `jj evolog -r @`; revsets cover only
  visible commits and superseded versions are hidden.

## Config

Precedence (later wins): built-in → user → repo → workspace → CLI (`--config`). User file:
`~/.config/jj/config.toml` or `$HOME/.jjconfig.toml`.

```bash
jj config list
jj config get ui.editor
jj config set --user ui.editor nvim
jj config set --repo user.email "x@y"
jj config edit --user
jj config path --user
jj config set --file ~/.config/jj/conf.d/aliases.toml ui.editor nvim
```

`config {set,edit,unset}` need a target: `--user`, `--repo`, `--workspace` or `--file <PATH>`.
`--user` writes the *first* loaded user file (or the first in `conf.d/`) without prompting. Use
`--file` to name a specific fragment; the path must be one jj already recognizes.

```toml
[user]
name = "Name"
email = "me@example.com"

[ui]
default-command = "log"       # bare `jj`
editor = "nvim"
diff-formatter = "difftastic" # non-interactive diff/show renderer
diff-editor = ":builtin"      # interactive hunk editor; or "meld", "vscode"
merge-editor = "meld"
pager = "less -FRX"
paginate = "never"            # for agents/scripts

[git]
fetch = "origin"
push = "origin"

[aliases]
l = ["log", "-r", "trunk()..@"]

[revset-aliases]
"immutable_heads()" = "builtin_immutable_heads()"
```

### Multi-command aliases

An alias is one `jj` invocation; `&&`, `;` and pipes mean nothing in it. Shell out through
`jj util exec`:

```toml
[aliases]
pmain = ["util", "exec", "--", "sh", "-c",
         "jj bookmark set main -r @- && jj git push --bookmark main"]
```

- **`-r @-`, not `-r @`.** After edit-then-`new`, `@` is an empty commit and the finished work is
  `@-`.
- **Quoting.** The pipeline is one `sh -c` argument. Extra args land in `$0`, `$1`, …, so
  `jj pmain extra` does not append to the push. Take no arguments or handle `"$@"`.
- **Exit status.** `&&` short-circuits, so a failed `bookmark set` skips the push and the alias exits
  non-zero.

Disable an alias, built-in or from an earlier config layer, with `aliases.<name>.enabled = false`
(v0.46).

## Fsmonitor (watchman)

Watchman replaces jj's full stat walk with an OS-backed changed-path query, which matters in large
repos. Needs `watchman` on `PATH`.

```toml
[fsmonitor]
backend = "watchman"

[fsmonitor.watchman]
register-snapshot-trigger = true   # optional background `jj util snapshot`
```

The backend speeds snapshots from normal commands; the trigger also snapshots in the background as
files change. Check with `jj debug watchman status`. Each snapshot is still a hidden working-copy
commit kept until GC.

## Interactive tools — builtin TUI (scm-record)

Agents should avoid these; they block on a terminal or GUI. Commands that launch `ui.diff-editor`:
`jj split`, `jj squash -i`, `jj diffedit [--from a --to b]`, `jj commit -i`, `jj absorb -i`,
`jj restore -i`, `jj arrange`. `jj resolve <path>` launches `ui.merge-editor`.

With `ui.diff-editor` unset or `:builtin`, jj uses the scm-record TUI. Its menu bar is mouse-only,
but every action has a key. `?` shows the full help.

| Key | Action |
|-----|--------|
| `j`/`k`, `↓`/`↑` | next / previous item |
| `h`/`l`, `←`/`→` | collapse / expand (file → hunk → line) |
| `Ctrl+u` / `Ctrl+d` | page up / down |
| `Space` | toggle item |
| `Enter` | toggle and advance |
| `a` / `A` | invert all / invert uniformly |
| `f` / `F` | fold current / all |
| `e` | edit commit message |
| `c` | confirm: apply and exit |
| `q` / `Esc` | cancel (applies nothing) |

Confirming without a selection also applies nothing. On macOS, Page Up/Down need `Fn`+arrows; use
the letter keys.

## Diff and merge tools

Three settings:

- `ui.diff-formatter` — renders `jj diff`/`jj show` (e.g. difftastic). Non-interactive.
- `ui.diff-editor` — interactive hunk picker for `split`, `squash -i`, `diffedit`. Default
  `:builtin`; GUI editors work.
- `ui.merge-editor` — three-way resolver for `jj resolve`.

Override per invocation with `--tool`:

```bash
jj show -r @-                       # ui.diff-formatter
jj diff -r @- --tool :git           # builtins: :git, :color-words, :stat, :summary
jj diff -r @- --tool delta
jj diff -r @- --tool vscode         # built-in definition, no config needed
```

`vscode`, `vscodium`, `meld`, `kdiff3` and `vimdiff` have built-in definitions; config only sets
defaults or flags:

```toml
[ui]
diff-formatter = "difftastic"   # or ["difft", "--color=always"]
diff-editor    = "vscode"
merge-editor   = "vscode"
```

Custom merge-tool definitions use `$left`, `$right`, `$base` and the required `$output`. GUI tools
must block until editing finishes (built-ins supply the wait flags). Unattended agents should use
non-interactive formatters or edit conflict markers directly.

### Custom tools — Zed, p4merge

Tools without a built-in need a `[merge-tools.<name>]` table. Tools that accept only files, not
directories, need `diff-invocation-mode = "file-by-file"` and `edit-args = []` (VS Code's built-in
does the same). Without it p4merge fails with `'...' is (or points to) an invalid file`.

```toml
[merge-tools.zed]
program = "zed"
diff-args = ["--wait", "--diff", "$left", "$right"]
diff-invocation-mode = "file-by-file"
edit-args = []                  # no dir-diff support

[merge-tools.p4merge]
program = "/Applications/p4merge.app/Contents/MacOS/p4merge"
merge-args = ["$base", "$left", "$right", "$output"]
diff-args = ["$left", "$right"]
diff-invocation-mode = "file-by-file"
edit-args = []
```

```bash
jj diff -r @- --tool zed
jj resolve --tool p4merge
jj diff -r @- --tool p4merge
```

Defining a table does not change `ui.merge-editor`; set it to make the tool the `jj resolve`
default.

## Colocated repos — interop rules

`.jj` and `.git` share one working copy. jj **imports git state and exports its own on every
command**, so most interop is automatic.

- **git branch == jj bookmark**, kept in sync both ways on the next command.
- **git HEAD tracks a parent of `@`** and is normally detached; it is separate from the branch ref.
  It shows in two common states:

  ```text
  C @                         C @, feature
  |   (empty)                 |   (contains the feature patch)
  B feature, Git HEAD         B Git HEAD
  |                           |
  A                           A
  ```

  Left: `jj new` made an empty `@` above bookmarked `B`; Git `HEAD` is `B`, so Git tools see a clean
  tree. Right: `jj edit feature` made `C` the working copy; Git `HEAD` is its parent `B`, so Git
  tools show `C`'s recorded patch as staged or unstaged. That does **not** mean it is uncommitted in
  jj. Run `jj new` after finishing an amended tip to return to the left state without moving the
  bookmark or pushed history.
- **Stale Git index stat cache.** jj rewrites working-copy files and moves Git `HEAD` but does not
  refresh stat data in `.git/index`. After a commit that changes file sizes without changing what Git
  sees (e.g. CRLF→LF under `.gitattributes` `eol=lf`), `git status` lists ` M` files while `jj st`
  is clean. Confirm: `git diff` is empty, `git hash-object <f>` equals `git rev-parse HEAD:<f>`, and
  `git ls-files --debug <f>` shows a cached `size` that differs from disk. Git trusts a non-zero size
  mismatch, so `git update-index --refresh` and `git reset` do not help. Rebuild the index:
  `git read-tree HEAD && git update-index -q --refresh`. Safe because jj ignores the Git index.
- **Completed raw `git` changes** are imported by the next jj command. Mutating Git often requires
  attaching the detached `HEAD` to a branch first and may cause bookmark conflicts or divergent
  changes. Inspect stale-looking state before forcing `jj git import`. In a **non-colocated** repo
  (v0.45), `jj git import` no longer imports the commit at a detached `HEAD`; attach it to a branch
  first. Colocated repos track `HEAD` continuously.
- **Git HEAD is tracked per workspace** (v0.45); existing repos migrate on first use. Since v0.46
  each colocated workspace is also a Git worktree with its own `HEAD`.
- **Do not run `git` and `jj` concurrently**; imports/exports race.
- **`gh` works directly** (reads `.git`). Non-colocated: `GIT_DIR=$(jj git root) gh pr list`.
- **Prefer jj for commit, merge, rebase.** jj ignores Git's staging area and cannot model unresolved
  Git index conflicts or unfinished `git rebase`/`git merge`. A completed Git mutation can usually be
  imported; do not hand jj an in-progress one.

## Machine-readable output

Use `--no-graph -T <template>`:

```bash
jj log --no-graph -r @ -T 'change_id.short()'
jj log --no-graph -r @- -T 'commit_id'
jj log --no-graph -r @ -T 'if(empty, "empty", "dirty")'
jj log --no-graph -r 'bookmarks()' -T 'bookmarks ++ "\n"'
jj log --no-graph -r @ -T 'description'
```

Fields/methods: `change_id`, `commit_id`, `description`, `author`, `empty`, `conflict`, `bookmarks`,
`parents`, `.short()`, `.shortest(n)`, `description.first_line()`, `author.email()`. Prefer predicate
revsets to parsing text: `conflicts()`, `@ & empty()`, `mine() & description(exact:"")`.

## Push safety and immutability

- **`jj git push` refuses** commits with **no description**, **conflicts**, or marked **private**
  (`git.private-commits`). Override per push with `--allow-empty-description`, `--allow-conflicts`,
  `--allow-private`, but prefer fixing the commit. Empty commits with a description are pushable.

  ```toml
  [git]
  private-commits = "description('wip:*') | description('private:*')"
  ```

  Descendants of private commits cannot be pushed either. Commits already on the remote and
  immutable commits are excluded from the private set.
- **Divergent bookmarks:** after `jj git fetch`, a bookmark moved both locally and remotely shows as
  conflicted (`name??`). Resolve with `jj bookmark set name -r <rev>`.

### Immutability

Immutability is a **revset**: every commit in `::immutable_heads()` (the heads and their ancestry) is
refused for rewrite. `edit`, `describe`, `rebase`, `squash`, `abandon` and similar fail with
`Commit … is immutable`. Freezing published commits prevents the rewrites that cause force-pushes.
Building on top (`jj new <immutable>`) is allowed.

v0.45 default:

```toml
[revset-aliases]
"immutable_heads()" = "builtin_immutable_heads()"   # = trunk() | tags() | untracked_remote_bookmarks()
```

So everything up to `main@origin` (plus tags and untracked remote bookmarks) is frozen; local
commits past it stay mutable. Pushing a *tracked* PR bookmark does not freeze it. Widen to taste:

```toml
[revset-aliases]
"immutable_heads()" = "builtin_immutable_heads() | remote_bookmarks()"   # freeze anything pushed
"immutable_heads()" = "main@origin | tags()"
"immutable_heads()" = "builtin_immutable_heads() | frozen"               # plus a landmark bookmark
```

```bash
jj config set --repo 'revset-aliases."immutable_heads()"' 'builtin_immutable_heads() | remote_bookmarks()'
```

Caveats:
- **Advisory.** Anyone can change the alias, and `--ignore-immutable` overrides it per rewrite. It
  stops accidents and is not a security boundary.
- `root()` is always immutable.
- An empty or malformed alias makes *nothing* immutable. Verify with `jj log -r 'immutable_heads()'`.

## File tracking

New files are auto-tracked on snapshot unless gitignored.

```bash
jj file untrack <path>          # must be gitignored first
jj file track <path>            # a non-ignored path excluded by snapshot.auto-track
jj file track --include-ignored <path>  # force-track an ignored or oversized path
jj file list [fileset]
jj file show <path>...
jj file search --pattern <pat>
jj file annotate <path>         # blame
jj file chmod (normal|executable) <path>...   # works cross-platform, even on conflicted files
jj file edit -r <rev> <path>    # edit one file in any revision via ui.editor; descendants rebase
jj file delete -r <rev> <fileset>...   # delete paths from a revision without touching @
```

`file edit`/`file delete` (v0.46) rewrite the revision in place; `--restore-descendants` keeps
descendants' content rather than their diff. `file edit` creates the file if absent and
materializes conflict markers if conflicted. Agents can drive it with a scripted editor:
`jj --config "ui.editor=['./write.sh']" file edit -r <rev> <path>` (the script receives the temp
path as `$1`).

`[snapshot] auto-track = "none()"` disables auto-tracking (value is a fileset, e.g.
`"glob:**/*.rs"`).

**Large files:** jj will not *auto*-track a new file above `snapshot.max-new-file-size` (default
1MiB); it warns instead. Already-tracked files bypass the limit. Ways past it:

- `jj file track --include-ignored <path>` — one file, no config change.
- `jj --config snapshot.max-new-file-size=50MiB st` — one invocation.
- `[snapshot] max-new-file-size = "50MiB"` — standing change.
- `max-new-file-size = 0` — disable the check.

LFS is unsupported (see limits below).

**Line endings:** `working-copy.eol-conversion` defaults to `"none"` (bytes preserved), reasonable
for an LF workflow. `"input"` converts CRLF to LF on snapshot and checks out LF, for **every file
jj classifies as text**, not just paths named in `.gitattributes`; normalizing a CRLF file can give
a whole-file diff. `"input-output"` stores LF and checks out CRLF. jj ignores `.gitattributes` EOL
rules, so they cannot scope this. Use `"input"` only for repo-wide LF normalization.

`working-copy.exec-bit-change` is `"respect"` / `"ignore"` / `"auto"` (Unix only).
`snapshot.auto-update-stale = true` applies `jj workspace update-stale` automatically, handy with
multiple workspaces.

## History of a single file

```bash
jj log <path>                     # visible commits that touched it
jj log -r 'files("<path>")'       # same, composable
jj log -p <path>                  # with per-commit diff
jj file annotate <path>
```

Auto-snapshots are hidden and absent from file history. To recover in-progress versions, find hidden
commit IDs with `jj evolog -r <change>`, then `jj show <commit-id>` or
`jj restore --from <commit-id> <path>`.

## Running formatters — jj fix

`jj fix` runs configured tools over the files of a revset and rewrites those commits in place. Use it
to format before pushing.

```bash
jj fix                        # @ and descendants that need it
jj fix -s <rev>               # <rev> and descendants
jj fix -s 'main..@'           # a whole stack (only -s/--source selects revisions)
```

`jj fix` only **modifies** content; it is not a validation gate. Each tool reads the file on
**stdin** and writes the fixed file to **stdout**, which replaces the file. A report-only linter has
empty stdout and would blank the file. Use a tool's autofix/stdout mode, or none. A nonzero exit
suppresses the rewrite.

```toml
[fix.tools.rustfmt]
command = ["rustfmt", "--emit", "stdout"]
patterns = ["glob:'**/*.rs'"]

[fix.tools.prettier]
command = ["prettier", "--stdin-filepath", "$path"]
patterns = ["glob:'**/*.{ts,tsx,js,json,css,md}'"]

[fix.tools.ruff]
command = ["ruff", "check", "--fix", "--quiet", "-", "--stdin-filename", "$path"]
patterns = ["glob:'**/*.py'"]       # linter in autofix mode: fixed source on stdout
```

`$path` is the repo-relative path. `clippy` and similar report-only checkers have no stdout fix mode;
run them via `jj run`. `jj fix` respects immutability and rebases descendants like any edit; run it
before `jj git push`.

## Run commands across revisions

`jj run` checks out revisions in isolated working copies and runs a command in each. By default,
successful filesystem changes amend those revisions and rebase descendants. For tests and other
read-only checks always pass `--ignore-changes`, which discards side effects and allows immutable
revisions.

```bash
jj run -r 'trunk()..@' --ignore-changes -j 4 -- cargo test    # test every change, no rewrite
jj run -r 'trunk()..@' -j 4 -- cargo fmt                      # deliberately format every change
```

Each process gets `JJ_CHANGE_ID`, `JJ_COMMIT_ID` and `JJ_WORKSPACE_ROOT`. Rewrites apply atomically
after the run; a failed command's changes are not saved by default. `--ignore-errors` continues and
makes the overall command succeed, so never use it when a failure must fail CI.

## Bisecting

`jj bisect run` searches a range by exit status: `0` good, `125` skip, `127` abort, other non-zero
bad. Range heads are assumed bad; their ancestors outside the range are assumed good.

```bash
jj bisect run --range 'v1.2.0..main' -- cargo test
jj bisect run --range '<known-good>..<known-bad>' -- ./repro.sh
```

Each candidate becomes the working-copy revision during the run; its commit ID is in
`JJ_BISECT_TARGET`. Monotonicity must hold: flaky tests or a bug that comes and goes invalidate the
result. When skips leave the first-bad revision ambiguous, jj says so.

Before bisecting, `jj bisect run` (v0.46) checks that the command tells the endpoints apart and
that the range goes from bad to good. `--trust-endpoints` skips these checks.

## Workspaces

Several working directories backed by one repo, each with its **own `@`**, so agents can work on
different revisions in parallel.

```bash
jj workspace add ../feature-b
jj workspace add --name build ../wc2 -r <rev>
jj workspace add --no-colocate ../wc3    # no Git worktree
jj workspace list
jj workspace root
jj workspace rename <new>
jj workspace remove <name>...            # snapshot, unregister, delete directory and Git worktree
jj workspace forget [<name>]             # unregister; leaves the directory, removes the Git worktree
jj workspace update-stale                # resync a workspace whose @ was rewritten elsewhere
```

- **Colocated workspaces (v0.46).** In a colocated repo with `git.colocate = true` (the default),
  `workspace add` also creates a Git worktree: the new directory gets a `.git` file pointing at
  `<repo>/.git/worktrees/<name>`, so `git` and `gh` work there. Needs `git` ≥ 2.42.
  `jj git colocation status|enable|disable` works per workspace to toggle this later.
- `jj workspace remove` snapshots the target first, so it fails on a stale workspace. Run
  `jj workspace update-stale` in it first.
- `jj undo`/`redo` refuse operations from another workspace (see
  [Undo / operation log](#undo--operation-log)).

- Workspaces share history, bookmarks and the op log. Rewriting a commit in one can leave another's
  `@` **stale**: run `jj workspace update-stale` there.
- Cleanup: `jj workspace remove <name>`.
- There is no per-tree branch checkout; each `@` just points at a revision. Do not edit the same
  working-copy commit from several workspaces (one goes stale). Colocated repos share a Git backend,
  so still do not mix concurrent mutating Git and jj commands.

## Sparse working copies

Sparse patterns choose which paths of the working-copy commit exist on disk, without changing
contents, tracking or history. Useful for monorepos.

```bash
jj sparse list
jj sparse edit
jj sparse set --clear --add README.md --add src
jj sparse set --add tests
jj sparse set --remove vendor
jj sparse reset                         # materialize everything
jj workspace add --sparse-patterns empty ../minimal-wc
```

Patterns are per workspace. A missing path may be merely sparse; check with `jj file list` /
`jj file show` rather than the filesystem.

## Git compatibility limits

- **Submodules** — not materialized in the working copy (not destroyed either).
- **Git LFS** — unsupported; pointer files are ordinary files.
- **git hooks** — not run. Format with `jj fix`, validate per change with `jj run --ignore-changes`,
  keep CI as the final gate.
- **`.gitattributes`** — ignored (no filters, eol, clean/smudge).
- **Annotated tags** — readable, but only lightweight ones can be created.
- **Shallow / partial clones** — shallow works but cannot be deepened; partial is unsupported.
- **git config** — only remote config and `core.excludesFile` are honored.
- **Colocated hygiene** — keep `.jj/` gitignored; use read-only git and mutate through jj. A bookmark
  whose jj and git positions disagree shows as `name@git`.

## Signing commits

```toml
[signing]
behavior = "own"        # also "keep" (default), "force", "drop"
backend = "ssh"         # or "gpg", "gpgsm"
key = "~/.ssh/id_ed25519.pub"
```

```bash
jj sign -r <revset>
jj unsign -r <revset>   # rewrites commits to remove signatures
```

## Recovering odd states

- **Stale working copy** (`jj st` warns): another workspace or interrupted command rewrote `@`.
  `jj workspace update-stale`.
- **Divergent change**: inspect with `jj log -r 'divergent()'`, select a side by change offset
  (`abc/0`) or commit ID. Resolve with `jj converge`, or for a stale rewritten stack use the range
  checks in *Change IDs versus commit IDs*; abandoning only the tip leaves the rest divergent.
- **Hidden commits**: pre-rewrite versions, including every auto snapshot. Find with `jj evolog`,
  revive by commit ID (`jj new <commit-id>` / `jj edit`), or pull single files with
  `jj restore --from <commit-id>`. See *Auto working-copy snapshots*.
- **Conflicted bookmark** after fetch (`name??`): `jj bookmark set name -r <rev>`.

## Getting help

- `jj <cmd> --help` — flags.
- `jj help <cmd>` — fuller docs.
- `jj help -k revsets` / `-k templates` / `-k config` — concept docs.
