# lean-agent

A small terminal coding agent implemented in Lean 4, using the architecture of
[`tau`](https://github.com/alejandro-ao/tau) as the reference shape:

- `LeanAgent.Core` owns provider-neutral messages, tools, results, and events.
- `LeanAgent.Loop` owns the model/tool loop.
- `LeanAgent.CodingTools` provides `read`, `write`, `edit`, and `bash`.
- `LeanAgent.OpenAI` adapts OpenAI-compatible Chat Completions tool calling.
- `Main` provides one-shot print-mode CLI execution.

## Build

This project uses a small Lean FFI adapter backed by the native `libcurl` C API
for HTTPS requests. It does not execute the `curl` command-line program.
Transport defaults are intentionally conservative:

- total request timeout: 120 seconds
- connection timeout: 30 seconds
- maximum response body: 32 MiB
- user agent: `lean-agent/0.1.0`

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
lake exe lean-agent --model deepseek-v4-pro -p "use the pro model for this request"
lake exe lean-agent --base-url http://localhost:11434/v1 --model local-model -p "summarize files"
lake exe lean-agent --api-key-env OPENAI_API_KEY --base-url https://api.openai.com/v1 --model gpt-4.1-mini -p "summarize files"
```
