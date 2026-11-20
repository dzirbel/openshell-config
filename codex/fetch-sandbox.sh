#!/usr/bin/env bash
# Host-side import of a committed proposal from OpenShell into a review worktree.
set -euo pipefail
usage() {
    cat <<'HELP'
Usage: git fetch-sandbox REF [SANDBOX_PATH [WORKTREE_PATH]]

Fetch a branch, commit ID, or HEAD and create a local review worktree.
SANDBOX_PATH defaults to: git config sandbox.path
SSH host defaults to openshell-codex-dev.default; override with sandbox.host.
Only committed changes are transferred. Existing branches/folders are preserved.
HELP
}
[[ ${1:-} != --help && ${1:-} != -h ]] || { usage; exit 0; }
(( $# >= 1 && $# <= 3 )) || { usage >&2; exit 2; }
fail() { printf '%s\n' "$*" >&2; exit 1; }
root=$(git rev-parse --show-toplevel)
cd "$root"
ref=$1
# Reject options, revision expressions, and refspecs that could update local refs.
git check-ref-format "refs/heads/$ref" >/dev/null || fail 'Use a branch name, commit ID, or HEAD.'
remote_path=${2:-$(git config --get sandbox.path || true)}
[[ $remote_path == /* ]] || fail 'Supply the absolute VM repository path, or set git config sandbox.path /sandbox/path/to/repo.'
host=$(git config --get sandbox.host || true)
host=${host:-openshell-codex-dev.default}
[[ $host =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail 'sandbox.host must be an SSH host alias.'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ssh_config="$script_dir/ssh_config"
if [[ ! -r $ssh_config ]]; then
    printf 'Missing SSH configuration: %s\nGenerate it with: make -C %q ssh-config\n' \
        "$ssh_config" "$script_dir" >&2
    exit 1
fi
printf -v ssh_command 'ssh -F %q' "$ssh_config"
base=$(git rev-parse HEAD)
# Reserve a ref for this invocation so other fetches cannot change its result.
fetch_ref="refs/fetch-sandbox/$$-$RANDOM"
git update-ref --no-deref "$fetch_ref" "$base" ""
trap 'git update-ref --no-deref -d "$fetch_ref"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git -c core.sshCommand="$ssh_command" fetch --no-tags --no-recurse-submodules \
    --no-write-fetch-head "$host:$remote_path" "+$ref:$fetch_ref"
commit=$(git rev-parse --verify "$fetch_ref^{commit}")
git merge-base "$base" "$commit" >/dev/null || fail 'Proposal and local HEAD have no common history; no worktree created.'
short=$(git rev-parse --short=12 "$commit")
task=${ref#refs/heads/}
task=${task#agent/}
branch="review/$task-$short"
name=${task//\//-}
destination=${3:-"$(dirname "$root")/$(basename "$root")-review-$name-$short"}
git show-ref --verify --quiet "refs/heads/$branch" && fail "Already imported as $branch; no existing review was changed."
[[ ! -e $destination && ! -L $destination ]] || fail "Destination already exists: $destination"
git worktree add -b "$branch" "$destination" "$commit"
printf '\nReview branch: %s\nCommit: %s\nWorktree: %s\n' "$branch" "$commit" "$destination"
printf 'Compare with your starting checkout:\n  git -C %q diff %q\n' "$destination" "$base...HEAD"
