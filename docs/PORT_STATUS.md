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

- Agent harness deepen: `AgentHarness.lean` — `createUserMessage`/`createFailureMessage` (Pi user/assistant message builders), `HarnessStreamOptions`/`HarnessStreamOptionsPatch` + `cloneStreamOptions`/`applyStreamOptionsPatch`, `findDuplicateNames`, `PendingSessionWrite` inductive + `getPendingWrites`/`addPendingWrite`/`flushPendingWrites`, `getResource?`/`setResource` resource map, `navigateTree` (session tree walk to target leaf, editor text for user messages, branch messages), `getStreamOptions`/`setStreamOptions`; `AgentHarnessRef` (IO.Ref-backed subscribe/unsubscribe/emit/getResource?/setResource/getPendingWrites/flushPendingWrites) for Pi `handlers`/`resources`/`pendingSessionWrites`; `compact` keeps 3-arg explicit-summary signature (backward-compatible with `CodingAgent.AgentSession`), `compactAuto` added for auto-pipeline. `Compaction.lean` — full offline pipeline: `CompactionSettings` (enabled/reserveTokens/keepRecentTokens/maxMessages/maxTokens/compactionThreshold), `estimateTokenCount` (chars/4 heuristic per message), `shouldCompact` (token+message threshold), `selectCompactionWindow` (findCutPoint with valid-cut-point alignment + turn-start detection), `buildCompactionSummary` (serialize compacted messages), `prepareCompactionAuto` (Option CompactionResult), `compact` (auto), `compactSession` (apply to Session), `compactWithSummary` (legacy); backward-compatible `prepareCompaction` returns `PrepareCompactionResult` for `CodingAgent.Compaction`. New `Messages.lean` — `convertToLlm` (AgentMessage→LLM Message array; compactionSummary/branchSummary/bashExecution/custom→user mapping with prefix/suffix wrapping), `COMPACTION_SUMMARY_PREFIX/SUFFIX`, `BRANCH_SUMMARY_PREFIX/SUFFIX`, `bashExecutionToText`. No files outside `LeanAgent/Agent/Harness/` modified (AgentSession.lean untouched).
- Coding-agent: `Utils.ChildProcess` — `ChildProcessResult` + `spawnProcess` (IO.Process.spawn piped) + `spawnProcessSync` (timeout poll) + `waitForChildProcess` (EXIT_STDIO_GRACE_MS post-exit sleep); `Utils.Clipboard` — `copyToClipboard` (pbcopy/clip/wl-copy/xclip/xsel/termux via IO.Process.spawn piped stdin) + OSC 52 fallback (`emitOsc52`/`base64Encode`/`MAX_OSC52_ENCODED_LENGTH`) + `isRemoteSession`/`isWaylandSession` (inlined from clipboard-image.ts); native addon treated as unavailable; `Utils.FsWatch` — `FsWatcher` interface + `closeWatcher`/`watchWithErrorHandler` + `FS_WATCH_RETRY_DELAY_MS` (no native fs.watch in Lean); `Utils.Photon` — `loadPhoton` returns none (WASM Exclusion) + `PhotonImage` stub; `Utils.ImageConvert` — `convertImageBytesToPng`/`convertToPng` (PNG fast path; else none — Photon Exclusion) + local `base64Encode`/`base64Decode`; `Utils.ImageProcess` — `ProcessImageResult`/`normalizeImage`/`processImage` (MIME normalization ported; resize returns error — Photon Exclusion) + **Lean-side** `getImageDimensions` (PNG IHDR/JPEG SOF0/SOF2/GIF/WebP VP8/VP8L/VP8X header parse); `Utils.WindowsSelfUpdate` — quarantine stubs (Node process.report Exclusion). All `missing` → `partial`.
- Coding-agent: `Utils.Shell` — `isLegacyWslBashPath` (drive:\windows\{system32,sysnative}\bash.exe regex) + `getBashShellConfig` (WSL `-s`/stdin vs `-c`); `findBashOnPath` (`where bash.exe`+existsSync verify on Windows, `which bash` trust on Unix) + `getShellConfig` (custom→Windows Git Bash→PATH; Unix `/bin/bash`→PATH→`sh` fallback; throws on Windows miss) over injectable `ShellDeps` (`defaultShellDeps` wires real IO) so the pure resolution is offline-testable; `getShellEnv` (case-insensitive PATH key + binDir augment, returns `(key,value)` — Pi spreads env) + `findPathKey`; `killProcessTree` (win `taskkill /F /T`, unix `kill -9 -<pid>` process-group + single-pid fallback) + `track`/`untrack`/`killTrackedDetachedChildren` (global `IO.Ref` set) + `sanitizeBinaryOutput` re-export from Harness.Truncate. `TestShell.*` (22 cases) covers WSL path detection, bash-config, full getShellConfig matrix (unix/win32 fallback/throws/custom/WSL-transport), findBashOnPath, getShellEnv (augment/already-present/empty/windows-key-case), sanitize re-export, tracked-pid roundtrip, killProcessTree + killTrackedDetachedChildren no-throw. `missing` → `implemented`.
- Coding-agent: `Tools.FileMutationQueue` — `withFileMutationQueue` serializes mutations per canonical file path (one `Std.Mutex Unit` per key; distinct files run in parallel), `getMutationQueueKey` (resolvePath + canonicalizePath for symlink collapse, missing → resolved fallback), `getOrCreateQueue` (atomic get-or-create under a registration mutex). `TestFileMutationQueue.*` covers key resolution (existing/missing), result passthrough, registry reuse, and `IO.asTask` concurrency: same-file critical sections serialize (non-overlapping), different files run in parallel. Divergence: per-file mutexes retained for process lifetime (Pi cleans up via chained-queue identity; bounded by distinct files). `partial` stub → `implemented`.
- Coding-agent: `Tools.PathUtils` — `expandPath`/`resolveToCwd` (normalizePath/resolvePath with Unicode-space + `@`-strip), `pathExists`, `resolveReadPath` (tries macOS filename fallbacks when the literal path misses: `tryMacOSScreenshotPath` ` AM.`/` PM.` case-insensitive → `<U+202F>AM.` Char-list scanner, `tryNFDVariant` pass-through — full NFD decomposition deferred, host FS normalizes on macOS, `tryCurlyQuoteVariant` `U+0027`→`U+2019`, combined NFD+curly). Full `path-utils.test.ts` matrix (`TestPathUtils.*`). `partial` stub → `implemented`.
- Coding-agent: `Utils.Paths` completed — `isLocalPath` (scheme gate, `file:` local), `normalizePath` (trim/`@`-strip/Unicode-space/tilde `~`|`~/`|`~\`/`file://`), `canonicalizePath` (realpath+fallback), `resolvePath` (lexical `.`/`..` resolve against base, Node `path.resolve` semantics), `relativePath` (Node `path.relative`), `getCwdRelativePath` (`..${sep}` parent-traversal rejection preserving `..config` literal names), `formatPathRelativeToCwdOrAbsolute` (fwd-slash normalize), `markPathIgnoredByCloudSync` (best-effort `xattr`/`setfattr`); `file://` decoding mirrors Node `fileURLToPath` (localhost/empty host, UTF-8 percent-decode, malformed→IO error). Full `paths.test.ts` matrix (`TestPaths.*`). `partial` -> `implemented`.
- Coding-agent: `SlashCommands` (`BUILTIN_SLASH_COMMANDS` 22 commands + `findBuiltin?`/`isBuiltin`/`builtinNames`) + `SystemPrompt` (`buildSystemPrompt` default/custom paths, tool snippets, auto-guidelines, project context, skills block, date/cwd, injectable paths+date) modules; offline tests (`TestSlashCommands.*`, `TestSystemPrompt.*`); `SourceInfo` gains `createSourceInfo`/`createSyntheticSourceInfo` (+ `PathMetadata` subset).
- Coding-agent: `Utils.Git` (`parseGitUrl` protocol gate + `git:` shorthand, `splitRef`, `parseGenericGitUrl`, `buildGitSource`, `hasUnsafeGitInstallPart`, minimal `parseUrl`/`decodeURIComponent?`) porting Pi `utils/git.ts`; full `git-ssh-url.test.ts` matrix (`TestGit.*`). `hosted-git-info` npm dep deferred (generic parser covers matrix).
- Coding-agent: `Utils.VersionCheck` self-contained semver (`parseSemver?`/`compareSemver` with prerelease precedence) + `comparePackageVersions`/`isNewerPackageVersion` + env-gated network entry points (`getLatestPiRelease`/`getLatestPiVersion`/`checkForNewPiVersion`) over injectable `LatestVersionTransport`; full `version-check.test.ts` matrix (`TestVersionCheck.*`). npm `semver` replaced by in-tree parser.
- Coding-agent: `Utils.Changelog` `normalizeChangelogLinks` (markdown-link scanner + repo canonicalization + tag-pinned path resolution) + `parseChangelog` + `compareVersions`/`getNewEntries`; full `changelog.test.ts` matrix (`TestChangelog.*`).
- Coding-agent: `Utils.Ansi` `stripAnsi` (CSI/OSC scanner with param backtracking + 8-bit C1), `Utils.Html` `decodeHtmlEntity`/`decodeHtmlEntityAt` (named + numeric + hex), `Utils.PiUserAgent` `getPiUserAgent` (`TestAnsi.*`/`TestHtml.*`/`TestPiUserAgent.*`).
- Coding-agent: `Utils.OpenBrowser` `openBrowser` (no-shell platform launcher, best-effort) + `Utils.ToolsManager` `ToolConfig` registry (fd/rg) + per-platform asset-name computation + `PI_OFFLINE` gate + `commandExists` + `getToolPath` (`TestOpenBrowser.*`/`TestToolsManager.*`); download/extract deferred.
- Coding-agent: `HttpDispatcher` `parseHttpIdleTimeoutMs`/`formatHttpIdleTimeoutMs` + `httpIdleTimeoutChoices` + `applyHttpProxySettings` (injectable env, `??=` semantics) (`TestHttpDispatcher.*`); undici global-dispatcher install deferred (Node-only).
- Coding-agent: `Keybindings` `migrateKeybindingsConfig` (legacy→namespaced, conflict resolution) + `orderKeybindingsConfig` + `toKeybindingsConfig` + minimal `KeybindingsManager` (`create`/`reload`/`loadFromFile`/`getEffectiveConfig` defaults∪user merge); full `keybindings-migration.test.ts` matrix (`TestKeybindings.*`). pi-tui `TUI_KEYBINDINGS`/`KEYBINDINGS` registry modeled as app.* subset.
- Coding-agent: `Utils.SyntaxHighlight` `renderHighlightedHtml` (span-walker + entity decode via `Utils.Html` + theme formatter resolution: exact → dot-prefix → dash-prefix) (`TestSyntaxHighlight.*`); `highlight`/`supportsLanguage` (highlight.js npm) deferred.
- Coding-agent: `Utils.ExifOrientation` `getExifOrientation` (JPEG/WebP EXIF byte parse, TIFF IFD tag `0x0112`, LE/BE) + `orientationTransform` map (`TestExifOrientation.*`); `applyExifOrientation` pixel transform (photon) deferred.
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
