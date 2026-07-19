# LeanAgent ↔ Pi port status (dashboard)

Living counts for the full rewrite. **Not** a completion certificate.  
Charter: [`goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md), [`goals/FULL_PI_PORT_GOAL.md`](goals/FULL_PI_PORT_GOAL.md).

## Package rollup (honest)

| Domain | Pi `src/**/*.ts` | Ledger | Reality |
| --- | ---: | --- | --- |
| AI | 147 | [`AI_PARITY.md`](AI_PARITY.md) | **159 implemented / 0 partial / 0 missing** (offline inventory CLOSED; milestones M1–M6 offline done) |
| Agent | 25 | [`AGENT_PARITY.md`](AGENT_PARITY.md) | **partial** — core offline loop usable; harness thin vs Pi |
| Coding-agent | 160 | [`CODING_AGENT_PARITY.md`](CODING_AGENT_PARITY.md) | **MVP partial** — tools + EventBus/Defaults + Config/SessionManager/AgentSession façades; most `src` rows still missing |
| TUI | 28 | [`TUI_PARITY.md`](TUI_PARITY.md) | **components started** — Component/Spacer/Text/Box/SelectList/Loader/Input/Markdown ported; TUI class + differential rendering still missing |
| Orchestrator | 13 | [`ORCHESTRATOR_PARITY.md`](ORCHESTRATOR_PARITY.md) | **missing** (inventory only) |

**Inventory file count source:** `vendor/pi/packages/*/src/**/*.ts` at pin `54113731`.

## Definition of done

See `FULL_PI_PORT_PROMPT.md` §8. Product remains **IN PROGRESS** until all five packages are terminal (`implemented` or Exclusion-`deferred` only).

## Recent slice notes

- Coding-agent: `SlashCommands` (`BUILTIN_SLASH_COMMANDS` 22 commands + `findBuiltin?`/`isBuiltin`/`builtinNames`) + `SystemPrompt` (`buildSystemPrompt` default/custom paths, tool snippets, auto-guidelines, project context, skills block, date/cwd, injectable paths+date) modules; offline tests (`TestSlashCommands.*`, `TestSystemPrompt.*`); `SourceInfo` gains `createSourceInfo`/`createSyntheticSourceInfo` (+ `PathMetadata` subset).
- Coding-agent: `Utils.Git` (`parseGitUrl` protocol gate + `git:` shorthand, `splitRef`, `parseGenericGitUrl`, `buildGitSource`, `hasUnsafeGitInstallPart`, minimal `parseUrl`/`decodeURIComponent?`) porting Pi `utils/git.ts`; full `git-ssh-url.test.ts` matrix (`TestGit.*`). `hosted-git-info` npm dep deferred (generic parser covers matrix).
- Coding-agent: `Telemetry` (truthy flag + env-override gating) + `Timings` (`PI_TIMING=1`-gated startup profiler with per-namespace deltas, injectable clock, negative-delta filter) modules replacing stubs; offline tests (`testCodingAgentTelemetryFlag`, `testCodingAgentTimings`).
- Coding-agent: `AuthGuidance` (login/model/api-key messages, unknown-provider substitution) + `Exec` (`execCommand` no-shell spawn with piped capture + timeout kill + cancel ref) modules; offline tests (`testCodingAgentAuthGuidanceMessages`, `testCodingAgentExecCommand`); Config gains `getDocsPath`/`getBinDir`/`getToolsDir`/`getPromptsDir`.
- Coding-agent: `Migrations` module — startup fs migrations (`migrateAuthToAuthJson` oauth.json/settings.json apiKeys→auth.json, `migrateSessionsFromAgentRoot` stray .jsonl→sessions/<encoded-cwd>/, `migrateCommandsToPrompts`, `migrateToolsToBin`, `checkDeprecatedExtensionDirs`, `runMigrations`) + `encodeSessionDir`; offline tests (`testCodingAgentMigrations*`).
- Coding-agent: `PromptTemplates` module — `parseCommandArgs`/`substituteArgs` (bash-style `$1`/`$@`/`${N:-default}`/`${@:N[:L]}`)/`expandPromptTemplate`/`loadPromptTemplates` with argument-hint frontmatter; full Pi `prompt-templates.test.ts` matrix ported (`testCodingAgentPromptTemplates*`); `SourceInfo` modeled.
- Coding-agent: Mime/Frontmatter/Deprecation utils; AuthStorage; Compaction; ProviderAttribution; Config/SessionManager/AgentSession; many core/tools rows still missing.
- Agent: force-sequential when tool.executionMode=sequential under parallel config (`testAgentLoopForceSequentialToolMode`).
- Agent: session entry types model_change/thinking_level_change/compaction in buildContext (`testHarnessSessionContextEntryTypes`).
- Agent: parallel tool_execution_end completion order vs source-order results (`testAgentLoopParallelEndOrderSourceOrder`); AgentHarness appendMessage/compact/setModel/setThinkingLevel.
- Agent: `Truncate` Pi truncateHead/Tail/Line + sanitizeBinaryOutput (`testHarnessTruncate`); durable `JsonlSessionRepo` create/open/list/delete/fork (`testJsonlSessionRepoDurable`).
- Agent: Session façade `buildContext` / branch messages over InMemorySessionStorage.
- Agent: `InMemorySessionRepo` create/openSession/list/delete/fork + tests.
- Agent: `InMemorySessionStorage` leaf pointer + labels (Pi memory-storage subset).
- AI: offline inventory CLOSED (159 implemented, 0 partial/missing); evidence inventory-audit-ai.txt + lake-test.log.
- Agent: offline agent-loop tests for transformContext + custom convertToLlm.
- AI: Bedrock progressive AWS event-stream mid-transfer; AI ledger 0 partial/missing (inventory complete).
- AI: progressive AWS event-stream mid-transfer for Bedrock (`aws_mode` progressive pump + NDJSON events).
- AI: Faux chunked stream + mid-abort; Cloudflare login; credential per-provider locks; ledger promotions for progressive SSE protocols.
- AI: Cloudflare auth login prompts; promote faux/images/protocol progressive-SSE rows; Faux chunked stream.
- AI: Faux provider Pi streamWithDeltas (chunked deltas, mid-stream abort, factory throw); promote faux/images ledger rows.
- Coding-agent: `EventBus` + `Defaults` (`DEFAULT_THINKING_LEVEL`) with offline tests.
- Agent: `streamProxyHttp` progressive line-oriented SSE mid-transfer parse.
- AI: progressive SSE for Google Generative AI, Vertex, and Mistral stream paths.
- AI: progressive SSE for OpenAI Responses/Codex/Azure/Anthropic via ProgressiveSse.feedWhile + delayed local SSE routes.
- AI: OpenAI Completions progressive HTTP + incremental SSE (`streamRawProgressive`); `SSE.feed`/`finish`; offline delayed SSE server test.
- AI CLI: `lean-agent ai list` / `ai help` (Pi cli.ts offline surface).

- AI: `MutableAssistantMessageEventStream` push/end/result; promoted json-parse, simple-options, event-stream, validation.

- AI offline: Pi `retry.test.ts` + overflow LiteLLM false-positive fix (ServiceUnavailableError).
- AI offline: full Pi `overflow.test.ts` matrix + trailing orphan transform; promoted `transform-messages`/`openai-prompt-cache`/`overflow` to implemented.
- Agent: `LeanAgent.Agent.Proxy` progressive HTTP line-oriented SSE (was buffered-only).
- AI catalogs: pin-synced Together (19), Anthropic (25), Moonshot AI/CN, Z.AI/Z.AI Coding CN, Xiaomi (+ token-plan AMS/CN/SGP), OpenRouter (257), Cloudflare Workers AI (13), Cloudflare AI Gateway (37); extended `testPinnedProviderModelCatalogIds`.
- Prior: lazyApi wrappers, Headers helpers, groq/xai/cerebras/deepseek pins.

- Coding-agent: `grep` / `find` / `git_status` tools; `AGENTS.md`/`CLAUDE.md` into system prompt via `Project.buildSystemPrompt`.
- Agent harness: `messagesOnBranch`, `appendChild`, `replaceEntryMessage`.
- TUI: `LeanAgent.Tui.Render` event/transcript formatting starter.
- Orchestrator: in-memory `Registry` spawn/status/list starter.
- Ledgers: full Pi `src` inventory rows for coding-agent (160), tui (28), orchestrator (13).
- Evidence: `{SCRATCH}/lake-test.log` green; inventory-audit.txt.

**Global DoD: NOT MET** — do not close FULL_PI_PORT_GOAL until AI/agent/coding-agent/tui/orchestrator rows are terminal.
