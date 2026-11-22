#!/usr/bin/env bash
set -euo pipefail
umask 077

action=${1:?Missing SSH config action}
sandbox=${2:?Missing sandbox name}
[[ $sandbox =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] || {
    printf 'Invalid sandbox name: %s\n' "$sandbox" >&2
    exit 2
}
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/openshell/recreate/$sandbox"
if [[ -f $backup_dir/incomplete ]]; then
    printf 'An interrupted migration exists for %s. Use make restore.\n' "$sandbox" >&2
    exit 1
fi
[[ $action != check ]] || exit 0

config=${3:?Missing SSH config path}
case $action in
    publish)
        mkdir -p -- "$(dirname -- "$config")"
        temporary=$(mktemp "$config.XXXXXX")
        trap 'rm -f -- "$temporary"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        openshell sandbox ssh-config "$sandbox" >"$temporary"
        alias_name=$(awk '/^Host / { print $2; exit }' "$temporary")
        [[ -n $alias_name ]] || { echo 'Missing SSH Host alias' >&2; exit 1; }
        mv -fT -- "$temporary" "$config"
        printf 'SSH alias: %s (%s)\n' "$alias_name" "$config"
        ;;
    agy)
        workdir=${4:?Missing working directory}
        alias_name=$(awk '/^Host / { print $2; exit }' "$config")
        [[ -n $alias_name ]] || { echo 'Missing SSH Host alias' >&2; exit 1; }
        # OpenShell's SSH supervisor can allocate a PTY without exporting SSH_TTY.
        # shellcheck disable=SC2016
        printf -v command 'cd -- %q && SSH_TTY="$(tty)" exec agy' "$workdir"
        exec ssh -F "$config" -t "$alias_name" "$command"
        ;;
    *)
        printf 'Unknown SSH config action: %s\n' "$action" >&2
        exit 2
        ;;
esac
