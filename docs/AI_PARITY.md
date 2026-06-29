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
| OpenAI-compatible chat completions | `LeanAgent.AI.Api.OpenAICompletions`, `LeanAgent.OpenAI`, `LeanAgent.Models` | partial | Protocol logic now lives under `AI.Api`; legacy `LeanAgent.OpenAI` is a compatibility wrapper. Non-streaming Chat Completions, streaming request path through `streamSimple`, SSE chunk parsing, text/thinking/tool delta event reconstruction, tool calls, empty-tools omission, tool history handling, basic option/header serialization, prompt cache payload fields, usage parsing, model-rate cost calculation through Models runtime, retry policy, provider error diagnostics, header-only auth dispatch, and OpenAI Responses request/stream dispatch exist. Native callback-style live streaming transport, images, and the full compat matrix are missing. |
| Static model catalog | `LeanAgent.Models` | partial | Starter catalog covers DeepSeek, OpenAI fallback, OpenRouter, Groq, xAI, Cerebras, Together, and Fireworks representative OpenAI-compatible models. Generated full catalog and dynamic refresh are missing. |
| Provider/model collection | `LeanAgent.Models` | partial | Runtime provider collection now supports registration, lookup, refresh hooks, auth application, auth-driven base URL/header overrides, simple stream/complete dispatch, default registration for the starter OpenAI-compatible provider family, generic OpenAI Responses dispatch, and Azure OpenAI Responses stream dispatch. OpenAI-compatible and Responses `streamSimple` paths use streaming request formats but still buffer the HTTP response before returning events. Full generated catalog, dynamic providers, and callback-style live streaming are missing. |
| Agent-facing messages | `LeanAgent.Core`, `LeanAgent.AI.Types` | partial | Pi-style message/content/usage/diagnostic types and legacy conversions exist. Runtime still uses simplified `Core.AgentMessage`. |
| Images | `LeanAgent.AI.Types`, `LeanAgent.AI.Images`, `LeanAgent.AI.Images.Registry`, `LeanAgent.AI.Api.OpenRouterImages`, `LeanAgent.AI.Images.Models` | partial | Image content/model/option/result types, global image API registry, API mismatch guard, source unregister/reset with built-in replay, runtime image provider collection, auth application, `generateImages` dispatch, OpenRouter Images provider factory/runtime, and the current Pi OpenRouter image model catalog exist. Shared auth can resolve stored OAuth credentials, but provider-specific OAuth image behavior, abort signals, and live provider matrix tests remain missing. |
| OAuth/auth store | `LeanAgent.AI.Auth`, `LeanAgent.AI.OAuth`, `LeanAgent.AI.EnvApiKeys`, `LeanAgent.AI.Providers.CloudflareAuth` | partial | Env API-key auth, Pi provider env-key map, auth context with injectable wall-clock milliseconds, in-memory and file-backed API-key/OAuth credentials, provider auth resolution, OAuth refresh/toAuth resolution under credential-store modify, OAuth provider registry, OAuth provider info list, high-level refresh/API-key helpers, model-aware base URL auth resolution, and Cloudflare Workers AI / AI Gateway auth helpers exist. OAuth login/device-code providers, lazy OAuth wrappers, file locks, and typed ModelsError codes are missing. |
| Compat/global API registry | `LeanAgent.AI.Compat`, `LeanAgent.AI.Compat.Aliases` | partial | Global API provider registry, built-in OpenAI-compatible/OpenAI Responses/Azure OpenAI Responses registrations, source-id unregister, reset, `streamSimple`/`completeSimple` dispatch, fixed-API legacy aliases, API mismatch guard, and Pi mapped provider env API-key injection exist. Full legacy static catalog exports, image entrypoints, typed full-stream options, and most non-OpenAI builtins are still missing. |

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
| `src/index.ts` | `LeanAgent.AI` or `LeanAgent.lean` exports | partial | Lean root exports core AI modules, OAuth registry helpers, and image dispatch modules, but not the full Pi AI public surface. |
| `src/compat.ts` | `LeanAgent.AI.Compat` | partial | Global registry, simple dispatch, and legacy alias support exist. Full legacy surface, static catalog passthroughs, image exports, faux compat registration, typed full-stream options, and all builtin APIs are still missing. |
| `src/cli.ts` | future `lean-agent ai ...` commands | missing | Not needed for core loop yet. |
| `src/models.ts` | `LeanAgent.Models` | partial | Static catalog plus runtime `Provider`/`Collection`, `createModels`, `createProvider`, auth application, and simple completion dispatch. Generated catalog and full provider family are missing. |
| `src/models.generated.ts` | generated Lean catalog or checked-in catalog | partial | Lean has a hand-curated starter catalog for key OpenAI-compatible providers. Full generated catalog parity is missing. |
| `src/types.ts` | `LeanAgent.AI.Types` | partial | Core content/message/usage/stream-option types and image model/option/result types exist. Provider-specific compat and full stream runtime still missing. |
| `src/env-api-keys.ts` | `LeanAgent.AI.EnvApiKeys`, `LeanAgent.AI.Auth` | partial | Full Pi provider env-key map exists, including Anthropic OAuth-token precedence, `findEnvKeys`, `getEnvApiKey`, Bedrock ambient credential marker, and Vertex explicit/default ADC path marker. File-backed API-key/OAuth storage exists in `LeanAgent.AI.Auth`; OAuth login flows are still tracked separately. |
| `src/session-resources.ts` | `LeanAgent.AI.SessionResources` | implemented | Global cleanup registry exists with unregister handles, optional session id propagation, and aggregate cleanup errors. |
| `src/legacy-api-aliases.ts` | `LeanAgent.AI.Compat.Aliases` | partial | Fixed-API legacy aliases exist for Anthropic, Azure OpenAI Responses, Google, Google Vertex, Mistral, OpenAI Codex Responses, OpenAI Completions, and OpenAI Responses. They dispatch through the compat registry with simple stream options; typed full-stream option parity is still missing. |
| `src/oauth.ts` | `LeanAgent.AI.OAuth` | partial | OAuth credential/auth resolution contracts exist in `LeanAgent.AI.Auth`; Lean also has OAuth prompt/info types, provider interface, provider registry, register/unregister/reset/list/info helpers, `refreshOAuthToken`, and `getOAuthApiKey` with expiry refresh. Built-in Anthropic/GitHub Copilot/OpenAI Codex login flows, device-code polling, provider refresh implementations, and model modification hooks are missing. |
| `src/bedrock-provider.ts` | `LeanAgent.AI.Providers.Bedrock` | missing | Depends on AWS/Bedrock support. |
| `src/image-models.ts` | `LeanAgent.AI.Images.Models` | implemented | Static image provider/model lookup helpers exist for the current Pi image catalog. |
| `src/image-models.generated.ts` | `LeanAgent.AI.Images.Models` | implemented | Current Pi generated OpenRouter image model list is checked in as Lean data with 37 models. |
| `src/images-models.ts` | `LeanAgent.AI.Images`, `LeanAgent.AI.Images.Models` | partial | Runtime image model type, lookup functions, mutable image provider collection, provider CRUD, model refresh, auth application, and error-as-result `generateImages` exist. Shared OAuth credential resolution exists; image-specific OAuth providers/tests remain missing. |
| `src/images.ts` | `LeanAgent.AI.Images` | partial | `generateImages` and explicit `generateImagesWithApi` dispatch through registered image API providers. OpenRouter Images is registered as a built-in provider. |
| `src/images-api-registry.ts` | `LeanAgent.AI.Images.Registry` | implemented | Image API provider registry supports register, lookup, list, source unregister, clear/reset, built-in replay, and Pi-style API mismatch wrapping. |

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
| Usage and cost | `LeanAgent.AI.Types`, `LeanAgent.Core`, `LeanAgent.Models`, `LeanAgent.AI.Api.OpenAICompletions`, `LeanAgent.AI.Api.OpenAIResponses` | partial | Usage/cost types, JSON helpers, legacy provider usage bridge, OpenAI-compatible token parsing, Responses usage parsing, OpenAI-compatible model-rate cost calculation through Models runtime, and Responses service-tier cost multipliers exist. Cross-provider cost coverage is still incomplete. |
| Stop reasons and errors | `LeanAgent.AI.Types`, `LeanAgent.AI.Util.Diagnostics`, `LeanAgent.Http` | partial | Stop reason types, assistant diagnostics, provider error extraction, and transport response header capture exist. Error stacks and provider `onResponse`/diagnostic header surfacing are incomplete. |
| Thinking/reasoning levels | `LeanAgent.AI.Types`, `LeanAgent.Models` | partial | Thinking level types, model `thinkingLevelMap` entries, supported-level filtering, xhigh opt-in, null suppression, simple-option reasoning clamp, and OpenAI-compatible/Responses payload alias mapping exist. Full generated metadata and non-OpenAI protocol wiring are still incomplete. |
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
| `getSupportedThinkingLevels` | `LeanAgent.Models` | implemented | Pi-style non-reasoning/off behavior, default xhigh suppression, explicit xhigh opt-in, and null map suppression exist. |
| `clampThinkingLevel` | `LeanAgent.Models` | implemented | Pi-style clamp over supported model thinking levels exists, including upward fallback before downward fallback. |
| `modelsAreEqual` | `LeanAgent.Models` | implemented | Compares provider and model id. |

## Auth Layer

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `auth/types.ts` | `LeanAgent.AI.Auth` | partial | API-key credential, OAuth credential with extra-field preservation, auth result, provider auth, auth context, OAuth auth contract, and credential store contracts exist. Login callbacks/prompts are not modeled yet. |
| `auth/context.ts` | `LeanAgent.AI.Auth` | partial | Default env/file-existence context exists with `~` expansion. Browser-specific behavior is not relevant yet. |
| `auth/credential-store.ts` | `LeanAgent.AI.Auth` | partial | In-memory and JSON file-backed API-key/OAuth credential stores exist, including OAuth extra-field persistence. Per-provider promise chains and cross-process file locks are missing. |
| `auth/helpers.ts` | `LeanAgent.AI.Auth`, `LeanAgent.AI.Providers.CloudflareAuth` | partial | Env API-key auth helper, model-aware base URL auth resolution, and Cloudflare Workers AI / AI Gateway auth helpers exist. OAuth/lazy OAuth and most ambient provider helpers are missing. |
| `auth/resolve.ts` | `LeanAgent.AI.Auth` | partial | API-key provider auth resolution with request overrides and optional model base URL context exists. Stored OAuth credentials now own the provider, refresh under credential-store `modify` when expired, persist refreshed credentials, and derive request auth through `toAuth`. Typed `ModelsError` auth/oauth codes are missing. |

## API Protocol Implementations

| Pi source | Lean target | Status | Notes |
| --- | --- | --- | --- |
| `api/lazy.ts` | `LeanAgent.AI.Api.Lazy`, `LeanAgent.Models.ProviderStreams.lazy` | implemented | Lean does not dynamically import TS modules, but the equivalent boundary exists: setup/load failures become assistant error streams, and provider dispatch uses it instead of throwing. |
| `api/simple-options.ts` | `LeanAgent.AI.Api.SimpleOptions`, `LeanAgent.AI.Types`, `LeanAgent.Models`, `LeanAgent.AI.Api.OpenAICompletions`, `LeanAgent.AI.Api.OpenAIResponses` | partial | Simple option fields exist and are applied to OpenAI-compatible and Responses payloads/headers. Context-aware `maxTokens` clamping now uses estimated context tokens plus a 4096-token safety margin, preserves explicit request caps, defaults to model max output when known, and avoids emitting a synthetic cap when model max output is unknown. `onPayload` and `onResponse` hooks can inspect/replace JSON payloads and observe HTTP status/headers on both OpenAI-compatible and Responses runtimes. `adjustMaxTokensForThinking` matches Pi default/custom thinking budgets and xhigh-to-high clamping. Abort signals remain missing. |
| `api/openai-completions.ts` | `LeanAgent.AI.Api.OpenAICompletions` | partial | Refactored into an API module with legacy wrapper, payload/header serialization, non-streaming completion, streaming request/response parsing, text/thinking/tool delta events, tool calls, empty-tools behavior, tool-history tools array, prompt cache payload fields, usage parsing, retry policy, provider error diagnostics, reasoning/max-token/temperature/tool-choice options, thinking-level payload aliases/off mapping through Models dispatch, and response parsing. Native callback-style live SSE transport, images, and full compat matrix are missing. |
| `api/openai-completions.lazy.ts` | `LeanAgent.AI.Api.OpenAICompletions` | deferred | Lean does not need TS lazy import; dispatch boundary is explicit through `ProviderStreams`. |
| `api/openai-responses.ts` | `LeanAgent.AI.Api.OpenAIResponses`, `LeanAgent.Models` | partial | Responses request payload construction, prompt-cache/session affinity fields, cache-affinity/custom headers, GitHub Copilot dynamic headers, non-streaming HTTP completion, provider error handling, usage parsing, service-tier cost multipliers, thinking-level payload aliases/off-null semantics, reasoning/message/function-call output parsing, streaming SSE event parsing, terminal-event enforcement, tool-call argument delta handling, HTTP streaming wrapper, and generic Models dispatch exist. Provider-specific catalog/factory integration beyond generic dispatch is still missing. |
| `api/openai-responses-shared.ts` | `LeanAgent.AI.Api.OpenAIResponsesShared` | partial | Shared message/tool serialization now converts system/user/assistant/tool-result replay items, consumes `TransformMessages`, normalizes OpenAI Responses tool-call IDs including foreign `fc_<hash>` item IDs, omits different-model `fc_` item IDs to avoid pairing validation, serializes image-capable tool outputs, and converts tools with `strict`. Full Responses request runtime remains in `LeanAgent.AI.Api.OpenAIResponses`; broader shared streaming conversion parity is still incomplete. |
| `api/openai-responses.lazy.ts` | `LeanAgent.AI.Api.OpenAIResponses` | deferred | Lazy wrapper can be skipped if dispatch is explicit. |
| `api/openai-codex-responses.ts` | `LeanAgent.AI.Api.OpenAICodexResponses` | missing | OAuth and WebSocket/cached transport later. |
| `api/openai-codex-responses.lazy.ts` | `LeanAgent.AI.Api.OpenAICodexResponses` | deferred | Lazy wrapper. |
| `api/azure-openai-responses.ts` | `LeanAgent.AI.Api.AzureOpenAIResponses`, `LeanAgent.Models` | partial | Azure base URL normalization, resource-name/default URL resolution, API-version query, deployment-name mapping, prompt-cache key clamp, `store=false`, `api-key` header transport, payload/response hooks via shared Responses runtime, streaming response parsing, and compat built-in dispatch exist. SDK abort semantics and full generated provider catalog integration are missing. |
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
| `api/cloudflare.ts` | `LeanAgent.AI.Api.Cloudflare` | implemented | Cloudflare Workers AI and AI Gateway base URL templates plus account/gateway env identifiers exist and are exercised by Cloudflare auth tests. |
| `api/github-copilot-headers.ts` | `LeanAgent.AI.Api.GitHubCopilotHeaders` | implemented | Copilot initiator inference, vision input detection, dynamic `X-Initiator`, `Openai-Intent`, and `Copilot-Vision-Request` headers exist and are wired into OpenAI Responses requests. |
| `api/openai-prompt-cache.ts` | `LeanAgent.AI.Api.OpenAIPromptCache` | partial | Prompt cache key clamping and Chat Completions payload fields exist, including `cacheRetention=none`, `long`, and `PI_CACHE_RETENTION=long`. Session affinity headers and provider-specific long-cache suppression are missing. |
| `api/openrouter-images.ts` | `LeanAgent.AI.Api.OpenRouterImages` | partial | OpenRouter Images Chat Completions payload construction, data-URL image inputs, modalities, API-key auth, custom headers, payload/response hooks, retry, provider diagnostics, response text/data-URL image parsing, usage parsing, and cost calculation exist. Abort signal support and live provider matrix tests are missing. |
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
| Azure OpenAI Responses | `azure-openai-responses.ts`, `azure-openai-responses.models.ts` | `LeanAgent.AI.Api.AzureOpenAIResponses`, future `LeanAgent.AI.Providers.AzureOpenAIResponses` | partial |
| Cerebras | `cerebras.ts`, `cerebras.models.ts` | `LeanAgent.Models` | partial |
| Cloudflare AI Gateway | `cloudflare-ai-gateway.ts`, `cloudflare-ai-gateway.models.ts` | future `LeanAgent.AI.Providers.CloudflareAIGateway`, `LeanAgent.AI.Providers.CloudflareAuth` | partial |
| Cloudflare Workers AI | `cloudflare-workers-ai.ts`, `cloudflare-workers-ai.models.ts` | future `LeanAgent.AI.Providers.CloudflareWorkersAI`, `LeanAgent.AI.Providers.CloudflareAuth` | partial |
| Cloudflare auth | `cloudflare-auth.ts` | `LeanAgent.AI.Providers.CloudflareAuth` | partial |
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
| OpenRouter images | `openrouter-images.ts` | `LeanAgent.AI.Providers.OpenRouterImages` | partial |
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
| `images.ts` | `LeanAgent.AI.Images` | partial | Generic image generation dispatch exists, with OpenRouter Images registered as a built-in provider. |
| `images-models.ts` | `LeanAgent.AI.Images`, `LeanAgent.AI.Images.Models` | partial | Runtime image model type, lookup helpers, image provider collection, provider factory, refresh, auth merge, and error-as-result dispatch exist. Shared OAuth credential resolution exists; image-specific OAuth providers/tests remain missing. |
| `image-models.ts` | `LeanAgent.AI.Images.Models` | implemented | Static image model access exists for the current Pi image catalog. |
| `image-models.generated.ts` | `LeanAgent.AI.Images.Models` | implemented | Current generated OpenRouter image catalog is represented as checked-in Lean data with 37 models. |
| `images-api-registry.ts` | `LeanAgent.AI.Images.Registry` | implemented | Register/get/list/unregister/clear/reset image API dispatch exists with built-in replay and API mismatch wrapping. |
| `api/openrouter-images.ts` | `LeanAgent.AI.Api.OpenRouterImages` | partial | OpenRouter Images request/runtime/parser behavior exists with local HTTP tests. Abort signal support and live provider matrix tests are missing. |
| `providers/openrouter-images.ts` | `LeanAgent.AI.Providers.OpenRouterImages` | partial | Built-in OpenRouter image API registration and Pi-style OpenRouter image provider factory with `OPENROUTER_API_KEY` auth and 37-model catalog exist. Lazy import behavior is represented by direct Lean dispatch. |

## Test Mapping

Initial Lean parity should port tests in this order:

| Pi tests | Lean target | Status | Why first |
| --- | --- | --- | --- |
| `models-runtime.test.ts`, `providers.test.ts`, `supports-xhigh.test.ts`, `xhigh.test.ts` | model catalog and thinking tests | partial | Protects provider/model registry, cost calculation, thinking-level map helpers, auth-applied base URL overrides, and header-only auth dispatch. |
| `env-api-keys.test.ts`, `compat-env.test.ts`, Cloudflare auth tests | auth/env tests | partial | Env API-key, stored credential precedence, file-backed API-key/OAuth credential roundtrip/integration, OAuth refresh/toAuth resolution, OAuth credential ownership without env fallback, OAuth provider registry/high-level helper behavior, full provider env map, Anthropic OAuth-token precedence, Bedrock/Vertex ambient markers, Cloudflare Workers AI / AI Gateway auth resolution, compat registry dispatch, request API key pass-through, known-provider env key injection, catalog-outside provider env injection, and legacy alias registry dispatch are covered. OAuth login/device-code provider flows remain missing. |
| `stream.test.ts`, `empty.test.ts`, `abort.test.ts` | event stream tests | partial | Stream result, text/thinking/tool events, partial snapshots, tool delta payloads, and empty-content completion are covered in Lean. Async iterator/backpressure, provider abort behavior, and live timing remain missing. |
| `openai-completions-*.test.ts` | OpenAI completions tests | partial | Payload tests cover empty tools, tool history, tool choice, max tokens, temperature, reasoning effort, thinking-level payload aliases, prompt cache key/retention, streaming payload/SSE parsing, buffered streaming runtime dispatch, request/response headers, usage parsing, provider HTTP diagnostics, repaired tool arguments, and legacy assistant tool-call omission. Network provider matrix and true live-stream timing tests are missing. |
| `retry.test.ts`, `diagnostics.test.ts`, `estimate.test.ts`, `overflow.test.ts`, `validation.test.ts`, `unicode-surrogate.test.ts` | util tests | partial | Retry classifier/policy, diagnostics extraction/round-trip, estimate utilities, provider header filtering/merge, proxy env resolution, JSON repair/streaming fallback, JSON Schema validation/coercion, Unicode surrogate sanitization helpers, overflow detection, and OpenAI transient HTTP retry are covered. Live provider unicode-surrogate tests are missing. |
| `faux-provider.test.ts` | faux provider tests | partial | Deterministic provider handle, queued responses, helper blocks, model-aware factories, usage/cache estimates, model rewrite, collection dispatch, and event reconstruction are covered. Global compat registration, async timing, and abort behavior are missing. |
| `session-resources.test.ts` | session resource cleanup tests | implemented | Cleanup registration, unregister handles, session id propagation, continued cleanup after failures, and aggregate errors are covered. |
| `images*.test.ts`, `openrouter-images.test.ts` | image tests | partial | Generic image API registry, built-in replay, image provider collection CRUD/refresh/auth merge/error result, OpenRouter provider factory auth, full current image catalog lookup/count, OpenRouter Images payload construction, local HTTP dispatch, headers, response hooks, output parsing, usage/cost parsing, and missing-key errors are covered. Live provider matrix tests are still missing. |
| Anthropic/Google/Mistral/Bedrock/Azure/Codex tests | provider protocol tests | partial | Azure OpenAI Responses base URL, deployment mapping, payload, local streaming transport, and compat built-in dispatch are covered. Anthropic/Google/Mistral/Bedrock/Codex provider protocol tests are still missing. |

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
- Env API key auth, in-memory and file-backed API-key/OAuth credential stores, OAuth provider registry helpers, auth resolution. Status: partial; OAuth login/device-code provider flows are missing.
- `createProvider` for single API dispatch. Status: partial; API-map dispatch and lazy error stream behavior exist, but full mixed-provider parity is not complete.

Exit criteria:

- `Main.lean` no longer owns provider-specific auth/default resolution. Status: implemented for current DeepSeek/OpenAI CLI selection.
- Tests mapped from `models-runtime.test.ts`, `env-api-keys.test.ts`, `providers.test.ts`, `supports-xhigh.test.ts`, and `xhigh.test.ts`. Status: partial; auth resolution, stored/file credential precedence, runtime lookup/dispatch, cost calculation, and thinking-level map/clamp behavior are covered.

### M4: OpenAI-Compatible API Family

Deliver:

- Refactor `LeanAgent.OpenAI` into `LeanAgent.AI.Api.OpenAICompletions`. Status: implemented structurally; `LeanAgent.OpenAI` is now a compatibility wrapper.
- Add prompt cache fields, retry, response diagnostics, tool choice behavior, empty tools behavior. Status: partial; prompt cache payload fields, retry policy, basic provider diagnostics, response header capture, tool choice, and empty-tools behavior exist. Full response diagnostics are incomplete because provider callbacks/live stream diagnostics are missing.
- Add provider factories for DeepSeek, OpenAI, OpenRouter, Groq, xAI, Cerebras, Together, Fireworks where they share OpenAI-compatible protocol. Status: partial; default runtime catalog has representative OpenAI-compatible models for each, but provider modules and full generated catalogs are missing.

Exit criteria:

- DeepSeek remains the default path. Status: implemented; catalog selection still checks DeepSeek first.
- OpenAI-compatible Pi tests that do not require live network are ported. Status: partial; payload, diagnostics, retry, Responses runtime dispatch, and provider-family catalog tests exist, but full non-network Pi test coverage is incomplete.

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
- Compat/global API registry after new `Models` API is stable. Status: partial; registry, reset, source unregister, built-in OpenAI-compatible/OpenAI Responses/Azure OpenAI Responses entries, simple dispatch, fixed-API legacy aliases, and env key injection exist.

Exit criteria:

- Image tests pass.
- Compat API is a thin wrapper over the new model collection, not a second runtime.

## Rules for Updating This Ledger

- Every AI change must update this file in the same commit when status changes.
- New Lean modules must cite the Pi source row they are closing in commit notes or PR text.
- A row can become `implemented` only with tests or an explicit reason why runtime validation is impossible.
- `vendor/pi` is read-only. Do not edit reference files.
- Prefer behavior parity over line-by-line TypeScript translation.
