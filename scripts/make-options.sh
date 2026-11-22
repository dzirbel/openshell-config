#!/usr/bin/env bash
# Sourced by Make recipes. Only the options requested by the recipe are resolved.

option_exists() {
    local value=$1 option
    shift
    for option; do
        [[ $option != "$value" ]] || return 0
    done
    return 1
}

# Print a window of choices and leave its selected index in REPLY.
pick_option() {
    local name=$1 default=$2 rows=$3 columns=$4
    shift 4
    local -a choices=("$@")
    local count=$# selected=-1 first=0 visible=$((rows - 2))
    local index key heading
    (( visible <= 7 )) || visible=7
    (( visible <= count )) || visible=$count
    for index in "${!choices[@]}"; do
        if [[ ${choices[index]} == "$default" ]]; then
            selected=$index
            break
        fi
    done

    while :; do
        if (( selected >= 0 && selected < first )); then
            first=$selected
        elif (( selected >= first + visible )); then
            first=$((selected - visible + 1))
        fi
        heading="$name (Up/Down, Enter, Esc)"
        if (( selected >= 0 )); then
            heading="$name ($((selected + 1))/$count, Up/Down, Enter, Esc)"
        fi
        printf '%.*s\n' "$((columns - 1))" "$heading" >&2
        for ((index = first; index < first + visible; index++)); do
            if (( index == selected )); then
                printf '\e[7m> %.*s\e[0m\n' "$((columns - 3))" "${choices[index]}" >&2
            else
                printf '  %.*s\n' "$((columns - 3))" "${choices[index]}" >&2
            fi
        done

        IFS= read -rsn1 key || key=$'\004'
        if [[ $key == $'\e' ]]; then
            IFS= read -rsn2 -t 0.15 key || key=$'\004'
        fi
        # Go back to the menu heading and clear the previously drawn window.
        printf '\e[%dA\r\e[J' "$((visible + 1))" >&2
        case $key in
            '')
                if (( selected >= 0 )); then
                    REPLY=$selected
                    return 0
                fi
                ;;
            '[A'|'OA')
                (( selected >= 0 )) || selected=0
                selected=$(((selected + count - 1) % count))
                ;;
            '[B'|'OB') selected=$(((selected + 1) % count)) ;;
            $'\004') return 1 ;;
        esac
    done
}

read_option() {
    local name=$1 default=$2 mode=$3 size rows columns index prompt
    shift 3
    local -a choices=("$@")

    if (( $# > 0 )) && [[ -n $default ]] && ! option_exists "$default" "$@"; then
        default=$1
    fi

    if (( $# > 0 )) && [[ -t 2 && ${TERM:-dumb} != dumb ]] && size=$(stty size 2>/dev/null); then
        read -r rows columns <<<"$size"
        if (( rows >= 5 && columns >= 20 )); then
            [[ $mode != custom ]] || choices+=('Enter a custom value...')
            pick_option "$name" "$default" "$rows" "$columns" "${choices[@]}" || return
            if (( REPLY == $# )); then
                IFS= read -er -p "Custom $name: "
            else
                REPLY=${choices[REPLY]}
                printf '%s: %s\n' "$name" "$REPLY" >&2
            fi
            return
        fi
    fi

    if (( $# > 0 )); then
        for index in "${!choices[@]}"; do
            printf '  %s) %s\n' "$((index + 1))" "${choices[index]}" >&2
        done
        if [[ $mode == custom ]]; then
            printf '  c) Custom value\n' >&2
        fi
        prompt=$name
        [[ -z $default ]] || prompt+=" [Enter for $default]"
        IFS= read -r -p "$prompt: " || return
        if [[ $mode == custom && $REPLY == c ]]; then
            IFS= read -er -p "Custom $name: "
            return
        fi
        for index in "${!choices[@]}"; do
            if [[ $REPLY == "$((index + 1))" ]]; then
                REPLY=${choices[index]}
                break
            fi
        done
    else
        IFS= read -er -i "$default" -p "$name: " || return
    fi
    REPLY=${REPLY:-$default}
}

# An empty default requires a value from the caller or the terminal.
choose_option() {
    local name=$1 default=$2 mode=$3 value REPLY
    shift 3
    local interactive=false

    if [[ -v $name ]]; then
        value=${!name}
    elif [[ -t 0 ]]; then
        interactive=true
    elif [[ -n $default ]]; then
        value=$default
    else
        printf '%s is required without terminal input. Pass %s=... to make.\n' "$name" "$name" >&2
        return 2
    fi

    while :; do
        if [[ $interactive == true ]]; then
            read_option "$name" "$default" "$mode" "$@" || return
            value=$REPLY
        fi
        if [[ -z $value && -z $default ]]; then
            printf '%s requires a non-empty value.\n' "$name" >&2
        elif [[ $mode == custom ]] || option_exists "$value" "$@"; then
            printf -v "$name" '%s' "$value"
            return
        else
            printf 'Invalid %s "%s". Choose one of: %s\n' "$name" "$value" "$*" >&2
        fi
        [[ $interactive == true ]] || return 2
    done
}

choose_listed_option() {
    local name=$1 default=$2 names
    shift 2
    local -a choices=()
    # Listing is optional. The default and custom entry still work if it fails.
    if [[ ! -v $name && -t 0 ]] && names=$("$@" 2>/dev/null) && [[ -n $names ]]; then
        mapfile -t choices <<<"$names"
    fi
    choose_option "$name" "$default" custom "${choices[@]}"
}

pending_sandboxes() {
    local marker
    for marker in "${XDG_STATE_HOME:-$HOME/.local/state}"/openshell/recreate/*/incomplete; do
        [[ -f $marker ]] || continue
        marker=${marker%/incomplete}
        printf '%s\n' "${marker##*/}"
    done
}

resolve_options() {
    local option
    for option; do
        case $option in
            *@!*) [[ $HARNESS != "${option#*@!}" ]] || continue ;;
            *@*) [[ $HARNESS == "${option#*@}" ]] || continue ;;
        esac
        option=${option%@*}
        case $option in
            HARNESS) choose_option HARNESS '' fixed codex claude antigravity opencode ;;
            TOOLCHAIN)
                local default=plain
                [[ $HARNESS != codex ]] || default=android
                choose_option TOOLCHAIN "$default" fixed plain android plasma
                ;;
            SANDBOX) choose_listed_option SANDBOX "${HARNESS:-codex}-dev" openshell sandbox list --names ;;
            SANDBOX:new) choose_option SANDBOX "$HARNESS-dev" custom ;;
            SANDBOX:pending) choose_listed_option SANDBOX "$HARNESS-dev" pending_sandboxes ;;
            WORKDIR) choose_option WORKDIR '' custom ;;
            IMAGE) choose_option IMAGE "localhost/openshell-$HARNESS:$TOOLCHAIN" custom ;;
            PROVIDER) choose_listed_option PROVIDER openrouter openshell provider list --names ;;
            PROVIDER:new) choose_option PROVIDER openrouter custom ;;
            PORT) choose_option PORT '' custom ;;
            *) printf 'Unknown Make option "%s".\n' "$option" >&2; return 2 ;;
        esac
    done
}

print_options() {
    local target=$1 option
    shift
    printf '  %-14s' "$target"
    (( $# > 0 )) || printf ' (no options)'
    for option; do
        printf ' %s' "${option%%[:@]*}"
        case $option in
            *@!*) printf ' (unless HARNESS=%s)' "${option#*@!}" ;;
            *@*) printf ' (when HARNESS=%s)' "${option#*@}" ;;
        esac
    done
    printf '\n'
}
