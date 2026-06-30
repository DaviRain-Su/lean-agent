# LeanAgent Architecture

LeanAgent follows Pi's package boundaries while using Lean modules instead of
TypeScript packages. `vendor/pi` is the comparison target.

AI-module parity is tracked in [`docs/AI_PARITY.md`](AI_PARITY.md). Update that
ledger whenever `packages/ai` coverage changes.

## Module Map

| Pi domain | LeanAgent modules |
| --- | --- |
| `packages/ai` | `LeanAgent.Http`, `LeanAgent.AI.*` (Types, Api, Auth, OAuth, Compat, Providers, Images, Util), `LeanAgent.Models` |
| `packages/agent` | `LeanAgent.Agent.*` (Types, Loop, Agent), `LeanAgent.Session` |
| `packages/coding-agent` | `LeanAgent.CodingTools`, `LeanAgent.Project`, `Main` |
| `packages/tui` | future `LeanAgent.Tui` |
| `packages/orchestrator` | future `LeanAgent.Orchestrator` |
| root distribution | `lakefile.lean`, README, docs, release/install scripts |

## Dependency Direction

Dependencies must flow downward:

```text
Distribution/Main
  -> CodingAgent (CodingTools, Project)
  -> Agent Core (Agent.Types, Agent.Loop, Agent.Agent, Session)
  -> AI Provider (AI.Compat, AI.Api.*, AI.Providers.*, Models)
  -> HTTP/FFI (Http, native http_client.c)
```

TUI and Orchestrator must consume Agent Core events and sessions. They must not
own model/tool loop behavior.

OMP functionality must be implemented as higher-level capabilities on top of
Pi-compatible core modules.

## AI Provider Catalog

`LeanAgent.Models` and `LeanAgent.AI.Providers.*` port Pi's `packages/ai`
model/provider boundary. The runtime collection (`Models.Core`) supports
provider registration, lookup, auth application, dynamic model refresh, and
multi-API dispatch. A checked-in static catalog covers 30+ built-in providers
including DeepSeek, OpenAI, Anthropic, Google, Bedrock, Azure, GitHub Copilot,
Mistral, OpenRouter, and more.

`ModelInfo`: provider id, API kind, base URL, context window, output limit,
reasoning flag, thinking-level map, compatibility metadata, and cost.
`Provider`: runtime unit with auth, model listing, refresh hook, and
`streamSimple`/`completeSimple` dispatch.
`Collection`: mutable provider registry with auth-aware model listing.

The complete `packages/ai` migration order and status lives in
[`docs/AI_PARITY.md`](AI_PARITY.md).

## Runtime Flow

```text
Main
  -> resolve runtime config (Models.resolveSelection)
  -> load project extensions (Project.loadExtensions)
  -> build Agent + tools (Agent.create, CodingTools.defaultAgentTools)
  -> create AgentSession (ephemeral / JSONL create / resume)
  -> prompt/continue session (Agent.prompt -> Agent.Loop.runAgentLoop)
  -> persist JSONL entries (Session.persistMessages)
  -> emit terminal or JSON events (AgentEventSink)
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

Current event types (see `Session.jsonEvent`):

- `agent_start`
- `agent_end` with `messages`
- `turn_start`
- `turn_end`
- `message_start`
- `message_update`
- `message_end`
- `tool_execution_start`
- `tool_execution_update`
- `tool_execution_end`

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
- `LeanAgent.Core` and `LeanAgent.Loop` are deprecated; new code must use `LeanAgent.Agent.*` and `LeanAgent.AI.*` types.
