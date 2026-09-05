---
name: orchestration
description: Coordinate coding with an Astra parent and selective Sol implementation or review.
---

# Astra Advisor

Keep requirements, architectural decisions, and final acceptance with the primary
GPT-6 Astra agent. Use one Sol worker when substantial bounded implementation can
replace work the parent would otherwise do. Small edits, tightly coupled reasoning,
and consultation usually stay with Astra.

## Choose the work that benefits from delegation

Use the context already available. Do enough targeted inspection to settle ownership
and interfaces; do not finish the implementation before deciding to delegate it.
Briefly state the chosen mode and reason when it affects how the task proceeds.
There is no mandatory declaration before every tool call.

| Mode | Use | Responsibility |
|---|---|---|
| `solo` | Small, tightly coupled, or faster to finish in the existing context | Astra implements and verifies |
| `delegate` | Substantial implementation with a clear boundary | One Sol worker implements and tests; Astra accepts |
| `audit` | An independent check is requested or a concrete risk warrants one | Astra implements; fresh Sol reviews |
| `full` | Both delegation and independent review add material value | Sol implements, Astra checks, then fresh Sol reviews |

Choose based on remaining work and handoff cost, not file count alone. Reassess when
scope or evidence changes and explain a material route change. Do not add a reviewer
merely because work was delegated.

## Delegate without repeating the work

Before the first delegation, read [role-contracts.md](references/role-contracts.md).
Use the namespaced custom roles and check the selected role's actual model and effort
from available tool metadata. Read [operations.md](references/operations.md) only for
installation, missing metadata, runtime inspection, or sandbox questions.

- Send the goal, owned files/modules, interfaces, constraints, and acceptance checks.
  Include the necessary references and settled decisions, not the entire conversation.
- Use `astra_advisor_sol_implementer` with a fresh context (`fork_turns: none`).
  The role pins Sol / high; omit per-spawn overrides.
- While the worker runs, do independent useful work. Do not edit its owned files or
  investigate the same code paths just to duplicate its work.
- Continue related fixes with the same worker. Update its instructions when decisions
  change. Start a new worker for a materially different scope, an unavailable worker,
  or demonstrated context confusion. A fresh reviewer remains a separate role.
- Inspect the actual diff and the worker's test evidence. Rerun checks when evidence
  is missing, stale, failed, or leaves a material risk; do not rerun every successful
  check solely because another agent ran it.
- Resolve design questions in the parent and send concrete corrections back. A worker
  failure is evidence to reassess scope or approach, not an automatic retry ladder.

## Keep the boundary clear

The primary model is GPT-6 Astra; high reasoning is a starting preference, not a
mandatory gate. Do not change the user's model or reasoning setting. If the primary
is observably another model, explain that this workflow requires an Astra parent.
If the primary cannot be observed, state that it is unverified and use available
context; do not ask the user to confirm metadata the tools can inspect.

If a selected custom role is unavailable or its model/effort conflicts with its pin,
report the missing capability. Continue independent work; do not silently substitute
another model or claim a delegated result. Installation is a separate setup action.
Delegation does not authorize publishing, deployment, spending, or broader changes.
Follow the user's and repository's existing approval boundaries.

For `audit` or `full`, use a fresh `astra_advisor_sol_reviewer` after inspecting the
diff and evidence. The reviewer does not implement fixes. A subsequent code change
invalidates its verdict for that code; review the affected change before acceptance.

## Account for cache and total work

Prompt caching reduces repeated input processing, not new reasoning or output.
Do not assume an Astra cache transfers to Sol or that a fresh worker has zero cached
input. Stable prefixes and continuing the same worker may improve reuse; neither
is a guarantee. Sending fewer task tokens can help, but workers also receive platform
instructions and tools. Do not claim savings from prompt length or model price alone.

Compare parent plus worker plus reviewer usage, including cached input and retries,
when runtime counters exist. Keep unknown usage unknown. Use the optional usage
inspection described in [operations.md](references/operations.md) when measuring;
ordinary delivery does not require a telemetry report.
