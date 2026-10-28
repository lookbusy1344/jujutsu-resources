# Jujutsu crib sheet for Git users

Tested with **jj 0.46.0** in a colocated repository (`.jj` and `.git`). Use `jj` for
history-changing operations; colocation lets Git-aware tools see the same commits and refs.

## Start or adopt a repository

```bash
jj git clone <url> [directory]    # colocated by default
jj git init                       # new colocated repository in the current directory
cd <existing-git-repository>
jj git init                       # add .jj beside an existing .git; no re-clone

jj config set --user user.name "Name"
jj config set --user user.email "me@example.com"  # set identity before the first real change
```

The last command imports the existing Git commits and refs. Continue using `jj` for mutations.

`config {set,edit,unset}` need a target — `--user`, `--repo`, `--workspace`, or `--file <PATH>`
(0.45). `--user` writes the first loaded user file without prompting; use `--file` to hit a specific
one (e.g. a `conf.d/` fragment) when several exist.

In a colocated repo, the Git branch ref mirrors its jj bookmark, while detached Git `HEAD` tracks a
parent of `@`. After `jj edit feature`, Git tools may therefore show the tip's already-recorded patch
as staged or unstaged. Run `jj new` when finished to put an empty `@` above the bookmarked tip and
make Git look clean, without moving the bookmark. Never run mutating Git and jj commands concurrently.

**jj 0.45.1 caveat:** before adopting an existing Git repository, ensure
`git rev-parse --show-ref-format` prints `files`; jj cannot import `reftable` refs. See the
reference guide for diagnosis and migration.

## The model

- The working copy (`@`) is itself a commit. There is no index and no `add`: jj snapshots file
  edits into `@` when the next jj command runs.
- A **change** is the logical piece of work. Its letter-based **change ID** survives edits,
  rebases, and other rewrites. A **commit** is one immutable version of that change; its hex
  **commit ID** changes on every rewrite. Normally name work by change ID or bookmark; use a
  commit ID when you need one exact historical version or when interoperating with Git. Change
  IDs are stable across clones too — a plain `git clone` carries them along — unless the commit
  gets rewritten along the way (`git rebase`, a GitHub squash-merge, etc).
- Rewriting history is routine. Descendants are rebased automatically, conflicts are stored in
  commits rather than stopping commands, and repository operations can be undone.
- jj refuses to rewrite configured **immutable** history, normally including trunk and tags.
  Create a new change or use `revert`; do not routinely bypass the guard with `--ignore-immutable`.
  "Immutable" is not a per-commit lock — it is a revset, `immutable_heads()`, and everything in its
  ancestry is frozen. The default is `trunk() | tags() | untracked_remote_bookmarks()`: in plain
  terms, everything from `root()` up to and including `main@origin` (plus tags) cannot be edited,
  rebased, or abandoned, while your local commits past it stay mutable. You can still build new
  commits on top. `main@origin` is the syntax for the bookmark `main` **on the remote `origin`** (as
  opposed to your local `main`) — a common thing to freeze. To protect all published work, widen the
  set in config: `revset-aliases."immutable_heads()" = "builtin_immutable_heads() | remote_bookmarks()"`.
  See the reference's *Immutability* section for recipes.
- Git branches map to jj **bookmarks**, but jj has no current branch. Local heads can remain
  anonymous; bookmarks are mainly stable names and the refs exchanged with Git remotes. An anonymous
  head is never garbage-collected while visible — the heads set keeps it reachable with no bookmark,
  tag, or reflog. Only hiding it (`jj abandon` or a rewrite) makes it collectable. In Git the same
  commit would be unreferenced and lost at the next `git gc`; jj inverts that default.

A **divergent change** has one change ID pointing at two visible commits, shown `(divergent)`. jj
renders each side with a change offset — `abc/0`, `abc/1` — and those work in revsets (`jj abandon
'abc/1'`). Bare `abc` errors; jj hints you toward `abc/0`, `abc/1`, or `change_id(abc)` for both.

`jj converge` (0.45) resolves divergence automatically: it synthesizes one replacement commit for a
divergent change, rebases descendants, and moves bookmarks. Bare `jj converge` handles every mutable
divergent change; `--no-interactive` aborts rather than prompting when its heuristics can't pick a
description, tree, or parents (differing descriptions is the usual blocker). Prefer it over the
manual abandon-the-old-line cleanup below unless you need to keep one side's exact commits.

If rewritten commits still appear as `(divergent)` after a bookmark was moved, look for an old
anonymous head with `jj log -r 'heads(divergent())'`. A bookmark can correctly point at the new tip
while the old stack remains visible. After confirming the old line has no bookmarks or needed
descendants, abandon its whole range — either the offset form `jj abandon '<old-root>/N::<old-tip>/N'`
or a commit-ID range `jj abandon '<old-root-commit-id>::<old-tip-commit-id>'`; abandoning only its tip
exposes the next old ancestor. Offsets renumber as sides are rewritten, so prefer commit IDs for
scripted cleanup. Offsets are also numbered per change independently, so `root/0` and `tip/0` are not
guaranteed to be on the same line — `jj log -r` the range and eyeball it before abandoning. See the
reference guide's *Change IDs versus commit IDs* section for the safety checks.

`@` is the revset symbol for the current working-copy commit. Use it anywhere a command accepts a
revision to target the current change, such as `jj describe -r @`, `jj squash -r @`, or
`jj log -r @`. It is not a change ID itself and moves when `jj new`, `jj commit`, or `jj edit`
changes the working-copy revision; capture the full change ID when a durable identifier is needed.

Other useful revision syntax: `@-` is the parent of `@`, `x-` a parent, `x+` a child, `::x` x and
its ancestors, `x::` x and its descendants, and `x..y` ancestors of y not also ancestors of x.

Revsets are a set algebra — operators take sets and return sets, so they nest: `heads(trunk()..@)`,
`roots(x::y)`. The two you reach for most:

- `x::y` — the **connected span** between x and y (both included). Use it to target a branch you
  will discard or rebase: `jj abandon 'n1::n10'`. To abandon a branch off a base, exclude the base —
  `n1::tip` or `common+::tip`, never `common::tip` (that includes `common` itself).
- `x..y` — what y **adds over** x (`= ::y ~ ::x`, y included, x not). Use it for review ranges:
  `jj log -r 'trunk()..@'` is your unlanded work.

They match on a linear chain but differ at merges: `x..y` crosses a merge and pulls in the merged-in
side line; `x::y` stays inside the span. Combine sets with `|` union, `&` intersection, `~`
difference; wrap tips and roots with `heads(...)` / `roots(...)`. Precedence: `&` and infix `~` bind
equally (left to right) and tighter than `|` — parenthesise when mixing them. The reference guide's
*Composing revsets* section has the full operator table.

## Revset cheat sheet

Common `-r` expressions. `x::y` is the connected span (both ends included); functions take and
return sets, so they nest.

```bash
jj log -r 'trunk()::bookmarks()'   # trunk down to every local bookmark tip
jj log -r 'trunk()::@'             # trunk down to the working copy — your current line
jj log -r 'trunk()::my-bookmark'   # trunk down to one named bookmark
jj log -r 'ancestors(@, 5)'        # @ and four more generations (five commits; depth counts @)
jj log -r 'bookmarks()'            # every local bookmark target
jj log -r 'remote_bookmarks()'     # every remote-tracking bookmark tip (@git excluded)
jj log -r 'remote_bookmarks()..bookmarks()'  # local commits not yet on any remote — your unpushed work
jj log -r 'fork_point(bookmarks() | remote_bookmarks())::(bookmarks() | remote_bookmarks())'
                                   # common root down to both local and remote tips — where local and remote diverge
jj log -r '::@ & bookmarks()'      # the nearest bookmarks behind you
jj log -r 'heads(all())'           # every visible tip, named or anonymous
jj log -r 'mine() & mutable()'     # your rewritable commits
jj log -r 'conflicts()'            # every visible conflicted change
jj log -r 'roots(ancestors(conflicts()))::conflicts()'  # earliest conflicted ancestors down to the conflicts
jj evolog -r @                     # how @ itself evolved across rewrites (was `jj obslog`)
```

Three forms that look plausible but **do not parse** in 0.45:

- `local_bookmarks()` — not a function. `bookmarks()` already means *local* bookmarks; use
  `remote_bookmarks()` for remote-tracking ones. The two diverge when a bookmark is pushed then
  advanced locally: `bookmarks()` sits at the new tip, `remote_bookmarks()` at the pushed commit,
  and `feature*` in `jj log` flags the gap. `remote_bookmarks()..bookmarks()` is what a push would
  send; `fork_point(bookmarks() | remote_bookmarks())` is their shared base.
- `conflict()` — the predicate is plural, `conflicts()`.
- `obslog(@)` — there is no `obslog` revset. Evolution (including hidden commit versions) is the
  `jj evolog -r @` command, not a `jj log` revset — `jj log` only sees visible commits.

The nested conflict revset is worth unpacking: `ancestors(conflicts())` is everything feeding any
conflicted commit; `roots(...)` narrows that to the earliest such commits; `roots(...)::conflicts()`
then spans from those roots down to the conflicts — the minimal sub-DAG that introduced and carries
the conflicts, i.e. where to start resolving.

## Inspect and commit

```bash
jj status                         # also snapshots pending filesystem edits into @
jj log                            # mutable changes plus limited immutable context; ~ means elided
jj log -r ::                      # complete visible history, including immutable ancestors
jj log -r 'main..@'               # current stack relative to main

jj show <change-id>               # metadata and complete patch for one change
jj diff --summary -r <change-id>  # files changed by it
jj diff -r <change-id> path       # its patch for one path
jj interdiff --from <old> --to <new> # patch changes between two versions under review
# Edit files, then:
jj commit -m 'feat: add thing'    # describe @, then create a new empty @ on top
jj commit -i -m 'feat: add thing' # choose changes to commit; leave the rest in the new @
# Equivalent, as two explicit operations:
jj describe -m 'feat: add thing'
jj new
```

`jj new` starts the next change. `jj describe` changes only the description, so editing while
pointing at an existing change is jj's equivalent of amending it.

## Edit and reorganize history

```bash
jj edit <change-id>               # make an older change @; edit it directly
# ...edit and test; the next jj command snapshots it and rebases descendants...
jj edit <stack-tip>               # return to the rewritten tip
jj prev --edit                    # edit the previous change in the stack
jj next --edit                    # edit the next change in the stack

jj squash                         # move @'s patch into @-; empty source is abandoned
jj squash -r <change-id>          # move a change into its parent
jj squash --into <change-id> path # move selected paths from @ into an ancestor
jj squash -i                      # choose hunks interactively

jj split                          # interactively split @ into two sequential changes
jj split <path>... -m 'msg'       # paths go to the first change; without -m one editor opens for both
jj absorb                         # distribute @'s hunks into ancestors that own those lines
jj absorb -i                      # choose which hunks are eligible for absorption
jj duplicate <change> -o <dest>  # copy/cherry-pick; the copy gets a new change ID

jj fix                            # run configured formatters over @ and rewrite it in place
jj fix -s <change-id>             # fix a change and its descendants
```

`jj squash -i` opens the configured diff editor. Selected hunks move from `@` into `@-` by
default, while unselected hunks remain in `@`; add `--into <change-id>` to choose another target.
Plain `jj squash` also opens an editor when source and destination both carry descriptions —
pass `-m 'msg'`, or `-u` to keep the destination's.

`rebase` moves changes; `duplicate` copies them. Choose the rebase scope deliberately:

```bash
jj rebase -r <change> -o <dest>  # only this change; descendants fill the gap
jj rebase -s <change> -o <dest>  # this change and all its descendants
jj rebase -b <change> -o <dest>  # its whole branch, relative to the destination
```

Without `--edit`, `prev` and `next` create a new empty working-copy change at the destination.
Use `jj edit <rev>` when a stack forks and navigation is ambiguous.

Use `jj abandon <change-id>` to remove an **unpublished** unwanted change; jj rebases its
descendants onto its parents. For shared history, preserve it and add an inverse change:

```bash
jj abandon <unwanted-change>
jj revert -r <published-bad-change> -o @
```

To throw away a whole anonymous branch, abandon its inclusive range. Say `common` is the shared
base and an unnamed branch `n1..n10` forks off it (n1 the first change, n10 the tip):

```bash
jj abandon 'n1::n10'              # or 'common+::n10' — anchor the root, not just the tip
```

Anchor both ends. A bare `jj abandon ::n10` means *all ancestors of n10*, which walks back
through `common` to the root; `n1::n10` and `common+::n10` stay inside the branch.

Recovery is the op log, not a git reflog: `jj abandon` does not erase history, it records an
operation that hides those changes. Undo it while the hidden commits still exist (before garbage
collection):

```bash
jj undo                           # reverse the abandon if it was the last operation
jj op log                         # else find the operation that abandoned the branch
jj op restore <op-id-before-it>   # restore the whole repo to that earlier state
```

## Interactive commands

Several commands drop into an interactive hunk picker or merge tool. The picker is
`ui.diff-editor` (default `:builtin`, a TUI); the merge tool is `ui.merge-editor`. Both can be
GUI editors (`meld`, `vscode`), in which case jj waits for the window to close.

```bash
jj split                          # pick hunks for the first of two sequential changes
jj squash -i                      # pick hunks to move from @ into @- (or --into <change-id>)
jj diffedit                       # edit @'s content directly in the diff editor
jj absorb -i                      # pick which hunks are eligible for absorption
jj restore -i                     # pick hunks to restore from @- into @
jj commit -i                      # pick what to commit; the rest stays in the new @
jj resolve path                   # open the merge tool for one conflicted path
jj arrange <revset>               # reorder/squash/split a graph interactively
```

Each opens `ui.diff-editor`: toggle hunks/lines, then save-and-close to apply. Closing without
selecting is a no-op. In the builtin TUI (`scm-record`) press **`?`** for the full keybinding
help; the top menu bar (`[File] [Edit] …`) is mouse-only, but every action has a direct key
(`Space` toggle, `c` confirm, `q` quit). These need a terminal or GUI, so avoid them in
unattended scripts — prefer
the path-scoped non-interactive forms (`jj split <path>...`, `jj squash --into <rev> path`) or
edit conflict markers directly. See the reference guide for diff-editor configuration.

## Branches, switching, stacks, and merges

Starting work creates graph ancestry, not a checked-out branch:

```bash
jj new main                       # anonymous new change based on main
# ...edit...
jj commit -m 'feat: first part'
jj bookmark create feature -r @-  # name the completed tip for Git/remotes

jj new feature                    # start a new child of feature
# ...edit, then commit the child...
jj commit -m 'feat: second part'
jj bookmark set feature -r @-     # explicitly move the bookmark to a newer tip

# Alternative: amend the existing feature tip instead of adding a child
jj edit feature
```

Bookmarks do not advance merely because a child is created, but a bookmark attached to a
rewritten change follows that change. List them with `jj bookmark list`. Moving a bookmark
backward or sideways needs `-B`/`--allow-backwards`; resolving a conflicted bookmark does not.

`jj bookmark delete feature` removes the local bookmark and records deletion for tracked remotes;
`jj bookmark forget feature` removes only the local name and leaves remotes untouched.

Adopt a branch that already exists on a remote:

```bash
jj git fetch
jj bookmark list --all-remotes
jj bookmark track feature@origin # create local feature and sync later remote movement
jj new feature                    # start a child; use jj edit feature to amend its tip
```

There is normally no stash workflow. `jj new other-branch` safely leaves unfinished `@` as an
anonymous head and starts a change elsewhere; return with `jj edit <saved-change-id>`.

Move an entire stack from one base branch to another. Here `feature` is the stack tip, `main` is
its old base, and `release` is the new base:

```bash
jj rebase -s 'roots(main..feature)' -o release
```

Change IDs and attached bookmarks survive the rewrite; commit IDs change. There is no `jj merge`
command — a merge is a commit with more than one parent, so create one by passing several parents to
`jj new`:

```bash
jj new left right -m 'merge left and right'
# ...optionally edit/test the merge result...
jj bookmark create merged -r @

jj new main a b c -m 'octopus'    # any number of parents; no special command
jj new left right --no-edit       # create the merge but leave @ where it is
```

There is no merge-in-progress state: the merge commit exists immediately, even when conflicted.

## Tags and parallel workspaces

```bash
jj tag set v1.2.3 -r @-           # lightweight Git-compatible tag; ancestors become immutable
jj git push -t v1.2.3

jj workspace add ../feature-b -r feature  # second working directory with its own @
jj workspace list
jj workspace remove feature-b    # snapshot, unregister, delete the directory and Git worktree
jj workspace forget feature-b    # unregister only; leaves the directory on disk
```

Workspaces share history, bookmarks, and the operation log, but each has an independent working-copy
commit. In a colocated repo each workspace is also a Git worktree, so `git` and `gh` work in it
(`--no-colocate` skips this; needs git ≥ 2.42). Avoid editing the same change from two workspaces;
if one becomes stale after another rewrites it, run `jj workspace update-stale` there. `jj undo`
refuses an operation made in another workspace unless given `--allow-cross-workspace`.

## Resolve conflicts

```bash
jj status                         # conflicted commits/paths are marked
jj resolve --list                 # list conflicts in @
jj resolve path                   # open the configured merge tool for one path
# Or replace the conflict-marked region in the file with the desired content, then:
jj status                         # snapshot and verify that the conflict disappeared
```

Rebase or merge conflicts do not interrupt the command. Resolve them in the conflicted change
with `jj edit <change-id>`, or in a child and `jj squash` the resolution back.

Markers render in the style set by `ui.conflict-marker-style`: `"diff"` (default — one side as a
snapshot plus `%%%%%%%` diffs to apply), `"snapshot"` (every side in full, base between them), or
`"git"` (diff3 `<<<`/`|||`/`===`/`>>>`, two-sided only; falls back to snapshot for a >2-sided file).
An N-parent merge produces an N-sided conflict. See the reference guide for the marker syntax.

## GitHub: fetch, push, PR, and merge

```bash
# Start or update work
jj git fetch
jj new main@origin                # start from the fetched remote main
# ...edit, commit, test...
jj bookmark create feature -r @-
jj git push --dry-run -b feature  # inspect the remote update first
jj git push -b feature
gh pr create --head feature --base main --fill

# Refresh/update the PR after editing or rebasing its changes
jj git fetch
jj rebase -b feature -o main@origin
jj git push -b feature            # lease-safe rewrite; no manual --force

# Merge on GitHub (choose --squash, --merge, or --rebase per repository policy)
gh pr merge feature --squash
jj git fetch
jj bookmark delete feature
jj git push --deleted             # delete remote branch if GitHub did not
jj new main@origin
```

There is no `pull`: fetch, then rebase the local branch. GitHub requires named refs, so push a
bookmark; `jj git push -c @-` creates an automatic bookmark when a specific name is unnecessary.
Push rejects undescribed, conflicted, or configured-private commits. Rewritten bookmarks update
with lease-style safety.

## Recovery and compatibility

```bash
jj undo                           # undo the latest repository-changing operation
jj redo                           # reapply the most recently undone operation
jj op log                         # repository-wide operation history
jj op show <operation-id>         # inspect what one operation changed
jj op restore <operation-id>      # restore repository state from an older operation
jj evolog -r <change-id>          # prior commit versions of one logical change
jj evolog -p -r <change-id>       # include the patch between successive versions
jj restore --from <rev> path      # restore a path's content into @
jj file edit -r <rev> path        # edit one file in any revision via the editor; descendants rebase
jj file delete -r <rev> path      # delete a path from any revision without touching @
jj restore -i                     # choose hunks to restore from @- into @
```

`jj log` shows the current commit graph and how changes relate. `jj op log` shows the history of
whole-repository states used for undo and recovery. `jj evolog` shows how one logical change evolved
through rewrites, including its earlier hidden commit versions.

- Git hooks do not run; Git LFS is unsupported; submodules are not materialized; and
  `.gitattributes` filters are ignored. Run formatters and linters with `jj fix` (tools
  configured under `[fix.tools.*]`) instead of relying on pre-commit hooks.
- New files over 1 MiB are not auto-tracked by default; explicitly use
  `jj file track --include-ignored <path>` or adjust `snapshot.max-new-file-size`.
- To stop tracking a file while keeping it on disk, ignore it first, then run
  `jj file untrack <path>`; ignoring an already-tracked file is not enough.

If a rewrite or conflict resolution goes wrong, inspect `jj op log` before repairing the graph
manually.

## Troubleshooting and help

```bash
jj bookmark list --conflicted       # bookmarks moved both locally and remotely
jj bookmark set <name> -r <chosen>  # resolve by selecting the intended revision
jj log -r 'conflicts()'             # find every visible conflicted change
jj run -r 'main..feature' --ignore-changes -- <test-command>
                                     # test each change without rewriting it
jj <command> --help                 # command flags and examples
jj help -k revsets                  # revision-query language
```

## Scripting

```bash
jj --no-pager log                    # one command without the pager
jj config set --user ui.paginate never  # or `paginate = "never"` under [ui]
jj log --no-graph -T 'change_id.short() ++ "\n"'
                                     # parseable output; no graph, no colour
```
