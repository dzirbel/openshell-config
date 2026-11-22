ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(ROOT)/versions.mk

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
# GNU Make only gives one running recipe access to terminal input.
.NOTPARALLEL:

STATE := $(ROOT)/.openshell
IMAGE_BUILD_ARGS := UBUNTU_IMAGE FEDORA_IMAGE \
    ANDROID_JDK_MAJOR ANDROID_JAVA_HOME ANDROID_API_LEVEL ANDROID_BUILD_TOOLS_VERSION \
    ANDROID_COMMAND_LINE_TOOLS_URL ANDROID_COMMAND_LINE_TOOLS_SHA256 \
    CODEX_URL CODEX_SHA256 CLAUDE_URL CLAUDE_SHA256 ANTIGRAVITY_URL ANTIGRAVITY_SHA512 \
    OPENCODE_URL OPENCODE_SHA512 OPENCODE_MODEL

# A suffix like :new chooses the prompt source. @harness and @!harness
# make an option conditional on the harness selected earlier in the list.
# Make exports command-line assignments and inherited environment variables.
define options
source "$(ROOT)/scripts/make-options.sh"
resolve_options $($@.options)
endef

define prepare_policy
policy="$(STATE)/policy/$$HARNESS-$$TOOLCHAIN.yaml"
(
    mkdir -p -- "$(STATE)/policy"
    temporary=$$(mktemp "$$policy.XXXXXX")
    trap 'rm -f -- "$$temporary"' EXIT
    inputs=("$(ROOT)/policies/base.yaml")
    for fragment in "$(ROOT)/policies/harness/$$HARNESS.yaml" "$(ROOT)/policies/toolchain/$$TOOLCHAIN.yaml"; do
        [[ ! -f $$fragment ]] || inputs+=("$$fragment")
    done
    sed 's|__ANDROID_JAVA_HOME__|$(ANDROID_JAVA_HOME)|g' "$${inputs[@]}" >"$$temporary"
    if ! cmp -s -- "$$temporary" "$$policy"; then
        mv -fT -- "$$temporary" "$$policy"
    fi
)
endef

define create_flags
create_flags=(--label "harness=$$HARNESS" --label "toolchain=$$TOOLCHAIN")
if [[ $$TOOLCHAIN == android ]]; then
    # Include explicit values for runtimes that do not inherit all image env.
    create_flags+=(--env "JAVA_HOME=$(ANDROID_JAVA_HOME)" \
        --env ANDROID_HOME=/opt/android-sdk --env ANDROID_USER_HOME=/sandbox/.android)
fi
endef

define print_group
echo
echo '$(1)'
$(foreach command,$(2), \
    print_options $(command) $($(command).options); \
    $(if $($(command).help),printf '    %s\n' '$($(command).help)';))
endef

.DEFAULT_GOAL := help
help:
	@source "$(ROOT)/scripts/make-options.sh"
	echo 'Usage: make TARGET [OPTION=value ...]'
	echo
	print_options help
	$(call print_group,One-time setup,$(setup_commands))
	$(call print_group,Sandbox management,$(sandbox_commands))
	$(call print_group,Policy management,$(policy_commands))
	$(call print_group,Authentication,$(auth_commands))
	$(call print_group,Development,$(development_commands))
	echo
	echo 'HARNESS, WORKDIR, and PORT are required when not using an interactive terminal.'

# One-time setup
setup_commands := provider-init

provider-init.options := PROVIDER:new
provider-init.help := Uses OPENROUTER_API_KEY from the environment or prompts for it without echo in a terminal.
provider-init:
	@api_key=$${OPENROUTER_API_KEY:-}
	if [[ -z $$api_key && -t 0 ]]; then
	    IFS= read -rs -p 'OpenRouter API key: ' api_key || api_key=
	    printf '\n' >&2
	fi
	if [[ -z $$api_key ]]; then
	    echo 'OpenRouter API key is required. Set OPENROUTER_API_KEY or enter it at the terminal prompt.' >&2
	    exit 2
	fi
	$(options)
	openshell profile import --url "$(OPENROUTER_PROFILE)"
	OPENROUTER_API_KEY="$$api_key" openshell provider create --name "$$PROVIDER" --type openrouter --from-existing

# Sandbox management
sandbox_commands := build create ssh-config recreate restore list

build.options := HARNESS TOOLCHAIN IMAGE
build:
	@$(options)
	podman build --skip-unused-stages=true --file "$(ROOT)/images/Containerfile" \
		--build-arg "HARNESS=$$HARNESS" --build-arg "TOOLCHAIN=$$TOOLCHAIN" \
		$(foreach arg,$(IMAGE_BUILD_ARGS),--build-arg "$(arg)=$($(arg))") \
		--tag "$$IMAGE" "$(ROOT)/images"

create.options := HARNESS TOOLCHAIN SANDBOX:new IMAGE PROVIDER@opencode
create:
	@$(options)
	$(create_flags)
	if [[ $$HARNESS == opencode && -n $$PROVIDER ]]; then
	    create_flags+=(--provider "$$PROVIDER")
	fi
	$(prepare_policy)
	"$(ROOT)/scripts/ssh-config.sh" check "$$SANDBOX"
	openshell sandbox create --name "$$SANDBOX" --from "$$IMAGE" --policy "$$policy" \
		--approval-mode manual --no-auto-providers "$${create_flags[@]}" --detach -- /bin/sleep infinity
	"$(ROOT)/scripts/ssh-config.sh" publish "$$SANDBOX" "$(STATE)/ssh/$$SANDBOX.conf"

ssh-config.options := SANDBOX
ssh-config:
	@$(options)
	"$(ROOT)/scripts/ssh-config.sh" publish "$$SANDBOX" "$(STATE)/ssh/$$SANDBOX.conf"

recreate.options := HARNESS TOOLCHAIN SANDBOX IMAGE
restore.options := HARNESS TOOLCHAIN SANDBOX:pending IMAGE
recreate restore:
	@$(options)
	$(prepare_policy)
	$(create_flags)
	"$(ROOT)/scripts/recreate.sh" "$@" "$$SANDBOX" "$$IMAGE" "$$policy" \
		"$(STATE)/ssh/$$SANDBOX.conf" "$$HARNESS" "$$TOOLCHAIN" "$${create_flags[@]}"

list:
	openshell sandbox list

# Policy management
policy_commands := policy policy-check policy-apply

policy.options := HARNESS TOOLCHAIN
policy-check.options := $(policy.options)
policy policy-check:
	@$(options)
	$(prepare_policy)
	if [[ $@ == policy ]]; then
	    cat "$$policy"
	else
	    openshell-prover check --boundary "$$policy" "$$policy"
	fi

policy-apply.options := HARNESS TOOLCHAIN SANDBOX
policy-apply:
	@$(options)
	$(prepare_policy)
	openshell policy set "$$SANDBOX" --policy "$$policy"

# Authentication
auth_commands := login status attach detach

login.options := HARNESS SANDBOX@!opencode WORKDIR@antigravity
login:
	@$(options)
	case $$HARNESS in
	    codex) openshell sandbox exec "$$SANDBOX" --tty -- codex login --device-auth ;;
	    claude) openshell sandbox exec "$$SANDBOX" --tty -- claude auth login --claudeai ;;
	    antigravity)
	        # Google's login selects its copy/paste flow in an SSH session.
	        "$(ROOT)/scripts/ssh-config.sh" agy "$$SANDBOX" "$(STATE)/ssh/$$SANDBOX.conf" "$$WORKDIR"
	        ;;
	    opencode) echo 'OpenCode uses the attached OpenRouter provider. See make provider-init and make attach.' ;;
	esac

status.options := HARNESS SANDBOX
status:
	@$(options)
	case $$HARNESS in
	    codex) openshell sandbox exec "$$SANDBOX" -- codex login status ;;
	    claude) openshell sandbox exec "$$SANDBOX" -- claude auth status ;;
	    antigravity) openshell sandbox get "$$SANDBOX" ;;
	    opencode) openshell sandbox provider list "$$SANDBOX" ;;
	esac

attach.options := SANDBOX PROVIDER
detach.options := $(attach.options)
attach detach:
	@$(options)
	openshell sandbox provider "$@" "$$SANDBOX" "$$PROVIDER" --wait

# Development
development_commands := shell tui serve forward

shell.options := SANDBOX WORKDIR
shell:
	@$(options)
	openshell sandbox exec "$$SANDBOX" --tty --workdir "$$WORKDIR" -- /bin/bash

tui.options := HARNESS SANDBOX WORKDIR
tui:
	@$(options)
	case $$HARNESS in
	    codex) command=(codex --no-daemon) ;;
	    claude) command=(claude) ;;
	    opencode) command=(opencode --standalone) ;;
	    antigravity)
	        exec "$(ROOT)/scripts/ssh-config.sh" agy "$$SANDBOX" "$(STATE)/ssh/$$SANDBOX.conf" "$$WORKDIR"
	        ;;
	esac
	openshell sandbox exec "$$SANDBOX" --tty --workdir "$$WORKDIR" -- "$${command[@]}"

serve.options := SANDBOX WORKDIR PORT
# Start the server in one terminal and the loopback-only forward in a second.
serve:
	@$(options)
	openshell sandbox exec "$$SANDBOX" --no-tty --workdir "$$WORKDIR" -- \
		opencode serve --hostname 127.0.0.1 --port "$$PORT"

forward.options := SANDBOX PORT
forward:
	@$(options)
	openshell forward start "127.0.0.1:$$PORT" "$$SANDBOX"

.PHONY: help $(setup_commands) $(sandbox_commands) $(policy_commands) \
    $(auth_commands) $(development_commands)
