# Astra Advisor

Keep GPT-6 Astra on requirements, design decisions, and final acceptance. Delegate
substantial bounded implementation to one GPT-5.6 Sol worker, and keep related fixes
with that worker. Small or tightly coupled changes stay in the existing Astra context.

Astra Advisor is a Codex plugin forked from [DannyMac180/sol-advisor](https://github.com/DannyMac180/sol-advisor), based on upstream commit `37b75cad535abdd46531f0227483a8842d045ab8` (v0.6.0). It keeps the native-agent approach and installer protections while adapting routing for an Astra parent. The original MIT license and attribution are preserved.

## Install

You need a current Codex client with plugin and native custom-agent support, access
to GPT-6 Astra and GPT-5.6 Sol, POSIX shell utilities, and jq. The verification
suite additionally requires Python 3.11 or later.

```sh
codex plugin marketplace add tatsuhitofuruta/astra-advisor --ref main
codex plugin add astra-advisor@astra-advisor
```

Resolve the installed plugin directory and install its companion roles:

```sh
codex plugin list --json
```

Find `astra-advisor@astra-advisor` and use its `source.path` as `<plugin-directory>`:

```sh
sh "<plugin-directory>/scripts/install-agents.sh"
sh "<plugin-directory>/scripts/install-agents.sh" --check
```

The installer adds only `astra-advisor-sol-implementer.toml` and
`astra-advisor-sol-reviewer.toml`. It preserves existing Sol Advisor profiles and
Codex defaults, and refuses to overwrite a conflicting or symlinked destination.
Start a new Astra task after installing the roles, then ask:

```text
Use $astra-advisor:orchestration to implement this feature and verify the result.
```

## How work is divided

| Mode | When it helps | Delivery |
|---|---|---|
| `solo` | Small changes or work tightly coupled to existing context | Astra implements and verifies |
| `delegate` | Substantial implementation with settled boundaries | One Sol / high worker implements and tests; Astra accepts |
| `audit` | Requested or justified independent review | Astra implements; fresh Sol / high reviews |
| `full` | Both implementation delegation and review add value | Sol implements, Astra checks, then fresh Sol reviews |

The parent chooses based on remaining work, context, and handoff cost. No fixed file
count, mandatory pre-tool ceremony, or automatic review ladder is required. The
parent checks the actual diff and evidence; it reruns tests when there is a reason,
not solely because a worker ran them. User and repository approval boundaries apply
to both parent and worker.

## Cache and cost

A cached Astra continuation may cost less in input processing than introducing the
same context to a Sol worker without a matching cache. Sol can also reuse its own
cache. The workflow therefore keeps small work local and reuses a worker for related
fixes. It does not assume caches transfer between models or guarantee a saving.

For meaningful comparisons, measure parent plus worker plus reviewer usage, including
cached input, new output, and retries. The runtime inspector can report observed token
counters without exposing conversation text. See [operations](plugins/astra-advisor/skills/orchestration/references/operations.md)
for usage inspection, installation updates, and sandbox interpretation.

## Development

```sh
sh plugins/astra-advisor/scripts/verify.sh
git diff --check
```

Run installer checks against disposable directories. Plugin installation and model
routing are separate: a valid manifest or installed profile does not prove which
model ran. This fork does not replace the original Sol Advisor installation.
