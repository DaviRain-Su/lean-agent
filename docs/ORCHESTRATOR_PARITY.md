# orchestrator Parity Ledger

Tracks LeanAgent parity with Pi `packages/orchestrator`.
Reference: `vendor/pi/packages/orchestrator` (read-only).

Full-project charter: [`docs/goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md).

**Status: NOT STARTED.** Process supervision / JSONL RPC after coding-agent event contracts stabilize.

## Started modules

| Lean | Status | Notes |
| --- | --- | --- |
| `LeanAgent.Orchestrator.Types` / `Registry` | partial | In-memory instance registry only; no OS process supervision yet |

## Status legend

| Status | Meaning |
| --- | --- |
| `implemented` | Behavior + offline tests on shipped APIs |
| `partial` | Started but incomplete vs Pi |
| `missing` | No Lean equivalent yet |
| `deferred` | Only FULL_PI_PORT Exclusion List §7 |

## Inventory (`src/**/*.ts` = 13 files)

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `src/cli.ts` | `LeanAgent.Orchestrator (missing)` | missing |  |
| `src/config.ts` | `LeanAgent.Orchestrator (missing)` | missing |  |
| `src/handler.ts` | `LeanAgent.Orchestrator (partial)` | partial | handle stub added; no OS process supervision yet. |
| `src/index.ts` | `LeanAgent.Orchestrator (partial)` | partial | indexVersion stub added; no OS process supervision yet. |
| `src/ipc/client.ts` | `LeanAgent.Orchestrator (partial)` | partial | ipcClient stub added; no OS process supervision yet. |
| `src/ipc/protocol.ts` | `LeanAgent.Orchestrator (partial)` | partial | ipcProtocol stub added; no OS process supervision yet. |
| `src/ipc/server.ts` | `LeanAgent.Orchestrator (partial)` | partial | ipcServer stub added; no OS process supervision yet. |
| `src/radius.ts` | `LeanAgent.Orchestrator (partial)` | partial | radius stub added; no OS process supervision yet. |
| `src/rpc-process.ts` | `LeanAgent.Orchestrator (partial)` | partial | rpcProcess stub added; no OS process supervision yet. |
| `src/serve.ts` | `LeanAgent.Orchestrator (partial)` | partial | serve stub added; no OS process supervision yet. |
| `src/storage.ts` | `LeanAgent.Orchestrator (partial)` | partial | storage stub added; no OS process supervision yet. |
| `src/supervisor.ts` | `LeanAgent.Orchestrator (partial)` | partial | supervise stub added; no OS process supervision yet. |
| `src/types.ts` | `LeanAgent.Orchestrator (partial)` | partial | InstanceStatus/Registry + isActive helper added; no OS process supervision yet. |

## Rules

- Do not mark `implemented` without shipped-API offline tests.
- Do not use `deferred` except Exclusion List in FULL_PI_PORT_PROMPT §7.
- Update this file whenever status changes.

