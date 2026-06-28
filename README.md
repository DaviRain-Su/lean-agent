# lean-agent

A small terminal coding agent implemented in Lean 4, using the architecture of
[`tau`](https://github.com/alejandro-ao/tau) as the reference shape:

- `LeanAgent.Core` owns provider-neutral messages, tools, results, and events.
- `LeanAgent.Loop` owns the model/tool loop.
- `LeanAgent.CodingTools` provides `list`, `read`, `write`, `edit`, and `bash`.
- `LeanAgent.OpenAI` adapts OpenAI-compatible Chat Completions tool calling.
- `Main` provides one-shot and line-REPL CLI execution.

The long-term architecture tracks Pi through the `vendor/pi` submodule. See
[`docs/PRD.md`](docs/PRD.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for the Pi-compatible Lean roadmap, including `packages/orchestrator`.

## Current Scope

The agent is currently a terminal coding agent. It can run in one-shot mode or
line REPL mode, inspect and edit files, run bounded shell commands, and loop
through OpenAI-compatible tool calls. It does not yet provide a full-screen TUI.

It also implements the first layer of OMP-style project customization:
file-backed slash commands from `.omp/commands/*.md` and skills from
`.omp/skills/<name>/SKILL.md`.

## Build

This project uses a small Lean FFI adapter backed by the native `libcurl` C API
for HTTPS requests. It does not execute the `curl` command-line program.
Transport defaults are intentionally conservative:

- total request timeout: 120 seconds
- connection timeout: 30 seconds
- maximum response body: 32 MiB
- user agent: `lean-agent/0.1.0`

The native adapter preserves the HTTP status code internally. The OpenAI-compatible
provider treats non-2xx responses as provider errors and includes the response
body in the error message for debugging.

On macOS, install Homebrew curl if the library is not already available:

```bash
brew install curl
```

On Linux, install the distro package that provides `libcurl` headers and
`libcurl` itself, for example `libcurl4-openssl-dev` on Debian/Ubuntu.

```bash
lake build
lake test
```

## Run

```bash
export DEEPSEEK_API_KEY=...
lake exe lean-agent -p "explain this repo"
```

When `DEEPSEEK_API_KEY` is set, `lean-agent` defaults to:

- base URL: `https://api.deepseek.com`
- model: `DEEPSEEK_MODEL`, then `deepseek-v4-flash`
- no-proxy host: `api.deepseek.com`

The DeepSeek default bypasses local HTTPS proxies because some local proxy/TLS
combinations fail the Chat Completions handshake. Override this with
`LEAN_AGENT_NO_PROXY`; set it to an empty value to rely entirely on libcurl's
normal proxy environment handling.

DeepSeek model defaults follow the official model/pricing page:

- `deepseek-v4-flash`: default model for this agent, lower cost, supports Tool Calls and JSON Output.
- `deepseek-v4-pro`: available with `--model deepseek-v4-pro`, higher cost and lower concurrency limit.
- Both current V4 models list 1M context length and max 384K output length.
- `deepseek-chat` and `deepseek-reasoner` are compatibility names scheduled for deprecation at Beijing time `2026-07-24 23:59`; do not use them for new defaults.

Official pricing snapshot from the same page, per 1M tokens:

| Model | Cache-hit input | Cache-miss input | Output | Concurrency |
| --- | ---: | ---: | ---: | ---: |
| `deepseek-v4-flash` | 0.02 CNY | 1 CNY | 2 CNY | 2500 |
| `deepseek-v4-pro` | 0.025 CNY | 3 CNY | 6 CNY | 500 |

If DeepSeek is not configured, it falls back to `OPENAI_API_KEY`,
`OPENAI_MODEL`, and `gpt-4.1-mini`.

Useful options:

```bash
lake exe lean-agent --help
lake exe lean-agent --cwd /path/to/project -p "add a regression test"
lake exe lean-agent --repl --cwd /path/to/project
lake exe lean-agent --repl --session ./session.jsonl
lake exe lean-agent --resume ./session.jsonl -p "continue from prior context"
lake exe lean-agent --json-events -p "print machine-readable events"
lake exe lean-agent --repl -p "first task, then keep chatting"
lake exe lean-agent --model deepseek-v4-pro -p "use the pro model for this request"
lake exe lean-agent --base-url http://localhost:11434/v1 --model local-model -p "summarize files"
lake exe lean-agent --api-key-env OPENAI_API_KEY --base-url https://api.openai.com/v1 --model gpt-4.1-mini -p "summarize files"
```

REPL commands:

- `/help`: show REPL commands.
- `/context`: show the current model, working directory, and message count.
- `/commands`: list discovered `.omp` slash commands.
- `/skills`: list discovered `.omp` skills.
- `/clear`: clear conversation context.
- `/exit` or `/quit`: exit the REPL.

## OMP Project Extensions

LeanAgent discovers OMP-style project files from the working directory:

- `.omp/commands/*.md`: file-backed slash commands.
- `.omp/skills/<name>/SKILL.md`: reusable skill instructions.

It also checks user-level directories:

- `~/.omp/agent/commands/*.md`
- `~/.omp/agent/skills/<name>/SKILL.md`

Project entries win over user entries when names collide. Command frontmatter may
define `name` and `description`; otherwise the filename is used. Command bodies
support `$ARGUMENTS`, `$@`, `$1`, `$2`, and `$@[start]` / `$@[start:length]`
argument placeholders.

Example:

```markdown
---
description: Prepare a release
---

Review commits since the last tag and release `$ARGUMENTS`.
```

Run it with:

```bash
lake exe lean-agent --repl
/release 1.2.3
```

Skills can be invoked explicitly:

```bash
/skill:system-prompts rewrite this tool prompt
```

## Tools

Tool access is scoped to the configured working directory. Paths that resolve
outside that directory are rejected, including common `..` and symlink escapes.

- `list`: list immediate directory entries.
- `read`: read a UTF-8 text file with optional line offset and limit.
- `write`: write a full file under the working directory.
- `edit`: replace text only when the default match is unique; use `replace_all`
  when every occurrence should be replaced.
- `bash`: run a shell command with `timeout_seconds`, defaulting to 120 seconds.

## Roadmap

Near-term work should focus on making the agent more interactive:

- Add transcript persistence so runs can be inspected and resumed.
- Add structured JSON event output for external UIs.
- Add a TUI after the REPL/event model is stable.
