# LeanAgent Architecture

LeanAgent follows Pi's package boundaries while using Lean modules instead of
TypeScript packages. `vendor/pi` is the comparison target.

AI-module parity is tracked in [`docs/AI_PARITY.md`](AI_PARITY.md). Update that
ledger whenever `packages/ai` coverage changes.

## Module Map

| Pi domain | LeanAgent modules |
| --- | --- |
| `packages/ai` | `LeanAgent.Http`, `LeanAgent.Models`, `LeanAgent.OpenAI` |
| `packages/agent` | `LeanAgent.Core`, `LeanAgent.Loop`, `LeanAgent.Session` |
| `packages/coding-agent` | `LeanAgent.CodingTools`, `LeanAgent.Project`, `Main` |
| `packages/tui` | future `LeanAgent.Tui` |
| `packages/orchestrator` | future `LeanAgent.Orchestrator` |
| root distribution | `lakefile.lean`, README, docs, release/install scripts |

## Dependency Direction

Dependencies must flow downward:

```text
Distribution/Main
  -> CodingAgent
  -> Agent Core
  -> AI Provider
  -> HTTP/FFI
```

TUI and Orchestrator must consume Agent Core events and sessions. They must not
own model/tool loop behavior.

OMP functionality must be implemented as higher-level capabilities on top of
Pi-compatible core modules.

## AI Provider Catalog

`LeanAgent.Models` is the first Lean port of Pi's `packages/ai` model/provider
boundary:

- `ModelInfo`: provider id, API kind, base URL, context window, output limit,
  reasoning flag, and compatibility metadata.
- `ProviderInfo`: provider id, display name, auth env var, model env var,
  default model, and known static models.
- `ProviderCatalog`: lookup by provider id, API-key env var, and model id.

Current catalog scope is intentionally static:

- DeepSeek: `deepseek-v4-flash`, `deepseek-v4-pro`.
- OpenAI fallback: `gpt-4.1-mini`.

Dynamic model refresh, OAuth auth, image APIs, and mixed API dispatch remain
future work. CLI defaults must resolve through this catalog instead of hardcoded
provider constants.

The complete `packages/ai` migration order and status lives in
[`docs/AI_PARITY.md`](AI_PARITY.md).

## Current Runtime Flow

```text
Main
  -> resolve runtime config
  -> load project extensions
  -> build provider + tools
  -> run agent loop
  -> render terminal events
```

The target flow is:

```text
Main
  -> create AgentSession
  -> prompt/continue session
  -> persist JSONL entries
  -> emit terminal or JSON events
```

## Session Model

The first Lean session format is intentionally smaller than Pi's full tree
session model:

- JSONL file.
- First line: session header.
- Remaining lines: append-only message entries.
- Entries include `id`, `parentId`, and `timestamp` so a future tree model can
  be introduced without changing the file family.

Future work can add branch summaries, compaction, labels, model changes, and
tree navigation after the v1 append-only session is stable.

## AgentSession Runtime API

`LeanAgent.Session` is the public Agent Core boundary for CLI, future TUI, and
future Orchestrator code:

- `Persistence.ephemeral`: in-memory run only.
- `Persistence.create path`: create or append to a JSONL session file.
- `Persistence.resume path`: load an existing JSONL session file and append.
- `create config cwd model persistence`: build an `AgentSession`.
- `prompt session text sink`: append a user message, run the loop, persist new messages.
- `continueSession session sink`: run the loop from existing context without adding a user message. The last message must be a user message or tool result; assistant-final sessions require a new prompt instead.
- `clear session`: clear in-memory context.

CLI modes must call this API instead of managing `messages` directly.

## JSON Event Schema

`--json-events` emits one JSON object per line. Every object includes:

- `timestamp`: UTC ISO-like timestamp string.
- `type`: event discriminator.

Current event types:

- `agent_start`
- `agent_end`
- `turn_start` with `turn`
- `turn_end` with `turn`
- `message_start` with `role`
- `message_delta` with `delta`
- `message_end` with serialized `message`
- `tool_execution_start` with `tool_call`
- `tool_execution_end` with `tool_call_id`, `name`, `ok`, `content`, `error`
- `error` with `message`

## Orchestrator Placement

The orchestrator layer maps to Pi's `packages/orchestrator`. It should be added
after JSON events and session persistence exist.

Initial Lean target:

- `serve`: start local supervisor process.
- `spawn`: launch an agent instance in a cwd.
- `list`: list instances.
- `status`: inspect one instance.
- `stop`: stop one instance.
- `rpc` / `rpc-stream`: send JSON commands and receive JSON events.

Implementation should use the same AgentSession API as CLI modes.

## Rules

- Do not copy TypeScript internals verbatim; port behavior and contracts.
- Do not add OMP advanced tools before their Pi dependency layer exists.
- Do not put session, TUI, or orchestrator state in `Main.lean`.
- Keep `vendor/pi` read-only during LeanAgent feature work.
