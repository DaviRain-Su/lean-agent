# coding-agent Parity Ledger

Tracks LeanAgent parity with Pi `packages/coding-agent`.
Reference: `vendor/pi/packages/coding-agent` (read-only).

Full-project charter: [`docs/goals/FULL_PI_PORT_PROMPT.md`](goals/FULL_PI_PORT_PROMPT.md).

**Status: IN PROGRESS (MVP).** Tools: read/list/write/edit/bash/grep/find/git_status.
Config + SessionManager + thin AgentSession offline façades started.
Full interactive TUI modes, RPC, extensions runtime still missing.


## Status legend

| Status | Meaning |
| --- | --- |
| `implemented` | Behavior + offline tests on shipped APIs |
| `partial` | Started but incomplete vs Pi |
| `missing` | No Lean equivalent yet |
| `deferred` | Only FULL_PI_PORT Exclusion List §7 |

## Inventory (`src/**/*.ts` = 160 files)

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `src/bun/cli.ts` | — | deferred | Exclusion: Bun runtime entrypoint (not portable). |
| `src/bun/register-bedrock.ts` | — | deferred | Exclusion: Bun-only Bedrock register hook. |
| `src/bun/restore-sandbox-env.ts` | — | deferred | Exclusion: Bun sandbox env restore. |
| `src/cli.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/args.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/config-selector.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/file-processor.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/initial-message.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/list-models.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/project-trust.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/session-picker.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/cli/startup-ui.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/config.ts` | `LeanAgent.CodingAgent.Config` | partial | getAgentDir/getSessionsDir/expandTildePath + env key names (`testCodingAgentConfigPaths`); getConfigDir added. Install-method/Bun detection Exclusion. |
| `src/core/agent-session-runtime.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/agent-session-services.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/agent-session.ts` | `LeanAgent.CodingAgent.AgentSession` | partial | Thin create/prompt/compact/setModel/thinking + EventBus + optional durable SessionManager (`testCodingAgentSessionManagerAndAgentSession`); executeBash added. << Pi ~3k LOC. |
| `src/core/auth-guidance.ts` | `LeanAgent.CodingAgent.AuthGuidance` | implemented | `getProviderLoginHelp`/`formatNoModelsAvailableMessage`/`formatNoModelSelectedMessage`/`formatNoApiKeyFoundMessage` (unknown-provider substitution) (`testCodingAgentAuthGuidanceMessages`); docs path injectable. |
| `src/core/auth-storage.ts` | `LeanAgent.CodingAgent.AuthStorage` | partial | JSON auth.json map set/get/erase/reload (`testCodingAgentAuthStorage`); reload added. OAuth refresh + proper-lockfile concurrent lock open. |
| `src/core/bash-executor.ts` | `LeanAgent.CodingTools.makeBashTool` + `Agent.Harness.Truncate` | partial | Real subprocess bash execution via `makeBashTool`; output truncation (`DEFAULT_MAX_BYTES`/`truncateTail`) resolves to `Harness.Truncate`. Node WriteStream temp-file spillover + rolling-buffer streaming is Exclusion-adjacent (Node streams). |
| `src/core/compaction/branch-summarization.ts` | `LeanAgent.CodingAgent.Compaction` | partial | branchSummary via harness + coding-agent message format. |
| `src/core/compaction/compaction.ts` | `LeanAgent.CodingAgent.Compaction` | partial | offline compact/shouldCompact façade (`testCodingAgentCompactionFacade`); compact added. |
| `src/core/compaction/index.ts` | `LeanAgent.CodingAgent.Compaction` | partial | barrel via Compaction module. |
| `src/core/compaction/utils.ts` | `LeanAgent.Agent.Harness.Compaction` | partial | shared estimate/cut helpers via harness. |
| `src/core/defaults.ts` | `LeanAgent.CodingAgent.Defaults` | implemented | `DEFAULT_THINKING_LEVEL = medium` (`testCodingAgentDefaultThinkingLevel`). |
| `src/core/diagnostics.ts` | `LeanAgent.CodingAgent.Diagnostics` | implemented | ResourceDiagnostic + formatDiagnostic (`testCodingAgentUtilsDiagnosticsPaths`). |
| `src/core/event-bus.ts` | `LeanAgent.CodingAgent.EventBus` | implemented | `createEventBus` / emit / on+unsubscribe / clear with handler error isolation (`testCodingAgentEventBusEmitOnClear`). |
| `src/core/exec.ts` | `LeanAgent.CodingAgent.Exec` | implemented | `execCommand` (no-shell spawn, piped stdout/stderr, exit code, timeout kill, cooperative cancel ref) returning `ExecResult` (`testCodingAgentExecCommand`); JS `AbortSignal` → cooperative `IO.Ref Bool` (subset; polling-based). |
| `src/core/experimental.ts` | `LeanAgent.CodingAgent.Experimental` | implemented | `PI_EXPERIMENTAL=1` flag (`testCodingAgentUtilsDiagnosticsPaths`). |
| `src/core/export-html/ansi-to-html.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/export-html/index.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/export-html/tool-renderer.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/extensions/index.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/extensions/loader.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/extensions/runner.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/extensions/types.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/extensions/wrapper.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/footer-data-provider.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/http-dispatcher.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/index.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/keybindings.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/messages.ts` | `LeanAgent.CodingAgent.Messages` | implemented | bash/compaction/branch prefixes + convertCustomToLlm subset (`testCodingAgentMessagesAndProviderNames`). |
| `src/core/model-registry.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/model-resolver.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/output-guard.ts` | — | deferred | Exclusion: Node `process.stdout.write` takeover / raw stdout queue — not portable to Lean IO. |
| `src/core/package-manager.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/project-trust.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/prompt-templates.ts` | `LeanAgent.CodingAgent.PromptTemplates` | implemented | `parseCommandArgs`/`substituteArgs`/`expandPromptTemplate` + `loadPromptTemplates` (global/project/explicit) with argument-hint frontmatter (`testCodingAgentPromptTemplates*`); ported full Pi `prompt-templates.test.ts` matrix. |
| `src/core/provider-attribution.ts` | `LeanAgent.CodingAgent.ProviderAttribution` | partial | Host match + OpenRouter/NVIDIA/Cloudflare/Vercel headers (`testCodingAgentProviderAttribution`); hostMatch added; isOpenCode added. OpenCode host path open. |
| `src/core/provider-display-names.ts` | `LeanAgent.CodingAgent.ProviderDisplayNames` | implemented | BUILT_IN map + getProviderDisplayName (`testCodingAgentMessagesAndProviderNames`). |
| `src/core/resolve-config-value.ts` | `LeanAgent.CodingAgent.ResolveConfigValue` | partial | `$VAR`/`${VAR}` template + env resolve offline; `!command` detected but not executed (`testCodingAgentResolveConfigValue`); resolve added. |
| `src/core/resource-loader.ts` | `LeanAgent.Project.buildSystemPrompt` | partial | AGENTS.md/CLAUDE.md load; not full resource loader; loadResource added. |
| `src/core/sdk.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/session-cwd.ts` | `LeanAgent.CodingAgent.SessionCwd` | implemented | missing-cwd issue/error/prompt/assert (`testCodingAgentSessionCwd`); assertCwd added. |
| `src/core/session-manager.ts` | `LeanAgent.CodingAgent.SessionManager` | partial | create/list/open/append over JsonlSessionRepo (`testCodingAgentSessionManagerAndAgentSession`); createSession added. Not full tree migrate/list progress. |
| `src/core/settings-manager.ts` | `LeanAgent.CodingTools / Main / Project` | partial | settingsManager stub added. |
| `src/core/skills.ts` | `LeanAgent.CodingAgent.Skills` | partial | SKILL.md frontmatter parse + project skill infos (`testCodingAgentSkillsParse`); skillCollides helper added; ignore/collision matrix open; loadProjectSkill added. |
| `src/core/slash-commands.ts` | `LeanAgent.CodingTools / Main / Project` | partial | slashCommands stub added. |
| `src/core/source-info.ts` | `LeanAgent.CodingAgent.PromptTemplates.SourceInfo` | partial | `SourceInfo` (path/source/scope/origin/baseDir) + `SourceScope`/`SourceOrigin` modeled in PromptTemplates; `createSyntheticSourceInfo` used by `loadPromptTemplates`. Not full `PathMetadata`/package-manager integration. |
| `src/core/telemetry.ts` | `LeanAgent.CodingAgent.Telemetry` | implemented | `isTruthyEnvFlag` (1/true/yes, case-insensitive) + `isInstallTelemetryEnabled` (env override over settings default) (`testCodingAgentTelemetryFlag`). |
| `src/core/timings.ts` | `LeanAgent.CodingAgent.Timings` | implemented | `PI_TIMING=1`-gated profiler: `TimingRegistry`, `resetTimings`, `time` (per-namespace delta with injectable clock), `printTimings`/`formatTimingGroup` (negative-delta filter + total) (`testCodingAgentTimings`). |
| `src/core/tools/bash.ts` | `LeanAgent.CodingTools.makeBashTool` | partial |  |
| `src/core/tools/edit-diff.ts` | `LeanAgent.CodingTools / Main / Project` | partial | editDiff stub added. |
| `src/core/tools/edit.ts` | `LeanAgent.CodingTools.makeEditTool` | partial |  |
| `src/core/tools/file-mutation-queue.ts` | `LeanAgent.CodingTools / Main / Project` | partial | fileMutationQueue stub added. |
| `src/core/tools/find.ts` | `LeanAgent.CodingTools.makeFindTool` | partial | fd/find-backed; findTool stub added. |
| `src/core/tools/grep.ts` | `LeanAgent.CodingTools.makeGrepTool` | partial | rg-backed |
| `src/core/tools/index.ts` | `LeanAgent.CodingTools.defaultTools` | partial | subset of allToolNames |
| `src/core/tools/ls.ts` | `LeanAgent.CodingTools.makeListTool` | partial | list tool |
| `src/core/tools/output-accumulator.ts` | `LeanAgent.CodingTools / Main / Project` | partial | outputAccumulator stub added. |
| `src/core/tools/path-utils.ts` | `LeanAgent.CodingTools / Main / Project` | partial | pathUtils stub added. |
| `src/core/tools/read.ts` | `LeanAgent.CodingTools.makeReadTool` | partial | cwd-sandbox read; readTool stub added. |
| `src/core/tools/render-utils.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/tools/tool-definition-wrapper.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/core/tools/truncate.ts` | `LeanAgent.Agent.Harness.Truncate` | implemented | Shared dual-limit (lines+bytes) truncation `truncateHead`/`truncateTail`/`truncateLine` + `TruncationResult` (`truncatedBy`/`firstLineExceedsLimit`/`lastLinePartial`) + `formatSize`/`utf8ByteLength`; constants `DEFAULT_MAX_LINES`/`DEFAULT_MAX_BYTES`/`GREP_MAX_LINE_LENGTH`. Covered by `testHarnessTruncate`. |
| `src/core/tools/write.ts` | `LeanAgent.CodingTools.makeWriteTool` | partial | writeTool stub added. |
| `src/index.ts` | `LeanAgent.CodingTools / Main / Project` | partial | toolsIndex stub added. |
| `src/main.ts` | `Main.lean` | partial | MVP CLI flags only |
| `src/migrations.ts` | `LeanAgent.CodingAgent.Migrations` | implemented | `migrateAuthToAuthJson`/`migrateSessionsFromAgentRoot`/`migrateCommandsToPrompts`/`migrateToolsToBin`/`checkDeprecatedExtensionDirs`/`runMigrations` + `encodeSessionDir` (`testCodingAgentMigrations*`); interactive keypress wait + POSIX 0o600 mode + keybindings.json migration (needs `core/keybindings.ts`) documented as subset. |
| `src/modes/index.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/armin.ts` | `LeanAgent.CodingTools / Main / Project` | partial | armin stub added. |
| `src/modes/interactive/components/assistant-message.ts` | `LeanAgent.CodingTools / Main / Project` | partial | assistantMessage stub added. |
| `src/modes/interactive/components/bash-execution.ts` | `LeanAgent.CodingTools / Main / Project` | partial | bashExecution stub added. |
| `src/modes/interactive/components/bordered-loader.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/branch-summary-message.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/compaction-summary-message.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/config-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/countdown-timer.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/custom-editor.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/custom-message.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/daxnuts.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/diff.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/dynamic-border.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/earendil-announcement.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/extension-editor.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/extension-input.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/extension-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/first-time-setup.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/footer.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/index.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/keybinding-hints.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/login-dialog.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/model-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/oauth-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/scoped-models-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/session-selector-search.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/session-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/settings-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/show-images-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/skill-invocation-message.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/theme-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/thinking-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/tool-execution.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/tree-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/trust-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/user-message-selector.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/user-message.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/components/visual-truncate.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/interactive-mode.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/model-search.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/theme/theme-controller.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/interactive/theme/theme.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/print-mode.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/rpc/jsonl.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/rpc/rpc-client.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/rpc/rpc-mode.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/modes/rpc/rpc-types.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/package-manager-cli.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/rpc-entry.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/ansi.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/changelog.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/child-process.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/clipboard-image.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/clipboard-native.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/clipboard.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/deprecation.ts` | `LeanAgent.CodingAgent.Utils.Deprecation` | implemented | once-only warn + clear for tests (`testCodingAgentDeprecationAndFrontmatter`). |
| `src/utils/exif-orientation.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/frontmatter.ts` | `LeanAgent.CodingAgent.Utils.Frontmatter` | partial | strip/extract + simple key:value parse offline (no full YAML). |
| `src/utils/fs-watch.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/git.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/highlight-js-lib-index.d.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/html.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/image-convert.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/image-process.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/image-resize-core.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/image-resize-worker.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/image-resize.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/json.ts` | `LeanAgent.CodingAgent.Utils.JsonComments` | implemented | stripJsonComments offline (`testCodingAgentUtilsDiagnosticsPaths`). |
| `src/utils/mime.ts` | `LeanAgent.CodingAgent.Utils.Mime` | partial | JPEG/PNG/GIF/WEBP magic sniff offline (`testCodingAgentMimeSniff`); BMP/APNG edge cases open. |
| `src/utils/open-browser.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/paths.ts` | `LeanAgent.CodingAgent.Utils.Paths` | partial | isLocalPath/normalizePath/canonicalizePath offline subset. |
| `src/utils/photon.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/pi-user-agent.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/shell.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/sleep.ts` | `LeanAgent.CodingAgent.Utils.Sleep` | implemented | abort-aware sleep (`testCodingAgentUtilsDiagnosticsPaths`). |
| `src/utils/syntax-highlight.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/tools-manager.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/version-check.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |
| `src/utils/windows-self-update.ts` | `LeanAgent.CodingTools / Main / Project` | missing |  |

## Rules

- Do not mark `implemented` without shipped-API offline tests.
- Do not use `deferred` except Exclusion List in FULL_PI_PORT_PROMPT §7.
- Update this file whenever status changes.

