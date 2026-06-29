# AI Parity Ledger

This file tracks LeanAgent parity with Pi `packages/ai`. It is the source of
truth for preventing AI-module omissions.

Reference root: `vendor/pi/packages/ai`

Current Pi package version: `@earendil-works/pi-ai` `0.80.2`

## Status Legend

| Status | Meaning |
| --- | --- |
| `implemented` | Lean has equivalent behavior and tests. |
| `partial` | Lean has a subset, or behavior is API-compatible only for selected providers. |
| `missing` | No Lean equivalent exists yet. |
| `deferred` | Intentionally not implemented in the current milestone, with a reason. |

Every row must move through this ledger before it is considered complete.

## Current Lean Coverage

| Pi area | Lean modules | Status | Notes |
| --- | --- | --- | --- |
| HTTP transport | `LeanAgent.Http`, `LeanAgent.AI.Util.Proxy` | partial | Native libcurl JSON POST, custom request headers, parsed response headers, no-proxy support, and proxy env helper logic exist. Streaming callbacks and explicit proxy injection for non-libcurl transports are missing. |
| OpenAI-compatible chat completions | `LeanAgent.AI.Api.OpenAICompletions`, `LeanAgent.OpenAI` | partial | Protocol logic now lives under `AI.Api`; legacy `LeanAgent.OpenAI` is a compatibility wrapper. Non-streaming Chat Completions, streaming request path through `streamSimple`, SSE chunk parsing, text/thinking/tool delta event reconstruction, tool calls, empty-tools omission, tool history handling, basic option/header serialization, prompt cache payload fields, usage parsing, retry policy, and provider error diagnostics exist. Native callback-style live streaming transport, images, and Responses API are missing. |
| Static model catalog | `LeanAgent.Models` | partial | Starter catalog covers DeepSeek, OpenAI fallback, OpenRouter, Groq, xAI, Cerebras, Together, and Fireworks representative OpenAI-compatible models. Generated full catalog and dynamic refresh are missing. |
| Provider/model collection | `LeanAgent.Models` | partial | Runtime provider collection now supports registration, lookup, refresh hooks, auth application, simple stream/complete dispatch, and default registration for the starter OpenAI-compatible provider family. OpenAI-compatible `streamSimple` uses the streaming request path but still buffers the response before returning events. Full generated catalog, dynamic providers, and callback-style live streaming are missing. |
| Agent-facing messages | `LeanAgent.Core`, `LeanAgent.AI.Types` | partial | Pi-style message/content/usage/diagnostic types and legacy conversions exist. Runtime still uses simplified `Core.AgentMessage`. |
| Images | `LeanAgent.AI.Types` | partial | Image content types exist. Image generation APIs and image model catalog are missing. |
| OAuth/auth store | `LeanAgent.AI.Auth` | partial | Env API-key auth, auth context, in-memory credentials, and provider auth resolution exist. OAuth and file-backed stores are missing. |
| Compat/global API registry | none | missing | No `compat` registry or legacy global entrypoint. |

## Implementation Gates

Before implementing Pi `packages/agent` features that depend on AI:

1. Define AI types first: content blocks, messages, tools, usage, stream events, stop reasons.
2. Add a stream/result abstraction, even if an API starts as non-streaming internally.
3. Move auth resolution out of `Main.lean` and into a Pi-style provider/model layer.
4. Implement OpenAI-compatible APIs as API modules, not as CLI-specific provider helpers.
5. Add tests mapped from Pi tests for every completed row.

Before starting OMP advanced work:

1. `Models` collection must support provider registration, lookup, auth application, and completion dispatch.
2. OpenAI-compatible provider family must be solid enough for DeepSeek, OpenAI, OpenRouter, Groq, xAI, Cerebras, Together, and similar providers.
3. Agent core must consume AI stream events rather than direct provider responses.

## Source Inventory

| Group | Pi files | Lean target | Current status |
| --- | ---: | --- | --- |
| Root entrypoints and package API | 16 | `LeanAgent.AI`, `LeanAgent.Models`, `LeanAgent.Compat`, docs | partial |
| API protocol implementations | 28 | `LeanAgent.AI.Api.*` | partial |
| Auth | 5 | `LeanAgent.AI.Auth.*` | partial |
| Providers and model catalogs | 74 | `LeanAgent.AI.Providers.*`, generated/catalog data | partial |
| Utils | 14 | `LeanAgent.AI.Util.*` | partial |
| Tests | 83+ | `Tests.lean`, future focused test modules | partial |

## Root Entrypoints

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `src/index.ts` | `LeanAgent.AI` or `LeanAgent.lean` exports | partial | Lean root exports modules, but not Pi AI public surface. |
| `src/compat.ts` | `LeanAgent.AI.Compat` | missing | Needs global API registry and legacy helpers. |
| `src/cli.ts` | future `lean-agent ai ...` commands | missing | Not needed for core loop yet. |
| `src/models.ts` | `LeanAgent.Models` | partial | Static catalog plus runtime `Provider`/`Collection`, `createModels`, `createProvider`, auth application, and simple completion dispatch. Generated catalog and full provider family are missing. |
| `src/models.generated.ts` | generated Lean catalog or checked-in catalog | partial | Lean has a hand-curated starter catalog for key OpenAI-compatible providers. Full generated catalog parity is missing. |
| `src/types.ts` | `LeanAgent.AI.Types` | partial | Core content/message/usage/stream-option types exist. Provider-specific compat and full stream runtime still missing. |
| `src/env-api-keys.ts` | `LeanAgent.AI.Auth` | partial | Env API-key auth exists for registered providers. Full provider env map and ambient credential probes are missing. |
| `src/session-resources.ts` | `LeanAgent.AI.SessionResources` | missing | Needed for cross-provider handoff and session resources. |
| `src/legacy-api-aliases.ts` | `LeanAgent.AI.Compat.Aliases` | missing | Needed only when compat API is implemented. |
| `src/oauth.ts` | `LeanAgent.AI.OAuth` | missing | Depends on auth and device-code support. |
| `src/bedrock-provider.ts` | `LeanAgent.AI.Providers.Bedrock` | missing | Depends on AWS/Bedrock support. |
| `src/image-models.ts` | `LeanAgent.AI.Images.Models` | missing | Image phase. |
| `src/image-models.generated.ts` | generated image model catalog | missing | Image phase. |
| `src/images-models.ts` | `LeanAgent.AI.Images.Models` | missing | Image phase. |
| `src/images.ts` | `LeanAgent.AI.Images` | missing | Image generation API. |
| `src/images-api-registry.ts` | `LeanAgent.AI.Images.Registry` | missing | Image API dispatch. |

## Types Layer

Pi `src/types.ts` is a hard prerequisite. Lean should add `LeanAgent/AI/Types.lean`
before expanding provider behavior.

| Contract | Lean target | Status | Notes |
| --- | --- | --- | --- |
| API/provider identifiers | `LeanAgent.AI.Types` | implemented | Central string aliases exist for text and image APIs/providers. |
| Text/image content blocks | `LeanAgent.AI.Types` | implemented | Text, thinking, image, and tool-call content blocks exist with JSON helpers. |
| User/assistant/tool result messages | `LeanAgent.AI.Types` | partial | Pi-style messages exist with JSON helpers. Runtime migration from `Core.AgentMessage` is not complete. |
| Tool schema and tool call content | `LeanAgent.AI.Types`, `LeanAgent.AI.Schema`, `LeanAgent.AI.Validation` | partial | Tool call exists, with JSON Schema subset validation/coercion. Full TypeBox/AJV parity is missing. |
| Assistant stream events | `LeanAgent.AI.Types`, `LeanAgent.AI.EventStream`, `LeanAgent.AI.Util.SSE`, `LeanAgent.Loop` | partial | Event data types, stream/result container, partial snapshots, SSE parser, OpenAI streaming response parser, and agent-loop bridge exist. Async iteration and native callback-style live provider streaming are still missing. |
| Usage and cost | `LeanAgent.AI.Types`, `LeanAgent.Core`, `LeanAgent.AI.Api.OpenAICompletions` | partial | Usage/cost types, JSON helpers, legacy provider usage bridge, and OpenAI-compatible token parsing exist. Model-price cost calculation is not wired into provider responses. |
| Stop reasons and errors | `LeanAgent.AI.Types`, `LeanAgent.AI.Util.Diagnostics`, `LeanAgent.Http` | partial | Stop reason types, assistant diagnostics, provider error extraction, and transport response header capture exist. Error stacks and provider `onResponse`/diagnostic header surfacing are incomplete. |
| Thinking/reasoning levels | `LeanAgent.AI.Types` | partial | Thinking level types exist. Model thinking-level maps/helpers still missing. |
| Simple stream options | `LeanAgent.AI.Types` | partial | Core option fields exist. Callback/abort semantics and provider-specific options are missing. |

## Models Runtime

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `Provider` interface | `LeanAgent.Models.Provider` | partial | Runtime unit has id/name/base metadata, auth, model listing, refresh hook, and `streamSimple`/`completeSimple`. Generic typed stream APIs and live async streams are missing. |
| `Models` interface | `LeanAgent.Models.Collection` | partial | Collection supports provider registration, lookup, best-effort model listing, refresh, auth application, `streamSimple`, and `completeSimple`. |
| `MutableModels` | `LeanAgent.Models.Collection` | implemented | `setProvider`, `deleteProvider`, and `clearProviders` exist with tests through runtime dispatch. |
| `createModels` | `LeanAgent.Models.Collection` | implemented | Constructor accepts credential store/auth context and defaults to in-memory credentials. |
| `createProvider` | `LeanAgent.Models.Provider` | partial | Single/mapped API dispatch, refresh state, and lazy setup/load error streams exist. Full mixed-API parity is still missing. |
| `hasApi` | `LeanAgent.Models` | implemented | Runtime API equality helper exists. |
| `calculateCost` | `LeanAgent.Models` | implemented | Pi-style per-million token cost calculation exists, including 1h cache-write multiplier. |
| `getSupportedThinkingLevels` | `LeanAgent.Models` | partial | Basic reasoning/off mapping exists. Model-specific thinking-level maps are missing. |
| `clampThinkingLevel` | `LeanAgent.Models` | partial | Basic clamp exists. Model-specific map/null suppression is missing. |
| `modelsAreEqual` | `LeanAgent.Models` | implemented | Compares provider and model id. |

## Auth Layer

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `auth/types.ts` | `LeanAgent.AI.Auth` | partial | API-key credential, auth result, provider auth, auth context, and credential store contracts exist. OAuth contracts are missing. |
| `auth/context.ts` | `LeanAgent.AI.Auth` | partial | Default env/file-existence context exists with `~` expansion. Browser-specific behavior is not relevant yet. |
| `auth/credential-store.ts` | `LeanAgent.AI.Auth` | partial | In-memory credential store exists. Serialized/file-backed storage is missing. |
| `auth/helpers.ts` | `LeanAgent.AI.Auth` | partial | Env API-key auth helper exists. OAuth/lazy OAuth and ambient provider helpers are missing. |
| `auth/resolve.ts` | `LeanAgent.AI.Auth` | partial | API-key provider auth resolution with request overrides exists. OAuth refresh/error codes are missing. |

## API Protocol Implementations

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `api/lazy.ts` | `LeanAgent.AI.Api.Lazy`, `LeanAgent.Models.ProviderStreams.lazy` | implemented | Lean does not dynamically import TS modules, but the equivalent boundary exists: setup/load failures become assistant error streams, and provider dispatch uses it instead of throwing. |
| `api/simple-options.ts` | `LeanAgent.AI.Api.SimpleOptions`, `LeanAgent.AI.Types`, `LeanAgent.Models`, `LeanAgent.AI.Api.OpenAICompletions`, `LeanAgent.AI.Api.OpenAIResponses` | partial | Simple option fields exist and are applied to OpenAI-compatible and Responses payloads/headers. Context-aware `maxTokens` clamping now uses estimated context tokens plus a 4096-token safety margin, preserves explicit request caps, defaults to model max output when known, and avoids emitting a synthetic cap when model max output is unknown. `onPayload` and `onResponse` hooks can inspect/replace JSON payloads and observe HTTP status/headers on both OpenAI-compatible and Responses runtimes. `adjustMaxTokensForThinking` matches Pi default/custom thinking budgets and xhigh-to-high clamping. Abort signals remain missing. |
| `api/openai-completions.ts` | `LeanAgent.AI.Api.OpenAICompletions` | partial | Refactored into an API module with legacy wrapper, payload/header serialization, non-streaming completion, streaming request/response parsing, text/thinking/tool delta events, tool calls, empty-tools behavior, tool-history tools array, prompt cache payload fields, usage parsing, retry policy, provider error diagnostics, basic reasoning/max-token/temperature/tool-choice options, and response parsing. Native callback-style live SSE transport, images, and full compat matrix are missing. |
| `api/openai-completions.lazy.ts` | `LeanAgent.AI.Api.OpenAICompletions` | deferred | Lean does not need TS lazy import; dispatch boundary is explicit through `ProviderStreams`. |
| `api/openai-responses.ts` | `LeanAgent.AI.Api.OpenAIResponses` | partial | Responses request payload construction, prompt-cache/session affinity fields, cache-affinity/custom headers, GitHub Copilot dynamic headers, non-streaming HTTP completion, provider error handling, usage parsing, reasoning/message/function-call output parsing, streaming SSE event parsing, terminal-event enforcement, tool-call argument delta handling, and HTTP streaming wrapper exist. SDK-equivalent request hooks, service-tier cost multipliers, and provider dispatch integration are still missing. |
| `api/openai-responses-shared.ts` | `LeanAgent.AI.Api.OpenAIResponsesShared` | partial | Shared message/tool serialization now converts system/user/assistant/tool-result replay items, consumes `TransformMessages`, normalizes OpenAI Responses tool-call IDs including foreign `fc_<hash>` item IDs, omits different-model `fc_` item IDs to avoid pairing validation, serializes image-capable tool outputs, and converts tools with `strict`. Streaming event parsing, usage conversion, service-tier pricing, and full Responses request runtime remain missing. |
| `api/openai-responses.lazy.ts` | `LeanAgent.AI.Api.OpenAIResponses` | deferred | Lazy wrapper can be skipped if dispatch is explicit. |
| `api/openai-codex-responses.ts` | `LeanAgent.AI.Api.OpenAICodexResponses` | missing | OAuth and WebSocket/cached transport later. |
| `api/openai-codex-responses.lazy.ts` | `LeanAgent.AI.Api.OpenAICodexResponses` | deferred | Lazy wrapper. |
| `api/azure-openai-responses.ts` | `LeanAgent.AI.Api.AzureOpenAIResponses` | missing | Needs Azure base URL handling. |
| `api/azure-openai-responses.lazy.ts` | `LeanAgent.AI.Api.AzureOpenAIResponses` | deferred | Lazy wrapper. |
| `api/anthropic-messages.ts` | `LeanAgent.AI.Api.AnthropicMessages` | missing | Large protocol, thinking, cache, tool normalization. |
| `api/anthropic-messages.lazy.ts` | `LeanAgent.AI.Api.AnthropicMessages` | deferred | Lazy wrapper. |
| `api/google-generative-ai.ts` | `LeanAgent.AI.Api.GoogleGenerativeAI` | missing | Gemini API. |
| `api/google-generative-ai.lazy.ts` | `LeanAgent.AI.Api.GoogleGenerativeAI` | deferred | Lazy wrapper. |
| `api/google-vertex.ts` | `LeanAgent.AI.Api.GoogleVertex` | missing | Vertex auth and endpoint handling. |
| `api/google-vertex.lazy.ts` | `LeanAgent.AI.Api.GoogleVertex` | deferred | Lazy wrapper. |
| `api/google-shared.ts` | `LeanAgent.AI.Api.GoogleShared` | missing | Tool conversion and thinking helpers. |
| `api/mistral-conversations.ts` | `LeanAgent.AI.Api.MistralConversations` | missing | Mistral protocol. |
| `api/mistral-conversations.lazy.ts` | `LeanAgent.AI.Api.MistralConversations` | deferred | Lazy wrapper. |
| `api/bedrock-converse-stream.ts` | `LeanAgent.AI.Api.BedrockConverseStream` | missing | AWS SDK equivalent needed or deferred with reason. |
| `api/bedrock-converse-stream.lazy.ts` | `LeanAgent.AI.Api.BedrockConverseStream` | deferred | Lazy wrapper. |
| `api/cloudflare.ts` | `LeanAgent.AI.Api.Cloudflare` | missing | Cloudflare gateway/workers helper. |
| `api/github-copilot-headers.ts` | `LeanAgent.AI.Api.GitHubCopilotHeaders` | implemented | Copilot initiator inference, vision input detection, dynamic `X-Initiator`, `Openai-Intent`, and `Copilot-Vision-Request` headers exist and are wired into OpenAI Responses requests. |
| `api/openai-prompt-cache.ts` | `LeanAgent.AI.Api.OpenAIPromptCache` | partial | Prompt cache key clamping and Chat Completions payload fields exist, including `cacheRetention=none`, `long`, and `PI_CACHE_RETENTION=long`. Session affinity headers and provider-specific long-cache suppression are missing. |
| `api/openrouter-images.ts` | `LeanAgent.AI.Api.OpenRouterImages` | missing | Image generation phase. |
| `api/openrouter-images.lazy.ts` | `LeanAgent.AI.Api.OpenRouterImages` | deferred | Lazy wrapper. |
| `api/transform-messages.ts` | `LeanAgent.AI.Api.TransformMessages` | partial | Provider-agnostic conversion covers non-vision image placeholders, cross-model thinking/text signature downgrade, foreign tool thought-signature removal, callback-driven tool-call id normalization with tool-result remapping, skipped errored/aborted assistant turns, and synthetic no-result tool results for orphaned calls. Provider-specific normalizers and live cross-provider handoff matrix are still missing. |

## Provider Factories

All provider factory files must have a corresponding row. Model catalog files
should be generated or checked in as Lean data.

| Provider | Pi files | Lean target | Status |
| --- | --- | --- | --- |
| All builtins | `providers/all.ts` | `LeanAgent.AI.Providers.All` | missing |
| Amazon Bedrock | `amazon-bedrock.ts`, `amazon-bedrock.models.ts` | `LeanAgent.AI.Providers.AmazonBedrock` | missing |
| Ant Ling | `ant-ling.ts`, `ant-ling.models.ts` | `LeanAgent.AI.Providers.AntLing` | missing |
| Anthropic | `anthropic.ts`, `anthropic.models.ts` | `LeanAgent.AI.Providers.Anthropic` | missing |
| Azure OpenAI Responses | `azure-openai-responses.ts`, `azure-openai-responses.models.ts` | `LeanAgent.AI.Providers.AzureOpenAIResponses` | missing |
| Cerebras | `cerebras.ts`, `cerebras.models.ts` | `LeanAgent.Models` | partial |
| Cloudflare AI Gateway | `cloudflare-ai-gateway.ts`, `cloudflare-ai-gateway.models.ts` | `LeanAgent.AI.Providers.CloudflareAIGateway` | missing |
| Cloudflare Workers AI | `cloudflare-workers-ai.ts`, `cloudflare-workers-ai.models.ts` | `LeanAgent.AI.Providers.CloudflareWorkersAI` | missing |
| Cloudflare auth | `cloudflare-auth.ts` | `LeanAgent.AI.Providers.CloudflareAuth` | missing |
| DeepSeek | `deepseek.ts`, `deepseek.models.ts` | `LeanAgent.Models` | partial |
| Faux test provider | `faux.ts` | `LeanAgent.AI.Providers.Faux` | partial |
| Fireworks | `fireworks.ts`, `fireworks.models.ts` | `LeanAgent.Models` | partial |
| GitHub Copilot | `github-copilot.ts`, `github-copilot.models.ts` | `LeanAgent.AI.Providers.GitHubCopilot` | missing |
| Google | `google.ts`, `google.models.ts` | `LeanAgent.AI.Providers.Google` | missing |
| Google Vertex | `google-vertex.ts`, `google-vertex.models.ts` | `LeanAgent.AI.Providers.GoogleVertex` | missing |
| Groq | `groq.ts`, `groq.models.ts` | `LeanAgent.Models` | partial |
| Hugging Face | `huggingface.ts`, `huggingface.models.ts` | `LeanAgent.AI.Providers.HuggingFace` | missing |
| Kimi Coding | `kimi-coding.ts`, `kimi-coding.models.ts` | `LeanAgent.AI.Providers.KimiCoding` | missing |
| MiniMax | `minimax.ts`, `minimax.models.ts` | `LeanAgent.AI.Providers.MiniMax` | missing |
| MiniMax CN | `minimax-cn.ts`, `minimax-cn.models.ts` | `LeanAgent.AI.Providers.MiniMaxCN` | missing |
| Mistral | `mistral.ts`, `mistral.models.ts` | `LeanAgent.AI.Providers.Mistral` | missing |
| Moonshot AI | `moonshotai.ts`, `moonshotai.models.ts` | `LeanAgent.AI.Providers.MoonshotAI` | missing |
| Moonshot AI CN | `moonshotai-cn.ts`, `moonshotai-cn.models.ts` | `LeanAgent.AI.Providers.MoonshotAICN` | missing |
| NVIDIA | `nvidia.ts`, `nvidia.models.ts` | `LeanAgent.AI.Providers.NVIDIA` | missing |
| OpenAI | `openai.ts`, `openai.models.ts` | `LeanAgent.Models` | partial |
| OpenAI Codex | `openai-codex.ts`, `openai-codex.models.ts` | `LeanAgent.AI.Providers.OpenAICodex` | missing |
| OpenCode | `opencode.ts`, `opencode.models.ts` | `LeanAgent.AI.Providers.OpenCode` | missing |
| OpenCode Go | `opencode-go.ts`, `opencode-go.models.ts` | `LeanAgent.AI.Providers.OpenCodeGo` | missing |
| OpenRouter | `openrouter.ts`, `openrouter.models.ts` | `LeanAgent.Models` | partial |
| OpenRouter images | `openrouter-images.ts` | `LeanAgent.AI.Providers.OpenRouterImages` | missing |
| Together | `together.ts`, `together.models.ts` | `LeanAgent.Models` | partial |
| Vercel AI Gateway | `vercel-ai-gateway.ts`, `vercel-ai-gateway.models.ts` | `LeanAgent.AI.Providers.VercelAIGateway` | missing |
| xAI | `xai.ts`, `xai.models.ts` | `LeanAgent.Models` | partial |
| Xiaomi | `xiaomi.ts`, `xiaomi.models.ts` | `LeanAgent.AI.Providers.Xiaomi` | missing |
| Xiaomi Token Plan AMS | `xiaomi-token-plan-ams.ts`, `xiaomi-token-plan-ams.models.ts` | `LeanAgent.AI.Providers.XiaomiTokenPlanAMS` | missing |
| Xiaomi Token Plan CN | `xiaomi-token-plan-cn.ts`, `xiaomi-token-plan-cn.models.ts` | `LeanAgent.AI.Providers.XiaomiTokenPlanCN` | missing |
| Xiaomi Token Plan SGP | `xiaomi-token-plan-sgp.ts`, `xiaomi-token-plan-sgp.models.ts` | `LeanAgent.AI.Providers.XiaomiTokenPlanSGP` | missing |
| ZAI | `zai.ts`, `zai.models.ts` | `LeanAgent.AI.Providers.ZAI` | missing |
| ZAI Coding CN | `zai-coding-cn.ts`, `zai-coding-cn.models.ts` | `LeanAgent.AI.Providers.ZAICodingCN` | missing |

## Utils

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `utils/abort-signals.ts` | `LeanAgent.AI.Util.Abort` | missing | Lean cancellation model needs separate design. |
| `utils/diagnostics.ts` | `LeanAgent.AI.Util.Diagnostics`, `LeanAgent.Http` | partial | Diagnostic error info, assistant message diagnostics, append helper, provider error body extraction, and response header capture exist. Exact JS thrown-value/stack behavior and assistant-level response-header diagnostics are incomplete. |
| `utils/estimate.ts` | `LeanAgent.AI.Util.Estimate` | implemented | Pi-style context/message/token estimation exists, including usage-anchor trailing-token logic, image estimate, and UTF-16 text length behavior. |
| `utils/event-stream.ts` | `LeanAgent.AI.EventStream`, `LeanAgent.AI.Util.SSE`, `LeanAgent.Loop` | partial | Synchronous event/result container, partial snapshot reconstruction, buffered SSE response parsing, legacy provider wrapper, and loop consumption bridge exist. Async iteration/backpressure and live transport callbacks are not implemented. |
| `utils/hash.ts` | `LeanAgent.AI.Util.Hash` | implemented | Pi-compatible deterministic `shortHash`, including UTF-16 code-unit behavior, exists with golden tests. |
| `utils/headers.ts` | `LeanAgent.AI.Util.Headers`, `LeanAgent.Http`, `LeanAgent.AI.Api.OpenAICompletions`, `LeanAgent.AI.Api.OpenAIResponses` | partial | Provider header filtering, case-insensitive merge/override behavior, custom request headers, response header parsing, and OpenAI-compatible/Responses `onResponse` hook integration exist. Cross-provider callback coverage is still missing. |
| `utils/json-parse.ts` | `LeanAgent.Json`, `LeanAgent.AI.Util.JsonParse` | partial | Malformed string repair, parse-with-repair, empty streaming fallback, and basic partial object closure exist. Full `partial-json` behavior for arbitrary incomplete structures is missing. |
| `utils/node-http-proxy.ts` | `LeanAgent.AI.Util.Proxy` | partial | Provider-scoped/ambient proxy env lookup, default port mapping, `NO_PROXY` host/port matching, inferred proxy protocols, and HTTP(S)-only validation exist. Full WHATWG URL parsing and transport integration beyond libcurl are incomplete. |
| `utils/overflow.ts` | `LeanAgent.AI.Util.Overflow` | partial | Common provider overflow messages, non-overflow throttling/rate-limit exclusions, silent usage overflow, and length-stop full-context heuristics exist. Full JS regex parity remains incomplete. |
| `utils/provider-env.ts` | `LeanAgent.AI.Util.ProviderEnv` | implemented | Scoped provider env lookup, ambient env fallback, empty-value suppression, and merge semantics exist. Bun-specific `/proc/self/environ` fallback is not applicable to Lean. |
| `utils/retry.ts` | `LeanAgent.AI.Util.Retry` | partial | Retryable assistant/provider error classification, non-retryable quota guard, delay cap, and OpenAI-compatible request retry policy exist. Full Pi regex coverage and cross-provider retry integration are incomplete. |
| `utils/sanitize-unicode.ts` | `LeanAgent.AI.Util.SanitizeUnicode` | partial | Lean string sanitizer preserves valid Unicode, and a UTF-16 code-unit helper removes unpaired high/low surrogates while preserving valid pairs. Provider serialization integration is not wired yet. |
| `utils/typebox-helpers.ts` | `LeanAgent.AI.Schema` | partial | `stringEnum` helper exists for provider-compatible string enum schemas. Full TypeBox helper surface is not implemented. |
| `utils/validation.ts` | `LeanAgent.AI.Validation`, `LeanAgent.AI.Schema` | partial | Tool lookup, argument validation, JSON Schema primitive coercion, required/object/array/enum checks, and formatted validation errors exist. Full TypeBox compiler/AJV behavior, symbol metadata, and all JSON Schema keywords are incomplete. |

## Images

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `images.ts` | `LeanAgent.AI.Images` | missing | Image generation API. |
| `images-models.ts` | `LeanAgent.AI.Images.Models` | missing | Runtime model types. |
| `image-models.ts` | `LeanAgent.AI.Images.Models` | missing | Static image model access. |
| `image-models.generated.ts` | generated Lean image catalog | missing | Generated or checked-in data. |
| `images-api-registry.ts` | `LeanAgent.AI.Images.Registry` | missing | Image API dispatch. |
| `api/openrouter-images.ts` | `LeanAgent.AI.Api.OpenRouterImages` | missing | First image provider candidate. |
| `providers/openrouter-images.ts` | `LeanAgent.AI.Providers.OpenRouterImages` | missing | Image provider factory. |

## Test Mapping

Initial Lean parity should port tests in this order:

| Pi tests | Lean target | Status | Why first |
| --- | --- | --- | --- |
| `models-runtime.test.ts`, `providers.test.ts`, `supports-xhigh.test.ts`, `xhigh.test.ts` | model catalog and thinking tests | partial | Protects provider/model registry. |
| `env-api-keys.test.ts`, `compat-env.test.ts` | auth/env tests | partial | Env API-key and stored credential precedence are covered. Full provider env map and compat env tests are missing. |
| `stream.test.ts`, `empty.test.ts`, `abort.test.ts` | event stream tests | partial | Stream result, text/thinking/tool events, partial snapshots, tool delta payloads, and empty-content completion are covered in Lean. Async iterator/backpressure, provider abort behavior, and live timing remain missing. |
| `openai-completions-*.test.ts` | OpenAI completions tests | partial | Payload tests cover empty tools, tool history, tool choice, max tokens, temperature, reasoning effort, prompt cache key/retention, streaming payload/SSE parsing, buffered streaming runtime dispatch, request/response headers, usage parsing, provider HTTP diagnostics, repaired tool arguments, and legacy assistant tool-call omission. Network provider matrix and true live-stream timing tests are missing. |
| `retry.test.ts`, `diagnostics.test.ts`, `estimate.test.ts`, `overflow.test.ts`, `validation.test.ts`, `unicode-surrogate.test.ts` | util tests | partial | Retry classifier/policy, diagnostics extraction/round-trip, estimate utilities, provider header filtering/merge, proxy env resolution, JSON repair/streaming fallback, JSON Schema validation/coercion, Unicode surrogate sanitization helpers, overflow detection, and OpenAI transient HTTP retry are covered. Live provider unicode-surrogate tests are missing. |
| `faux-provider.test.ts` | faux provider tests | partial | Deterministic provider handle, queued responses, helper blocks, model-aware factories, usage/cache estimates, model rewrite, collection dispatch, and event reconstruction are covered. Global compat registration, async timing, and abort behavior are missing. |
| `images*.test.ts`, `openrouter-images.test.ts` | image tests | missing | Separate image phase. |
| Anthropic/Google/Mistral/Bedrock/Azure/Codex tests | provider protocol tests | missing | After core OpenAI-compatible path is stable. |

## Milestones

### M1: Core AI Types

Deliver:

- `LeanAgent.AI.Types` for content blocks, messages, tools, usage, stop reasons, stream options. Status: partial.
- Migration path from old `LeanAgent.Core.AgentMessage` to AI message types. Status: partial.
- Tests for serialization and basic content filtering. Status: partial.

Exit criteria:

- Existing CLI still runs.
- Old simplified messages are either wrappers around AI types or explicitly marked legacy.

### M2: Event Stream and Complete

Deliver:

- `LeanAgent.AI.EventStream` with event iteration/result semantics. Status: partial; sync stream containers and OpenAI SSE transcript reconstruction exist.
- Wrapper that turns current non-streaming `LeanAgent.OpenAI.provider` into a stream-compatible API. Status: partial; OpenAI streaming request/runtime path exists, native callback-style live transport is not wired.
- Tests mapped from `stream.test.ts` and `empty.test.ts`. Status: partial.

Exit criteria:

- Agent loop can consume stream events or complete results through the same boundary. Status: partial; current loop consumes buffered stream events, and OpenAI-compatible providers now use the streaming endpoint through `streamSimple`.

### M3: Models Collection and Auth

Deliver:

- Runtime `Models` collection with provider registration, lookup, refresh no-op for static providers. Status: partial; simple dispatch and lazy setup/load error streams exist, full dynamic provider behavior is missing.
- Env API key auth, in-memory credential store, auth resolution. Status: partial; OAuth and persistent stores are missing.
- `createProvider` for single API dispatch. Status: partial; API-map dispatch and lazy error stream behavior exist, but full mixed-provider parity is not complete.

Exit criteria:

- `Main.lean` no longer owns provider-specific auth/default resolution. Status: implemented for current DeepSeek/OpenAI CLI selection.
- Tests mapped from `models-runtime.test.ts`, `env-api-keys.test.ts`, and `providers.test.ts`. Status: partial; auth resolution, stored credential precedence, runtime lookup/dispatch, and cost calculation are covered.

### M4: OpenAI-Compatible API Family

Deliver:

- Refactor `LeanAgent.OpenAI` into `LeanAgent.AI.Api.OpenAICompletions`. Status: implemented structurally; `LeanAgent.OpenAI` is now a compatibility wrapper.
- Add prompt cache fields, retry, response diagnostics, tool choice behavior, empty tools behavior. Status: partial; prompt cache payload fields, retry policy, basic provider diagnostics, response header capture, tool choice, and empty-tools behavior exist. Full response diagnostics are incomplete because provider callbacks/live stream diagnostics are missing.
- Add provider factories for DeepSeek, OpenAI, OpenRouter, Groq, xAI, Cerebras, Together, Fireworks where they share OpenAI-compatible protocol. Status: partial; default runtime catalog has representative OpenAI-compatible models for each, but provider modules and full generated catalogs are missing.

Exit criteria:

- DeepSeek remains the default path. Status: implemented; catalog selection still checks DeepSeek first.
- OpenAI-compatible Pi tests that do not require live network are ported. Status: partial; payload, diagnostics, retry, and provider-family catalog tests exist, but full non-network Pi test coverage is incomplete.

### M5: Provider Protocol Expansion

Deliver in this order:

- Anthropic Messages.
- Google Generative AI and Google Vertex.
- Mistral Conversations.
- Azure OpenAI Responses.
- OpenAI Responses and Codex Responses.
- Bedrock Converse Stream.

Exit criteria:

- Each provider has factory, model catalog, auth semantics, and protocol tests before marking implemented.

### M6: Images and Compat

Deliver:

- Image content support in message types.
- Image generation registry and OpenRouter image provider.
- Compat/global API registry after new `Models` API is stable.

Exit criteria:

- Image tests pass.
- Compat API is a thin wrapper over the new model collection, not a second runtime.

## Rules for Updating This Ledger

- Every AI change must update this file in the same commit when status changes.
- New Lean modules must cite the Pi source row they are closing in commit notes or PR text.
- A row can become `implemented` only with tests or an explicit reason why runtime validation is impossible.
- `vendor/pi` is read-only. Do not edit reference files.
- Prefer behavior parity over line-by-line TypeScript translation.
