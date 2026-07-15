# Goal: Full LeanAgent parity with Pi `packages/agent`

Use this document as a **long-running Goal** for an implementer agent.  
Pair with the system/agent instructions in [`AGENT_FULL_PARITY_PROMPT.md`](AGENT_FULL_PARITY_PROMPT.md).

---

## Goal kind

`code-change` — multi-phase, multi-session, until Agent ledger is closed.

## One-line objective

Implement LeanAgent’s full **Pi `packages/agent`** equivalent (core loop + stateful Agent + harness session/compaction/skills/system-prompt + optional proxy) with offline tests and an accurate `docs/AGENT_PARITY.md`, without breaking existing CLI/session/AI layers.

## Why this goal exists

Core agent loop/API already has a solid offline slice. Remaining work is large (harness, session tree, compaction, façade). A single short goal cannot finish it; this goal is the **standing charter** for sequential autonomous slices until definition-of-done holds.

## Source of truth

| Artifact | Path |
| --- | --- |
| Pi reference (read-only) | `vendor/pi/packages/agent` |
| Parity ledger | `docs/AGENT_PARITY.md` |
| Architecture | `docs/ARCHITECTURE.md` |
| Implementer prompt | `docs/goals/AGENT_FULL_PARITY_PROMPT.md` |
| Lean targets | `LeanAgent/Agent/**`, `LeanAgent/Session.lean`, `Tests.lean` |

Initialize submodule if empty: `git submodule update --init vendor/pi`.

## Global acceptance criteria (goal complete only when all hold)

1. **Core runtime closed**: `types` / `agent-loop` / `agent` rows in `AGENT_PARITY.md` are `implemented` or explicitly `deferred` with reason; offline ports of Pi `agent.test.ts` + `agent-loop.test.ts` cover all non-network behaviors that matter for coding-agent.
2. **Harness landed**: session storage/repo (memory + jsonl), compaction + branch summary (mock LLM), system-prompt + skills integration story, agent-harness façade — each with offline tests mapped from Pi harness tests **or** deferred with reason.
3. **Proxy**: implemented with tests **or** deferred with reason citing no CLI/RPC consumer yet.
4. **Quality bar**: `lake build` + `lake test` exit 0; success line `lean-agent tests passed`.
5. **Ledger honesty**: no `implemented` without tests driving shipped APIs; no claim of TUI/orchestrator.
6. **Compatibility**: existing JSONL sessions and DeepSeek/OpenAI CLI path still work (`lean-agent --help`; session resume smoke if session format changes).
7. **Docs**: `AGENT_PARITY.md` current; `ARCHITECTURE.md` lists Agent Harness module boundaries.

## Non-goals (entire goal)

- Full AI transport live streaming / mid-request abort (belongs to `AI_PARITY`)
- TUI package, Orchestrator/RPC process supervision
- OMP advanced tools (LSP/DAP/task agents) beyond what Pi agent harness already needs
- Live multi-provider e2e matrix
- Rewriting coding-agent CLI UX for its own sake

## Phase checklist (harness mines first unchecked box)

Work **in order**. Mark `- [x]` only after code + tests + ledger for that phase item are done and `lake test` is green.

### Phase 0 — Bootstrap

- [ ] Confirm `vendor/pi` checked out; record pin in ledger notes if missing
- [ ] Snapshot current `AGENT_PARITY.md` open rows into a short “remaining work” section if helpful
- [ ] Ensure `lake test` is green on baseline before large edits

### Phase A — Finish core Agent / Loop / Types

- [ ] Image-capable prompt path + tests
- [ ] waitForIdle / run settlement semantics (or documented Lean equivalent) + tests
- [ ] Remaining offline `agent.test.ts` cases (failure lifecycle, listener await order if applicable, tool update settle)
- [ ] Remaining offline `agent-loop.test.ts` cases (beforeToolCall args, parallel event order, sequential force, afterToolCall terminate)
- [ ] convertToLlm / transformContext edge parity needed by above tests
- [ ] Core ledger rows updated; `lake test` green

### Phase B — Session harness

- [ ] UUID helper + tests
- [ ] Memory storage/repo + tests
- [ ] JSONL storage/repo (tree-capable) + tests
- [ ] Integrate with or evolve `LeanAgent.Session` without breaking v1 resume
- [ ] Ledger harness/session rows updated; `lake test` green

### Phase C — Compaction & branch summary

- [ ] Compaction core (cut points, prepare, estimate hooks) + offline tests
- [ ] Branch summarization + offline tests (mock streamFn for summaries)
- [ ] Ledger rows updated; `lake test` green

### Phase D — Skills, system prompt, templates, utils

- [ ] System prompt builder + tests
- [ ] Prompt templates + tests
- [ ] Skills harness coordinated with `LeanAgent.Project` + tests
- [ ] truncate/shell-output as required by harness + tests
- [ ] Ledger rows updated; `lake test` green

### Phase E — AgentHarness façade

- [ ] Harness API (prompt/steer/followUp/nextTurn, queue events, abort policy) + tests
- [ ] Optional Main/Session wiring behind stable API (no behavior regression)
- [ ] Ledger rows updated; `lake test` green

### Phase F — Proxy (optional)

- [ ] Implement proxy **or** mark deferred with reason
- [ ] If implemented: tests + ledger; `lake test` green

### Phase G — Close-out

- [ ] Full ledger audit: every Pi `src/**` file has a row with terminal status
- [ ] ARCHITECTURE + README links accurate
- [ ] `lake test` green; CLI help smoke; capture logs to scratch if Goal harness provides `{SCRATCH}`
- [ ] Write short “Agent complete vs Pi” summary in `docs/AGENT_PARITY.md` (Current Coverage table all terminal)

## Per-slice mini acceptance (every autonomous turn)

Each turn that claims progress must:

1. Advance ≥1 checklist item meaningfully.
2. Add/adjust tests that call shipped code.
3. Update `docs/AGENT_PARITY.md`.
4. Leave `lake test` green.
5. If deviating from Pi, append one bullet under the goal’s **Deviations** section (what + why only).

## Verification plan (final + each major phase)

1. **gating**: `lake test` → exit 0, stdout contains `lean-agent tests passed`. Capture `{SCRATCH}/lake-test.log` when scratch is available.
2. **gating**: New tests for the phase exist in `Tests.lean` (or split modules) and name-map to Pi tests in comments or ledger Test Mapping table.
3. **gating**: `docs/AGENT_PARITY.md` rows for that phase show `implemented` or `deferred` with reason.
4. **gating**: No edits under `vendor/pi`.
5. **evidence**: `lake exe lean-agent --help` exit 0 → `{SCRATCH}/cli-smoke.log` when CLI/session touched.
6. **evidence (Phase B+)**: Offline session round-trip test loads/saves JSONL without live network.
7. **final**: Checklist Phase 0–G all `[x]` (or F deferred with reason); global acceptance criteria 1–7 hold.

## Implementation approach

- Vertical slices; green tree always.
- Mock `StreamFn` + real tools for offline parity.
- Immutable Agent value + `IO.Ref` during runs is fine if semantics match Pi.
- Prefer new files under `LeanAgent/Agent/Harness/` for harness; keep `Loop`/`Agent` focused.
- Reuse `LeanAgent.AI.Util.Estimate`, `AI.Types`, `AI.EventStream`, existing Session JSON helpers.
- Coordinate skills with `LeanAgent.Project` — document ownership in ARCHITECTURE when wiring.

## Assumed scope (files)

**Primary write:**

- `LeanAgent/Agent/Types.lean`
- `LeanAgent/Agent/Loop.lean`
- `LeanAgent/Agent/Agent.lean`
- `LeanAgent/Agent.lean`
- `LeanAgent/Session.lean`
- `LeanAgent/Agent/Harness/**` (created as needed)
- `Tests.lean` (agent sections)
- `docs/AGENT_PARITY.md`, `docs/ARCHITECTURE.md` (as needed)
- `Main.lean` only for thin wiring

**Read-only:**

- `vendor/pi/packages/agent/**`
- `docs/AI_PARITY.md` (for dependency gates)
- `docs/goals/AGENT_FULL_PARITY_PROMPT.md`

## Risks / contradictions

| Risk | Mitigation |
| --- | --- |
| Goal too large for one classifier pass | Completeness = checklist + ledger; intermediate slices are valid if green |
| Live streaming missing in AI | Do not block harness; mark live-abort rows partial/deferred |
| Session format vs Pi tree model | Keep v1 loaders; add tree features with version field or parentId |
| Tests.lean size | Section banners first; split only if lake supports multi-root tests cleanly |
| Skills duplication (Project vs Harness) | Single discovery path; harness consumes Project or shared helper |

## Deviations

_(Implementers append one bullet per intentional Pi divergence: what changed + why.)_

## How to launch (operator)

### A. Single long Goal message (recommended)

Paste into Goal mode:

```text
Execute docs/goals/AGENT_FULL_PARITY_GOAL.md until Global acceptance criteria hold.
Follow docs/goals/AGENT_FULL_PARITY_PROMPT.md as system instructions.
Work Phase 0 → G in order. Each turn: one checklist slice, tests on shipped APIs,
update docs/AGENT_PARITY.md, lake test green. vendor/pi is read-only.
Capture lake test to {SCRATCH}/lake-test.log when available.
Do not stop while an unblocked checklist item remains.
```

### B. Phase-scoped Goals (safer for verifiers)

Run one Goal per phase, e.g.:

```text
Execute only Phase A of docs/goals/AGENT_FULL_PARITY_GOAL.md.
Use docs/goals/AGENT_FULL_PARITY_PROMPT.md. Acceptance: Phase A checklist all [x],
lake test green, AGENT_PARITY core rows updated.
```

Repeat for B, C, D, E, F, G.

### C. Continuous “keep going” Goal

```text
Standing goal: advance AGENT_FULL_PARITY_GOAL.md from the first unchecked checklist
item until Phase G. Never skip phases. Always leave lake test green. Prefer finishing
the current phase before starting the next.
```

## Success snapshot (for humans)

When complete you should be able to say:

- Lean has a Pi-aligned **Agent core** and **Harness** usable by coding-agent / future TUI.
- Offline tests lock tool loop, queues, hooks, session, compaction, harness façade.
- `docs/AGENT_PARITY.md` is the audit trail of what matches Pi and what was deferred.
