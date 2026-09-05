# Installation and runtime evidence

## Install the native roles

From a checkout, install the two namespaced profiles:

```sh
sh plugins/astra-advisor/scripts/install-agents.sh
sh plugins/astra-advisor/scripts/install-agents.sh --check
```

The default target is the existing `CODEX_HOME/agents`, or `~/.codex/agents` when
CODEX_HOME is unset. Use `--target-dir PATH` for a disposable or alternate target.
The installer preserves other plugins' profiles and refuses differing, symlinked,
or nonregular destination files. It does not modify config.toml. Start a new task
after installation so the custom roles become available.

If a profile has been intentionally customized, compare it with the shipped file
and decide how to preserve it; the installer does not overwrite it. For an update,
move the old owned profile to a backup outside the discovery directory, then run
the installer again. Do not move unknown files or overwrite user modifications.

For an unavailable role or uncertain installation, check only the needed profile:

```sh
sh plugins/astra-advisor/scripts/install-agents.sh --check-role implementer
sh plugins/astra-advisor/scripts/install-agents.sh --check-role reviewer
```

For an installed skill at `<plugin>/skills/orchestration`, the installer and runtime
inspector are under `../../scripts`. Do not run installation automatically merely
because a task selects delegation.

## Observe the selected role

Prefer the model and effort exposed in native tool metadata. If a needed field is
missing, inspect the exact local rollout using its native thread UUID:

```sh
sh plugins/astra-advisor/scripts/inspect-agent-runtime.sh CHILD_THREAD_UUID
sh plugins/astra-advisor/scripts/inspect-agent-runtime.sh --primary PRIMARY_THREAD_UUID
```

The primary should be `gpt-6-astra`. Its reasoning effort may be user-selected.
Both auxiliary roles should be `gpt-5.6-sol` / `high`. Never silently substitute
another model or treat an installed template as proof of which model actually ran.

The inspector emits only allowlisted routing fields. `--sessions-dir PATH` selects
a fixture or alternate session tree. It rejects ambiguous filenames, missing required
metadata, and conflicting identity, source, or working-directory metadata. It reports
model and effort from the latest turn, so a deliberate model change earlier in the
task does not invalidate current metadata. An inspection failure means the metadata
is unavailable or inconsistent; it does not by itself prove a wrong model.

## Optional usage inspection

```sh
sh plugins/astra-advisor/scripts/inspect-agent-runtime.sh --primary --usage PRIMARY_THREAD_UUID
sh plugins/astra-advisor/scripts/inspect-agent-runtime.sh --usage CHILD_THREAD_UUID
```

Usage comes from the latest available cumulative `token_count` record. Missing counters
are null, not zero. Input totals include repeated context across requests and are not
the current context-window size. Cached input is a subset of input; reasoning output,
when reported, is a subset of output and must not be added again. For successive
snapshots, use differences rather than summing cumulative counters. If a task changes
models, its cumulative usage can span those models; do not price the entire total
using only the latest model.

Compare the parent and all workers/reviewers over the same task boundary. A new worker
may begin with inherited token counters when history is forked; use its starting
baseline rather than adding an inherited total twice. These profiles use fresh context.
The inspector reports tokens, not a bill or account limit. API billing, Codex credits,
cache writes, and subscription allowances must be interpreted using the relevant
[current pricing](https://learn.chatgpt.com/docs/pricing).

For cache reuse, see the [official prompt-caching guide](https://developers.openai.com/api/docs/guides/prompt-caching).
The total result depends on matching prefixes, runtime routing and retention,
new output, task success, and rework. No fixed savings percentage is promised.

## Reviewer sandbox

The reviewer requests read-only access, but the host may impose a broader policy.
Use observed sandbox and permission metadata. If hard isolation is required and
unavailable, stop the review lane. Otherwise, explicitly instruct no writes and
compare the relevant repository state before and after review. Report broader or
unverified enforcement honestly; a prompt is not an enforced filesystem boundary.

## Maintainer checks

```sh
sh plugins/astra-advisor/scripts/verify.sh
git diff --check
```

Use disposable targets and synthetic rollouts for script tests. A passing fixture suite
establishes the script behavior covered by those tests, not model quality, real cache
hits, or end-to-end routing in every Codex host.
