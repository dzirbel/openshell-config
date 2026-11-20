#!/usr/bin/env bash
# Rebuild the VM, keeping /sandbox and the existing sandbox name/SSH alias.
set -euo pipefail
umask 077

action=${1:?Usage: recreate.sh recreate-or-restore sandbox image policy ssh_config [--env KEY=VALUE ...]}
sandbox=${2:?Missing sandbox name}
image=${3:?Missing image}
policy=${4:?Missing policy path}
ssh_config=${5:?Missing SSH configuration path}
shift 5
sandbox_environment=("$@")
[[ $action == recreate || $action == restore ]] || exit 2
[[ $sandbox =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || exit 2

backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/openshell/recreate/$sandbox"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
exec 9>"$backup_dir/lock"
flock -n 9 || { echo "Another migration is running for $sandbox." >&2; exit 1; }
backup="$backup_dir/sandbox.tar.gz"
ssh_before="$backup_dir/ssh_config.before"
pending="$backup_dir/incomplete"
if [[ $action == recreate && -f $pending ]]; then
    echo 'An earlier migration is incomplete. Run make restore instead of replacing its backup.' >&2
    exit 1
fi
if [[ $action == restore && ! -f $pending ]]; then
    echo 'No interrupted migration to restore.' >&2
    exit 1
fi
partial=
ssh_temporary=
remote_stage=
ssh_blocked=false
backup_ready=false
replacement_started=false
[[ ! -f $pending ]] || replacement_started=true

on_exit() {
    result=$?
    trap - EXIT
    [[ -z $partial ]] || rm -f -- "$partial"
    [[ -z $ssh_temporary ]] || rm -f -- "$ssh_temporary"
    # The host backup remains authoritative even after a failed upload/extract.
    [[ -z $remote_stage ]] || remote /bin/rm -rf -- "$remote_stage" || true
    if (( result != 0 )); then
        if [[ $replacement_started == false && $ssh_blocked == true && -f $ssh_before ]]; then
            cp -- "$ssh_before" "$ssh_config"
            rm -f -- "$ssh_before"
        fi
        if [[ $backup_ready == true ]]; then
            printf '\nMigration did not finish. Verified backup retained at:\n  %s\n' "$backup" >&2
            printf 'After resolving the error, retry restoration with:\n  make -C %q restore SANDBOX=%q IMAGE=%q\n' \
                "$(dirname "$ssh_config")" "$sandbox" "$image" >&2
        else
            echo 'This attempt stopped before deleting any sandbox.' >&2
        fi
    fi
    exit "$result"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

remote() {
    openshell sandbox exec "$sandbox" --no-tty --no-login-shell -- "$@"
}

create() {
    openshell sandbox create --name "$sandbox" --from "$image" \
        --policy "$policy" --approval-mode manual --no-auto-providers \
        "${sandbox_environment[@]}" --detach -- /bin/sleep infinity
}

wait_until_deleted() {
    for (( attempt=0; attempt<60; attempt++ )); do
        names=$(openshell sandbox list --names)
        if ! grep -Fxq -- "$sandbox" <<<"$names"; then return; fi
        sleep 1
    done
    echo "Timed out waiting for $sandbox to finish deletion." >&2
    return 1
}

# Validate the inputs before interrupting the existing VM.
podman image exists "$image"
openshell-prover check --boundary "$policy" "$policy" >/dev/null

if [[ $action == restore ]]; then
    (cd "$backup_dir" && sha256sum --check --status sandbox.tar.gz.sha256)
    tar -tzf "$backup" >/dev/null
    backup_ready=true
fi

# Stop GUI auto-reconnections from launching writers during the transfer.
if [[ -f $ssh_config ]]; then
    # Recovery must not overwrite the saved connection with the blocked one.
    [[ -f $ssh_before ]] || cp -- "$ssh_config" "$ssh_before"
    ssh_temporary=$(mktemp "${ssh_config}.XXXXXX")
    sed -E 's|^[[:space:]]*ProxyCommand[[:space:]].*|    ProxyCommand false|' \
        "$ssh_config" >"$ssh_temporary"
    mv -- "$ssh_temporary" "$ssh_config"
    ssh_temporary=
    ssh_blocked=true
fi

if [[ $action == recreate ]]; then
    echo "Restarting $sandbox to stop applications before taking the backup..."
    openshell sandbox stop "$sandbox"
    openshell sandbox start "$sandbox"
    echo "Saving all of /sandbox to $backup..."
    partial=$(mktemp "$backup_dir/.sandbox.XXXXXX.tar.gz")
    remote /bin/tar --create --gzip --file=- --directory=/sandbox . >"$partial"
    tar -tzf "$partial" >/dev/null
    mv -- "$partial" "$backup"
    partial=
    (cd "$backup_dir" && sha256sum sandbox.tar.gz >sandbox.tar.gz.sha256)
    backup_ready=true

    echo "Replacing $sandbox from $image..."
    touch "$pending"
    openshell sandbox stop "$sandbox"
    replacement_started=true
    openshell sandbox delete "$sandbox"
    wait_until_deleted
    create
else
    # Explicit recovery never replaces the verified archive with a partial VM.
    replacement_started=true
    names=$(openshell sandbox list --names)
    if grep -Fxq -- "$sandbox" <<<"$names"; then
        openshell sandbox stop "$sandbox"
        openshell sandbox start "$sandbox"
    else
        create
    fi
fi

echo 'Restoring and verifying /sandbox...'
# Plain SSH exec also has OpenShell's 4 MiB pending-input limit. The dedicated
# upload protocol waits for consumption instead. Stage on disk, not /tmp (RAM).
remote_stage=$(remote /usr/bin/mktemp -d /sandbox/.openshell-restore.XXXXXX)
[[ $remote_stage =~ ^/sandbox/\.openshell-restore\.[a-zA-Z0-9]+$ ]]
openshell sandbox upload "$sandbox" "$backup" "$remote_stage/" --no-git-ignore
remote_archive="$remote_stage/sandbox.tar.gz"
echo 'Checking uploaded archive checksum...'
read -r expected_hash _ <"$backup_dir/sandbox.tar.gz.sha256"
actual_hash=$(remote /usr/bin/sha256sum "$remote_archive")
[[ ${actual_hash%% *} == "$expected_hash" ]] || {
    echo 'Uploaded archive checksum mismatch.' >&2; exit 1;
}
echo 'Extracting /sandbox...'
remote /bin/tar --extract --gzip --preserve-permissions --no-same-owner \
    --file="$remote_archive" --directory=/sandbox
echo 'Comparing restored files against the backup...'
remote /bin/tar --compare --gzip --file="$remote_archive" --directory=/sandbox
remote /bin/rm -rf -- "$remote_stage"
remote_stage=

# Publish the connection only after successful restoration and comparison.
ssh_temporary=$(mktemp "${ssh_config}.XXXXXX")
openshell sandbox ssh-config "$sandbox" >"$ssh_temporary"
mv -- "$ssh_temporary" "$ssh_config"
ssh_temporary=
rm -f -- "$ssh_before" "$pending"
printf '\n%s is ready. Last /sandbox backup: %s\n' "$sandbox" "$backup"
