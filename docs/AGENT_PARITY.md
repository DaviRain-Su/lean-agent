# Agent Parity Ledger

This file tracks LeanAgent parity with Pi `packages/agent`. It is the source of
truth for preventing agent-runtime omissions.

Reference root: `vendor/pi/packages/agent`

Pinned submodule commit: see `git submodule status vendor/pi`.

AI-layer dependencies are tracked in [`AI_PARITY.md`](AI_PARITY.md). Agent work
should consume `LeanAgent.AI.*` types and stream boundaries rather than legacy
`LeanAgent.Core` / `LeanAgent.Loop`.

## Status Legend

| Status | Meaning |
| --- | --- |
| `implemented` | Lean has equivalent behavior and tests. |
| `partial` | Lean has a subset, or behavior diverges in known ways. |
| `missing` | No Lean equivalent exists yet. |
| `deferred` | Intentionally not implemented in the current milestone, with a reason. |

## Current Lean Coverage

| Pi area | Lean modules | Status | Notes |
| --- | --- | --- | --- |
| Agent types | `LeanAgent.Agent.Types` | partial | AgentMessage, tools, events, hooks, queues, loop config, listener handles exist. Custom message kinds and full TypeBox tool typing remain incomplete. |
| Agent loop | `LeanAgent.Agent.Loop` | partial | Offline tool turns, post-tool steering, idle follow-up, prepareNextTurn, shouldStopAfterTurn, all-must-terminate batch, sequential force via per-tool `executionMode`, tool-result message events. Live stream abort mid-tool and full event-ordering matrix remain incomplete. |
| Stateful Agent | `LeanAgent.Agent.Agent` | partial | create/prompt/promptMessages/promptMessage/continue/abort/reset/queues/subscribe+unsubscribe. Queue drain via `IO.Ref`. Nested busy reject. sessionId forwarded to streamFn. `waitForIdle` and image-bearing string overloads remain incomplete. |
| Session JSONL | `LeanAgent.Session` | partial | Append-only JSONL header + messages with parentId. Pi harness session repo/tree/compaction models are missing. |
| Harness | — | missing | branch summary, compaction, skills harness, system prompt helpers, memory/jsonl repos. |
| Proxy utilities | — | missing | `packages/agent/src/proxy.ts` not ported. |

## Source Inventory

| Group | Pi files | Lean target | Current status |
| --- | ---: | --- | --- |
| Core runtime | `src/agent.ts`, `src/agent-loop.ts`, `src/types.ts` | `LeanAgent.Agent.*` | partial |
| Entry barrel | `src/index.ts` | `LeanAgent.Agent` | partial |
| Harness | `src/harness/**` | future `LeanAgent.Agent.Harness.*` / Session expansion | missing |
| Proxy | `src/proxy.ts` | future | missing |
| Tests | `test/agent.test.ts`, `test/agent-loop.test.ts`, harness tests | `Tests.lean` agent section | partial |

## Core Runtime

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `types.ts` AgentMessage | `Agent.Types.AgentMessage` | partial | Wraps `AI.Message` plus `custom`. Pi string-content shortcuts and broader custom kinds incomplete. |
| `types.ts` AgentTool / results | `Agent.Types.AgentTool`, `AgentToolResult` | partial | execute + details + terminate. Streaming tool update callback surface is present; not fully exercised under parallel races. |
| `types.ts` AgentEvent | `Agent.Types.AgentEvent` | partial | start/end/turn/message/tool lifecycle events exist; tool results emit message_start/end. |
| `types.ts` AgentLoopConfig | `Agent.Types.AgentLoopConfig` | partial | Hooks and queue pollers exist. convertToLlm is per-message Option filter rather than batch Promise transform. |
| `types.ts` QueueMode / pending queues | `PendingMessageQueue` | implemented | `oneAtATime` and `all` drain modes with tests. |
| `agent-loop.ts` runAgentLoop | `Agent.Loop.runAgentLoop` | implemented | Emits agent/turn/message lifecycle and enters shared runLoop; offline tool+final turn covered. |
| `agent-loop.ts` runAgentLoopContinue | `Agent.Loop.runAgentLoopContinue` | partial | Validates last message is not assistant before continuing. |
| `agent-loop.ts` tool batch terminate | `shouldTerminateExecutedBatch` | implemented | Terminates only when **every** tool result has `terminate=true` (Pi `shouldTerminateToolBatch`); partial terminate continues. |
| `agent-loop.ts` sequential force | `shouldRunToolsSequentially` | implemented | Config sequential **or** any matching tool `executionMode=sequential`. |
| `agent-loop.ts` runLoop steering/follow-up | `Agent.Loop.runLoop` | implemented | Initial steering poll, post-turn steering re-poll after full tool batch, follow-up only when idle; `shouldStopAfterTurn` early exit skips remaining queues. Offline tests cover tool→result→next turn, steering after tools, idle follow-up. |
| `agent-loop.ts` prepareNextTurn | `Agent.Loop.runLoop` + config hook | implemented | Applied before next turn; offline test asserts second-turn system prompt. |
| `agent-loop.ts` shouldStopAfterTurn | `Agent.Loop.runLoop` + config hook | implemented | Early exit without follow-up poll / extra LLM call; offline test. |
| `agent.ts` Agent class | `Agent.Agent` | partial | Functional/immutable Agent value with `IO.Ref` during runs. |
| `agent.ts` steer / followUp | `Agent.steer`, `Agent.followUp` | implemented | Queue-only; does not enter transcript until drained. |
| `agent.ts` createLoopConfig queue drain | `Agent.createLoopConfig` | implemented | Drains write back through `IO.Ref Agent`. `skipInitialSteeringPoll` skips only the first poll. |
| `agent.ts` continue from assistant tail | `Agent.continue` | implemented | Drains steering (with skip-initial-poll) then follow-ups; errors if both empty. |
| `agent.ts` nested prompt while busy | `Agent.throwIfBusy` | implemented | Checks `activeRun` / `isStreaming`; offline busy reject tests for prompt and continue. |
| `agent.ts` waitForIdle / signal getter | — | missing | |
| `agent.ts` prompt overloads | `prompt`, `promptMessage`, `promptMessages` | partial | String, single AgentMessage, multi-message batch. Image-bearing string overload still missing. |
| `agent.ts` listener unsubscribe | `subscribe` / `unsubscribe` + `ListenerHandle` | implemented | Stable listener ids; unsubscribe drops callbacks; offline test. |
| `agent.ts` sessionId to streamFn | `createLoopConfig` + `streamAssistantResponse` | implemented | Forwarded via `SimpleStreamOptions.sessionId`; offline test. |
| `agent.ts` prepareNextTurn vs WithContext | `prepareNextTurn` | partial | Context-bearing hook only (covers Pi WithContext path). |

## Harness (future)

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `harness/session/*` | expand `LeanAgent.Session` | missing | tree session, repos, labels |
| `harness/compaction/*` | future | missing | |
| `harness/skills.ts` | partial overlap with `LeanAgent.Project` OMP skills | partial | Project-level OMP skills exist; harness skill runtime does not. |
| `harness/system-prompt.ts` | future / `Prompt` | missing | |
| `harness/agent-harness.ts` | future | missing | |
| `proxy.ts` | future | missing | |

## Implementation Gates

Before expanding coding-agent or TUI against Agent:

1. Queue drain + continue-from-assistant-tail semantics must match Pi offline tests.
2. Agent loop must consume `AI` stream events (buffered OK) rather than legacy Core providers.
3. Session JSONL must remain append-compatible when harness tree features land.

Before harness compaction/branch summary:

1. Stable AgentMessage JSON serialization (done for AI.Message path).
2. Usage/token estimate hooks from AI layer.

## Test Mapping

| Pi tests | Lean target | Status |
| --- | --- | --- |
| `agent.test.ts` queue / continue steering / follow-up | `testAgent*` queue and continue tests | partial |
| `agent.test.ts` sessionId / busy / subscribe | `testAgentForwardsSessionIdToStreamFn`, `testAgentBusyRejectsNestedPromptAndContinue`, `testAgentListenerUnsubscribe` | implemented |
| `agent.test.ts` multi-message prompt | `testAgentPromptMessagesMulti` | implemented |
| `agent-loop.test.ts` tool call + result | `testAgentLoopToolCallThenFinalTurn` | implemented |
| `agent-loop.test.ts` steering after tools | `testAgentLoopSteeringAfterToolBatch` | implemented |
| `agent-loop.test.ts` prepareNextTurn | `testAgentLoopPrepareNextTurn` | implemented |
| `agent-loop.test.ts` shouldStopAfterTurn | `testAgentLoopShouldStopAfterTurn` | implemented |
| `agent-loop.test.ts` terminate all / partial | `testAgentLoopTerminateAllToolsStops`, `testAgentLoopPartialTerminateContinues` | implemented |
| `agent-loop.test.ts` idle follow-up | `testAgentLoopFollowUpWhenIdle` | implemented |
| harness tests | future | missing |

## Rules for Updating This Ledger

- Every Agent change that moves status must update this file in the same commit.
- New Lean modules must cite the Pi source row they are closing.
- A row becomes `implemented` only with tests or an explicit reason why runtime validation is impossible.
- `vendor/pi` is read-only. Do not edit reference files.
- Prefer behavior parity over line-by-line TypeScript translation.

## Long-running full port

To finish the entire `packages/agent` surface over many autonomous turns, use:

- Implementer prompt: [`docs/goals/AGENT_FULL_PARITY_PROMPT.md`](goals/AGENT_FULL_PARITY_PROMPT.md)
- Goal charter + phase checklist: [`docs/goals/AGENT_FULL_PARITY_GOAL.md`](goals/AGENT_FULL_PARITY_GOAL.md)

