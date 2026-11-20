# Repository guidance

[README.md](README.md) describes the project goals. `codex/` is the only harness
configuration and targets x86-64 Linux. Run `make -C codex` for the target list.
Sandbox targets expect a running OpenShell gateway using the VM driver and the
same user's local Podman image store.

## Image and policy

- [codex/Containerfile](codex/Containerfile) installs Codex and the Android SDK.
  Keep the Codex release, archive checksum, and Makefile image tag in sync.
  Build downloads run on the host, outside the guest network policy.
- The image's Codex launcher uses `/sandbox/.codex` for both TUI and desktop SSH
  sessions. The image seeds configuration for fresh guests, and restored
  `/sandbox` files overwrite those defaults. Keep guest auth files and migration
  archives out of Git and the image.
- [codex/policy.yaml](codex/policy.yaml) defines the OpenShell filesystem and
  network boundary. Codex uses `danger-full-access` inside that boundary. Sandbox
  creation uses manual approvals and disables automatic credential providers.
  Keep network grants narrow and check the running policy with
  `openshell policy get <sandbox>` before applying or recreating, since either can
  discard live approvals. Filesystem and process policy changes require recreation.
- [codex/Makefile](codex/Makefile) passes the same Android environment on create,
  recreate, and restore. `/opt/android-sdk` is read-only, with writable Android
  user state in `/sandbox/.android`.

## Host workflows

- The default VM is `codex-dev`. The checkout has one generated, Git-ignored
  `codex/ssh_config` even when `SANDBOX` is overridden. Desktop SSH uses that file
  through an absolute `Include` in the host's SSH config.
- [codex/recreate.sh](codex/recreate.sh) stops active sessions and replaces the VM.
  Keep the verified private backup of `/sandbox` before deletion. The backup is
  under `${XDG_STATE_HOME:-$HOME/.local/state}/openshell/recreate/<sandbox>/`.
  Use `make -C codex restore` to resume an incomplete migration with the same
  sandbox and image. Preserve the dedicated upload and checksum checks because
  large archives can exceed OpenShell's exec input buffer.
- [codex/fetch-sandbox.sh](codex/fetch-sandbox.sh) implements the host Git alias
  `git fetch-sandbox`. Its `-h` output describes the arguments and Git settings.
  Preserve the local review workflow. Fetch only committed proposals with shared
  history into separate worktrees and leave the active checkout intact.

Use Bash syntax checks, ShellCheck, and Make dry runs for local validation.
`openshell-prover check --boundary codex/policy.yaml codex/policy.yaml` checks the
saved policy locally. Use disposable VMs to test lifecycle changes.
