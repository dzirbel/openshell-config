# OpenShell configuration

My custom OpenShell configuration, scripts, and orchestration.

Currently only supports Codex, with more coming soon as I experiment with them. Only supports x86 Linux. Code is generally AI-written, but closely reviewed and documentation is always hand-written.

## Goals

- Use a wide variety of harnesses (GUI and TUI), launched and running on the main system but only interacting with OpenShell sandboxes.
- Use a wide variety of AI models (subscriptions, API, local) within each sandbox (TBD between different sandboxes per agent, per service, etc).
- Tight and explicit control over network requests made by agents.
- Isolated and minimal development environments in the sandboxes, e.g. no Gradle daemon overlaps or shared dependency caches.
- Sandboxes are easy to recreate, although this might be expensive for their build cache, etc.
- Easy and local code handoffs from agent sandboxes to the main system for review and finalization.
- Very limited access and credentials by agents, e.g. no write access to my git repositories.
- Keep configuration as minimal as possible; use out-of-the-box or community setup whenever possible.
- Possible to still use harnesses on the main system, e.g. for this repository itself or to aid in system configuration.
