# Run from this directory, or use make -C codex <target> from the repository root.
SANDBOX ?= codex-dev
IMAGE := localhost/openshell-codex:0.167.1
SANDBOX_ENV := --env ANDROID_HOME=/opt/android-sdk --env ANDROID_USER_HOME=/sandbox/.android

.DEFAULT_GOAL := help
.PHONY: help build create recreate restore login status tui shell ssh-config policy-apply

help:
	@echo 'First use: make build; make create; make login; make status; make tui'
	@echo 'Update image: make build; make recreate (preserves /sandbox)'
	@echo 'Also: make restore, make shell, make ssh-config, make policy-apply'

build:
	podman build --tag $(IMAGE) --file Containerfile .

create:
	openshell sandbox create --name $(SANDBOX) --from $(IMAGE) \
		--policy "$(CURDIR)/policy.yaml" --approval-mode manual \
		$(SANDBOX_ENV) --no-auto-providers --detach -- /bin/sleep infinity
	$(MAKE) --no-print-directory ssh-config

recreate:
	./recreate.sh recreate "$(SANDBOX)" "$(IMAGE)" "$(CURDIR)/policy.yaml" "$(CURDIR)/ssh_config" $(SANDBOX_ENV)

# Retry an interrupted migration using its last verified /sandbox backup.
restore:
	./recreate.sh restore "$(SANDBOX)" "$(IMAGE)" "$(CURDIR)/policy.yaml" "$(CURDIR)/ssh_config" $(SANDBOX_ENV)

login:
	openshell sandbox exec $(SANDBOX) --tty -- codex login --device-auth

status:
	openshell sandbox exec $(SANDBOX) -- codex login status

tui:
	openshell sandbox exec $(SANDBOX) --tty --workdir /sandbox/project -- codex --no-daemon

shell:
	openshell sandbox exec $(SANDBOX) --tty --workdir /sandbox/project -- /bin/bash

# Creation calls this automatically. Publish only after generation succeeds.
ssh-config:
	@set -eu; umask 077; \
	config="$(CURDIR)/ssh_config"; \
	temporary=$$(mktemp "$$config.XXXXXX"); \
	trap 'rm -f -- "$$temporary"' EXIT; \
	trap 'exit 129' HUP; \
	trap 'exit 130' INT; \
	trap 'exit 143' TERM; \
	openshell sandbox ssh-config "$(SANDBOX)" > "$$temporary"; \
	mv -fT -- "$$temporary" "$$config"

# Applies network edits to this sandbox; filesystem edits require recreation.
policy-apply:
	openshell policy set $(SANDBOX) --policy "$(CURDIR)/policy.yaml"
