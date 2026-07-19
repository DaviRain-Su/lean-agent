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
| Agent loop | `LeanAgent.Agent.Loop` | partial | Major offline paths exist (tools, queues, hooks, terminate, prepareNextTurn, shouldStopAfterTurn). Offline tests cover `transformContext` before LLM, custom `convertToLlm`, and parallel tool end-order vs source-order (`testAgentLoopParallelEndOrderSourceOrder`). Remaining: full Pi agent-loop matrix edge cases; concurrent waitForIdle Exclusion-adjacent. |
| Stateful Agent | `LeanAgent.Agent.Agent` | partial | prompt/images/queues/subscribe/failure path improved (`IO.Ref` lifecycle). Concurrent waitForIdle / full agent.test matrix open. |
| Session JSONL v1 | `LeanAgent.Session` | partial | CLI v1 append-only works; not full Pi session tree model. |
| Harness session tree | `Agent.Harness.Storage`, `Agent.Harness.Session` | partial | SessionTree + InMemory + JsonlSessionRepo + entry types model/thinking/compaction in `buildContext` (`testHarnessSessionContextEntryTypes`). Remaining: append-only journal without full rewrite; active_tools_change/session_info. |
| Compaction / branch | `Agent.Harness.Compaction` | partial | Offline prepare/compact/summary helpers; not full Pi compaction entry integration. |
| System prompt / skills | `Agent.Harness.SystemPrompt`, `Skills` | partial | Skills XML + Project map; not full harness skill runtime. |
| Templates / truncate | `Agent.Harness.Templates`, `Truncate` | partial | Templates basic; Truncate has Pi `truncateHead`/`truncateTail`/`truncateLine`/`sanitizeBinaryOutput` offline (`testHarnessTruncate`). |
| AgentHarness façade | `Agent.Harness.AgentHarness` | partial | prompt/steer/followUp/nextTurn + appendMessage/compact/setModel/setThinkingLevel (`testAgentHarnessAppendCompactSetters`); still << Pi agent-harness.ts (~1k LOC). |
| Proxy | `LeanAgent.Agent.Proxy` | partial | Offline SSE reconstruction of Pi proxy events (`processProxyEvent`, toolcall partial JSON, usage/done/error), URL builder, progressive HTTP `streamProxyHttp` with line-oriented mid-transfer parse + abort preflight (`testAgentProxyProgressiveHttpLocal`). Concurrent async consumers during transfer still open. |
| Node env / durable harness | — | deferred | Exclusion: Node multi-process env not applicable; durable features that are portable must still be ported under harness rows as partial/missing. |

## Source Inventory

| Group | Pi files | Lean target | Current status |
| --- | ---: | --- | --- |
| Core runtime | `src/agent.ts`, `src/agent-loop.ts`, `src/types.ts` | `LeanAgent.Agent.*` | partial |
| Entry barrel | `src/index.ts` | `LeanAgent.Agent` + Harness import | partial |
| Harness | `src/harness/**` | `LeanAgent.Agent.Harness.*` | partial |
| Proxy | `src/proxy.ts` | `LeanAgent.Agent.Proxy` | partial |
| Tests | `test/agent*.ts`, `test/harness/*` | `Tests.lean` agent/harness section | partial |

## Core Runtime (file inventory)

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `types.ts` | `Agent.Types` | partial | Core contracts present (ToolExecutionMode, QueueMode, AgentMessage with custom helpers isCustomType/isBashExecution/isBranchSummary/isCompactionSummary added); not full Pi types surface (TypeBox-level, full custom-message matrix). |
| `agent-loop.ts` | `Agent.Loop` | partial | Major paths + offline tests including transformContext/custom convertToLlm + parallel end-order matrix (`testAgentLoopParallelEndOrderSourceOrder`). |
| `agent.ts` | `Agent.Agent` | partial | prompt/images/queues/subscribe/failure + waitForIdle settle; concurrent waitForIdle Exclusion-adjacent; full agent.test matrix open. |
| `index.ts` | `LeanAgent.Agent` | partial | Barrel re-exports Agent/Loop/Types/Harness/Proxy. |

## Harness (file inventory)

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `harness/agent-harness.ts` | `Harness.AgentHarness` | partial | prompt/steer/followUp/nextTurn/appendMessage/compact/setModel/setThinkingLevel; steer added; still thin vs ~1k LOC Pi harness. |
| `harness/types.ts` | `Harness.*` types in Storage/Session/Compaction | partial | Subset of harness types; not full SessionStorage/Repo interfaces. |
| `harness/messages.ts` | `Harness.Compaction` + custom message helpers | partial | Compaction/branch summary message helpers; full custom message matrix open. |
| `harness/prompt-templates.ts` | `Harness.Templates` | partial | Basic placeholders offline. |
| `harness/skills.ts` | `Harness.Skills` | partial | Skills XML + Project map; not full skill runtime. |
| `harness/system-prompt.ts` | `Harness.SystemPrompt` | partial | Formatting helpers offline. |
| `harness/session/uuid.ts` | `Harness.Uuid` | implemented | uuidv7 + shape tests (`testHarnessUuidv7`). |
| `harness/session/memory-storage.ts` | `Harness.Storage.InMemorySessionStorage` | partial | Leaf/labels/appendMessage + modelChange/thinkingLevelChange/compaction appenders. |
| `harness/session/memory-repo.ts` | `Harness.Storage.InMemorySessionRepo` | partial | create/openSession/list/delete/fork (`testInMemorySessionRepoCreateOpenListFork`). |
| `harness/session/repo-utils.ts` | `Harness.Storage` helpers | partial | createSessionId/timestamp, getMessagePathToRoot, fork helpers offline. |
| `harness/session/session.ts` | `Harness.Session` | partial | Session façade + buildContext with model/thinking/compaction entries (`testHarnessSessionContextEntryTypes`). active_tools_change / full Pi entry matrix open. |
| `harness/session/jsonl-storage.ts` | `Harness.Storage` writeTreeJsonl/readTreeJsonl + v3 writeJsonlSessionFile | partial | Message-tree JSONL + durable v3 header (cwd/timestamp); leaf/label entry types still thin. |
| `harness/session/jsonl-repo.ts` | `Harness.Storage.JsonlSessionRepo` | partial | Durable create/open/list/delete/fork + append rewrite (`testJsonlSessionRepoDurable`). Not full Pi FileSystem injection / streaming append journal. |
| `harness/compaction/compaction.ts` | `Harness.Compaction` | partial | Offline prepare/compact helpers. |
| `harness/compaction/branch-summarization.ts` | `Harness.Compaction` | partial | Offline branch summary helpers. |
| `harness/compaction/utils.ts` | `Harness.Compaction` | partial | Shared compaction helpers offline. |
| `harness/utils/truncate.ts` | `Harness.Truncate` | implemented | truncateHead/Tail/Line, formatSize, utf8ByteLength, TruncationResult (`testHarnessTruncate`). |
| `harness/utils/shell-output.ts` | `Harness.Truncate` | partial | sanitizeBinaryOutput + truncateTailChars + shell head/tail lines offline; executeShellWithCapture not fully ported (needs ExecutionEnv). |
| `proxy.ts` | `Agent.Proxy` | partial | Offline SSE reconstruction + progressive HTTP line parse; concurrent live consumers Exclusion-adjacent. |
| `node.ts` | — | deferred | Node barrel re-export of NodeExecutionEnv; Exclusion Node-only. |
| `harness/env/nodejs.ts` | — | deferred | Node multi-process env Exclusion. |

## Test Mapping

| Pi tests | Lean | Status |
| --- | --- | --- |
| agent-loop tool/steering/hooks/terminate | `testAgentLoop*` | implemented |
| agent-loop parallel end-order / source-order | `testAgentLoopParallelEndOrderSourceOrder` | implemented |
| agent-loop force sequential tool mode | `testAgentLoopForceSequentialToolMode` | implemented |
| agent-loop transformContext / custom convertToLlm | `testAgentLoopTransformContextBeforeLlm`, `testAgentLoopCustomConvertToLlm` | implemented |
| agent-harness append/compact/setters | `testAgentHarnessAppendCompactSetters` | implemented |
| agent prompt/sessionId/busy/subscribe/images/failure | `testAgent*` | implemented |
| harness uuid/session/storage | `testHarness*` | implemented |
| harness InMemorySessionStorage leaf/labels | `testInMemorySessionStorageLeafAndLabels` | implemented |
| harness InMemorySessionRepo create/list/fork | `testInMemorySessionRepoCreateOpenListFork` | implemented |
| harness Session façade buildContext | `testHarnessSessionFacadeBuildContext` | implemented |
| harness Session entry types context | `testHarnessSessionContextEntryTypes` | implemented |
| harness truncate head/tail/sanitize | `testHarnessTruncate` | implemented |
| harness JsonlSessionRepo durable | `testJsonlSessionRepoDurable` | implemented |
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
