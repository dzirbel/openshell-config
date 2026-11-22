#!/usr/bin/env bash
# Rebuild the VM, keeping /sandbox and the existing sandbox name/SSH alias.
set -euo pipefail
umask 077

action=${1:?Usage: recreate.sh recreate-or-restore sandbox image policy ssh_config harness toolchain [create flags]}
sandbox=${2:?Missing sandbox name}
image=${3:?Missing image}
policy=${4:?Missing policy path}
ssh_config=${5:?Missing SSH configuration path}
harness=${6:?Missing harness}
toolchain=${7:?Missing toolchain}
shift 7
create_flags=("$@")
[[ $action == recreate || $action == restore ]] || exit 2
[[ $sandbox =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || exit 2
mkdir -p -- "$(dirname -- "$ssh_config")"

backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/openshell/recreate/$sandbox"
mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
exec 9>"$backup_dir/lock"
flock -n 9 || { echo "Another migration is running for $sandbox." >&2; exit 1; }
backup="$backup_dir/sandbox.tar.gz"
ssh_before="$backup_dir/ssh_config.before"
pending="$backup_dir/incomplete"
plan="$backup_dir/replacement.json"
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
            printf 'After resolving the error, retry restoration with:\n  make -C %q restore SANDBOX=%q HARNESS=%q TOOLCHAIN=%q IMAGE=%q\n' \
                "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")" "$sandbox" "$harness" "$toolchain" "$image" >&2
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
        "${create_flags[@]}" "${provider_flags[@]}" --detach -- /bin/sleep infinity
}

read_providers() {
    local page token="" names
    while :; do
        page=$(openshell sandbox provider list "$sandbox" --output json --page-token "$token") || return
        names=$(jq -r '.providers | map(.name | strings)[]' <<<"$page") || return
        [[ -z $names ]] || printf '%s\n' "$names"
        token=$(jq -r '.next_page_token // empty' <<<"$page") || return
        [[ -n $token ]] || break
    done
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
image_id=$(podman image inspect --format '{{.Id}}' "$image")
openshell-prover check --boundary "$policy" "$policy" >/dev/null

provider_flags=()
if [[ $action == restore ]]; then
    (cd "$backup_dir" && sha256sum --check --status sandbox.tar.gz.sha256)
    tar -tzf "$backup" >/dev/null
    backup_ready=true
    if [[ -f $plan ]]; then
        jq -e --arg harness "$harness" --arg toolchain "$toolchain" --arg image "$image_id" \
            '.harness == $harness and .toolchain == $toolchain and .image_id == $image' "$plan" >/dev/null || {
            echo 'Restore requires the harness, toolchain and built image used for the interrupted replacement.' >&2
            exit 1
        }
        providers=$(jq -r '.providers[]' "$plan")
        original_id=$(jq -er '.original_id' "$plan")
    elif [[ $harness == codex && $toolchain == android ]]; then
        # Backups from before fleet support had no attached provider or plan.
        providers=
        original_id=
    else
        echo 'Missing replacement plan for this migration.' >&2
        exit 1
    fi
else
    details=$(openshell sandbox get "$sandbox" --output json)
    original_id=$(jq -er '.id | select(length > 0)' <<<"$details")
    original_harness=$(jq -r '.labels.harness // empty' <<<"$details")
    if [[ -n $original_harness && $original_harness != "$harness" ]]; then
        printf '%s uses %s. Create a fresh sandbox to switch harnesses.\n' "$sandbox" "$original_harness" >&2
        exit 1
    fi
    providers=$(read_providers)
fi
while IFS= read -r provider; do
    [[ -z $provider ]] || provider_flags+=(--provider "$provider")
done <<<"$providers"

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
    jq -n --arg harness "$harness" --arg toolchain "$toolchain" --arg image "$image_id" \
        --arg original_id "$original_id" --arg providers "$providers" \
        '{harness: $harness, toolchain: $toolchain, image_id: $image, original_id: $original_id,
          providers: ($providers | split("\n") | map(select(length > 0)))}' >"$plan"
    touch "$pending"
    replacement_started=true
    openshell sandbox stop "$sandbox"
    openshell sandbox delete "$sandbox"
    wait_until_deleted
    create
else
    # Explicit recovery never replaces the verified archive with a partial VM.
    replacement_started=true
    names=$(openshell sandbox list --names)
    if grep -Fxq -- "$sandbox" <<<"$names"; then
        details=$(openshell sandbox get "$sandbox" --output json)
        current_id=$(jq -er '.id | select(length > 0)' <<<"$details")
        if [[ $current_id == "$original_id" ]]; then
            openshell sandbox stop "$sandbox"
            openshell sandbox delete "$sandbox"
            wait_until_deleted
            create
        else
            openshell sandbox stop "$sandbox"
            openshell sandbox start "$sandbox"
        fi
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
rm -f -- "$ssh_before" "$pending" "$plan"
printf '\n%s is ready. Last /sandbox backup: %s\n' "$sandbox" "$backup"
