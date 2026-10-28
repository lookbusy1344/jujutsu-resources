# jjui — Single-File Guide

**Validated:** 2026-08-24 · **jjui version:** v0.10.9 · **minimum jj:** v0.37

`jjui` is a keyboard-driven terminal interface for Jujutsu. It presents the revision graph, common
history-editing operations, Git remotes, bookmarks, the operation log, diffs, and command execution
without hiding the underlying jj model.

This guide follows the structure of the
[official jjui documentation](https://idursun.github.io/jjui/) but condenses it into one searchable
file. Key bindings below are the v0.10.9 defaults; press `F1` inside jjui for the bindings active in
your installation and configuration.

## Overview

Start jjui in the repository containing the current directory:

```bash
jjui
```

The Revisions view is the home screen. Other views are layered over it, and `esc` normally returns
to the previous view or cancels the current mode.

Global keys:

| Key | Action |
|---|---|
| `F1` | Open full contextual help |
| `?` | Expand the status-bar help |
| `esc` | Cancel, close, or clear the current selection |
| `q` | Quit jjui |
| `ctrl+z` | Suspend jjui and return to the shell |
| `j` / `k`, arrows | Move down / up in lists |
| `pgdown` / `pgup` | Move by page |

The highlighted item is the implicit operand. `space` selects additional revisions, and supported
operations act on the whole selection. Press `esc` in the Revisions view to clear it.

## Installing jjui

jjui v0.10.9 requires jj v0.37 or newer.

### Homebrew

```bash
brew install jjui
```

### Windows

```powershell
winget install IbrahimDursun.jjui

# Or with Scoop:
scoop bucket add extras
scoop install jjui
```

### Arch Linux

```bash
paru -S jjui-bin
# or: yay -S jjui-bin
```

Use `jjui` instead of `jjui-bin` to build the AUR package from source.

### Nix

```bash
nix run nixpkgs#jjui
# Or use the upstream flake:
nix run github:idursun/jjui
```

### Go

```bash
go install github.com/idursun/jjui/cmd/jjui@latest
```

Use `@HEAD` instead of `@latest` for current upstream development. Pre-built binaries are also
available from the [GitHub releases](https://github.com/idursun/jjui/releases).

### From source

```bash
jj git clone https://github.com/idursun/jjui.git
cd jjui
go install ./...
```

For a Nix development shell without cloning first, run `nix develop github:idursun/jjui`.

## Migrating pre-v0.10 configuration

v0.10 replaced `[keys]`, `[leader]`, and `[custom_commands]` with `[[actions]]` and `[[bindings]]`.
Convert leader mappings to `seq`, and bind built-ins by their action ID and scope. Old `[keys]`
entries are ignored; the other legacy sections produce startup warnings. Consult the
[v0.10 migration table](https://idursun.github.io/jjui/migrating/v0_10/) for exact mappings.

## Customization

### `config.toml`

jjui reads TOML configuration at startup:

- Linux/macOS: `~/.config/jjui/config.toml`
- Windows: `%AppData%/jjui/config.toml`
- Repository override: `<repo>/.jjui/config.toml`

Open the global file in `$EDITOR` with:

```bash
jjui --config
```

Setting `JJUI_CONFIG_DIR` makes jjui load `config.toml` and `config.lua` from that directory instead
of combining the normal global and repository files.

A practical starting configuration:

```toml
[revisions]
log_batching = true
log_batch_size = 50

[preview]
position = "auto"          # auto | right | bottom
show_at_start = false
width_percentage = 50.0
width_increment_percentage = 5.0

[oplog]
limit = 200

[suggest.exec]
mode = "fuzzy"             # off | regex | fuzzy

[ui]
auto_refresh_interval = 0   # seconds; 0 disables automatic refresh
set_window_title = true
mouse_support = true
flash_message_display_seconds = 4
```

#### Complete configuration reference

Configuration is layered as built-in defaults, global TOML, then repository TOML. A custom
`JJUI_CONFIG_DIR` replaces the normal global/repository lookup. Command-line `--limit`, `--period`,
and `--revset` override their effective startup values for that run.

| Key | Type | v0.10.9 default | Purpose |
|---|---|---|---|
| `limit` | integer | `0` | Revision limit; zero is unlimited |
| `bindings_profile` | string | `":builtin"` | Base bindings file; user bindings overlay it |
| `ui.theme` | string or table | `""` | Theme name, or `{ light, dark }` names |
| `ui.background_blend` | number or table | theme value | Selection blend; global or per appearance |
| `ui.set_window_title` | boolean | `true` | Include repository path in terminal title |
| `ui.auto_refresh_interval` | integer | `0` | Refresh period in seconds; zero disables it |
| `ui.flash_message_display_seconds` | integer | `4` | Success lifetime; zero makes it sticky |
| `ui.mouse_support` | boolean | `true` | Click, scroll, range-select, and resize support |
| `ui.colors.<selector>` | color/style | none | Override active theme selectors |
| `suggest.exec.mode` | string | `"off"` | `off`, `regex`, or `fuzzy` prompt suggestions |
| `revisions.log_batching` | boolean | `true` | Load the graph incrementally |
| `revisions.log_batch_size` | integer | `50` | Revisions per batch |
| `revisions.template` | string | unset | Override jj's `templates.log` |
| `revisions.revset` | string | unset | Override jj's `revsets.log` |
| `preview.revision_command` | string array | `jj show` args | Revision preview command |
| `preview.evolog_command` | string array | `jj evolog -p` args | Evolution preview command |
| `preview.oplog_command` | string array | `jj op show` args | Operation preview command |
| `preview.file_command` | string array | `jj diff` args | File preview command |
| `preview.position` | string | `"auto"` | `auto`, `right`, or `bottom` |
| `preview.show_at_start` | boolean | `false` | Open preview at startup |
| `preview.width_percentage` | number | `50.0` | Initial pane width percentage |
| `preview.width_increment_percentage` | number | `5.0` | Keyboard resize step |
| `oplog.limit` | integer | `200` | Operations loaded |
| `git.default_remote` | string | `"origin"` | Initially selected Git remote |
| `ssh.hijack_askpass` | boolean | `false` | Let jjui provide an SSH askpass helper |
| `actions` | array of tables | compatibility action | Custom Lua actions |
| `bindings` | array of tables | built-in profile | Key-to-action overlays |

The default preview arrays omit the `jj` executable because jjui supplies it:

```toml
[preview]
revision_command = ["show", "--color", "always", "-r", "$change_id"]
evolog_command = ["evolog", "--color", "always", "-r", "$commit_id", "-p", "-n", "1"]
oplog_command = ["op", "show", "$operation_id", "--color", "always"]
file_command = ["diff", "--color", "always", "-r", "$change_id", "$file"]
```

`bindings_profile` may be an absolute path or a path relative to the jjui config directory. Set it
to `:builtin` to reset the base; `[[bindings]]` entries still apply afterward. The built-in
compatibility action named `revisions.toggle_select` selects the highlighted revision and then jumps
to its parent.

#### jj configuration used only inside jjui

jjui sets the `JJUI` environment variable when it invokes jj. Use jj's conditional configuration to
change formatting or pagination only inside jjui:

```toml
[[--scope]]
--when.environments = ["JJUI"]

[--scope.ui]
paginate = "never"
diff-formatter = "delta"
```

This belongs in jj's config, not jjui's `config.toml`.

### Actions and bindings

An action is a named operation; a binding connects it to a key in a scope. Define a Lua-backed
action and bind it from `config.toml`:

```toml
[[actions]]
name = "copy-change-id"
desc = "copy change id"
lua = '''
local id = context.change_id()
if id then
  copy_to_clipboard(id)
  flash("Copied: " .. id)
end
'''

[[bindings]]
action = "copy-change-id"
key = "Y"
scope = "revisions"
desc = "copy change id"
```

Binding fields:

| Field | Meaning |
|---|---|
| `action` | Custom action name or built-in action ID |
| `scope` | View or mode in which the binding is active |
| `key` | One key, or an array of equivalent keys |
| `seq` | Multi-key sequence; use this instead of `key` |
| `desc` | Optional status/help label |
| `args` | Arguments for a built-in action |

Common scopes include `revisions`, `revisions.details`, `revisions.rebase`, `revisions.squash`,
`revisions.evolog`, `oplog`, `bookmarks`, `git`, and `diff`. Bind a built-in action directly:

```toml
[[bindings]]
action = "revset.edit"
key = "R"
scope = "revisions"
desc = "edit revset"
```

Use `seq = ["g", "r"]` for a multi-key binding. The authoritative action and scope catalog is
[`internal/config/default/bindings.toml`](https://github.com/idursun/jjui/blob/v0.10.9/internal/config/default/bindings.toml).

### `config.lua` and Lua scripting

Optional startup scripts live beside `config.toml` as `config.lua`. jjui calls a top-level
`setup(config)` function:

```lua
function setup(config)
  config.action("show-current", function()
    flash("Current: " .. revisions.current())
  end, {
    key = "H",
    scope = "revisions",
    desc = "show current change",
  })
end
```

Use `config.bind({...})` to bind an existing action. Lua modules under the configuration directory
can be loaded with `require("plugins.name")`. Install LuaLS metadata with:

```bash
jjui --install-lua-types
```

Frequently used Lua APIs:

| API | Purpose |
|---|---|
| `context.change_id()` / `commit_id()` | Read the highlighted revision IDs |
| `context.file()` / `checked_files()` | Read highlighted or selected files |
| `context.operation_id()` | Read the highlighted oplog operation |
| `revisions.current()` / `checked()` | Read revision selection |
| `revisions.refresh()` | Reload the graph after a command |
| `revset.current()` / `revset.set(value)` | Read or replace the visible revset |
| `jj(...)` | Run jj synchronously and return output/error |
| `jj_async(...)` | Run jj and yield until it completes |
| `jj_interactive(...)` | Give an interactive jj command the terminal |
| `flash(...)`, `choose(...)`, `input(...)` | Interact with jjui UI elements |
| `exec_shell(command)` | Run a shell command and wait |
| `copy_to_clipboard(text)` | Copy text using the system clipboard |
| `wait_close()` / `wait_refresh()` | Sequence scripted UI operations |

Built-in actions can be composed from Lua through `jjui.<scope>.<action>()`. Defining a custom
action with the same name replaces the built-in globally; call `jjui.builtin.*` from a wrapper
when the custom override must be bypassed. See the
[Lua API reference](https://idursun.github.io/jjui/customization/lua-scripting/) and
[Lua cookbook](https://idursun.github.io/jjui/lua-cookbook/) for the complete surface and workflows.

### Themes

Load a theme from `~/.config/jjui/themes/<name>.toml`:

```toml
# config.toml
[ui]
theme = "my-theme"
background_blend = 0.4
```

```toml
# themes/my-theme.toml
[colors]
text = { fg = "white" }
":selected" = { bg = "bright black", bold = true }
title = { fg = "magenta", bold = true }
border = "bright black"
```

Colors accept terminal names, ANSI-256 integers, or `#RRGGBB`. Style tables accept `fg`, `bg`,
`bold`, `underline`, `strikethrough`, `italic`, and `reverse`. A structured `[ui.theme]` table can
select different `light` and `dark` theme names.

Common selectors include `text`, `dimmed`, `:selected`, `border`, `title`, `shortcut`, `matched`,
`source_marker`, and `target_marker`. Scope selectors include `revisions`, `oplog`, `evolog`,
`git`, `bookmarks`, `help`, `preview`, `confirmation`, `status`, and `revset completion`; append
`:selected` to style selected rows. More-specific selectors override less-specific ones.

### Command-line options

```text
jjui [flags] [location]
```

| Flag | Alias | Purpose |
|---|---|---|
| `--revset <expr>` | `-r` | Set the session's default revset |
| `--period <seconds>` | `-p` | Override auto-refresh; `0` disables it |
| `--limit <n>` | `-n` | Limit revisions displayed; `0` means unlimited |
| `--config` | | Open global `config.toml` in `$EDITOR` |
| `--install-lua-types` | | Install LuaLS metadata |
| `--version` | | Print the jjui version |

Examples:

```bash
jjui /path/to/repo
jjui -r 'trunk()..@'
jjui --limit 50 --period 5
```

## Revisions

### Revisions overview

The main view displays the revision graph. Core keys:

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move down / up |
| `space` | Toggle revision selection |
| `@` | Jump to the working-copy revision |
| `J` / `K` | Jump to parent / children |
| `l`, right | Open revision Details |
| `d` | Show revision diff |
| `alt+d` | Compare two revision states |
| `enter` | Edit description inline |
| `D` | Edit description in external editor |
| `n` | Create a child of the highlighted/selected revision(s) |
| `alt+n` | Create a revision between selected graph positions |
| `e` / `alt+e` | Edit / force-edit revision |
| `E` | Diff-edit revision |
| `c` | Commit the working-copy revision |
| `s` / `alt+s` | Split sequentially / into parallel siblings |
| `B` | Create or move a bookmark on this revision |
| `ctrl+r` | Refresh revisions |

Revision operations:

| Key | Operation |
|---|---|
| `r` | Rebase |
| `S` | Squash |
| `A` | Absorb |
| `a` | Abandon |
| `y` | Duplicate |
| `R` | Revert |
| `M` | Set parents |
| `v` | Evolog |

Other views and tools:

| Key | View/tool |
|---|---|
| `L` | Revset editor |
| `b` | Bookmarks |
| `g` | Git commands |
| `o` | Operation log |
| `u` / `U` | Undo / redo |
| `p` / `P` | Toggle preview / move it to bottom |
| `/` | Quick search; `'` next and `"` previous match |
| `ctrl+t` | Fuzzy file finder |
| `f` | Ace Jump |
| `:` / `$` | Run jj / shell command |
| `W` | Command history |

With mouse support enabled, click a revision to move the cursor, control-click to toggle it in the
selection, or alt-click to select the range from the previous cursor position.

### Details

Press `l` or right to inspect files changed by a revision. Press `h`, left, or `esc` to close.

| Key | Action |
|---|---|
| `/` | Filter by case-insensitive path substring |
| `m` or `space` | Toggle file selection |
| `d` | Show highlighted file's diff |
| `r` | Restore files; choose `i` in confirmation for interactive hunks |
| `s` / `alt+s` | Split files sequentially / into siblings; confirmation offers `i` |
| `S` | Squash selected files into another revision |
| `A` | Absorb selected files |
| `*` | Change revset to revisions touching the highlighted file |

If files are selected, operations use them all; otherwise they use the highlighted file.

Mouse selection follows the Revisions view: click moves the cursor, control-click toggles a file,
and alt-click selects the range from the previous cursor position.

### Conflicts

Details marks conflicted files, but v0.10.9 has no dedicated default resolve binding. Press `:` and
run `resolve` or `resolve <path>` (omit the leading `jj`) to give the configured merge tool control
of the terminal. A Lua action can instead call `jj_interactive("resolve", "--tool", "<tool>")`.
Refresh with `ctrl+r` if the view does not update when the tool exits.

### Rebase

Press `r`; the current revision selection becomes the source. Change source scope with:

- `r`: selected revision(s) only (`jj rebase -r`)
- `B`: whole branch (`jj rebase -b`)
- `s`: source plus descendants (`jj rebase -s`)

Choose placement relative to the highlighted target:

- `o`: onto target without moving its existing descendants
- `a`: insert after target and rebase its descendants above the source
- `b`: insert before target
- `i`: mark an after-point, then choose a before-point and press `enter`
- `t`: pick a bookmark/tag or enter a raw target revset

Toggle `e` to abandon commits emptied by the rebase. Press `enter` to apply, `alt+enter` to force,
or `esc` to cancel.

### Absorb

Press `A` to distribute the source revision's changes into ancestors that last touched those lines.
Potential destinations are annotated before application. In absorb mode, `space` toggles target
selection and `s` selects the highlighted target plus its descendants; `enter` applies.

From Details, select files first and press `A` to restrict absorption to those files.

### Abandon

Press `a` to enter abandon mode. Preselected revisions remain selected; refine with `space`, or
press `s` to select a revision and all descendants. `enter` applies, `alt+enter` forces, and `esc`
cancels. Abandon rewrites history, so use it for unwanted unpublished work; use Revert for shared
history.

### Duplicate

Press `y`; selected revisions become the source. Choose placement with `o` (onto), `a` (after),
`b` (before), or `i` (between two points). Use `t` when the destination is outside the current
revset. Press `enter` to apply or `alt+enter` to force.

### Squash

Press `S`, navigate to the destination, and press `enter`. Before applying:

- `i`: toggle interactive hunk selection
- `e`: keep the source even if it becomes empty
- `d`: use the destination description and skip the message editor
- `t`: choose a target outside the visible graph

From Details, select files and press `S` to limit the squash to those files.

Hunk-level selection is not done in jjui itself: choosing `i` here (or in a Restore/Split
confirmation) hands the terminal to jj's configured diff editor — by default the scm-record TUI,
whose keys (`space` toggle, `c` confirm, `q` cancel) are listed in
[`jj-reference.md`](jj-reference.md) under *Interactive tools*.

### Revert

Press `R` to create inverse changes from selected revisions. Place the result with `o` (onto), `a`
(after), `b` (before), or `i` (between two points); `t` opens the target picker. Press `enter` to
apply or `alt+enter` to force. Unlike Abandon, Revert preserves the original shared history.

### Set parents

Press `M` to edit a revision's parents. Existing parents are marked `<< parent >>`; use `space`
on another revision to add it, or on an existing parent to remove it. `enter` applies and `esc`
cancels. Adding multiple parents creates a merge; removing a parent can dissolve one.

### Evolog

Press `v` to show every stored version of a logical change below the selected revision.

- `j` / `k`: navigate evolution entries
- `d`: diff the highlighted entry against its predecessor
- `p`: preview that patch
- `r`: choose an old version to restore from, then select the destination revision and press `enter`
- `esc`: close or cancel restore mode

Restore mode runs the equivalent of `jj restore --from <old-commit-id> --into <target-change-id>`.

### Inline describe

Press `enter` to edit the highlighted revision's description inline:

- `enter`: insert a newline
- `alt+enter` or `ctrl+s`: apply
- `alt+shift+enter`: force apply
- `alt+e`: continue in the external editor
- `esc`: cancel

For an initially undescribed revision, cancelled text is retained as a draft and restored the next
time that revision is described inline.

### Ace Jump

Press `f` to annotate visible revision IDs with short jump labels. Type the shortest unambiguous
label—normally one to three keys—to move immediately. `esc` cancels.

## Views

### Revset

Press `L` to edit the revset that controls the Revisions view. Completions include functions,
aliases, bookmarks, tags, and revsets used earlier in the session.

- `tab` / `shift+tab`: cycle completions
- `up` / `down` or `ctrl+p` / `ctrl+n`: navigate completions/history
- `enter`: apply
- `esc` or `ctrl+c`: cancel

An empty submission resets to the session default, including a value supplied with `jjui -r`.

### Operation log

Press `o` to browse repository-wide operation history.

| Key | Action |
|---|---|
| `d` | Diff the highlighted operation |
| `p` | Preview `jj op show` |
| `r` | Restore the whole repository view to that operation |
| `R` | Revert only that operation while retaining later work |
| `/`, `'`, `"` | Search, next match, previous match |
| `esc` | Return to Revisions |

Operation restore is itself recorded and can be undone. Nevertheless, inspect the operation and
choose Revert when only one older action should be inverted.

### Undo and redo

Press `u` for Undo or `U` for Redo. Use `h` / `l` to inspect the offered operations, `enter` to
apply, and `esc` to cancel.

### Git

Press `g` to open fetch/push commands. Use `tab` / `shift+tab` to choose the remote, `/` to filter,
and `enter` to run the highlighted entry. Press `p` or `f` once to filter to push or fetch commands;
press the same key again for the default action.

Push shortcuts after filtering:

| Key | Effective jj operation |
|---|---|
| `p` | Push tracking bookmarks in the current revset |
| `a` | Push all bookmarks plus deletions |
| `c` | Push selected change |
| `b` | Push eligible bookmarks on selected revisions |
| `d` | Push deletions |
| `t` | Push tracked bookmarks |

Fetch shortcuts:

| Key | Effective jj operation |
|---|---|
| `f` | Fetch selected remote |
| `t` | Fetch tracked bookmarks from selected remote |
| `a` | Fetch all remotes |

### Bookmarks

Press `b` for the bookmark menu:

- `m`: move a bookmark to the highlighted revision
- `t` / `u`: track / untrack
- `f`: forget locally without deleting the remote bookmark
- `d`: delete
- `/`: filter by name
- `tab` / `shift+tab`: cycle local and remote scopes

Press `B` directly on a revision for inline create/move: enter a new bookmark name to create it or
an existing name to move it.

## Tools

### Preview

Press `p` to toggle the context-aware preview and `P` to switch between side and bottom placement.

| Context | Preview content |
|---|---|
| Revision | `jj show` |
| File in Details | `jj diff` for that file |
| Evolog entry | One evolution patch |
| Oplog entry | `jj op show` |

Preview navigation: `ctrl+n` / `ctrl+p` scroll by line, `ctrl+d` / `ctrl+u` by half-page, and
`ctrl+h` / `ctrl+l` expand or shrink its width. Commands and placeholders are configurable under
`[preview]`; available placeholders include `$change_id`, `$commit_id`, `$operation_id`, and
`$file`.

The mouse wheel scrolls the preview. Drag its separator to resize it when mouse support is enabled.

### Diff viewer

Press `d` from a revision, file, evolog entry, or oplog entry. In the full-screen viewer:

| Key | Action |
|---|---|
| `j` / `k`, arrows | Scroll by line |
| `f` / `b`, page keys | Scroll by page |
| `d` / `u`, control variants | Scroll by half-page |
| `g` / `G` | Top / bottom |
| `h` / `l`, arrows | Horizontal scroll |
| `w` | Toggle line wrapping |
| `ctrl+t` | Select one changed file or return to all files |
| `[` / `]` | Previous / next changed file |
| `esc` | Close |

Only `esc` closes the viewer. `q` is not bound in the diff scope, so it falls through to the
global binding and quits jjui.

From Revisions, `alt+d` starts a range diff: choose the second revision and press `enter`. `x`
swaps from/to, while `f` and `t` open pickers for the respective endpoints.

### Flash messages and command history

Successful command output appears briefly; errors remain until dismissed with `esc`. Press `W` to
open command history, `j` / `k` to navigate, `d` to delete an entry, and `W` or `esc` to close.
History records every jj command run by jjui, not only commands entered manually.

### Fuzzy file finder

Press `ctrl+t` to find a file in the current revision. Type to fuzzy-filter, use `space` to refine
within current matches, and select with `enter`. The active revset changes to revisions touching
that file.

Press `ctrl+t` again inside the finder for live mode: the graph and preview update as the query
changes. In live mode, arrows navigate revisions and `ctrl+n` / `ctrl+p` scroll the preview.

### Command execution

Press `:` to run a jj subcommand (omit the leading `jj`) or `$` to run a shell command. Both support
context placeholders:

| Placeholder | Expands to |
|---|---|
| `$file` | Highlighted file |
| `$change_id` / `$commit_id` | Highlighted revision IDs |
| `$operation_id` | Highlighted oplog ID |
| `$revset` | Active revset expression |
| `$checked_commit_ids` | Selected revisions as a revset expression |
| `$checked_files` | Selected file paths |

Examples entered in jjui:

```text
: diff -r $change_id --git
$ cargo test
```

Commands receive the terminal interactively. A failed command is returned to the input for editing
and retrying. Prompt history is stored below `$XDG_CACHE_HOME/jjui/history/`.

## Complete v0.10.9 default key map

This appendix lists every action binding in jjui v0.10.9's built-in profile, grouped by scope.
Bindings in the global `ui` scope remain available unless a more specific mode consumes the key.
Normal text-entry editing supplied by the line editor is not repeated; the apply, cancel,
completion, and navigation actions around those inputs are listed.

### Global UI and help

| Scope | Key | Action |
|---|---|---|
| UI | `esc` | Cancel or close current mode |
| UI | `q` | Quit jjui |
| UI | `?` | Expand status help |
| UI | `F1` | Open full help |
| UI | `ctrl+z` | Suspend jjui |
| Help | `j` / down | Scroll down |
| Help | `k` / up | Scroll up |
| Help | `pgdown` / `pgup` | Page down / up |
| Help | `g` / `G` | Top / bottom |
| Help | `/` | Filter help |
| Help filter | `enter` | Apply filter |
| Help/filter | `esc` | Close / cancel filter |

### Revisions

| Key | Action |
|---|---|
| `j` / down | Move down |
| `k` / up | Move up |
| `pgdown` / `pgup` | Page down / up |
| `ctrl+r` | Refresh |
| `space` | Toggle selection, then jump to parent |
| `@` | Jump to working copy |
| `shift+j` / `shift+k` | Jump to parent / children |
| `right` / `l` | Open Details |
| `enter` | Open inline describe |
| `shift+d` | Describe in external editor |
| `n` | New child revision |
| `alt+n` | Open new-between mode |
| `e` / `alt+e` | Edit / force edit |
| `shift+e` | Diff edit |
| `c` | Commit |
| `d` | Diff |
| `alt+d` | Open range diff |
| `s` / `alt+s` | Split / split parallel |
| `r` | Open rebase |
| `shift+s` | Open squash |
| `shift+a` | Open absorb |
| `a` | Open abandon |
| `y` | Open duplicate |
| `shift+r` | Open revert |
| `shift+m` | Open set-parents |
| `v` | Open evolog |
| `shift+b` | Set bookmark inline |
| `shift+l` | Edit revset with cleared input |
| `b` | Open Bookmarks |
| `g` | Open Git |
| `o` | Open oplog |
| `u` / `shift+u` | Open undo / redo |
| `p` | Toggle preview |
| `shift+p` | Toggle preview at bottom |
| `/` | Start quick search |
| `f` | Ace Jump |
| `ctrl+t` | Open fuzzy file search |
| `:` / `$` | Open jj / shell command input |
| `shift+w` | Open command history |
| `esc` | Clear revision selection |

Quick search uses `'` for the next match, `"` for the previous match, and `esc` to clear. Its
text-input submode uses `enter` to apply and `esc` to cancel.

### Rebase mode

| Key | Action |
|---|---|
| `r` | Source is selected revision(s) only |
| `shift+b` | Source is branch |
| `s` | Source includes descendants |
| `o` / `a` / `b` | Target onto / after / before |
| `i` | Insert between after/before points |
| `t` | Open target picker |
| `e` | Toggle skip-emptied |
| `enter` / `alt+enter` | Apply / force apply |
| `f` / `@` | Ace Jump / working copy |
| `j` / `k`, arrows | Navigate |
| `pgdown` / `pgup` | Page down / up |
| `esc` | Cancel |

### Squash mode

| Key | Action |
|---|---|
| `i` | Toggle interactive hunk selection |
| `e` | Toggle keep-emptied |
| `d` | Toggle destination description |
| `t` | Open target picker |
| `enter` / `alt+enter` | Apply / force apply |
| `f` / `@` | Ace Jump / working copy |
| `j` / `k`, arrows | Navigate |
| `pgdown` / `pgup` | Page down / up |
| `esc` | Cancel |

### Revert and duplicate modes

Both modes share target controls. Revert opens with `shift+r`; Duplicate opens with `y`.

| Key | Action |
|---|---|
| `o` / `a` / `b` | Target onto / after / before |
| `i` | Insert between after/before points |
| `t` | Open target picker |
| `enter` / `alt+enter` | Apply / force apply |
| `f` / `@` | Ace Jump / working copy |
| `j` / `k`, arrows | Navigate |
| `pgdown` / `pgup` | Page down / up |
| `esc` | Cancel |

### Details and its dialogs

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move down / up |
| `pgdown` / `pgup` | Page down / up |
| `m` / `space` | Toggle file selection |
| `/` | Filter paths |
| `d` | Diff file |
| `s` / `alt+s` | Split / split parallel |
| `shift+s` | Squash selected files |
| `r` | Restore selected files |
| `shift+a` | Absorb selected files |
| `*` | Show revisions changing file |
| `p` / `shift+p` | Preview / preview at bottom |
| `ctrl+r` | Refresh details |
| `h` / left / `esc` | Close Details |

The Details filter uses `enter` to keep the filter and `esc` to clear it. Confirmation dialogs use
`h` / `l` or left / right to choose, `enter` to apply, `alt+enter` to force, and `esc` to cancel.
For Restore and Split confirmations, `i` selects the interactive editor option.

### Evolog mode

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move down / up |
| `pgdown` / `pgup` | Page down / up |
| `d` | Diff evolution entry |
| `r` | Enter restore mode |
| `p` / `shift+p` | Preview / preview at bottom |
| `enter` | Apply restore target |
| `esc` | Cancel or close |

### Abandon and absorb modes

| Key | Action |
|---|---|
| `space` | Toggle revision selection |
| `s` | Select highlighted revision and descendants |
| `enter` | Apply |
| `alt+enter` | Force apply (Abandon only) |
| `f` / `@` | Ace Jump / working copy |
| `j` / `k`, arrows | Navigate |
| `pgdown` / `pgup` | Page down / up |
| `esc` | Cancel |

### Set-parents mode

| Key | Action |
|---|---|
| `space` | Toggle parent addition/removal |
| `enter` | Apply |
| `f` / `@` | Ace Jump / working copy |
| `j` / `k`, arrows | Navigate |
| `pgdown` / `pgup` | Page down / up |
| `esc` | Cancel |

### Inline describe and set-bookmark inputs

| Scope | Key | Action |
|---|---|---|
| Inline describe | `enter` | Insert newline |
| Inline describe | `alt+enter` / `ctrl+s` | Apply |
| Inline describe | `alt+shift+enter` | Force apply |
| Inline describe | `alt+e` | Open external editor |
| Inline describe | `esc` | Cancel/stash eligible draft |
| Set bookmark | `tab` / `shift+tab` | Complete forward / backward |
| Set bookmark | `enter` | Apply |
| Set bookmark | `esc` | Cancel |

### Diff-range and new-between modes

| Scope | Key | Action |
|---|---|---|
| Diff range | `j` / `k`, arrows | Navigate |
| Diff range | `pgdown` / `pgup` | Page down / up |
| Diff range | `x` | Swap from/to |
| Diff range | `f` / `t` | Pick from / to target |
| Diff range | `enter` | Open diff |
| Diff range | `esc` | Cancel |
| New between | `j` / `k`, arrows | Navigate |
| New between | `pgdown` / `pgup` | Page down / up |
| New between | `space` | Toggle insert-before point |
| New between | `enter` | Apply |
| New between | `esc` | Cancel |

### Target picker, Ace Jump, and prompt inputs

| Scope | Key | Action |
|---|---|---|
| Target picker | `up` / `ctrl+p` | Move up |
| Target picker | `down` / `ctrl+n` | Move down |
| Target picker | `tab` / `shift+tab` | Complete forward / backward |
| Target picker | `enter` / `alt+enter` | Apply / force apply |
| Target picker | `esc` | Cancel |
| Ace Jump | label keys / `enter` | Select label / apply |
| Ace Jump | `esc` | Cancel |
| jj/shell prompt | `ctrl+r` | Complete command/history |
| jj/shell prompt | `up` / `ctrl+p` | Previous suggestion |
| jj/shell prompt | `down` / `ctrl+n` | Next suggestion |
| jj/shell prompt | `ctrl+u` / `pgup` | Suggestion page up |
| jj/shell prompt | `ctrl+d` / `pgdown` | Suggestion page down |
| jj/shell prompt | `enter` / `esc` | Execute / cancel |

### Revset editor and preview pane

| Scope | Key | Action |
|---|---|---|
| Revset | `tab` / `shift+tab` | Complete forward / backward |
| Revset | `up` / `ctrl+p` | Move up in history/completions |
| Revset | `down` / `ctrl+n` | Move down in history/completions |
| Revset | `enter` | Apply |
| Revset | `esc` / `ctrl+c` | Cancel |
| Preview | `ctrl+p` / `ctrl+n` | Scroll up / down |
| Preview | `ctrl+u` / `ctrl+d` | Half-page up / down |
| Preview | `ctrl+h` / `ctrl+l` | Expand / shrink |

### Fuzzy file search

| Key | Action |
|---|---|
| `up` / `ctrl+p` | Move up |
| `down` / `ctrl+n` | Move down |
| `pgup` / `ctrl+u` | Page up |
| `pgdown` / `ctrl+d` | Page down |
| `ctrl+b` / `ctrl+f` | Preview half-page up / down |
| `ctrl+t` | Toggle live mode |
| `alt+e` | Edit selected file |
| `space` | Refine current fuzzy matches |
| `enter` | Apply and close |
| `esc` | Cancel |

### Bookmarks

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move down / up |
| `pgdown` / `pgup` | Page down / up |
| `tab` / `shift+tab` | Next / previous remote scope |
| `m` | Filter to move commands |
| `d` | Filter to delete commands |
| `f` | Filter to forget commands |
| `t` | Filter to track commands |
| `u` | Filter to untrack commands |
| `/` | Free-text filter |
| `enter` | Apply highlighted command |
| `esc` | Cancel filter or close |

### Git

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move down / up |
| `pgdown` / `pgup` | Page down / up |
| `tab` / `shift+tab` | Next / previous remote |
| `p` | Filter/execute push |
| `f` | Filter/execute fetch |
| `/` | Free-text filter |
| `enter` | Apply highlighted command |
| `esc` | Cancel filter or close |

### Oplog

| Key | Action |
|---|---|
| `j` / `k`, arrows | Move down / up |
| `pgdown` / `pgup` | Page down / up |
| `d` | Diff operation |
| `r` / `shift+r` | Restore / revert operation |
| `p` / `shift+p` | Preview / preview at bottom |
| `/` | Quick search |
| `'` / `"` | Next / previous match |
| `esc` | Clear search or close |

### Undo, redo, diff, and command history

| Scope | Key | Action |
|---|---|---|
| Undo | `h` / `l` | Previous / next option |
| Undo | `enter` / `esc` | Apply / cancel |
| Redo | `h` / `l` | Previous / next option |
| Redo | `enter` / `esc` | Apply / cancel |
| Diff | `j` / `k`, arrows | Scroll down / up |
| Diff | `pgdown` / `f` / `space` | Page down |
| Diff | `pgup` / `b` | Page up |
| Diff | `d` / `ctrl+d` | Half-page down |
| Diff | `u` / `ctrl+u` | Half-page up |
| Diff | `g` / `G` | Top / bottom |
| Diff | `h` / `l`, arrows | Scroll left / right |
| Diff | `w` | Toggle wrap |
| Diff | `ctrl+t` | Pick changed file |
| Diff | `[` / `]` | Previous / next file |
| Diff | `esc` | Close |
| Command history | `j` / `k`, arrows | Move down / up |
| Command history | `d` | Delete selected entry |
| Command history | `shift+w` / `esc` | Close |

### Generic choice, input, and password dialogs

| Scope | Key | Action |
|---|---|---|
| Choice | `j` / `k`, arrows | Move down / up |
| Choice | `/` | Filter choices |
| Choice/filter | `enter` | Apply |
| Choice/filter | `esc` | Cancel |
| Generic input | `enter` / `esc` | Apply / cancel |
| Password | `enter` | Apply |
| Password | `esc` / `ctrl+c` | Cancel |

## Sources and keeping this guide current

- [Official jjui documentation](https://idursun.github.io/jjui/)
- [jjui repository](https://github.com/idursun/jjui)
- [v0.10.9 release](https://github.com/idursun/jjui/releases/tag/v0.10.9)
- [Default v0.10.9 bindings](https://github.com/idursun/jjui/blob/v0.10.9/internal/config/default/bindings.toml)

jjui evolves quickly. After upgrading, check `jjui --version`, press `F1` for runtime bindings, and
compare custom actions against the upstream default bindings and migration notes.
