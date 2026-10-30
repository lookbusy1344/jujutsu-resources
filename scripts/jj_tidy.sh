#!/bin/bash
# Check and compact the jj repository containing the current directory: verify
# integrity, trim the op log to the last N days once an operation is older than
# N + OP_PRUNE_GRACE_DAYS days, and garbage-collect. Changes
# are confirmed unless --yes is supplied. The working copy is snapshotted to
# report uncommitted changes in @, including under --dry-run, and again before
# the first change. Git
# progress output is suppressed.

set -uo pipefail

MIN_LOOSE_COUNT=50
DEFAULT_OP_KEEP_DAYS=21
MIN_OP_KEEP_DAYS=14
OP_PRUNE_GRACE_DAYS=2
SECONDS_PER_DAY=86400
EXIT_USAGE=1
EXIT_NOT_JJ=2
EXIT_DAMAGED=3
EXIT_BUSY=4
EXIT_MAINTENANCE=5
FIND_EXPIRED_NON_MONOTONIC=2
MULTIPLE_OP_HEADS_ERROR='resolved to more than one operation'
NOT_COLOCATED='not counted (not colocated)'

assume_yes=0
dry_run=0
gc_requested=0
op_keep_days=$DEFAULT_OP_KEEP_DAYS

usage() {
  printf 'Usage: %s [-y | --yes] [--dry-run] [--gc] [--keep-days N]\n' "${0##*/}"
  printf '  -y, --yes      answer yes to every prompt\n'
  printf '  --dry-run      check and show the proposed work without changing the repo\n'
  printf '  --gc           offer GC whatever the loose-object count\n'
  printf '  --keep-days N  retain at least N days of op log (default %d, minimum %d);\n' \
    "$DEFAULT_OP_KEEP_DAYS" "$MIN_OP_KEEP_DAYS"
  printf '                 prune only once an operation is %d days older than that\n' \
    "$OP_PRUNE_GRACE_DAYS"
}

error() {
  printf '\033[1;31m%s\033[0m\n' "$@" >&2
}

# Bold yellow on a terminal; plain when piped, so output stays parseable.
warn() {
  if [[ -t 1 ]]; then
    printf '\033[1;33m%s\033[0m\n' "$@"
  else
    printf '%s\n' "$@"
  fi
}

# die CODE MESSAGE... : print each message as an error line and exit with CODE.
die() {
  local code=$1; shift
  error "$@"
  exit "$code"
}

set_keep_days() {
  local value=${1-}
  if [[ ! "$value" =~ ^[0-9]+$ ]] || (( 10#$value < MIN_OP_KEEP_DAYS )); then
    error "--keep-days needs a whole number of days, at least $MIN_OP_KEEP_DAYS, got '$value'"
    usage >&2
    exit "$EXIT_USAGE"
  fi
  op_keep_days=$((10#$value))
}

while (( $# )); do
  case "$1" in
    -y|--yes)      assume_yes=1 ;;
    --dry-run)     dry_run=1 ;;
    --gc)          gc_requested=1 ;;
    --keep-days)   set_keep_days "${2-}"; shift ;;
    --keep-days=*) set_keep_days "${1#*=}" ;;
    -h|--help)     usage; exit 0 ;;
    *) error "Unknown option: $1"; usage >&2; exit "$EXIT_USAGE" ;;
  esac
  shift
done

# Ask a y/n question; succeeds on yes. --yes succeeds without prompting. No input is no.
confirm() {
  local answer=
  (( assume_yes )) && return 0
  read -r -p "$1 (y/n): " answer
  [[ "$answer" == [Yy]* ]]
}

count_rows() {
  awk 'NF { n++ } END { print n + 0 }'
}

# Prints "<op id>\t<start epoch seconds>" per operation, newest first. Walks
# every operation, so a failure means the op store is damaged. --at-op @
# refuses to merge multiple operation heads, so the walk is read-only.
op_age_rows() {
  jj --at-op @ op log --no-graph --ignore-working-copy \
    -T 'if(!root, id ++ "\t" ++ time.start().format("%s") ++ "\n")'
}

# find_expired_head CUTOFF TRIGGER : reads op_age_rows on stdin and, when an
# operation below the current one (which jj cannot abandon) started before
# TRIGGER, prints the first operation older than CUTOFF. The gap between the
# two stops repeated runs from pruning a few operations at a time. Exits
# FIND_EXPIRED_NON_MONOTONIC if a retained timestamp follows an expired one
# (concurrent histories or clock changes): topological order is then not
# chronological, and the prune is off.
find_expired_head() {
  awk -F '\t' -v cutoff="$1" -v trigger="$2" -v non_monotonic="$FIND_EXPIRED_NON_MONOTONIC" '
    NR == 1 { next }
    $2 < trigger { triggered = 1 }
    $2 < cutoff {
      if (!head) head = $1
      expired = 1
      next
    }
    expired { unsafe = 1 }
    END {
      if (!triggered) exit 0
      if (unsafe) exit non_monotonic
      if (head) print head
    }'
}

# Counts the operations `jj op abandon ..<head>` selects: the ancestors of
# <head>, which need not be every later row of the topological log.
count_ops_through() {
  jj --at-op "$1" op log --no-graph --ignore-working-copy -T 'if(!root, "x\n")' |
    count_rows
}

# Prints jj's short form of operation id $1.
short_op_id() {
  jj --at-op "$1" op log --limit 1 --no-graph --ignore-working-copy -T 'id.short()'
}

# Prints "<loose count> (<loose size> KiB)".
loose_objects() {
  git count-objects -v |
    awk '/^count:/ { c = $2 } /^size:/ { s = $2 }
      END { if (c == "" || s == "") exit 1; print c " (" s " KiB)" }'
}

# Succeeds when a jj process has a working directory or an open file inside the
# repo. jj takes no lock that other jj processes honour, so this is the only way
# to see a command in flight. It cannot see a command that starts later.
jj_running_in_repo() {
  local pids
  pids=$(pgrep -x jj 2>/dev/null | paste -sd, -)
  [[ -n "$pids" ]] || return 1
  lsof -Fn -p "$pids" 2>/dev/null |
    awk -v root="$repo_root" '
      /^n/ {
        path = substr($0, 2)
        if (path == root || index(path, root "/") == 1) found = 1
      }
      END { exit !found }'
}

repo_root=$(jj root --ignore-working-copy 2>/dev/null) ||
  die "$EXIT_NOT_JJ" "Not in a jj repo: $PWD"
cd "$repo_root" || exit "$EXIT_NOT_JJ"
# Physical path, to match the paths lsof reports.
repo_root=$(pwd -P)

# This must be the first repository load after `jj root`. jj rejects --at-op @
# with MULTIPLE_OP_HEADS_ERROR when the repo has several operation heads. Any
# ordinary jj command would merge them, so the op log stays unread and the
# prune is skipped. Any other failure means jj cannot load the repo.
unmerged_ops=0
if ! load_error=$(jj --ignore-working-copy --at-op @ op log --limit 1 --no-graph \
  -T '""' 2>&1 >/dev/null); then
  [[ "$load_error" == *"$MULTIPLE_OP_HEADS_ERROR"* ]] || {
    printf '%s\n' "$load_error" >&2
    die "$EXIT_DAMAGED" "jj could not load the repository: $repo_root"
  }
  unmerged_ops=1
fi

# jj has no fsck: op_age_rows walks every operation instead. A damaged repo
# stops the script before the prune and GC delete objects a repair may need.
damaged=0
op_count=unknown
age_rows=
if (( ! unmerged_ops )); then
  if age_rows=$(op_age_rows); then
    op_count=$(count_rows <<<"$age_rows")
  else
    error "jj operation-log age scan failed: $repo_root"
    damaged=1
  fi
fi

# A colocated repo shares the git object store, so git fsck covers it and the
# loose-object count gates the GC prompt. A non-colocated repo has no cheap
# count, so GC is always offered. --no-dangling hides jj's hidden commits,
# which only the op log reaches.
colocated=0
[[ -d "$repo_root/.git" ]] && colocated=1
many_loose=1
loose_summary=$NOT_COLOCATED
if (( colocated )); then
  git fsck --strict --no-dangling --no-progress || {
    error "git fsck failed: $repo_root"
    damaged=1
  }
  if loose_summary=$(loose_objects); then
    (( ${loose_summary%% *} > MIN_LOOSE_COUNT )) || many_loose=0
  else
    error "git count-objects failed: $repo_root"
    loose_summary=unknown
    damaged=1
  fi
fi

wc_note=

print_repo() {
  printf 'Repository: %s\n' "$repo_root"
  [[ -n "$wc_note" ]] && warn "$wc_note"
  return 0
}

print_summary() {
  print_repo
  printf 'Operations: %s\n' "$op_count"
  printf 'Loose objects: %s\n' "$loose_summary"
  printf 'Retention: %d days\n' "$op_keep_days"
}

if (( damaged )); then
  print_summary
  die "$EXIT_DAMAGED" "Skipping op-log prune and GC: repair this repository first."
fi

# Report uncommitted changes in @. The `empty` query snapshots the working
# copy, which would merge unmerged operation heads or race a running jj
# command, so those cases skip the check.
if (( unmerged_ops )); then
  wc_note='@ not checked: unmerged concurrent operations'
elif jj_running_in_repo; then
  wc_note='@ not checked: jj is busy in this repository'
elif wc_empty=$(jj --quiet --no-pager log -r @ --no-graph -T empty); then
  case "$wc_empty" in
    true) ;;
    false) wc_note='@ is dirty' ;;
    *) wc_note="@ check failed: unexpected output '$wc_empty'" ;;
  esac
else
  wc_note='@ check failed (jj log -r @)'
fi

expired_head=
skip_reason=
if (( unmerged_ops )); then
  skip_reason='Skipping op-log prune: unmerged concurrent operations. Any jj command merges them.'
else
  now=$(date +%s)
  cutoff=$(( now - op_keep_days * SECONDS_PER_DAY ))
  trigger=$(( cutoff - OP_PRUNE_GRACE_DAYS * SECONDS_PER_DAY ))
  expired_head=$(find_expired_head "$cutoff" "$trigger" <<<"$age_rows")
  case $? in
    0) ;;
    "$FIND_EXPIRED_NON_MONOTONIC")
      skip_reason='Skipping op-log prune: operation timestamps are not monotonic.'
      expired_head= ;;
    *) die "$EXIT_DAMAGED" "jj operation-log age scan failed: $repo_root" ;;
  esac
fi

# A clean repo with no work to offer reports only its path.
if [[ -z "$expired_head" && -z "$skip_reason" ]] && (( ! gc_requested && ! many_loose )); then
  print_repo
  exit 0
fi

print_summary
[[ -n "$skip_reason" ]] && printf '%s\n' "$skip_reason"

expired_count=0
if [[ -n "$expired_head" ]]; then
  expired_count=$(count_ops_through "$expired_head") ||
    die "$EXIT_DAMAGED" "Could not count operations selected by ..$expired_head"
  printf 'Proposed removal: %s operations\n' "$expired_count"
  boundary=$(short_op_id "$expired_head") ||
    die "$EXIT_DAMAGED" "Could not read operation $expired_head"
  printf 'Abandonment boundary: %s\n' "$boundary"
fi

if (( dry_run )); then
  printf 'Dry run: no changes made.\n'
  exit 0
fi

# Only GC reclaims what a prune leaves behind, so a confirmed prune implies GC.
prune=0
gc=0
if [[ -n "$expired_head" ]] &&
  confirm "Abandon $expired_count operations older than $op_keep_days days and run 'jj util gc'?"; then
  prune=1
  gc=1
elif (( gc_requested || many_loose )); then
  if confirm "Run 'jj util gc'?"; then
    gc=1
  else
    printf 'Skipped jj util gc.\n'
  fi
fi

(( gc )) || exit 0

jj_running_in_repo &&
  die "$EXIT_BUSY" "Stopping: another jj process appears to be using this repository."

jj --quiet util snapshot || die "$EXIT_MAINTENANCE" "jj util snapshot failed: $repo_root"

# The snapshot merged any unmerged operation heads, so the integrity walk
# skipped above runs now, before GC deletes anything.
if (( unmerged_ops )) && ! op_age_rows >/dev/null; then
  die "$EXIT_DAMAGED" "jj operation-log age scan failed: $repo_root" \
    "Skipping GC: repair this repository first."
fi

# The abandon runs without --ignore-working-copy: the working copy must follow
# the rewritten current operation, or jj reports it as a sibling of the op log.
if (( prune )); then
  jj op abandon "..$expired_head" || die "$EXIT_MAINTENANCE" "jj op abandon failed: $repo_root"
fi

# `jj util gc` respects jj's op log and keep-refs, which raw git gc does not.
# Its default two-week grace period protects files a concurrent command has
# just written. The snapshot above lets GC skip the working copy. Git's
# progress output is captured and shown only on failure.
printf 'Running jj util gc...\n'
gc_log=$(jj util gc --ignore-working-copy 2>&1) || {
  printf '%s\n' "$gc_log" >&2
  die "$EXIT_MAINTENANCE" "jj util gc failed: $repo_root"
}

post_rows=$(op_age_rows) ||
  die "$EXIT_MAINTENANCE" "Could not read post-maintenance operation count: $repo_root"
printf 'Post-maintenance operations: %s\n' "$(count_rows <<<"$post_rows")"

post_loose=$NOT_COLOCATED
if (( colocated )); then
  post_loose=$(loose_objects) ||
    die "$EXIT_MAINTENANCE" "Could not read post-maintenance loose-object count: $repo_root"
fi
printf 'Post-maintenance loose objects: %s\n' "$post_loose"
