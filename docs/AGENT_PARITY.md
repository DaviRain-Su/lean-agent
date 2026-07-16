# Agent Parity Ledger

This file tracks LeanAgent parity with Pi `packages/agent`. It is the source of
truth for preventing agent-runtime omissions.

Reference root: `vendor/pi/packages/agent`

Pinned submodule: `54113731b2e70ceb61ea1948fdfe83395ff2fd90` (`vendor/pi`).

AI-layer dependencies are tracked in [`AI_PARITY.md`](AI_PARITY.md). Agent work
consumes `LeanAgent.AI.*` types and stream boundaries rather than legacy
`LeanAgent.Core` / `LeanAgent.Loop`.

## Status Legend

| Status | Meaning |
| --- | --- |
| `implemented` | Lean has equivalent behavior and tests. |
| `partial` | Lean has a subset, or behavior diverges in known ways. |
| `missing` | No Lean equivalent exists yet. |
| `deferred` | Intentionally not implemented in the current milestone, with a reason. |

## Honest summary (not “complete”)

Agent domain is **IN PROGRESS** under the full-project port charter
[`goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md).

- **Core loop / Agent API:** strong **partial** — many offline behaviors and tests exist; not every Pi `agent.test.ts` / `agent-loop.test.ts` case is ported; live-stream abort still open (AI transport).
- **Harness:** **partial / thin** — Storage/Compaction/AgentHarness are real code but far smaller than Pi harness (session tree, compaction, agent-harness.ts). Do **not** treat as full Pi harness parity.
- **Proxy / Node durable harness:** `missing` (or Exclusion deferred only for true Node-only bits) — not “product done.”

Earlier Goal runs that marked this package effectively complete were **wrong**. Prefer `partial` until offline Pi test matrices and harness file inventory close.

## Current Lean Coverage

| Pi area | Lean modules | Status | Notes |
| --- | --- | --- | --- |
| Agent types | `LeanAgent.Agent.Types` | partial | Core shapes exist; TypeBox-level typing and full custom-message matrix incomplete. |
| Agent loop | `LeanAgent.Agent.Loop` | partial | Major offline paths exist (tools, queues, hooks, terminate). Remaining Pi loop tests and live abort open. |
| Stateful Agent | `LeanAgent.Agent.Agent` | partial | prompt/images/queues/subscribe/failure path improved (`IO.Ref` lifecycle). Concurrent waitForIdle / full agent.test matrix open. |
| Session JSONL v1 | `LeanAgent.Session` | partial | CLI v1 append-only works; not full Pi session tree model. |
| Harness session tree | `Agent.Harness.Storage` | partial | Memory + jsonl parentId sketch; not full Pi jsonl-repo/session APIs. |
| Compaction / branch | `Agent.Harness.Compaction` | partial | Offline prepare/compact/summary helpers; not full Pi compaction entry integration. |
| System prompt / skills | `Agent.Harness.SystemPrompt`, `Skills` | partial | Skills XML + Project map; not full harness skill runtime. |
| Templates / truncate | `Agent.Harness.Templates`, `Truncate` | partial | Basic expand/truncate. |
| AgentHarness façade | `Agent.Harness.AgentHarness` | partial | Thin prompt/steer/followUp/nextTurn; << Pi agent-harness.ts. |
| Proxy | — | missing | Implement when coding-agent/orchestrator RPC needs it. |
| Node env / durable harness | — | deferred | Exclusion: Node multi-process env not applicable; durable features that are portable must still be ported under harness rows as partial/missing. |

## Source Inventory

| Group | Pi files | Lean target | Current status |
| --- | ---: | --- | --- |
| Core runtime | `src/agent.ts`, `src/agent-loop.ts`, `src/types.ts` | `LeanAgent.Agent.*` | partial |
| Entry barrel | `src/index.ts` | `LeanAgent.Agent` + Harness import | partial |
| Harness | `src/harness/**` | `LeanAgent.Agent.Harness.*` | partial |
| Proxy | `src/proxy.ts` | — | missing |
| Tests | `test/agent*.ts`, `test/harness/*` | `Tests.lean` agent/harness section | partial |

## Core Runtime

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `types.ts` | `Agent.Types` | partial | Core contracts present; not full Pi types surface. |
| `agent-loop.ts` | `Agent.Loop` | partial | Major paths + some tests; full Pi agent-loop.test.ts matrix open. |
| `agent.ts` prompt images | `promptWithImages` | partial | Works offline; part of larger agent.ts surface. |
| `agent.ts` waitForIdle | `waitForIdle` / `isIdle` | partial | Post-return settle only; not full async barrier semantics. |
| `agent.ts` failure lifecycle | `handleRunFailure` | partial | Transcript retention fixed; full agent.test matrix open. |
| Queues / continue | Agent | partial | Core paths tested; more Pi cases remain. |
| Nested busy | `throwIfBusy` | partial | Covered offline; concurrent streaming open. |

## Harness

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `session/uuid.ts` | `Harness.Uuid` | partial | Basic uuidv7 helper; not a claim of full session stack. |
| memory/jsonl storage | `Harness.Storage` | partial | Thin tree sketch vs Pi repos/storage/session. |
| compaction | `Harness.Compaction` | partial | Offline helpers only. |
| branch-summarization | `Harness.Compaction` | partial | Offline summary only. |
| system-prompt / skills | `SystemPrompt`, `Skills` | partial | Formatting + Project map; not full runtime. |
| prompt-templates | `Templates` | partial | Basic placeholders. |
| truncate / shell-output | `Truncate` | partial | Basic helpers. |
| agent-harness.ts | `AgentHarness` | partial | Thin façade vs ~1k LOC Pi harness. |
| proxy.ts | — | deferred | No consumer yet |
| env/nodejs.ts | — | deferred | Node-only |

## Test Mapping

| Pi tests | Lean | Status |
| --- | --- | --- |
| agent-loop tool/steering/hooks/terminate | `testAgentLoop*` | implemented |
| agent prompt/sessionId/busy/subscribe/images/failure | `testAgent*` | implemented |
| harness uuid/session/storage | `testHarness*` | implemented |
| harness compaction/branch | `testHarnessCompaction*`, `testHarnessBranchSummary` | implemented |
| agent-harness queues | `testAgentHarnessPromptAndQueues` | implemented |
| v1 session compat | `testSessionV1StillLoadsWithHarnessPresent` | implemented |

## Long-running full port docs

- [`docs/goals/AGENT_FULL_PARITY_PROMPT.md`](goals/AGENT_FULL_PARITY_PROMPT.md)
- [`docs/goals/AGENT_FULL_PARITY_GOAL.md`](goals/AGENT_FULL_PARITY_GOAL.md)

## Rules for Updating This Ledger

- Every Agent change that moves status must update this file in the same commit.
- A row becomes `implemented` only with tests or an explicit reason why runtime validation is impossible.
- `vendor/pi` is read-only.
- Prefer behavior parity over line-by-line TypeScript translation.
