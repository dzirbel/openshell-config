# OpenShell configuration

My custom OpenShell configuration, scripts, and orchestration.

Code is generally AI-written, but closely reviewed and documentation is always hand-written.

## Goals

- Use a wide variety of AI models (subscriptions, API, local) and harnesses with their processes and tools confined within the OpenShell sandboxes.
- Use a wide variety of GUI harnesses on the main system ("client"); easily SSH into any TUI harness hosted in an OpenShell sandbox.
- Tight and explicit control over network requests made by agents.
- Isolated and minimal development environments in the sandboxes, e.g. no Gradle daemon overlaps or shared dependency caches.
- Sandboxes are easy to recreate and preserve working state, although losing some build/dependency caches is acceptable.
- Easy and local code handoffs from agent sandboxes to the main system for review and finalization.
- Very limited access and credentials by agents, e.g. by default no write access to my git repositories.
- Keep configuration as minimal as possible; use out-of-the-box or community setup whenever possible.
- Possible to still use harnesses on the main system, e.g. for this repository itself or to aid in system configuration.

## Usage

#### One-time setup
- Install OpenShell, Podman, GNU Make, Git, and OpenSSH; make sure the default `openshell` gateway is set up
- Add `Include </absolute/path/to/openshell-config>/.openshell/ssh/*.conf` to the top of `~/.ssh/config`
- Run `git config --global alias.fetch-sandbox '!"'"$(pwd -P)"'/scripts/fetch-sandbox.sh"'` from this directory to create a `git fetch-sandbox` alias which pulls commits into worktrees on the client repository
- To use OpenRouter-backed harnesses like OpenCode export `OPENROUTER_API_KEY` on the client and run `make provider-init` (once per OpenShell workspace if you are using more than just the `default`). Defaults to Kimi K3.

#### Sandbox management
- `make build`: builds an OCI image with `podman` with the given `HARNESS` and `TOOLCHAIN` options
- `make create`: creates an OpenShell sandbox from the `make build` image with the given `HARNESS` and `TOOLCHAIN` options (and optional `SANDBOX` name, default `$HARNESS-dev`) and publishes its SSH configuration
- `make ssh-config`: regenerates the sandbox's SSH configuration file from `openshell` into `.openshell/ssh/<sandbox>.conf` (in this directory)
- `make recreate`: recreate the given `SANDBOX` (with `HARNESS` and `TOOLCHAIN` specifications), preserving its `/sandbox` directory; mainly used to apply new VM configuration options
    - Providers are reattached and the SSH entry is regenerated as well
    - Applies the OpenShell policy built from the repository, overriding any live approvals of the sandbox
- `make restore`: resumes an interrupted `make recreate` with the same `/sandbox` backup
- `make list`: list sandboxes; `openshell sandbox list` alias
- `openshell sandbox get NAME`: show sandbox details
- `openshell sandbox start|stop NAME`: start or stop a sandbox to free resources while preserving its filesystem and configuration
- `openshell sandbox delete NAME`: deletes a sandbox and its workspace

#### Policy management
- `make policy`: prints the generated sandbox policy for a given `HARNESS` and `TOOLCHAIN`
- `make policy-check`: validate the generated policy for a given `HARNESS` and `TOOLCHAIN` (using it as both the candidate and boundary)
- `make policy-apply`: applies the generated policy for a given `HARNESS` and `TOOLCHAIN` to the given `SANDBOX`, discarding its sandbox-specific approvals (provider-supplied rules will persist)
    - Only network changes can be reloaded, changes to `filesystem_policy` or `landlock` require `make recreate` to be applied
- `openshell policy get NAME --base`: show the live base policy, for comparison with `make policy`
- `openshell policy get NAME --full`: show the full effective policy, including provider-added rules

#### Authentication
- `make login`: authenticates the given `SANDBOX` for the given `HARNESS`:
    - Codex: starts the ChatGPT device-code flow
    - Claude: starts the Claude account sign-in flow
    - Antigravity: runs `agy` via SSH, which prompts for login if needed
    - OpenCode: prints OpenRouter setup instructions; see above
- `make status`: shows authentication state of the given `SANDBOX` for the given `HARNESS`:
    - Codex/Claude: prints live sign-in status
    - Antigravity: prints sandbox details; `agy` does not expose sign-in state
    - OpenCode: show attached OpenShell providers (does not validate the API key itself)
- `make attach|detach`: attaches/detaches a given `PROVIDER` (default `openrouter`) to the given `SANDBOX`
    - `make create` with `HARNESS=opencode` automatically attaches the `openrouter` provider

#### Development
- `make shell`: open a Bash shell into the given `SANDBOX` at the given `WORKDIR` (default `/sandbox/project`)
- `make tui`: open a TUI session in the given `SANDBOX` for the given `HARNESS` at the given `WORKDIR`
- `make serve`: start an OpenCode server at a given `PORT` (default `49374`) inside a given `SANDBOX` at a given `WORKDIR`; used with `make forward`
- `make forward`: forward the given `PORT` (default `49374`) of a given `SANDBOX`; used with `make serve`
- `git fetch-sandbox <ref>`: in a project git repository, fetches commits from `<ref>` (`HEAD`, branch, commit, etc.) into a local worktree for review
    - Defaults to `/sandbox/project/<project-dir>`; pass a different directory as `git fetch-sandbox <ref> <sandbox-project-dir>` or set it with `git config sandbox.path <sandbox-project-dir>`
    - Defaults to the SSH alias `openshell-codex-dev.default`; configure with `git config --local sandbox.host <generated-ssh-alias>`

## Support

- Sandbox harnesses: Codex, Claude, Antigravity, OpenCode
- Client interfaces:
    - TUI harnesses are accessed via `make tui`
    - Codex Desktop: plain SSH connection via Settings > Connections > SSH | \[[docs](https://learn.chatgpt.com/docs/remote-connections)\]
    - Claude Desktop: WIP, installs a guest helper over SSH/SFTP | \[[docs](https://code.claude.com/docs/en/desktop#ssh-sessions)\]
    - Antigravity App: WIP, "Connect to SSH Host"; installs a server in the sandbox and uses SSH TCP forwarding | \[[docs](https://antigravity.google/docs/ssh)\]
    - OpenCode: WIP, uses a forwarded HTTP server | \[[docs](https://opencode.ai/docs/cli/web)\]
- Toolchains:
    - `plain`: Ubuntu 24.04
    - `android`: Ubuntu 24.04 with JDK 21 and Android SDK 36
    - `plasma`: Fedora 43 with Plasma 6 and developer tools

## Architecture

- `Makefile`: main entrypoint to user commands, often delegating to `openshell`
- `images/Containerfile`: defines the OCI container image built by `podman` and used by OpenShell as the VM source; `TOOLCHAIN` and `HARNESS` arguments determine its contents
- `policies/`: OpenShell policy YAML fragments
    - `harness/` contains specifics for particular sandbox harnesses, e.g. allowing Codex access to `auth.openai.com`
    - `toolchain/` contains configurations for particular development environments, e.g. Android allowing `java` access to Maven downloads
- `scripts/`: bash scripts

## TODOs

- Extract dependency versions/URLs/etc
- Pick from a list instead of requiring `HARNESS`, `SANDBOX`, etc.
- Remove defaults unless truly safe
- Organize `Makefile`
- Easy checkout of a git repo inside a sandbox
- Simplify `git fetch-sandbox` setup and use/iterate on the handoff process
- Consider migrating images to Alpine Linux
- Consider removing Make `restore`, `list`, `policy`, `policy-check`, `attach`, `detach`
- `make check` or similar to run tests, verify dependencies are installed, etc.
- Combine/simplify `make serve` and `make forward`?
- Diff of live vs. repo policies
