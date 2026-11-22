# Base images. Distro packages follow the repositories for their base image.
UBUNTU_IMAGE := docker.io/library/ubuntu:24.04
FEDORA_IMAGE := registry.fedoraproject.org/fedora:43

# Android SDK. Google identifies the command-line tools 19.0 archive by build ID.
ANDROID_JDK_MAJOR := 21
ANDROID_JAVA_HOME := /usr/lib/jvm/java-$(ANDROID_JDK_MAJOR)-openjdk-amd64
ANDROID_API_LEVEL := 36
ANDROID_BUILD_TOOLS_VERSION := 36.0.0
ANDROID_COMMAND_LINE_TOOLS_BUILD := 13114758
ANDROID_COMMAND_LINE_TOOLS_URL := https://dl.google.com/android/repository/commandlinetools-linux-$(ANDROID_COMMAND_LINE_TOOLS_BUILD)_latest.zip
ANDROID_COMMAND_LINE_TOOLS_SHA256 := 7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee

# Harness downloads for Linux x86-64. Update each release and checksum together.
CODEX_VERSION := 0.167.1
CODEX_URL := https://github.com/openai/codex/releases/download/rust-v$(CODEX_VERSION)/codex-package-x86_64-unknown-linux-musl.tar.gz
CODEX_SHA256 := a945df3df83e849dd7b74787e27f8a459c1946b0e3afe3dc8eef8a8d1845fd4f

CLAUDE_VERSION := 2.1.323
CLAUDE_URL := https://downloads.claude.ai/claude-code-releases/$(CLAUDE_VERSION)/linux-x64/claude.zst
CLAUDE_SHA256 := d5f85ac4e9b7ca95e6bbeeeaf05af7c20ff62ddd2a0f49b1f4a0699c30ab0686

ANTIGRAVITY_VERSION := 1.5.13-5999302598852608
ANTIGRAVITY_URL := https://storage.googleapis.com/antigravity-public/antigravity-cli/$(ANTIGRAVITY_VERSION)/linux-x64/cli_linux_x64.tar.gz
ANTIGRAVITY_SHA512 := 014b37387703acab1f47cd532c8bb60167a6a3537b0f9891de03f1b1ffa9614307bc83c4b2f7551273b0877d722716b0cd9e26782f6b2a50705db4f05e18c68f

OPENCODE_VERSION := 2.3.2
OPENCODE_URL := https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/-/cli-linux-x64-baseline-$(OPENCODE_VERSION).tgz
OPENCODE_SHA512 := 73c7f53e2989d1db4a705d6c17b23e052b3248e1fa1f39842ea11f0d376ecea046d8ecc11fa835b0fc02fd1e4b8537fa91f1bb15e2c7e5416bf594d395c45d13
OPENCODE_MODEL := openrouter/moonshotai/kimi-k3

# Source release for the imported profile. OpenShell itself is installed on the host.
OPENROUTER_PROFILE_VERSION := v0.1.9
OPENROUTER_PROFILE := https://raw.githubusercontent.com/ai-openshell/openshell/$(OPENROUTER_PROFILE_VERSION)/providers/openrouter.yaml
