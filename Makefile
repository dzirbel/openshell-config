ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
HARNESS ?= codex
TOOLCHAIN ?= $(if $(filter codex,$(HARNESS)),android,plain)
SANDBOX ?= $(HARNESS)-dev
WORKDIR ?= /sandbox/project
IMAGE ?= localhost/openshell-$(HARNESS):$(TOOLCHAIN)
PROVIDER ?= openrouter
PORT ?= 49374
OPENROUTER_PROFILE := https://raw.githubusercontent.com/ai-openshell/openshell/v0.1.9/providers/openrouter.yaml

ifneq ($(words $(HARNESS)),1)
$(error Select one HARNESS)
endif
ifeq ($(filter codex claude antigravity opencode,$(HARNESS)),)
$(error Unknown HARNESS "$(HARNESS)". Choose codex, claude, antigravity, or opencode)
endif
ifneq ($(words $(TOOLCHAIN)),1)
$(error Select one TOOLCHAIN)
endif
ifeq ($(filter plain android plasma,$(TOOLCHAIN)),)
$(error Unknown TOOLCHAIN "$(TOOLCHAIN)". Choose plain, android, or plasma)
endif

STATE := $(ROOT)/.openshell
POLICY := $(STATE)/policy/$(HARNESS)-$(TOOLCHAIN).yaml
POLICY_INPUTS := $(ROOT)/policies/base.yaml \
    $(wildcard $(ROOT)/policies/harness/$(HARNESS).yaml $(ROOT)/policies/toolchain/$(TOOLCHAIN).yaml)
SSH_CONFIG := $(STATE)/ssh/$(SANDBOX).conf
CREATE_FLAGS := --label "harness=$(HARNESS)" --label "toolchain=$(TOOLCHAIN)"
ifeq ($(TOOLCHAIN),android)
# Include explicit values for runtimes that do not inherit all image env.
CREATE_FLAGS += --env JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    --env ANDROID_HOME=/opt/android-sdk --env ANDROID_USER_HOME=/sandbox/.android
endif
CREATE_PROVIDER = $(if $(and $(filter opencode,$(HARNESS)),$(strip $(PROVIDER))),--provider "$(PROVIDER)")

.DEFAULT_GOAL := help
.PHONY: help build create recreate restore list shell tui login status ssh-config \
    policy policy-check policy-apply provider-init attach detach serve forward
help:
	@echo 'make build create HARNESS=codex|claude|antigravity|opencode TOOLCHAIN=plain|android|plasma SANDBOX=NAME'
	@echo 'make list, shell, tui, login, status, ssh-config'
	@echo 'make recreate or restore with the same sandbox and selected harness/toolchain'
	@echo 'make policy, policy-check, policy-apply'
	@echo 'OpenCode: make provider-init once, then attach/detach, serve, and forward as needed'

build:
	podman build --skip-unused-stages=true --file "$(ROOT)/images/Containerfile" \
		--build-arg "HARNESS=$(HARNESS)" --build-arg "TOOLCHAIN=$(TOOLCHAIN)" \
		--tag "$(IMAGE)" "$(ROOT)/images"

$(POLICY): $(POLICY_INPUTS) $(ROOT)/Makefile
	@set -eu; mkdir -p "$(@D)"; \
	temporary=$$(mktemp "$@.XXXXXX"); \
	trap 'rm -f -- "$$temporary"' EXIT; \
	cat $(foreach file,$(POLICY_INPUTS),"$(file)") >"$$temporary"; \
	mv -fT -- "$$temporary" "$@"

policy: $(POLICY)
	@cat "$(POLICY)"

policy-check: $(POLICY)
	openshell-prover check --boundary "$(POLICY)" "$(POLICY)"

create: $(POLICY)
	"$(ROOT)/scripts/ssh-config.sh" check "$(SANDBOX)"
	openshell sandbox create --name "$(SANDBOX)" --from "$(IMAGE)" --policy "$(POLICY)" \
		--approval-mode manual --no-auto-providers $(CREATE_FLAGS) $(CREATE_PROVIDER) --detach -- /bin/sleep infinity
	"$(ROOT)/scripts/ssh-config.sh" publish "$(SANDBOX)" "$(SSH_CONFIG)"

recreate restore: $(POLICY)
	"$(ROOT)/scripts/recreate.sh" "$@" "$(SANDBOX)" "$(IMAGE)" "$(POLICY)" "$(SSH_CONFIG)" \
		"$(HARNESS)" "$(TOOLCHAIN)" $(CREATE_FLAGS)

list:
	openshell sandbox list

ssh-config:
	"$(ROOT)/scripts/ssh-config.sh" publish "$(SANDBOX)" "$(SSH_CONFIG)"

policy-apply: $(POLICY)
	openshell policy set "$(SANDBOX)" --policy "$(POLICY)"

shell:
	openshell sandbox exec "$(SANDBOX)" --tty --workdir "$(WORKDIR)" -- /bin/bash

ifeq ($(HARNESS),codex)
login:
	openshell sandbox exec "$(SANDBOX)" --tty -- codex login --device-auth
status:
	openshell sandbox exec "$(SANDBOX)" -- codex login status
tui:
	openshell sandbox exec "$(SANDBOX)" --tty --workdir "$(WORKDIR)" -- codex --no-daemon
else ifeq ($(HARNESS),claude)
login:
	openshell sandbox exec "$(SANDBOX)" --tty -- claude auth login --claudeai
status:
	openshell sandbox exec "$(SANDBOX)" -- claude auth status
tui:
	openshell sandbox exec "$(SANDBOX)" --tty --workdir "$(WORKDIR)" -- claude
else ifeq ($(HARNESS),antigravity)
# Google's login selects its copy/paste flow in an SSH session.
login tui:
	"$(ROOT)/scripts/ssh-config.sh" agy "$(SANDBOX)" "$(SSH_CONFIG)" "$(WORKDIR)"
status:
	openshell sandbox get "$(SANDBOX)"
else
login:
	@echo 'OpenCode uses the attached OpenRouter provider. See make provider-init and make attach.'
status:
	openshell sandbox provider list "$(SANDBOX)"
tui:
	openshell sandbox exec "$(SANDBOX)" --tty --workdir "$(WORKDIR)" -- opencode --standalone
endif

provider-init:
	@set -eu; : "$${OPENROUTER_API_KEY:?Set OPENROUTER_API_KEY on the host}"; \
	openshell profile import --url "$(OPENROUTER_PROFILE)"; \
	openshell provider create --name "$(PROVIDER)" --type openrouter --from-existing

attach detach:
	openshell sandbox provider "$@" "$(SANDBOX)" "$(PROVIDER)" --wait

# Start the server in one terminal and the loopback-only forward in a second.
serve:
	openshell sandbox exec "$(SANDBOX)" --no-tty --workdir "$(WORKDIR)" -- \
		opencode serve --hostname 127.0.0.1 --port "$(PORT)"

forward:
	openshell forward start "127.0.0.1:$(PORT)" "$(SANDBOX)"
