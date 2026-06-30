# LeanAgent

[![CI](https://github.com/DaviRain-Su/lean-agent/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/DaviRain-Su/lean-agent/actions/workflows/ci.yml)
![Lean 4.31.0](https://img.shields.io/badge/Lean-4.31.0-0b8ac6)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-444444)

LeanAgent is a Lean 4 coding agent and OpenAI-compatible terminal AI assistant.
It ports the core Pi coding-agent architecture into Lean, uses native
`libcurl`/OpenSSL FFI instead of shelling out to `curl`, and is designed to
grow toward a full Pi-compatible agent stack with TUI and orchestrator layers.

If you are searching for a Lean code agent, terminal coding assistant,
OpenAI-compatible CLI, DeepSeek-powered coding agent, or a Pi-inspired agent
runtime implemented in Lean, this repository is that project.

## Why This Repo

- Lean 4 implementation of a real coding agent runtime instead of a toy demo.
- Pi-aligned module boundaries tracked through the checked-in `vendor/pi`
  reference submodule.
- Native HTTP transport through Lean FFI, with no dependency on the `curl`
  command-line program.
- DeepSeek-first defaults with OpenAI-compatible fallback.
- JSONL session persistence, resume, and machine-readable event output for
  future TUI and orchestration layers.
- OMP-style project extensions through `.omp/commands/*.md` and
  `.omp/skills/<name>/SKILL.md`.

## Current Status

Implemented today:

- one-shot CLI and line REPL
- JSONL session persistence and resume
- JSON event output for external tooling
- built-in coding tools: `list`, `read`, `write`, `edit`, `bash`
- Pi-style AI/provider/model foundation under `LeanAgent.AI` and `LeanAgent.Models`
- native `libcurl` + OpenSSL transport through Lean FFI
- OMP-style project commands and skills

In progress:

- broader Pi `packages/ai` parity across providers and edge cases
- richer coding-agent ergonomics and tool surface
- future TUI and orchestrator layers on top of the stable session/event model

Not shipped yet:

- full-screen TUI
- orchestrator / RPC process supervision
- true callback-style live transport streaming across every provider

## Architecture

LeanAgent tracks Pi package boundaries in Lean modules:

- `LeanAgent.Agent`: agent runtime, loop, messages, events, hooks, sessions
- `LeanAgent.AI`: provider APIs, compat dispatch, OAuth, auth, utilities
- `LeanAgent.Models`: provider/model catalogs and runtime collection
- `LeanAgent.CodingTools`: filesystem and shell tools for coding tasks
- `LeanAgent.Project`: project-scoped OMP command and skill discovery
- `LeanAgent.Http`: native HTTP transport via Lean FFI
- `Main`: CLI entrypoint, REPL mode, JSON event output

Reference and planning docs:

- [Product roadmap](docs/PRD.md)
- [Architecture notes](docs/ARCHITECTURE.md)
- [AI parity ledger](docs/AI_PARITY.md)

## Quick Start

### 1. Install Native Dependencies

On macOS:

```bash
brew install curl openssl@3
```

On Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y libcurl4-openssl-dev libssl-dev
```

### 2. Build And Test

```bash
lake build
lake test
```

### 3. Run The Agent

```bash
export DEEPSEEK_API_KEY=...
lake exe lean-agent -p "explain this repo"
```

If DeepSeek is not configured, LeanAgent falls back to `OPENAI_API_KEY`,
`OPENAI_MODEL`, and `gpt-4.1-mini`.

## Provider Defaults

When `DEEPSEEK_API_KEY` is set, LeanAgent defaults to:

- base URL: `https://api.deepseek.com`
- model: `DEEPSEEK_MODEL`, then `deepseek-v4-flash`
- no-proxy host: `api.deepseek.com`

The DeepSeek path intentionally bypasses local HTTPS proxies by default because
some local proxy/TLS combinations break OpenAI-compatible handshakes. Override
this with `LEAN_AGENT_NO_PROXY`; set it to an empty value to use normal
libcurl proxy environment behavior.

For the current DeepSeek model lifecycle and pricing, use the official docs
instead of relying on README snapshots:

- <https://api-docs.deepseek.com/>
- <https://api-docs.deepseek.com/zh-cn/quick_start/pricing>

## CLI Examples

```bash
lake exe lean-agent --help
lake exe lean-agent --list-models
lake exe lean-agent --cwd /path/to/project -p "add a regression test"
lake exe lean-agent --repl --cwd /path/to/project
lake exe lean-agent --repl --session ./session.jsonl
lake exe lean-agent --resume ./session.jsonl -p "continue from prior context"
lake exe lean-agent --resume ./session.jsonl --continue
lake exe lean-agent --json-events -p "print machine-readable events"
lake exe lean-agent --model deepseek-v4-pro -p "use the pro model for this request"
lake exe lean-agent --base-url http://localhost:11434/v1 --model local-model -p "summarize files"
lake exe lean-agent --api-key-env OPENAI_API_KEY --base-url https://api.openai.com/v1 --model gpt-4.1-mini -p "summarize files"
```

## REPL Commands

- `/help`: show REPL commands
- `/context`: show the current model, working directory, and message count
- `/session`: show the current session file and message count
- `/commands`: list discovered `.omp` slash commands
- `/skills`: list discovered `.omp` skills
- `/clear`: clear conversation context
- `/exit` or `/quit`: exit the REPL

## OMP Project Extensions

LeanAgent discovers project-level customization from the working directory:

- `.omp/commands/*.md`
- `.omp/skills/<name>/SKILL.md`

It also checks user-level directories:

- `~/.omp/agent/commands/*.md`
- `~/.omp/agent/skills/<name>/SKILL.md`

Project entries win over user entries when names collide. Command frontmatter
may define `name` and `description`; otherwise the filename is used. Command
bodies support `$ARGUMENTS`, `$@`, `$1`, `$2`, and `$@[start]` /
`$@[start:length]` placeholders.

Example command file:

```markdown
---
description: Prepare a release
---

Review commits since the last tag and release `$ARGUMENTS`.
```

Use it from REPL:

```bash
lake exe lean-agent --repl
/release 1.2.3
```

Skills can also be invoked explicitly:

```bash
/skill:system-prompts rewrite this tool prompt
```

## Built-in Tools

Tool access is scoped to the configured working directory. Paths that resolve
outside that directory are rejected, including common `..` and symlink escapes.

- `list`: list immediate directory entries
- `read`: read a UTF-8 text file with optional line offset and limit
- `write`: write a full file under the working directory
- `edit`: replace text only when the default match is unique
- `bash`: run a shell command with a bounded timeout

## Provider Coverage

The checked-in catalog and runtime already cover a broad Lean-side surface:

- DeepSeek and OpenAI-compatible providers
- OpenAI Responses and OpenAI Codex Responses
- Anthropic Messages and Anthropic-compatible providers
- Google Generative AI and Google Vertex
- Mistral Conversations
- Azure OpenAI Responses
- Amazon Bedrock ConverseStream
- OpenRouter text and image routing
- GitHub Copilot OAuth/provider integration

Coverage is intentionally tracked in detail in
[docs/AI_PARITY.md](docs/AI_PARITY.md). That ledger is the source of truth for
what is implemented, partial, or still missing relative to Pi `packages/ai`.

## Developer Workflow

Useful local commands:

```bash
lake build
lake test
lake exe lean-agent --help
lake exe lean-agent --list-models
lake exe ai-import-smoke
lake exe compat-import-smoke
lake exe oauth-import-smoke
```

GitHub Actions CI runs build, tests, and smoke commands on Linux and macOS.

## Roadmap

Near-term priorities:

- keep closing Pi `packages/ai` parity gaps
- expand coding-agent ergonomics and tool surface
- stabilize the session/event model for external consumers
- add TUI after the event/session contracts stop moving
- add orchestrator primitives after the agent/runtime boundaries are stable

## Repository Layout

```text
LeanAgent/     Lean modules
native/        C FFI transport code
docs/          PRD, architecture notes, AI parity ledger
vendor/pi/     upstream reference submodule
Main.lean      CLI entrypoint
Tests.lean     test driver
```
