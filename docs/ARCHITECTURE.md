# LeanAgent Architecture

LeanAgent follows Pi's package boundaries while using Lean modules instead of
TypeScript packages. `vendor/pi` is the comparison target.

## Module Map

| Pi domain | LeanAgent modules |
| --- | --- |
| `packages/ai` | `LeanAgent.Http`, `LeanAgent.OpenAI`, future `LeanAgent.Provider` |
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
