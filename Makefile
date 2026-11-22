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

commands := help build create recreate restore list ssh-config policy policy-check policy-apply \
    login status provider-init attach detach shell tui serve forward

# A suffix like :new chooses the prompt source. @harness and @!harness
# make an option conditional on the harness selected earlier in the list.
build.options := HARNESS TOOLCHAIN IMAGE
create.options := HARNESS TOOLCHAIN SANDBOX:new IMAGE PROVIDER@opencode
recreate.options := HARNESS TOOLCHAIN SANDBOX IMAGE
restore.options := HARNESS TOOLCHAIN SANDBOX:pending IMAGE
ssh-config.options := SANDBOX
policy.options := HARNESS TOOLCHAIN
policy-check.options := $(policy.options)
policy-apply.options := HARNESS TOOLCHAIN SANDBOX
login.options := HARNESS SANDBOX@!opencode WORKDIR@antigravity
status.options := HARNESS SANDBOX
provider-init.options := PROVIDER:new
attach.options := SANDBOX PROVIDER
detach.options := $(attach.options)
shell.options := SANDBOX WORKDIR
tui.options := HARNESS SANDBOX WORKDIR
serve.options := SANDBOX WORKDIR PORT
forward.options := SANDBOX PORT

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

.DEFAULT_GOAL := help
.PHONY: $(commands)
help:
	@source "$(ROOT)/scripts/make-options.sh"
	echo 'Usage: make TARGET [OPTION=value ...]'
	echo
	echo 'Targets and options'
	$(foreach command,$(commands),print_options $(command) $($(command).options);)
	echo
	echo 'In a terminal, missing options prompt. Use Up/Down and Enter in pickers.'
	echo 'Without a terminal, supply HARNESS, WORKDIR, and PORT whenever the target uses them.'
	echo 'Export OPENROUTER_API_KEY before running make provider-init.'

build:
	@$(options)
	podman build --skip-unused-stages=true --file "$(ROOT)/images/Containerfile" \
		--build-arg "HARNESS=$$HARNESS" --build-arg "TOOLCHAIN=$$TOOLCHAIN" \
		$(foreach arg,$(IMAGE_BUILD_ARGS),--build-arg "$(arg)=$($(arg))") \
		--tag "$$IMAGE" "$(ROOT)/images"

policy policy-check:
	@$(options)
	$(prepare_policy)
	if [[ $@ == policy ]]; then
	    cat "$$policy"
	else
	    openshell-prover check --boundary "$$policy" "$$policy"
	fi

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

recreate restore:
	@$(options)
	$(prepare_policy)
	$(create_flags)
	"$(ROOT)/scripts/recreate.sh" "$@" "$$SANDBOX" "$$IMAGE" "$$policy" \
		"$(STATE)/ssh/$$SANDBOX.conf" "$$HARNESS" "$$TOOLCHAIN" "$${create_flags[@]}"

list:
	openshell sandbox list

ssh-config:
	@$(options)
	"$(ROOT)/scripts/ssh-config.sh" publish "$$SANDBOX" "$(STATE)/ssh/$$SANDBOX.conf"

policy-apply:
	@$(options)
	$(prepare_policy)
	openshell policy set "$$SANDBOX" --policy "$$policy"

shell:
	@$(options)
	openshell sandbox exec "$$SANDBOX" --tty --workdir "$$WORKDIR" -- /bin/bash

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

status:
	@$(options)
	case $$HARNESS in
	    codex) openshell sandbox exec "$$SANDBOX" -- codex login status ;;
	    claude) openshell sandbox exec "$$SANDBOX" -- claude auth status ;;
	    antigravity) openshell sandbox get "$$SANDBOX" ;;
	    opencode) openshell sandbox provider list "$$SANDBOX" ;;
	esac

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

provider-init:
	@: "$${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY on the host}"
	$(options)
	openshell profile import --url "$(OPENROUTER_PROFILE)"
	openshell provider create --name "$$PROVIDER" --type openrouter --from-existing

attach detach:
	@$(options)
	openshell sandbox provider "$@" "$$SANDBOX" "$$PROVIDER" --wait

# Start the server in one terminal and the loopback-only forward in a second.
serve:
	@$(options)
	openshell sandbox exec "$$SANDBOX" --no-tty --workdir "$$WORKDIR" -- \
		opencode serve --hostname 127.0.0.1 --port "$$PORT"

forward:
	@$(options)
	openshell forward start "127.0.0.1:$$PORT" "$$SANDBOX"
