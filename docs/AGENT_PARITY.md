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

## Agent complete vs Pi (summary)

Core **Agent / Loop / Types** offline contracts used by coding-agent are
**implemented** with tests on shipped APIs. A **Harness** layer covers session
tree storage (memory + jsonl v2), compaction/branch summary (offline mock
summary text), system-prompt skills formatting coordinated with Project OMP
skills, prompt templates, truncate utils, and an AgentHarness façade.

Still **deferred** (not product-blocking for CLI coding-agent today):

- Full Pi durable harness / extension hooks / observability stack
- `proxy.ts` (no RPC/orchestrator consumer yet)
- Live mid-stream abort / true concurrent waitForIdle races (buffered transport + sequential Lean runs)
- Exhaustive port of every Pi harness e2e/network test

## Current Lean Coverage

| Pi area | Lean modules | Status | Notes |
| --- | --- | --- | --- |
| Agent types | `LeanAgent.Agent.Types` | implemented | AgentMessage, tools, events, hooks, queues, listeners. TypeBox-only typing deferred. |
| Agent loop | `LeanAgent.Agent.Loop` | implemented | Tools, steering after batches, idle follow-up, prepareNextTurn, shouldStopAfterTurn, all-must-terminate, sequential force, tool-result message events, afterToolCall terminate. Live stream abort deferred (AI transport). |
| Stateful Agent | `LeanAgent.Agent.Agent` | implemented | prompt / promptWithImages / promptMessages / continue / queues / subscribe+unsubscribe / busy reject / sessionId / waitForIdle (post-return settle) / failure lifecycle events. `runWithLifecycle` shares `IO.Ref Agent` so streamFn throws keep already-committed user messages (`testAgentFailureLifecycleEvents`). |
| Session JSONL v1 | `LeanAgent.Session` | implemented | Append-only v1 CLI sessions; still load/resume with harness present. |
| Harness session tree | `Agent.Harness.Storage` | implemented | Memory repo + jsonl v2 with parentId; branch walk. |
| Compaction / branch | `Agent.Harness.Compaction` | implemented | prepare/compact/shouldCompact + branch summary offline. |
| System prompt / skills | `Agent.Harness.SystemPrompt`, `Skills` | implemented | Pi skills XML block; Project skill mapping. |
| Templates / truncate | `Agent.Harness.Templates`, `Truncate` | implemented | `$ARGUMENTS` / `$n` expand; shell truncate. |
| AgentHarness façade | `Agent.Harness.AgentHarness` | implemented | prompt/steer/followUp/nextTurn/abort/queue updates. |
| Proxy | — | deferred | No CLI/RPC consumer; add when orchestrator lands. |
| Node env / full durable harness | — | deferred | Node-specific env and durable multi-process harness not applicable to Lean binary. |

## Source Inventory

| Group | Pi files | Lean target | Current status |
| --- | ---: | --- | --- |
| Core runtime | `src/agent.ts`, `src/agent-loop.ts`, `src/types.ts` | `LeanAgent.Agent.*` | implemented |
| Entry barrel | `src/index.ts` | `LeanAgent.Agent` + Harness import | implemented |
| Harness | `src/harness/**` | `LeanAgent.Agent.Harness.*` | implemented (subset) |
| Proxy | `src/proxy.ts` | — | deferred |
| Tests | `test/agent*.ts`, `test/harness/*` | `Tests.lean` agent/harness section | implemented (offline subset) |

## Core Runtime

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `types.ts` | `Agent.Types` | implemented | Offline contracts covered. |
| `agent-loop.ts` | `Agent.Loop` | implemented | See tests `testAgentLoop*`. |
| `agent.ts` prompt images | `promptWithImages` | implemented | `testAgentPromptWithImages` |
| `agent.ts` waitForIdle | `waitForIdle` / `isIdle` | implemented | Settles after prompt returns; busy throws (`testAgentWaitForIdle`). Concurrent barrier wait deferred (no async interleaving). |
| `agent.ts` failure lifecycle | `handleRunFailure` | implemented | `testAgentFailureLifecycleEvents` |
| Queues / continue | Agent | implemented | Existing continue/steer tests. |
| Nested busy | `throwIfBusy` | implemented | |

## Harness

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `session/uuid.ts` | `Harness.Uuid` | implemented | `testHarnessUuidv7` |
| memory/jsonl storage | `Harness.Storage` | implemented | `testHarnessMemoryRepoBranch`, `testHarnessJsonlTreeRoundTrip` |
| compaction | `Harness.Compaction` | implemented | Offline summary injection |
| branch-summarization | `Harness.Compaction` | implemented | `testHarnessBranchSummary` |
| system-prompt / skills | `SystemPrompt`, `Skills` | implemented | Coordinated with `LeanAgent.Project` |
| prompt-templates | `Templates` | implemented | |
| truncate / shell-output | `Truncate` | implemented | |
| agent-harness.ts | `AgentHarness` | implemented | `testAgentHarnessPromptAndQueues` |
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
