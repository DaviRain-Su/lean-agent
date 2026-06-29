# LeanAgent PRD

LeanAgent is a Lean 4 implementation of the core Pi coding-agent architecture,
with OMP-style capabilities layered on top only after the Pi-compatible runtime
is stable.

## Reference Source

The upstream Pi repository is tracked as a git submodule at `vendor/pi`.
Treat it as the source-of-truth reference for module boundaries, behavior, and
terminology. Do not edit files under `vendor/pi` as part of LeanAgent
implementation work.

AI-module parity is tracked in [`docs/AI_PARITY.md`](AI_PARITY.md). That ledger
must be updated before marking any Pi `packages/ai` area complete.

## Product Goal

Build a self-contained Lean coding agent that can:

- Run OpenAI-compatible model/tool loops.
- Persist and resume sessions.
- Expose machine-readable events for print, JSON, RPC, and future TUI modes.
- Load project customization files such as OMP commands and skills.
- Grow toward OMP's advanced tool surface without depending on TypeScript/Bun.

## Pi Compatibility Domains

LeanAgent tracks Pi as six implementation domains:

| Domain | Pi reference | LeanAgent target |
| --- | --- | --- |
| AI | `packages/ai` | Provider/model config, OpenAI-compatible APIs, provider errors |
| Agent core | `packages/agent` | Stateful agent loop, messages, events, sessions |
| Coding agent | `packages/coding-agent` | CLI modes, tools, project context, slash commands |
| TUI | `packages/tui` | Future terminal UI consuming JSON/session events |
| Orchestrator | `packages/orchestrator` | Future multi-agent process supervision and IPC |
| Distribution app | root package/scripts | Lake build, release docs, install/runtime shape |

Current upstream `vendor/pi/packages` has five workspace packages; the sixth
LeanAgent domain is the root application/distribution layer.

## Current State

Implemented:

- Native libcurl HTTP client through Lean FFI.
- OpenAI-compatible Chat Completions provider.
- Pi-style static provider/model catalog for DeepSeek and OpenAI-compatible fallback.
- DeepSeek-first defaults.
- Basic model/tool loop.
- Tools: `list`, `read`, `write`, `edit`, `bash`.
- Line REPL.
- JSONL session persistence/resume and JSON event output.
- OMP-style `.omp/commands/*.md` and `.omp/skills/<name>/SKILL.md` discovery.

Not yet complete:

- Full Pi-compatible stateful `Agent` wrapper with queues, hooks, and dynamic turn preparation.
- Dynamic provider/model refresh, OAuth auth, and multi-API provider dispatch.
- Tool registry and richer tools.
- RPC/orchestrator.
- Full-screen TUI.
- OMP advanced tools.

## Roadmap

1. Pin Pi reference as `vendor/pi` and document the compatibility map.
2. Implement Pi AI/Core in Lean: static provider catalog, `AgentSession`, state, event sinks, JSONL sessions.
3. Implement Pi Agent runtime features: queued follow-ups, hooks, turn preparation, provider/model state.
4. Implement Pi Coding Agent mode layer: print, REPL, JSON events, session resume.
5. Expand project customization: AGENTS.md, prompt templates, command precedence.
6. Add tool registry and core coding tools: search, find, git status/diff.
7. Add orchestrator primitives: process registry, JSONL RPC, spawn/status/stop.
8. Build a minimal TUI over the stable event/session API.
9. Add OMP advanced capabilities: hashline edit, LSP, DAP, task agents, memory, advisor.

## Success Criteria

- `lake build` and `lake test` pass on every milestone.
- README reflects current user-facing behavior only.
- `docs/ARCHITECTURE.md` reflects implementation boundaries before new subsystems land.
- `docs/AI_PARITY.md` reflects current `packages/ai` parity before and after AI-module changes.
- New features include CLI smoke tests or unit tests.
- OMP work starts only after the corresponding Pi core dependency exists in Lean.
