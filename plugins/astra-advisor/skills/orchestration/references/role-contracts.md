# Role contracts

The primary owns requirements, scope, interfaces, and acceptance. The implementation
worker owns its assigned edits and checks. One auxiliary is the normal maximum;
`full` uses implementation followed by review, not a second implementation team.

## Implementation

Spawn the installed native custom agent:

```text
agent_type: astra_advisor_sol_implementer
fork_turns: none
```

It pins `gpt-5.6-sol` / `high`. Supply the following information concisely; section
headings are optional, the contract is not:

- Goal and observable completion condition.
- Owned files or modules, with boundaries that avoid concurrent edits.
- Interfaces and existing behavior to preserve.
- Constraints, settled design decisions, and user authorization boundaries.
- Relevant checks and evidence needed for acceptance.

Tell the worker it is not alone in the codebase and must preserve others' edits.
Ask it to report changed files, checks with actual results, decisions, and gaps.
Let it inspect necessary implementation details without forcing the parent to read
all of them first. If scope changes, update the existing worker when still relevant.
Use the native follow-up operation rather than spawning a new worker for each fix.

## Independent review

For `audit` or `full`, spawn a new context:

```text
agent_type: astra_advisor_sol_reviewer
fork_turns: none
```

It pins `gpt-5.6-sol` / `high` and requests a read-only sandbox. Supply the goal,
exact change set or base/head revisions, important interfaces and constraints, and
test evidence. Ask for one of:

- `ship`: no required correction found in the reviewed change.
- `fix-first`: concrete bounded corrections, with file references and evidence.
- `rethink`: a material design or scope problem requires a parent decision.

The reviewer inspects actual files and never fixes its findings. When fixes are
needed, use the existing implementer (or the parent for `audit`), then have the
changed code reviewed. Review is independent context, not proof against correlated
model errors. See [operations.md](operations.md) when sandbox enforcement is uncertain.

## Parent acceptance

Inspect the complete change set for scope and interfaces. Inspect actual verification
results, rerunning affected checks only when the evidence or remaining risk requires
it. Accept only the observed outcome and state unverified parts. Do not turn a worker's
completion message into proof of an unobserved deployment or external operation.
