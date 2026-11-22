# Repository guidance

[docs/fleet-draft.md](docs/fleet-draft.md) describes the fleet workflow. Run `make` for the target list.
Sandbox targets expect an x86-64 Linux OpenShell gateway using the VM driver
and the same user's local Podman image store.

- Use README.md as the source of truth on desired behavior. Never edit it; when
  making functionality changes, suggest updates for the user to write.
- [images/Containerfile](images/Containerfile) builds toolchain and harness
  stages independently. Keep upstream releases and checksums in sync. Build
  downloads run on the host, outside the guest network policy. Keep auth files
  and backups out of Git and the image.
- [policies/](policies/) contains the shared policy and selected fragments.
  Inspect the live base policy before replacing it. Keep grants narrow and use
  disposable VMs for lifecycle tests. Run Bash syntax checks, ShellCheck, Make
  dry runs, and `make policy-check` for local validation.
- [scripts/recreate.sh](scripts/recreate.sh) takes a verified private backup
  before replacing a VM. Use `make restore` to resume an interrupted migration.
  Preserve the dedicated upload and checksum checks for large archives.
- [scripts/fetch-sandbox.sh](scripts/fetch-sandbox.sh) implements the host
  `git fetch-sandbox` alias. Fetch only committed proposals with shared history
  into separate worktrees.
