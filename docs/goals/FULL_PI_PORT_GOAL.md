# Goal: Full Pi monorepo → LeanAgent port (entire project)

**Standing charter for long-running autonomous work.**  
Pair with implementer instructions: [`FULL_PI_PORT_PROMPT.md`](FULL_PI_PORT_PROMPT.md).

This supersedes earlier “agent-only full parity” goals that allowed early completion via thin harnesses and broad `deferred` use. Those docs remain historical; **this** is the rewrite charter.

---

## Goal kind

`code-change` — multi-package, multi-session, **until Global Definition of Done**.

## One-line objective

Port **all in-scope Pi packages** (`ai`, `agent`, `coding-agent`, `tui`, `orchestrator`) from TypeScript under `vendor/pi` into LeanAgent with **behavioral parity**, offline tests on shipped APIs, and honest ledgers — and **keep going until the port is actually finished**.

## Why this exists

LeanAgent is a rewrite of Pi in Lean 4, not a demo. Partial goals that accept skeletons + `deferred` complete in hours while tens of thousands of lines of Pi remain unported. This Goal forbids that.

## Source of truth

| Artifact | Path |
| --- | --- |
| Implementer prompt | `docs/goals/FULL_PI_PORT_PROMPT.md` |
| Pi reference (read-only) | `vendor/pi/packages/*` |
| Ledgers | `docs/AI_PARITY.md`, `docs/AGENT_PARITY.md`, (+ create coding-agent/tui/orchestrator ledgers) |
| Code | `LeanAgent/**`, `Main.lean`, `Tests.lean`, `native/` |

## Global acceptance criteria (Goal complete **only** when all hold)

Copied from the prompt’s Definition of Done — **all** required:

1. **Full inventory:** Every Pi `src/**/*.ts` under `packages/{ai,agent,coding-agent,tui,orchestrator}` has a ledger row: `implemented` **or** Exclusion-List `deferred` with reason. No silent omissions.
2. **AI package:** No in-scope `missing`; offline tests cover non-network Pi AI matrix to the level required by the AI ledger’s own completion rules; remaining `partial` only for Exclusion List.
3. **Agent package:** Honest `AGENT_PARITY.md`; core + harness behaviors real (not toy parentId-only / 100-line façade pretending to be agent-harness); offline agent/agent-loop/harness tests ported where applicable.
4. **Coding-agent package:** `CODING_AGENT_PARITY.md` present; CLI/tools/extensions/session UX parity for offline Pi coding-agent behaviors; Main thin.
5. **TUI package:** `TUI_PARITY.md` present; implemented against agent events **unless** PRD has an explicit human Non-goal freezing TUI (default: implement).
6. **Orchestrator package:** `ORCHESTRATOR_PARITY.md` present; implemented **unless** PRD human Non-goal.
7. **Quality:** `lake build` && `lake test` exit 0; output contains `lean-agent tests passed`.
8. **Honesty:** No `implemented` without shipped-API tests; README/ARCHITECTURE match reality; `vendor/pi` untouched by feature work.
9. **Evidence:** `{SCRATCH}/lake-test.log` (when Goal harness provides scratch) from a green full suite run after the final slice.

**If any criterion fails, the Goal is not complete.**  
Partial package demos must leave the Goal **open**.

## Hard rules (violations = incomplete)

- Do **not** use `deferred` except Exclusion List in `FULL_PI_PORT_PROMPT.md` §7.
- Do **not** mark a package complete because a skeleton compiles.
- Do **not** edit `vendor/pi`.
- Do **not** claim completion after only Agent or only AI work.
- Dependency order: **ai → agent → coding-agent → tui → orchestrator** (distribution continuous).
- Each turn: **one vertical slice** + offline tests + ledger + green `lake test`, then continue.

## Non-goals (human product freezes only)

Only if **humans** write them into `docs/PRD.md` as permanent freezes:

- Shipping a production TUI on a given date
- Shipping orchestrator multi-host clustering beyond Pi’s package
- OMP advanced tools not present in Pi

Agents must not invent Non-goals to finish early.

## Exclusion List (summary)

Bun/Node-only APIs, browser-only OAuth automation, live paid provider matrices, exact V8 stacks, full AJV universe, true multi-threaded waitForIdle under buffered HTTP — see prompt §7.  
Everything else stays in scope as `missing`/`partial` until implemented.

## Work protocol

1. Read `FULL_PI_PORT_PROMPT.md`.
2. Green `lake test` / fix.
3. Init `vendor/pi` if needed.
4. Re-audit ledgers; **downgrade false `implemented` → `partial`**.
5. Loop: lowest unfinished domain → one Pi file/cluster → implement → test → ledger → green → next.
6. Create package ledgers when entering coding-agent / tui / orchestrator depth.
7. Call Goal complete **only** when Global acceptance criteria 1–9 all hold with evidence.

## Verification plan (final — and re-check before any complete claim)

1. **gating:** `lake test` → exit 0, `lean-agent tests passed` → `{SCRATCH}/lake-test.log`.
2. **gating:** Inventory audit script or manual: count Pi `src` files vs ledger rows for all five packages; zero unscoped files.
3. **gating:** `AI_PARITY.md` / `AGENT_PARITY.md` / other package ledgers: no inflated `implemented`; Exclusion `deferred` only.
4. **gating:** Spot-check that “implemented” rows cite tests that call shipped APIs (open Tests.lean / modules).
5. **gating:** `git status vendor/pi` clean of feature edits; submodule pin noted.
6. **gating:** CLI `lean-agent --help` exit 0 → `{SCRATCH}/cli-smoke.log` if CLI surface changed this cycle.
7. **gating:** ARCHITECTURE module map lists all domains that claim code exists.
8. **fail complete if:** any package still mostly `partial`/`missing` without Exclusion, or harness/agent/AI rows claim implemented without Pi test mapping.

## Progress tracking (not completion)

Use package ledgers as the dashboard. Optional: add `docs/PORT_STATUS.md` with counts:

```text
ai:        implemented X / partial Y / missing Z / deferred W
agent:     ...
coding-agent: ...
tui:       ...
orchestrator: ...
```

Update counts when ledgers change. **Progress ≠ Done.**

## Launch paste

```text
Execute docs/goals/FULL_PI_PORT_GOAL.md until Global acceptance criteria 1–9 all hold.
Standing instructions: docs/goals/FULL_PI_PORT_PROMPT.md — full Pi→Lean rewrite/port.
Order: ai → agent → coding-agent → tui → orchestrator.
Each turn one vertical slice + offline shipped-API tests + ledger + lake test green.
No early complete on skeletons or broad deferred. vendor/pi read-only.
Capture lake test to {SCRATCH}/lake-test.log. Downgrade false implemented rows when found.
Do not stop while unblocked in-scope work remains.
```

## Deviations

_(Append one bullet per intentional divergence from Pi behavior: what + why. Not a place to list unfinished work.)_

## Relationship to older goals

| Doc | Status |
| --- | --- |
| `AGENT_FULL_PARITY_PROMPT.md` / `GOAL.md` | **Superseded** for “project complete”; may still inspire agent-domain slices but must not declare full product done |
| `FULL_PI_PORT_*` | **Current** full-project rewrite charter |
