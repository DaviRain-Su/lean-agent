import LeanAgent.Core
import LeanAgent.AI.Auth
import LeanAgent.AI.Api.AnthropicMessages
import LeanAgent.AI.Api.AzureOpenAIResponses
import LeanAgent.AI.Api.GoogleGenerativeAI
import LeanAgent.AI.Api.GoogleVertex
import LeanAgent.AI.Api.Lazy
import LeanAgent.AI.Api.MistralConversations
import LeanAgent.AI.Api.OpenAICompletions
import LeanAgent.AI.Api.OpenAICodexResponses
import LeanAgent.AI.Api.OpenAIResponses
import LeanAgent.AI.Api.SimpleOptions
import LeanAgent.AI.EventStream
import LeanAgent.AI.Types

namespace LeanAgent.Models

def deepSeekProviderId : String := "deepseek"
def deepSeekApiKeyEnv : String := "DEEPSEEK_API_KEY"
def deepSeekModelEnv : String := "DEEPSEEK_MODEL"
def deepSeekDefaultModel : String := "deepseek-v4-flash"
def deepSeekBaseUrl : String := "https://api.deepseek.com"

def openAIProviderId : String := "openai"
def openAIKeyEnv : String := "OPENAI_API_KEY"
def openAIModelEnv : String := "OPENAI_MODEL"
def openAIDefaultModel : String := "gpt-4.1-mini"
def openAIBaseUrl : String := "https://api.openai.com/v1"

def openAICodexProviderId : String := "openai-codex"
def openAICodexDefaultModel : String := "gpt-5.5"
def openAICodexBaseUrl : String := LeanAgent.AI.Api.OpenAICodexResponses.defaultBaseUrl

def azureOpenAIResponsesProviderId : String := "azure-openai-responses"
def azureOpenAIResponsesApiKeyEnv : String := "AZURE_OPENAI_API_KEY"
def azureOpenAIResponsesDefaultModel : String := "gpt-4o-mini"
def azureOpenAIResponsesBaseUrl : String := ""

def openRouterProviderId : String := "openrouter"
def openRouterApiKeyEnv : String := "OPENROUTER_API_KEY"
def openRouterDefaultModel : String := "openai/gpt-oss-120b"
def openRouterBaseUrl : String := "https://openrouter.ai/api/v1"

def groqProviderId : String := "groq"
def groqApiKeyEnv : String := "GROQ_API_KEY"
def groqDefaultModel : String := "openai/gpt-oss-120b"
def groqBaseUrl : String := "https://api.groq.com/openai/v1"

def xaiProviderId : String := "xai"
def xaiApiKeyEnv : String := "XAI_API_KEY"
def xaiDefaultModel : String := "grok-code-fast-1"
def xaiBaseUrl : String := "https://api.x.ai/v1"

def cerebrasProviderId : String := "cerebras"
def cerebrasApiKeyEnv : String := "CEREBRAS_API_KEY"
def cerebrasDefaultModel : String := "gpt-oss-120b"
def cerebrasBaseUrl : String := "https://api.cerebras.ai/v1"

def togetherProviderId : String := "together"
def togetherApiKeyEnv : String := "TOGETHER_API_KEY"
def togetherDefaultModel : String := "openai/gpt-oss-120b"
def togetherBaseUrl : String := "https://api.together.ai/v1"

def fireworksProviderId : String := "fireworks"
def fireworksApiKeyEnv : String := "FIREWORKS_API_KEY"
def fireworksDefaultModel : String := "accounts/fireworks/models/glm-5p2"
def fireworksBaseUrl : String := "https://api.fireworks.ai/inference/v1"

def anthropicProviderId : String := "anthropic"
def anthropicApiKeyEnv : String := "ANTHROPIC_API_KEY"
def anthropicOAuthTokenEnv : String := "ANTHROPIC_OAUTH_TOKEN"
def anthropicDefaultModel : String := "claude-sonnet-4-5"
def anthropicBaseUrl : String := "https://api.anthropic.com"

def googleProviderId : String := "google"
def googleApiKeyEnv : String := "GEMINI_API_KEY"
def googleDefaultModel : String := "gemini-2.5-flash"
def googleBaseUrl : String := "https://generativelanguage.googleapis.com/v1beta"

def googleVertexProviderId : String := "google-vertex"
def googleVertexApiKeyEnv : String := "GOOGLE_CLOUD_API_KEY"
def googleVertexDefaultModel : String := "gemini-2.5-flash"
def googleVertexBaseUrl : String := "https://{location}-aiplatform.googleapis.com"

def mistralProviderId : String := "mistral"
def mistralApiKeyEnv : String := "MISTRAL_API_KEY"
def mistralDefaultModel : String := "devstral-medium-latest"
def mistralBaseUrl : String := LeanAgent.AI.Api.MistralConversations.defaultBaseUrl

structure ModelCompat where
  supportsStore : Bool := true
  supportsDeveloperRole : Bool := true
  requiresReasoningContentOnAssistantMessages : Bool := false
  thinkingFormat : Option String := none
deriving Repr, BEq

structure ModelInfo where
  id : String
  name : String
  provider : String
  api : String
  baseUrl : String
  cost : LeanAgent.AI.UsageCost := {}
  contextWindow : Nat := 0
  maxTokens : Nat := 0
  reasoning : Bool := false
  thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[]
  input : Array String := #["text"]
  supportsToolCalls : Bool := true
  supportsJsonOutput : Bool := true
  compat : ModelCompat := {}
deriving Repr, BEq

def ModelInfo.qualifiedId (model : ModelInfo) : String :=
  model.provider ++ "/" ++ model.id

def ModelInfo.toModelRef (model : ModelInfo) : LeanAgent.AI.ModelRef :=
  { id := model.id
    api := model.api
    provider := model.provider
    baseUrl := some model.baseUrl
  }

def ModelInfo.toResponsesModel (model : ModelInfo) :
    LeanAgent.AI.Api.OpenAIResponsesShared.ResponsesModel :=
  { id := model.id
    provider := model.provider
    api := model.api
    input := model.input
    reasoning := model.reasoning
    supportsDeveloperRole := model.compat.supportsDeveloperRole
    contextWindow := model.contextWindow
    maxTokens := model.maxTokens
    cost := model.cost
    thinkingLevelMap := model.thinkingLevelMap
  }

def deepSeekCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    requiresReasoningContentOnAssistantMessages := true
    thinkingFormat := some "deepseek"
  }

def deepSeekV4Flash : ModelInfo :=
  { id := deepSeekDefaultModel
    name := "DeepSeek V4 Flash"
    provider := deepSeekProviderId
    api := "openai-completions"
    baseUrl := deepSeekBaseUrl
    contextWindow := 1000000
    maxTokens := 384000
    reasoning := true
    compat := deepSeekCompat
  }

def deepSeekV4Pro : ModelInfo :=
  { id := "deepseek-v4-pro"
    name := "DeepSeek V4 Pro"
    provider := deepSeekProviderId
    api := "openai-completions"
    baseUrl := deepSeekBaseUrl
    contextWindow := 1000000
    maxTokens := 384000
    reasoning := true
    compat := deepSeekCompat
  }

def cost (input output cacheRead cacheWrite : Float) : LeanAgent.AI.UsageCost :=
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
  }

def openAIModel
    (id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := false)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[])
    (input : Array String := #["text"]) : ModelInfo :=
  { id := id
    name := name
    provider := openAIProviderId
    api := "openai-responses"
    baseUrl := openAIBaseUrl
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
    reasoning := reasoning
    thinkingLevelMap := thinkingLevelMap
    input := input
  }

def openAIThinkingOffNullMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[{ level := .off, mapped := none }]

def openAIThinkingOffNoneMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[{ level := .off, mapped := some "none" }]

def openAIThinkingOffNullXHighMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := none }
   , { level := .level .xhigh, mapped := some "xhigh" }
   ]

def openAIThinkingOffNoneXHighMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := some "none" }
   , { level := .level .xhigh, mapped := some "xhigh" }
   ]

def openAIGpt55ThinkingMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := some "none" }
   , { level := .level .xhigh, mapped := some "xhigh" }
   , { level := .level .minimal, mapped := none }
   ]

def openAIGpt55ProThinkingMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := none }
   , { level := .level .xhigh, mapped := some "xhigh" }
   , { level := .level .minimal, mapped := none }
   , { level := .level .low, mapped := none }
   ]

def openAIGpt41Mini : ModelInfo :=
  openAIModel "gpt-4.1-mini" "GPT-4.1 mini" 0.4 1.6 0.1 0.0 1047576 32768 false #[] #["text", "image"]

def openAIResponsesModels : Array ModelInfo :=
  #[
    openAIModel "gpt-4" "GPT-4" 30.0 60.0 0.0 0.0 8192 8192 false #[] #["text"],
    openAIModel "gpt-4-turbo" "GPT-4 Turbo" 10.0 30.0 0.0 0.0 128000 4096 false #[] #["text", "image"],
    openAIModel "gpt-4.1" "GPT-4.1" 2.0 8.0 0.5 0.0 1047576 32768 false #[] #["text", "image"],
    openAIGpt41Mini,
    openAIModel "gpt-4.1-nano" "GPT-4.1 nano" 0.1 0.4 0.025 0.0 1047576 32768 false #[] #["text", "image"],
    openAIModel "gpt-4o" "GPT-4o" 2.5 10.0 1.25 0.0 128000 16384 false #[] #["text", "image"],
    openAIModel "gpt-4o-2024-05-13" "GPT-4o (2024-05-13)" 5.0 15.0 0.0 0.0 128000 4096 false #[] #["text", "image"],
    openAIModel "gpt-4o-2024-08-06" "GPT-4o (2024-08-06)" 2.5 10.0 1.25 0.0 128000 16384 false #[] #["text", "image"],
    openAIModel "gpt-4o-2024-11-20" "GPT-4o (2024-11-20)" 2.5 10.0 1.25 0.0 128000 16384 false #[] #["text", "image"],
    openAIModel "gpt-4o-mini" "GPT-4o mini" 0.15 0.6 0.075 0.0 128000 16384 false #[] #["text", "image"],
    openAIModel "gpt-5" "GPT-5" 1.25 10.0 0.125 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5-chat-latest" "GPT-5 Chat Latest" 1.25 10.0 0.125 0.0 128000 16384 false openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5-codex" "GPT-5-Codex" 1.25 10.0 0.125 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5-mini" "GPT-5 Mini" 0.25 2.0 0.025 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5-nano" "GPT-5 Nano" 0.05 0.4 0.005 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5-pro" "GPT-5 Pro" 15.0 120.0 0.0 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5.1" "GPT-5.1" 1.25 10.0 0.125 0.0 400000 128000 true openAIThinkingOffNoneMap #["text", "image"],
    openAIModel "gpt-5.1-chat-latest" "GPT-5.1 Chat" 1.25 10.0 0.125 0.0 128000 16384 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5.1-codex" "GPT-5.1 Codex" 1.25 10.0 0.125 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5.1-codex-max" "GPT-5.1 Codex Max" 1.25 10.0 0.125 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5.1-codex-mini" "GPT-5.1 Codex mini" 0.25 2.0 0.025 0.0 400000 128000 true openAIThinkingOffNullMap #["text", "image"],
    openAIModel "gpt-5.2" "GPT-5.2" 1.75 14.0 0.175 0.0 400000 128000 true openAIThinkingOffNoneXHighMap #["text", "image"],
    openAIModel "gpt-5.2-chat-latest" "GPT-5.2 Chat" 1.75 14.0 0.175 0.0 128000 16384 true openAIThinkingOffNullXHighMap #["text", "image"],
    openAIModel "gpt-5.2-codex" "GPT-5.2 Codex" 1.75 14.0 0.175 0.0 400000 128000 true openAIThinkingOffNullXHighMap #["text", "image"],
    openAIModel "gpt-5.2-pro" "GPT-5.2 Pro" 21.0 168.0 0.0 0.0 400000 128000 true openAIThinkingOffNullXHighMap #["text", "image"],
    openAIModel "gpt-5.3-chat-latest" "GPT-5.3 Chat (latest)" 1.75 14.0 0.175 0.0 128000 16384 false openAIThinkingOffNullXHighMap #["text", "image"],
    openAIModel "gpt-5.3-codex" "GPT-5.3 Codex" 1.75 14.0 0.175 0.0 400000 128000 true openAIThinkingOffNoneXHighMap #["text", "image"],
    openAIModel "gpt-5.3-codex-spark" "GPT-5.3 Codex Spark" 1.75 14.0 0.175 0.0 128000 32000 true openAIThinkingOffNullXHighMap #["text", "image"],
    openAIModel "gpt-5.4" "GPT-5.4" 2.5 15.0 0.25 0.0 272000 128000 true openAIThinkingOffNoneXHighMap #["text", "image"],
    openAIModel "gpt-5.4-mini" "GPT-5.4 mini" 0.75 4.5 0.075 0.0 400000 128000 true openAIThinkingOffNoneXHighMap #["text", "image"],
    openAIModel "gpt-5.4-nano" "GPT-5.4 nano" 0.2 1.25 0.02 0.0 400000 128000 true openAIThinkingOffNoneXHighMap #["text", "image"],
    openAIModel "gpt-5.4-pro" "GPT-5.4 Pro" 30.0 180.0 0.0 0.0 1050000 128000 true openAIThinkingOffNullXHighMap #["text", "image"],
    openAIModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000 true openAIGpt55ThinkingMap #["text", "image"],
    openAIModel "gpt-5.5-pro" "GPT-5.5 Pro" 30.0 180.0 0.0 0.0 1050000 128000 true openAIGpt55ProThinkingMap #["text", "image"],
    openAIModel "o1" "o1" 15.0 60.0 7.5 0.0 200000 100000 true #[] #["text", "image"],
    openAIModel "o1-pro" "o1-pro" 150.0 600.0 0.0 0.0 200000 100000 true #[] #["text", "image"],
    openAIModel "o3" "o3" 2.0 8.0 0.5 0.0 200000 100000 true #[] #["text", "image"],
    openAIModel "o3-deep-research" "o3-deep-research" 10.0 40.0 2.5 0.0 200000 100000 true #[] #["text", "image"],
    openAIModel "o3-mini" "o3-mini" 1.1 4.4 0.55 0.0 200000 100000 true #[] #["text"],
    openAIModel "o3-pro" "o3-pro" 20.0 80.0 0.0 0.0 200000 100000 true #[] #["text", "image"],
    openAIModel "o4-mini" "o4-mini" 1.1 4.4 0.275 0.0 200000 100000 true #[] #["text", "image"],
    openAIModel "o4-mini-deep-research" "o4-mini-deep-research" 2.0 8.0 0.5 0.0 200000 100000 true #[] #["text", "image"]
  ]

def openAICodexThinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .level .xhigh, mapped := some "xhigh" }
   , { level := .level .minimal, mapped := some "low" }
   ]

def openAICodexModel
    (id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (input : Array String := #["text", "image"]) : ModelInfo :=
  { id := id
    name := name
    provider := openAICodexProviderId
    api := LeanAgent.AI.Api.OpenAICodexResponses.api
    baseUrl := openAICodexBaseUrl
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
    reasoning := true
    thinkingLevelMap := openAICodexThinkingLevelMap
    input := input
  }

def openAICodexModels : Array ModelInfo :=
  #[ openAICodexModel "gpt-5.3-codex-spark" "GPT-5.3 Codex Spark" 1.75 14.0 0.175 0.0 128000 128000 #["text"]
   , openAICodexModel "gpt-5.4" "GPT-5.4" 2.5 15.0 0.25 0.0 272000 128000
   , openAICodexModel "gpt-5.4-mini" "GPT-5.4 mini" 0.75 4.5 0.075 0.0 272000 128000
   , openAICodexModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 272000 128000
   ]

def openRouterCompat : ModelCompat :=
  { thinkingFormat := some "openrouter" }

def openRouterGptOss120B : ModelInfo :=
  { id := openRouterDefaultModel
    name := "OpenAI: gpt-oss-120b"
    provider := openRouterProviderId
    api := "openai-completions"
    baseUrl := openRouterBaseUrl
    cost := cost 0.039 0.18 0.0 0.0
    contextWindow := 131072
    maxTokens := 4096
    reasoning := true
    compat := openRouterCompat
  }

def groqGptOss120B : ModelInfo :=
  { id := groqDefaultModel
    name := "GPT OSS 120B"
    provider := groqProviderId
    api := "openai-completions"
    baseUrl := groqBaseUrl
    cost := cost 0.15 0.6 0.075 0.0
    contextWindow := 131072
    maxTokens := 65536
    reasoning := true
  }

def xaiCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
  }

def xaiGrokCodeFast1 : ModelInfo :=
  { id := xaiDefaultModel
    name := "Grok Code Fast 1"
    provider := xaiProviderId
    api := "openai-completions"
    baseUrl := xaiBaseUrl
    cost := cost 0.2 1.5 0.02 0.0
    contextWindow := 32768
    maxTokens := 8192
    compat := xaiCompat
  }

def cerebrasCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
  }

def cerebrasGptOss120B : ModelInfo :=
  { id := cerebrasDefaultModel
    name := "GPT OSS 120B"
    provider := cerebrasProviderId
    api := "openai-completions"
    baseUrl := cerebrasBaseUrl
    cost := cost 0.35 0.75 0.0 0.0
    contextWindow := 131072
    maxTokens := 40960
    reasoning := true
    compat := cerebrasCompat
  }

def togetherCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    thinkingFormat := some "openai"
  }

def togetherGptOss120B : ModelInfo :=
  { id := togetherDefaultModel
    name := "GPT OSS 120B"
    provider := togetherProviderId
    api := "openai-completions"
    baseUrl := togetherBaseUrl
    cost := cost 0.15 0.6 0.0 0.0
    contextWindow := 131072
    maxTokens := 131072
    reasoning := true
    compat := togetherCompat
  }

def fireworksCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
  }

def fireworksGlm52 : ModelInfo :=
  { id := fireworksDefaultModel
    name := "GLM 5.2"
    provider := fireworksProviderId
    api := "openai-completions"
    baseUrl := fireworksBaseUrl
    cost := cost 1.4 4.4 0.26 0.0
    contextWindow := 1048576
    maxTokens := 131072
    reasoning := true
    compat := fireworksCompat
  }

def anthropicSonnet45 : ModelInfo :=
  { id := anthropicDefaultModel
    name := "Claude Sonnet 4.5 (latest)"
    provider := anthropicProviderId
    api := LeanAgent.AI.Api.AnthropicMessages.api
    baseUrl := anthropicBaseUrl
    cost := cost 3.0 15.0 0.3 3.75
    contextWindow := 200000
    maxTokens := 64000
    reasoning := true
    input := #["text", "image"]
  }

def anthropicHaiku45 : ModelInfo :=
  { id := "claude-haiku-4-5"
    name := "Claude Haiku 4.5 (latest)"
    provider := anthropicProviderId
    api := LeanAgent.AI.Api.AnthropicMessages.api
    baseUrl := anthropicBaseUrl
    cost := cost 1.0 5.0 0.1 1.25
    contextWindow := 200000
    maxTokens := 64000
    reasoning := true
    input := #["text", "image"]
  }

def anthropicOpus45 : ModelInfo :=
  { id := "claude-opus-4-5"
    name := "Claude Opus 4.5 (latest)"
    provider := anthropicProviderId
    api := LeanAgent.AI.Api.AnthropicMessages.api
    baseUrl := anthropicBaseUrl
    cost := cost 15.0 75.0 1.5 18.75
    contextWindow := 200000
    maxTokens := 64000
    reasoning := true
    input := #["text", "image"]
  }

def anthropicSonnet37 : ModelInfo :=
  { id := "claude-3-7-sonnet-20250219"
    name := "Claude Sonnet 3.7"
    provider := anthropicProviderId
    api := LeanAgent.AI.Api.AnthropicMessages.api
    baseUrl := anthropicBaseUrl
    cost := cost 3.0 15.0 0.3 3.75
    contextWindow := 200000
    maxTokens := 64000
    reasoning := true
    input := #["text", "image"]
  }

def googleModel
    (id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := true)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[]) : ModelInfo :=
  { id := id
    name := name
    provider := googleProviderId
    api := LeanAgent.AI.Api.GoogleGenerativeAI.api
    baseUrl := googleBaseUrl
    reasoning := reasoning
    thinkingLevelMap := thinkingLevelMap
    input := #["text", "image"]
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
  }

def googleThinkingOffOnlyMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[{ level := .off, mapped := none }]

def googleProThinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := none }
   , { level := .level .minimal, mapped := none }
   , { level := .level .low, mapped := some "LOW" }
   , { level := .level .medium, mapped := none }
   , { level := .level .high, mapped := some "HIGH" }
   ]

def googleGemma4ThinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := none }
   , { level := .level .minimal, mapped := some "MINIMAL" }
   , { level := .level .low, mapped := none }
   , { level := .level .medium, mapped := none }
   , { level := .level .high, mapped := some "HIGH" }
   ]

def googleGemini20Flash : ModelInfo :=
  googleModel "gemini-2.0-flash" "Gemini 2.0 Flash" 0.1 0.4 0.025 0.0 1048576 8192 false

def googleGemini20FlashLite : ModelInfo :=
  googleModel "gemini-2.0-flash-lite" "Gemini 2.0 Flash-Lite" 0.075 0.3 0.0 0.0 1048576 8192 false

def googleGemini25Flash : ModelInfo :=
  googleModel "gemini-2.5-flash" "Gemini 2.5 Flash" 0.3 2.5 0.03 0.0 1048576 65536

def googleGemini25FlashLite : ModelInfo :=
  googleModel "gemini-2.5-flash-lite" "Gemini 2.5 Flash-Lite" 0.1 0.4 0.01 0.0 1048576 65536

def googleGemini25Pro : ModelInfo :=
  googleModel "gemini-2.5-pro" "Gemini 2.5 Pro" 1.25 10.0 0.125 0.0 1048576 65536

def googleGemini3FlashPreview : ModelInfo :=
  googleModel "gemini-3-flash-preview" "Gemini 3 Flash Preview" 0.5 3.0 0.05 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleGemini3ProPreview : ModelInfo :=
  googleModel "gemini-3-pro-preview" "Gemini 3 Pro Preview" 2.0 12.0 0.2 0.0 1048576 65536 true googleProThinkingLevelMap

def googleGemini31FlashLite : ModelInfo :=
  googleModel "gemini-3.1-flash-lite" "Gemini 3.1 Flash Lite" 0.25 1.5 0.025 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleGemini31FlashLitePreview : ModelInfo :=
  googleModel "gemini-3.1-flash-lite-preview" "Gemini 3.1 Flash Lite Preview" 0.25 1.5 0.025 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleGemini31ProPreview : ModelInfo :=
  googleModel "gemini-3.1-pro-preview" "Gemini 3.1 Pro Preview" 2.0 12.0 0.2 0.0 1048576 65536 true googleProThinkingLevelMap

def googleGemini31ProPreviewCustomTools : ModelInfo :=
  googleModel "gemini-3.1-pro-preview-customtools" "Gemini 3.1 Pro Preview Custom Tools" 2.0 12.0 0.2 0.0 1048576 65536 true googleProThinkingLevelMap

def googleGemini35Flash : ModelInfo :=
  googleModel "gemini-3.5-flash" "Gemini 3.5 Flash" 1.5 9.0 0.15 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleGeminiFlashLatest : ModelInfo :=
  googleModel "gemini-flash-latest" "Gemini Flash Latest" 1.5 9.0 0.15 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleGeminiFlashLiteLatest : ModelInfo :=
  googleModel "gemini-flash-lite-latest" "Gemini Flash-Lite Latest" 0.25 1.5 0.025 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleGemma426BA4BIt : ModelInfo :=
  googleModel "gemma-4-26b-a4b-it" "Gemma 4 26B A4B IT" 0.0 0.0 0.0 0.0 262144 32768 true googleGemma4ThinkingLevelMap

def googleGemma431BIt : ModelInfo :=
  googleModel "gemma-4-31b-it" "Gemma 4 31B IT" 0.0 0.0 0.0 0.0 262144 32768 true googleGemma4ThinkingLevelMap

def googleModels : Array ModelInfo :=
  #[ googleGemini20Flash
   , googleGemini20FlashLite
   , googleGemini25Flash
   , googleGemini25FlashLite
   , googleGemini25Pro
   , googleGemini3FlashPreview
   , googleGemini3ProPreview
   , googleGemini31FlashLite
   , googleGemini31FlashLitePreview
   , googleGemini31ProPreview
   , googleGemini31ProPreviewCustomTools
   , googleGemini35Flash
   , googleGeminiFlashLatest
   , googleGeminiFlashLiteLatest
   , googleGemma426BA4BIt
   , googleGemma431BIt
   ]

def googleVertexModel
    (id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := true)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[]) : ModelInfo :=
  { id := id
    name := name
    provider := googleVertexProviderId
    api := LeanAgent.AI.Api.GoogleVertex.api
    baseUrl := googleVertexBaseUrl
    reasoning := reasoning
    thinkingLevelMap := thinkingLevelMap
    input := #["text", "image"]
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
  }

def googleVertexGemini25Flash : ModelInfo :=
  googleVertexModel "gemini-2.5-flash" "Gemini 2.5 Flash" 0.3 2.5 0.03 0.0 1048576 65536

def googleVertexGemini25FlashLite : ModelInfo :=
  googleVertexModel "gemini-2.5-flash-lite" "Gemini 2.5 Flash-Lite" 0.1 0.4 0.01 0.0 1048576 65536

def googleVertexGemini25Pro : ModelInfo :=
  googleVertexModel "gemini-2.5-pro" "Gemini 2.5 Pro" 1.25 10.0 0.125 0.0 1048576 65536

def googleVertexGemini3FlashPreview : ModelInfo :=
  googleVertexModel "gemini-3-flash-preview" "Gemini 3 Flash Preview" 0.5 3.0 0.05 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleVertexGemini31FlashLite : ModelInfo :=
  googleVertexModel "gemini-3.1-flash-lite" "Gemini 3.1 Flash Lite" 0.25 1.5 0.025 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleVertexGemini31ProPreview : ModelInfo :=
  googleVertexModel "gemini-3.1-pro-preview" "Gemini 3.1 Pro Preview" 2.0 12.0 0.2 0.0 1048576 65536 true googleProThinkingLevelMap

def googleVertexGemini31ProPreviewCustomTools : ModelInfo :=
  googleVertexModel "gemini-3.1-pro-preview-customtools" "Gemini 3.1 Pro Preview Custom Tools" 2.0 12.0 0.2 0.0 1048576 65536 true googleProThinkingLevelMap

def googleVertexGemini35Flash : ModelInfo :=
  googleVertexModel "gemini-3.5-flash" "Gemini 3.5 Flash" 1.5 9.0 0.15 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleVertexGeminiFlashLatest : ModelInfo :=
  googleVertexModel "gemini-flash-latest" "Gemini Flash Latest" 1.5 9.0 0.15 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleVertexGeminiFlashLiteLatest : ModelInfo :=
  googleVertexModel "gemini-flash-lite-latest" "Gemini Flash-Lite Latest" 0.25 1.5 0.025 0.0 1048576 65536 true googleThinkingOffOnlyMap

def googleVertexModels : Array ModelInfo :=
  #[ googleVertexGemini25Flash
   , googleVertexGemini25FlashLite
   , googleVertexGemini25Pro
   , googleVertexGemini3FlashPreview
   , googleVertexGemini31FlashLite
   , googleVertexGemini31ProPreview
   , googleVertexGemini31ProPreviewCustomTools
   , googleVertexGemini35Flash
   , googleVertexGeminiFlashLatest
   , googleVertexGeminiFlashLiteLatest
   ]

def mistralModel
    (id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := false)
    (input : Array String := #["text"]) : ModelInfo :=
  { id := id
    name := name
    provider := mistralProviderId
    api := LeanAgent.AI.Api.MistralConversations.api
    baseUrl := mistralBaseUrl
    reasoning := reasoning
    input := input
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
  }

def textImageInput : Array String := #["text", "image"]

def mistralModels : Array ModelInfo :=
  #[ mistralModel "codestral-latest" "Codestral (latest)" 0.3 0.9 0.03 0.0 256000 4096
   , mistralModel "devstral-2512" "Devstral 2" 0.4 2.0 0.04 0.0 262144 262144
   , mistralModel "devstral-latest" "Devstral 2" 0.4 2.0 0.04 0.0 262144 262144
   , mistralModel "devstral-medium-2507" "Devstral Medium" 0.4 2.0 0.04 0.0 128000 128000
   , mistralModel "devstral-medium-latest" "Devstral 2 (latest)" 0.4 2.0 0.04 0.0 262144 262144
   , mistralModel "devstral-small-2505" "Devstral Small 2505" 0.1 0.3 0.01 0.0 128000 128000
   , mistralModel "devstral-small-2507" "Devstral Small" 0.1 0.3 0.01 0.0 128000 128000
   , mistralModel "labs-devstral-small-2512" "Devstral Small 2" 0.0 0.0 0.0 0.0 256000 256000 false textImageInput
   , mistralModel "magistral-medium-latest" "Magistral Medium (latest)" 2.0 5.0 0.2 0.0 128000 16384 true
   , mistralModel "magistral-small" "Magistral Small" 0.5 1.5 0.05 0.0 128000 128000 true
   , mistralModel "ministral-3b-latest" "Ministral 3B (latest)" 0.04 0.04 0.004 0.0 128000 128000
   , mistralModel "ministral-8b-latest" "Ministral 8B (latest)" 0.1 0.1 0.01 0.0 128000 128000
   , mistralModel "mistral-large-2411" "Mistral Large 2.1" 2.0 6.0 0.2 0.0 131072 16384
   , mistralModel "mistral-large-2512" "Mistral Large 3" 0.5 1.5 0.05 0.0 262144 262144 false textImageInput
   , mistralModel "mistral-large-latest" "Mistral Large (latest)" 0.5 1.5 0.05 0.0 262144 262144 false textImageInput
   , mistralModel "mistral-medium-2505" "Mistral Medium 3" 0.4 2.0 0.04 0.0 131072 131072 false textImageInput
   , mistralModel "mistral-medium-2508" "Mistral Medium 3.1" 0.4 2.0 0.04 0.0 262144 262144 false textImageInput
   , mistralModel "mistral-medium-2604" "Mistral Medium 3.5" 1.5 7.5 0.15 0.0 262144 262144 true textImageInput
   , mistralModel "mistral-medium-3.5" "Mistral Medium 3.5" 1.5 7.5 0.0 0.0 262144 262144 true textImageInput
   , mistralModel "mistral-medium-latest" "Mistral Medium (latest)" 0.4 2.0 0.04 0.0 262144 262144 false textImageInput
   , mistralModel "mistral-nemo" "Mistral Nemo" 0.15 0.15 0.015 0.0 128000 128000
   , mistralModel "mistral-small-2506" "Mistral Small 3.2" 0.1 0.3 0.01 0.0 128000 16384 false textImageInput
   , mistralModel "mistral-small-2603" "Mistral Small 4" 0.15 0.6 0.015 0.0 256000 256000 true textImageInput
   , mistralModel "mistral-small-latest" "Mistral Small (latest)" 0.15 0.6 0.015 0.0 256000 256000 true textImageInput
   , mistralModel "open-mistral-7b" "Mistral 7B" 0.25 0.25 0.025 0.0 8000 8000
   , mistralModel "open-mistral-nemo" "Open Mistral Nemo" 0.15 0.15 0.015 0.0 128000 128000
   , mistralModel "open-mixtral-8x22b" "Mixtral 8x22B" 2.0 6.0 0.2 0.0 64000 64000
   , mistralModel "open-mixtral-8x7b" "Mixtral 8x7B" 0.7 0.7 0.07 0.0 32000 32000
   , mistralModel "pixtral-12b" "Pixtral 12B" 0.15 0.15 0.015 0.0 128000 128000 false textImageInput
   , mistralModel "pixtral-large-latest" "Pixtral Large (latest)" 2.0 6.0 0.2 0.0 128000 128000 false textImageInput
   ]

def azureModel
    (id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := false)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[])
    (input : Array String := #["text"]) : ModelInfo :=
  { id := id
    name := name
    provider := azureOpenAIResponsesProviderId
    api := "azure-openai-responses"
    baseUrl := azureOpenAIResponsesBaseUrl
    reasoning := reasoning
    thinkingLevelMap := thinkingLevelMap
    input := input
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
  }

def azureThinkingOffMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[{ level := .off, mapped := none }]

def azureThinkingOffXHighMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := none }
   , { level := .level .xhigh, mapped := some "xhigh" }
   ]

def azureGpt55ProThinkingMap : Array LeanAgent.AI.ThinkingLevelMapEntry :=
  #[ { level := .off, mapped := none }
   , { level := .level .xhigh, mapped := some "xhigh" }
   , { level := .level .minimal, mapped := none }
   , { level := .level .low, mapped := none }
   ]

def azureOpenAIResponsesModels : Array ModelInfo :=
  #[ azureModel "gpt-4" "GPT-4" 30.0 60.0 0.0 0.0 8192 8192
   , azureModel "gpt-4-turbo" "GPT-4 Turbo" 10.0 30.0 0.0 0.0 128000 4096 false #[] textImageInput
   , azureModel "gpt-4.1" "GPT-4.1" 2.0 8.0 0.5 0.0 1047576 32768 false #[] textImageInput
   , azureModel "gpt-4.1-mini" "GPT-4.1 mini" 0.4 1.6 0.1 0.0 1047576 32768 false #[] textImageInput
   , azureModel "gpt-4.1-nano" "GPT-4.1 nano" 0.1 0.4 0.025 0.0 1047576 32768 false #[] textImageInput
   , azureModel "gpt-4o" "GPT-4o" 2.5 10.0 1.25 0.0 128000 16384 false #[] textImageInput
   , azureModel "gpt-4o-2024-05-13" "GPT-4o (2024-05-13)" 5.0 15.0 0.0 0.0 128000 4096 false #[] textImageInput
   , azureModel "gpt-4o-2024-08-06" "GPT-4o (2024-08-06)" 2.5 10.0 1.25 0.0 128000 16384 false #[] textImageInput
   , azureModel "gpt-4o-2024-11-20" "GPT-4o (2024-11-20)" 2.5 10.0 1.25 0.0 128000 16384 false #[] textImageInput
   , azureModel "gpt-4o-mini" "GPT-4o mini" 0.15 0.6 0.075 0.0 128000 16384 false #[] textImageInput
   , azureModel "gpt-5" "GPT-5" 1.25 10.0 0.125 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5-chat-latest" "GPT-5 Chat Latest" 1.25 10.0 0.125 0.0 128000 16384 false azureThinkingOffMap textImageInput
   , azureModel "gpt-5-codex" "GPT-5-Codex" 1.25 10.0 0.125 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5-mini" "GPT-5 Mini" 0.25 2.0 0.025 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5-nano" "GPT-5 Nano" 0.05 0.4 0.005 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5-pro" "GPT-5 Pro" 15.0 120.0 0.0 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5.1" "GPT-5.1" 1.25 10.0 0.125 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5.1-chat-latest" "GPT-5.1 Chat" 1.25 10.0 0.125 0.0 128000 16384 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5.1-codex" "GPT-5.1 Codex" 1.25 10.0 0.125 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5.1-codex-max" "GPT-5.1 Codex Max" 1.25 10.0 0.125 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5.1-codex-mini" "GPT-5.1 Codex mini" 0.25 2.0 0.025 0.0 400000 128000 true azureThinkingOffMap textImageInput
   , azureModel "gpt-5.2" "GPT-5.2" 1.75 14.0 0.175 0.0 400000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.2-chat-latest" "GPT-5.2 Chat" 1.75 14.0 0.175 0.0 128000 16384 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.2-codex" "GPT-5.2 Codex" 1.75 14.0 0.175 0.0 400000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.2-pro" "GPT-5.2 Pro" 21.0 168.0 0.0 0.0 400000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.3-chat-latest" "GPT-5.3 Chat (latest)" 1.75 14.0 0.175 0.0 128000 16384 false azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.3-codex" "GPT-5.3 Codex" 1.75 14.0 0.175 0.0 400000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.3-codex-spark" "GPT-5.3 Codex Spark" 1.75 14.0 0.175 0.0 128000 32000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.4" "GPT-5.4" 2.5 15.0 0.25 0.0 1050000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.4-mini" "GPT-5.4 mini" 0.75 4.5 0.075 0.0 400000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.4-nano" "GPT-5.4 nano" 0.2 1.25 0.02 0.0 400000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.4-pro" "GPT-5.4 Pro" 30.0 180.0 0.0 0.0 1050000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.5" "GPT-5.5" 5.0 30.0 0.5 0.0 1050000 128000 true azureThinkingOffXHighMap textImageInput
   , azureModel "gpt-5.5-pro" "GPT-5.5 Pro" 30.0 180.0 0.0 0.0 1050000 128000 true azureGpt55ProThinkingMap textImageInput
   , azureModel "o1" "o1" 15.0 60.0 7.5 0.0 200000 100000 true #[] textImageInput
   , azureModel "o1-pro" "o1-pro" 150.0 600.0 0.0 0.0 200000 100000 true #[] textImageInput
   , azureModel "o3" "o3" 2.0 8.0 0.5 0.0 200000 100000 true #[] textImageInput
   , azureModel "o3-deep-research" "o3-deep-research" 10.0 40.0 2.5 0.0 200000 100000 true #[] textImageInput
   , azureModel "o3-mini" "o3-mini" 1.1 4.4 0.55 0.0 200000 100000 true
   , azureModel "o3-pro" "o3-pro" 20.0 80.0 0.0 0.0 200000 100000 true #[] textImageInput
   , azureModel "o4-mini" "o4-mini" 1.1 4.4 0.275 0.0 200000 100000 true #[] textImageInput
   , azureModel "o4-mini-deep-research" "o4-mini-deep-research" 2.0 8.0 0.5 0.0 200000 100000 true #[] textImageInput
   ]

structure ProviderInfo where
  id : String
  name : String
  baseUrl : String
  apiKeyEnv : String
  apiKeyEnvs : Array String := #[]
  modelEnv : Option String := none
  defaultModel : String
  models : Array ModelInfo := #[]
deriving Repr, BEq

def ProviderInfo.authEnvs (provider : ProviderInfo) : Array String :=
  let envs := if provider.apiKeyEnvs.isEmpty then #[provider.apiKeyEnv] else provider.apiKeyEnvs
  envs.filter fun env => !env.trimAscii.isEmpty

def ProviderInfo.model? (provider : ProviderInfo) (modelId : String) : Option ModelInfo :=
  provider.models.find? (fun model => model.id == modelId)

def ProviderInfo.supportsApi (provider : ProviderInfo) (api : String) : Bool :=
  provider.models.any fun model => model.api == api

def deepSeekProviderInfo : ProviderInfo :=
  { id := deepSeekProviderId
    name := "DeepSeek"
    baseUrl := deepSeekBaseUrl
    apiKeyEnv := deepSeekApiKeyEnv
    modelEnv := some deepSeekModelEnv
    defaultModel := deepSeekDefaultModel
    models := #[deepSeekV4Flash, deepSeekV4Pro]
  }

def openAIProviderInfo : ProviderInfo :=
  { id := openAIProviderId
    name := "OpenAI"
    baseUrl := openAIBaseUrl
    apiKeyEnv := openAIKeyEnv
    modelEnv := some openAIModelEnv
    defaultModel := openAIDefaultModel
    models := openAIResponsesModels
  }

def openAICodexProviderInfo : ProviderInfo :=
  { id := openAICodexProviderId
    name := "OpenAI Codex"
    baseUrl := openAICodexBaseUrl
    apiKeyEnv := ""
    defaultModel := openAICodexDefaultModel
    models := openAICodexModels
  }

def azureOpenAIResponsesProviderInfo : ProviderInfo :=
  { id := azureOpenAIResponsesProviderId
    name := "Azure OpenAI"
    baseUrl := azureOpenAIResponsesBaseUrl
    apiKeyEnv := azureOpenAIResponsesApiKeyEnv
    defaultModel := azureOpenAIResponsesDefaultModel
    models := azureOpenAIResponsesModels
  }

def openRouterProviderInfo : ProviderInfo :=
  { id := openRouterProviderId
    name := "OpenRouter"
    baseUrl := openRouterBaseUrl
    apiKeyEnv := openRouterApiKeyEnv
    defaultModel := openRouterDefaultModel
    models := #[openRouterGptOss120B]
  }

def groqProviderInfo : ProviderInfo :=
  { id := groqProviderId
    name := "Groq"
    baseUrl := groqBaseUrl
    apiKeyEnv := groqApiKeyEnv
    defaultModel := groqDefaultModel
    models := #[groqGptOss120B]
  }

def xaiProviderInfo : ProviderInfo :=
  { id := xaiProviderId
    name := "xAI"
    baseUrl := xaiBaseUrl
    apiKeyEnv := xaiApiKeyEnv
    defaultModel := xaiDefaultModel
    models := #[xaiGrokCodeFast1]
  }

def cerebrasProviderInfo : ProviderInfo :=
  { id := cerebrasProviderId
    name := "Cerebras"
    baseUrl := cerebrasBaseUrl
    apiKeyEnv := cerebrasApiKeyEnv
    defaultModel := cerebrasDefaultModel
    models := #[cerebrasGptOss120B]
  }

def togetherProviderInfo : ProviderInfo :=
  { id := togetherProviderId
    name := "Together"
    baseUrl := togetherBaseUrl
    apiKeyEnv := togetherApiKeyEnv
    defaultModel := togetherDefaultModel
    models := #[togetherGptOss120B]
  }

def fireworksProviderInfo : ProviderInfo :=
  { id := fireworksProviderId
    name := "Fireworks"
    baseUrl := fireworksBaseUrl
    apiKeyEnv := fireworksApiKeyEnv
    defaultModel := fireworksDefaultModel
    models := #[fireworksGlm52]
  }

def anthropicProviderInfo : ProviderInfo :=
  { id := anthropicProviderId
    name := "Anthropic"
    baseUrl := anthropicBaseUrl
    apiKeyEnv := anthropicApiKeyEnv
    apiKeyEnvs := #[anthropicOAuthTokenEnv, anthropicApiKeyEnv]
    defaultModel := anthropicDefaultModel
    models := #[anthropicSonnet45, anthropicHaiku45, anthropicOpus45, anthropicSonnet37]
  }

def googleProviderInfo : ProviderInfo :=
  { id := googleProviderId
    name := "Google"
    baseUrl := googleBaseUrl
    apiKeyEnv := googleApiKeyEnv
    defaultModel := googleDefaultModel
    models := googleModels
  }

def googleVertexProviderInfo : ProviderInfo :=
  { id := googleVertexProviderId
    name := "Google Vertex AI"
    baseUrl := googleVertexBaseUrl
    apiKeyEnv := googleVertexApiKeyEnv
    defaultModel := googleVertexDefaultModel
    models := googleVertexModels
  }

def mistralProviderInfo : ProviderInfo :=
  { id := mistralProviderId
    name := "Mistral"
    baseUrl := mistralBaseUrl
    apiKeyEnv := mistralApiKeyEnv
    defaultModel := mistralDefaultModel
    models := mistralModels
  }

structure ProviderCatalog where
  providers : Array ProviderInfo := #[]
deriving Repr, BEq

def defaultCatalog : ProviderCatalog :=
  { providers :=
    #[ deepSeekProviderInfo
     , openAIProviderInfo
     , openAICodexProviderInfo
     , azureOpenAIResponsesProviderInfo
     , openRouterProviderInfo
     , groqProviderInfo
       , xaiProviderInfo
       , cerebrasProviderInfo
       , togetherProviderInfo
       , fireworksProviderInfo
     , anthropicProviderInfo
     , googleProviderInfo
     , googleVertexProviderInfo
     , mistralProviderInfo
     ]
  }

def ProviderCatalog.provider? (catalog : ProviderCatalog) (id : String) : Option ProviderInfo :=
  catalog.providers.find? (fun provider => provider.id == id)

def ProviderCatalog.providerByApiKeyEnv? (catalog : ProviderCatalog) (apiKeyEnv : String) : Option ProviderInfo :=
  catalog.providers.find? (fun provider => provider.authEnvs.contains apiKeyEnv)

def ProviderCatalog.model? (catalog : ProviderCatalog) (providerId modelId : String) : Option ModelInfo :=
  match catalog.provider? providerId with
  | some provider => provider.model? modelId
  | none => none

def ProviderCatalog.defaultModelIdForApiKeyEnv? (catalog : ProviderCatalog) (apiKeyEnv : String) : Option String :=
  catalog.providerByApiKeyEnv? apiKeyEnv |>.map (fun provider => provider.defaultModel)

def modelLine (model : ModelInfo) : String :=
  let context :=
    if model.contextWindow == 0 then
      "context=unknown"
    else
      s!"context={model.contextWindow}"
  let maxTokens :=
    if model.maxTokens == 0 then
      "max_output=unknown"
    else
      s!"max_output={model.maxTokens}"
  s!"{model.qualifiedId}  {model.name}  api={model.api}  {context}  {maxTokens}"

def providerLines (provider : ProviderInfo) : List String :=
  s!"# {provider.name} ({provider.id})" :: provider.models.toList.map modelLine

def catalogLines : List ProviderInfo → List String
  | [] => []
  | provider :: rest => providerLines provider ++ catalogLines rest

def renderCatalog (catalog : ProviderCatalog := defaultCatalog) : String :=
  String.intercalate "\n" (catalogLines catalog.providers.toList)

def provider
    (baseUrl apiKey : String)
    (noProxy : Option String := none) : ModelProvider :=
  LeanAgent.AI.Api.OpenAICompletions.provider
    { apiKey := apiKey
      baseUrl := baseUrl
      noProxy := noProxy
    }

inductive ModelsErrorCode where
  | modelSource
  | modelValidation
  | provider
  | stream
  | auth
deriving BEq

def ModelsErrorCode.toString : ModelsErrorCode → String
  | .modelSource => "model_source"
  | .modelValidation => "model_validation"
  | .provider => "provider"
  | .stream => "stream"
  | .auth => "auth"

def modelsError (code : ModelsErrorCode) (message : String) : IO.Error :=
  IO.userError s!"ModelsError({code.toString}): {message}"

structure ProviderStreams where
  streamSimple :
    ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

def ProviderStreams.completeSimple
    (streams : ProviderStreams)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← streams.streamSimple model context options
  pure stream.result

def ProviderStreams.lazy (load : IO ProviderStreams) : ProviderStreams :=
  { streamSimple := fun model context options =>
      LeanAgent.AI.Api.Lazy.lazyStream model.toModelRef do
        let streams ← load
        streams.streamSimple model context options
  }

structure Provider where
  id : String
  name : String
  baseUrl : Option String := none
  headers : LeanAgent.AI.Auth.ProviderHeaders := #[]
  auth : LeanAgent.AI.Auth.ProviderAuth
  getModels : IO (Array ModelInfo)
  refreshModels : Option (IO Unit) := none
  streamSimple :
    ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
      IO LeanAgent.AI.AssistantMessageEventStream

def Provider.completeSimple
    (provider : Provider)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← provider.streamSimple model context options
  pure stream.result

structure ApiDispatch where
  api : String
  streams : ProviderStreams

structure CreateProviderOptions where
  id : String
  name : Option String := none
  baseUrl : Option String := none
  headers : LeanAgent.AI.Auth.ProviderHeaders := #[]
  auth : LeanAgent.AI.Auth.ProviderAuth
  models : Array ModelInfo := #[]
  refreshModels : Option (IO (Array ModelInfo)) := none
  apis : Array ApiDispatch

def apiDispatchFor? (dispatches : Array ApiDispatch) (api : String) : Option ProviderStreams :=
  dispatches.findSome? fun dispatch =>
    if dispatch.api == api then some dispatch.streams else none

def createProvider (input : CreateProviderOptions) : IO Provider := do
  let modelsRef ← IO.mkRef input.models
  let refreshModels :=
    input.refreshModels.map fun refresh => do
      let refreshed ← refresh
      modelsRef.set refreshed
  pure
    { id := input.id
      name := input.name.getD input.id
      baseUrl := input.baseUrl
      headers := input.headers
      auth := input.auth
      getModels := modelsRef.get
      refreshModels := refreshModels
      streamSimple := fun model context options => do
        LeanAgent.AI.Api.Lazy.lazyStream model.toModelRef do
          match apiDispatchFor? input.apis model.api with
          | some streams => streams.streamSimple model context options
          | none =>
              throw (modelsError .stream s!"Provider {input.id} has no API implementation for \"{model.api}\"")
    }

def hasApi (model : ModelInfo) (api : String) : Bool :=
  model.api == api

def modelsAreEqual (a b : Option ModelInfo) : Bool :=
  match a, b with
  | some a, some b => a.id == b.id && a.provider == b.provider
  | _, _ => false

def extendedThinkingLevels : Array LeanAgent.AI.ModelThinkingLevel :=
  #[ .off
   , .level .minimal
   , .level .low
   , .level .medium
   , .level .high
   , .level .xhigh
   ]

def getSupportedThinkingLevels (model : ModelInfo) : Array LeanAgent.AI.ModelThinkingLevel :=
  if !model.reasoning then
    #[.off]
  else
    extendedThinkingLevels.filter fun level =>
      match model.thinkingLevelMap.find? (fun entry => entry.level == level) with
      | some { mapped := none, .. } => false
      | some _ => true
      | none => level != .level .xhigh

def thinkingLevelMapValue? (model : ModelInfo) (level : LeanAgent.AI.ModelThinkingLevel) :
    Option (Option String) :=
  (model.thinkingLevelMap.find? fun entry => entry.level == level).map (fun entry => entry.mapped)

def thinkingLevelPayloadValueD
    (model : ModelInfo)
    (level : LeanAgent.AI.ModelThinkingLevel)
    (fallback : String) : String :=
  match thinkingLevelMapValue? model level with
  | some (some value) => value
  | _ => fallback

def offThinkingLevelPayloadValue? (model : ModelInfo) : Option String :=
  match thinkingLevelMapValue? model .off with
  | some (some value) => some value
  | _ => none

def openAICompletionsOptionsFromSimple
    (model : ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions :=
  let apiOptions := LeanAgent.AI.Api.OpenAICompletions.optionsFromSimple options
  let reasoningValue :=
    match apiOptions.reasoningEffort with
    | some effort => some (thinkingLevelPayloadValueD model (.level effort) effort.toString)
    | none =>
        match apiOptions.reasoning with
        | some effort => some (thinkingLevelPayloadValueD model (.level effort) effort.toString)
        | none => none
  let offValue :=
    if model.reasoning && reasoningValue.isNone then
      offThinkingLevelPayloadValue? model
    else
      none
  { apiOptions with
    reasoningEffortValue := reasoningValue
    offReasoningEffortValue := offValue
  }

def thinkingLevelIndex? : LeanAgent.AI.ModelThinkingLevel → Option Nat
  | .off => some 0
  | .level .minimal => some 1
  | .level .low => some 2
  | .level .medium => some 3
  | .level .high => some 4
  | .level .xhigh => some 5

def clampThinkingLevel
    (model : ModelInfo)
    (level : LeanAgent.AI.ModelThinkingLevel) : LeanAgent.AI.ModelThinkingLevel :=
  let available := getSupportedThinkingLevels model
  if available.contains level then
    level
  else
    match thinkingLevelIndex? level with
    | none => available[0]?.getD .off
    | some requested =>
        let upward := extendedThinkingLevels.filter fun candidate =>
          match thinkingLevelIndex? candidate with
          | some index => requested <= index && available.contains candidate
          | none => false
        match upward[0]? with
        | some candidate => candidate
        | none =>
            let downward := extendedThinkingLevels.filter fun candidate =>
              match thinkingLevelIndex? candidate with
              | some index => index < requested && available.contains candidate
              | none => false
            match downward.back? with
            | some candidate => candidate
            | none => available[0]?.getD .off

def perMillionCost (rate : Float) (tokens : Nat) : Float :=
  (rate / 1000000.0) * Float.ofNat tokens

def calculateCost (model : ModelInfo) (usage : LeanAgent.AI.Usage) : LeanAgent.AI.UsageCost :=
  let longWrite := usage.cacheWrite1h.getD 0
  let shortWrite := usage.cacheWrite - longWrite
  let input := perMillionCost model.cost.input usage.input
  let output := perMillionCost model.cost.output usage.output
  let cacheRead := perMillionCost model.cost.cacheRead usage.cacheRead
  let cacheWrite :=
    ((model.cost.cacheWrite * Float.ofNat shortWrite) + (model.cost.input * 2.0 * Float.ofNat longWrite)) /
      1000000.0
  { input := input
    output := output
    cacheRead := cacheRead
    cacheWrite := cacheWrite
    total := input + output + cacheRead + cacheWrite
  }

def applyUsageCost (model : ModelInfo) (usage : LeanAgent.AI.Usage) : LeanAgent.AI.Usage :=
  { usage with cost := calculateCost model usage }

def applyUsageCostToMessage (model : ModelInfo) (message : LeanAgent.AI.AssistantMessage) :
    LeanAgent.AI.AssistantMessage :=
  { message with usage := applyUsageCost model message.usage }

def mapEventMessage
    (f : LeanAgent.AI.AssistantMessage → LeanAgent.AI.AssistantMessage) :
    LeanAgent.AI.AssistantMessageEvent → LeanAgent.AI.AssistantMessageEvent
  | .start snapshot => .start (f snapshot)
  | .textStart index snapshot => .textStart index (f snapshot)
  | .textDelta index delta snapshot => .textDelta index delta (f snapshot)
  | .textEnd index content snapshot => .textEnd index content (f snapshot)
  | .thinkingStart index snapshot => .thinkingStart index (f snapshot)
  | .thinkingDelta index delta snapshot => .thinkingDelta index delta (f snapshot)
  | .thinkingEnd index content snapshot => .thinkingEnd index content (f snapshot)
  | .toolCallStart index snapshot => .toolCallStart index (f snapshot)
  | .toolCallDelta index delta snapshot => .toolCallDelta index delta (f snapshot)
  | .toolCallEnd index call snapshot => .toolCallEnd index call (f snapshot)
  | .done reason message => .done reason (f message)
  | .error reason message => .error reason (f message)

def applyUsageCostToStream
    (model : ModelInfo)
    (stream : LeanAgent.AI.AssistantMessageEventStream) :
    LeanAgent.AI.AssistantMessageEventStream :=
  let update := applyUsageCostToMessage model
  { events := stream.events.map (mapEventMessage update)
    finalResult := update stream.finalResult
  }

def legacyToolFromAITool (tool : LeanAgent.AI.Tool) : AgentTool :=
  { name := tool.name
    description := tool.description
    inputSchema := tool.parameters
    execute := fun call =>
      pure
        { toolCallId := call.id
          name := call.name
          ok := false
          content := "AI runtime provider placeholder tools are not executable"
          error := some "tool execution is owned by the agent loop"
        }
  }

def contextToProviderRequest (model : ModelInfo) (context : LeanAgent.AI.Context) : ProviderRequest :=
  { model := model.id
    system := context.systemPrompt.getD ""
    messages := context.messages.map LeanAgent.AI.toLegacyMessage
    tools := context.tools.map legacyToolFromAITool
  }

def clampMaxTokensToContext (model : ModelInfo) (context : LeanAgent.AI.Context) (maxTokens : Nat) : Nat :=
  LeanAgent.AI.Api.SimpleOptions.clampMaxTokensToContext model.contextWindow context maxTokens

def resolvedMaxTokens? (model : ModelInfo) (context : LeanAgent.AI.Context) (options : LeanAgent.AI.SimpleStreamOptions) :
    Option Nat :=
  LeanAgent.AI.Api.SimpleOptions.resolvedMaxTokens? model.contextWindow model.maxTokens context options

def clampSimpleOptionsToContext
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions) : LeanAgent.AI.SimpleStreamOptions :=
  let options :=
    LeanAgent.AI.Api.SimpleOptions.clampStreamOptionsToContext model.contextWindow model.maxTokens context options
  match options.reasoning with
  | none => options
  | some level =>
      match clampThinkingLevel model (.level level) with
      | .off => { options with reasoning := none }
      | .level clamped => { options with reasoning := some clamped }

def hasHeaderAuth (headers : Array (String × Option String)) : Bool :=
  headers.any fun (name, value) =>
    let name := name.toLower
    let valueSet :=
      match value with
      | some value => !value.trimAscii.isEmpty
      | none => false
    valueSet &&
      (name == "authorization" || name == "x-api-key" || name == "x-goog-api-key" ||
        name == "cf-aig-authorization")

def requireApiKeyOrHeaderAuth
    (providerId : String)
    (options : LeanAgent.AI.SimpleStreamOptions) : IO String := do
  match options.apiKey with
  | some apiKey => pure apiKey
  | none =>
      if hasHeaderAuth options.headers then
        pure ""
      else
        throw (modelsError .auth s!"missing API key for provider {providerId}")

def openAICompatibleStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.OpenAICompletions.OpenAICompatibleConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      let request := contextToProviderRequest model context
      let stream ← LeanAgent.AI.Api.OpenAICompletions.streamWithOptions
        config
        request
        model.api
        model.provider
        (openAICompletionsOptionsFromSimple model options)
      pure (applyUsageCostToStream model stream)
  }

def openAIResponsesStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      LeanAgent.AI.Api.OpenAIResponses.completeStreamWithOptions
        config
        model.toResponsesModel
        context
        (LeanAgent.AI.Api.OpenAIResponses.optionsFromSimple options)
  }

def openAICodexResponsesStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      match options.apiKey with
      | none => throw (modelsError .auth s!"missing OAuth access token for provider {model.provider}")
      | some apiKey =>
          let config : LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesConfig :=
            { apiKey := apiKey
              baseUrl := model.baseUrl
            }
          LeanAgent.AI.Api.OpenAICodexResponses.completeStreamWithOptions
            config
            model.toResponsesModel
            context
            (LeanAgent.AI.Api.OpenAICodexResponses.optionsFromSimple options)
  }

def azureOpenAIResponsesStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      match options.apiKey with
      | none => throw (modelsError .auth s!"missing API key for provider {model.provider}")
      | some apiKey =>
          let config : LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesConfig :=
            { apiKey := apiKey
              baseUrl := model.baseUrl
            }
          LeanAgent.AI.Api.AzureOpenAIResponses.completeStreamWithOptions
            config
            model.toResponsesModel
            context
            (LeanAgent.AI.Api.AzureOpenAIResponses.optionsFromSimple options)
  }

def anthropicMessagesOptionsFromSimple
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions :=
  let base := LeanAgent.AI.Api.AnthropicMessages.optionsFromSimple options
  match options.reasoning with
  | none =>
      { base with thinkingEnabled := some false }
  | some level =>
      let maxTokens := (resolvedMaxTokens? model context options).getD model.maxTokens
      let adjusted := LeanAgent.AI.Api.SimpleOptions.adjustMaxTokensForThinking
        (some maxTokens) model.maxTokens level options.thinkingBudgets
      let thinkingBudget := Nat.min adjusted.thinkingBudget (maxTokens - Nat.min maxTokens 1024)
      { base with
        maxTokens := some maxTokens
        thinkingEnabled := some true
        thinkingBudgetTokens := some thinkingBudget
      }

def anthropicMessagesStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      let stream ← LeanAgent.AI.Api.AnthropicMessages.completeStreamWithOptions
        config
        model.toModelRef
        model.input
        model.maxTokens
        model.reasoning
        context
        (anthropicMessagesOptionsFromSimple model context options)
      pure (applyUsageCostToStream model stream)
  }

def modelIdLower (model : ModelInfo) : String :=
  model.id.toLower

def isGemini3ProModel (model : ModelInfo) : Bool :=
  let id := modelIdLower model
  id.startsWith "gemini-3-pro" || id.startsWith "gemini-3.1-pro"

def isGemini3FlashModel (model : ModelInfo) : Bool :=
  let id := modelIdLower model
  id.startsWith "gemini-3-flash" ||
    id.startsWith "gemini-3.1-flash" ||
    id == "gemini-flash-latest" ||
    id == "gemini-flash-lite-latest"

def isGemma4Model (model : ModelInfo) : Bool :=
  (modelIdLower model).contains "gemma-4"

def googleDisabledThinkingLevel? (model : ModelInfo) : Option String :=
  if isGemini3ProModel model then
    some "LOW"
  else if isGemini3FlashModel model || isGemma4Model model then
    some "MINIMAL"
  else
    none

def googleThinkingLevel (model : ModelInfo) (effort : LeanAgent.AI.ThinkingLevel) : String :=
  if isGemini3ProModel model then
    match effort with
    | .minimal => "LOW"
    | .low => "LOW"
    | .medium => "HIGH"
    | .high => "HIGH"
    | .xhigh => "HIGH"
  else if isGemma4Model model then
    match effort with
    | .minimal => "MINIMAL"
    | .low => "MINIMAL"
    | .medium => "HIGH"
    | .high => "HIGH"
    | .xhigh => "HIGH"
  else
    match effort with
    | .minimal => "MINIMAL"
    | .low => "LOW"
    | .medium => "MEDIUM"
    | .high => "HIGH"
    | .xhigh => "HIGH"

def budgetForLevel (budgets : LeanAgent.AI.ThinkingBudgets) :
    LeanAgent.AI.ThinkingLevel → Option Nat
  | .minimal => budgets.minimal
  | .low => budgets.low
  | .medium => budgets.medium
  | .high => budgets.high
  | .xhigh => budgets.high

def googleThinkingBudget
    (model : ModelInfo)
    (effort : LeanAgent.AI.ThinkingLevel)
    (customBudgets : Option LeanAgent.AI.ThinkingBudgets) : Int :=
  match customBudgets.bind (fun budgets => budgetForLevel budgets effort) with
  | some budget => Int.ofNat budget
  | none =>
      if model.id.contains "2.5-pro" then
        match effort with
        | .minimal => 128
        | .low => 2048
        | .medium => 8192
        | .high => 32768
        | .xhigh => 32768
      else if model.id.contains "2.5-flash-lite" then
        match effort with
        | .minimal => 512
        | .low => 2048
        | .medium => 8192
        | .high => 24576
        | .xhigh => 24576
      else if model.id.contains "2.5-flash" then
        match effort with
        | .minimal => 128
        | .low => 2048
        | .medium => 8192
        | .high => 24576
        | .xhigh => 24576
      else
        -1

def googleGenerativeAIOptionsFromSimple
    (model : ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions :=
  let base := LeanAgent.AI.Api.GoogleGenerativeAI.optionsFromSimple options
  match options.reasoning with
  | none =>
      { base with
        thinkingEnabled := some false
        thinkingLevel := googleDisabledThinkingLevel? model
      }
  | some effort =>
      if isGemini3ProModel model || isGemini3FlashModel model || isGemma4Model model then
        { base with
          thinkingEnabled := some true
          thinkingLevel := some (googleThinkingLevel model effort)
        }
      else
        let budget := googleThinkingBudget model effort options.thinkingBudgets
        { base with
          thinkingEnabled := some true
          thinkingBudgetTokens := if budget < 0 then none else some budget.toNat
        }

def googleGenerativeAIStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      let stream ← LeanAgent.AI.Api.GoogleGenerativeAI.completeStreamWithOptions
        config
        model.toModelRef
        model.input
        model.reasoning
        context
        (googleGenerativeAIOptionsFromSimple model options)
      pure (applyUsageCostToStream model stream)
  }

def googleVertexOptionsFromSimple
    (model : ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.GoogleVertex.GoogleVertexOptions :=
  let googleOptions := googleGenerativeAIOptionsFromSimple model options
  { temperature := googleOptions.temperature
    maxTokens := googleOptions.maxTokens
    apiKey := googleOptions.apiKey
    transport := googleOptions.transport
    cacheRetention := googleOptions.cacheRetention
    sessionId := googleOptions.sessionId
    headers := googleOptions.headers
    onPayload := googleOptions.onPayload
    onResponse := googleOptions.onResponse
    timeoutMs := googleOptions.timeoutMs
    websocketConnectTimeoutMs := googleOptions.websocketConnectTimeoutMs
    maxRetries := googleOptions.maxRetries
    maxRetryDelayMs := googleOptions.maxRetryDelayMs
    metadata := googleOptions.metadata
    env := googleOptions.env
    reasoning := googleOptions.reasoning
    thinkingBudgets := googleOptions.thinkingBudgets
    toolChoice :=
      match googleOptions.toolChoice with
      | some .auto => some .auto
      | some .none => some .none
      | some .any => some .any
      | none => none
    thinkingEnabled := googleOptions.thinkingEnabled
    thinkingBudgetTokens := googleOptions.thinkingBudgetTokens
    thinkingLevel := googleOptions.thinkingLevel
  }

def googleVertexStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let config : LeanAgent.AI.Api.GoogleVertex.GoogleVertexConfig :=
        { apiKey := options.apiKey.getD ""
          baseUrl := model.baseUrl
        }
      let stream ← LeanAgent.AI.Api.GoogleVertex.completeStreamWithOptions
        config
        model.toModelRef
        model.input
        model.reasoning
        context
        (googleVertexOptionsFromSimple model options)
      pure (applyUsageCostToStream model stream)
  }

def usesMistralReasoningEffort (model : ModelInfo) : Bool :=
  model.id == "mistral-small-2603" ||
    model.id == "mistral-small-latest" ||
    model.id == "mistral-medium-3.5"

def mistralReasoningEffort (model : ModelInfo) (level : LeanAgent.AI.ThinkingLevel) : String :=
  thinkingLevelPayloadValueD model (.level level) "high"

def mistralOptionsFromSimple
    (model : ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.MistralConversations.MistralOptions :=
  let base := LeanAgent.AI.Api.MistralConversations.optionsFromSimple options
  match options.reasoning with
  | none => base
  | some requested =>
      if !model.reasoning then
        base
      else
        match clampThinkingLevel model (.level requested) with
        | .off => base
        | .level level =>
            if usesMistralReasoningEffort model then
              { base with reasoningEffort := some (mistralReasoningEffort model level) }
            else
              { base with promptMode := some "reasoning" }

def mistralConversationsStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let apiKey ← requireApiKeyOrHeaderAuth model.provider options
      let config : LeanAgent.AI.Api.MistralConversations.MistralConversationsConfig :=
        { apiKey := apiKey
          baseUrl := model.baseUrl
        }
      let stream ← LeanAgent.AI.Api.MistralConversations.completeStreamWithOptions
        config
        model.toModelRef
        model.input
        context
        (mistralOptionsFromSimple model options)
      pure (applyUsageCostToStream model stream)
  }

def googleVertexAdcPath : String := "~/.config/gcloud/application_default_credentials.json"

def googleVertexHasAdcCredentials
    (ctx : LeanAgent.AI.Auth.AuthContext) : IO Bool := do
  let credentialsPath ←
    match ← ctx.env "GOOGLE_APPLICATION_CREDENTIALS" with
    | some path => pure path
    | none => pure googleVertexAdcPath
  let hasCredentials ← ctx.fileExists credentialsPath
  let project ←
    match ← ctx.env "GOOGLE_CLOUD_PROJECT" with
    | some project => pure (some project)
    | none => ctx.env "GCLOUD_PROJECT"
  let location ← ctx.env "GOOGLE_CLOUD_LOCATION"
  pure (hasCredentials && project.isSome && location.isSome)

def googleVertexApiKeyAuth : LeanAgent.AI.Auth.ApiKeyAuth :=
  { name := "Google Cloud credentials"
    resolve := fun ctx credential _modelBaseUrl => do
      let credentialEnv := credential.map (fun value => value.env) |>.getD #[]
      match credential.bind (fun value => value.key) with
      | some key =>
          if key.trimAscii.toString.isEmpty then
            pure none
          else
            pure (some
              { auth := { apiKey := some key }
                env := credentialEnv
                source := some "stored credential"
              })
      | none =>
          match ← ctx.env googleVertexApiKeyEnv with
          | some key =>
              pure (some
                { auth := { apiKey := some key }
                  env := credentialEnv
                  source := some googleVertexApiKeyEnv
                })
          | none =>
              if ← googleVertexHasAdcCredentials ctx then
                pure (some
                  { auth := { apiKey := some LeanAgent.AI.Api.GoogleVertex.vertexCredentialsMarker }
                    env := credentialEnv
                    source := some "gcloud application default credentials"
                  })
              else
                pure none
  }

def openAICodexOAuthAuth : LeanAgent.AI.Auth.OAuthAuth :=
  { name := "OpenAI (ChatGPT Plus/Pro)"
    refresh := fun _ =>
      throw (IO.userError "OpenAI Codex OAuth refresh is not implemented")
    toAuth := fun credential =>
      pure { apiKey := some credential.access }
  }

def authForProviderInfo (info : ProviderInfo) : LeanAgent.AI.Auth.ProviderAuth :=
  if info.id == googleVertexProviderId then
    { apiKey := some googleVertexApiKeyAuth }
  else if info.id == openAICodexProviderId then
    { oauth := some openAICodexOAuthAuth }
  else
    { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth (info.name ++ " API key") info.authEnvs) }

def createCatalogProvider (info : ProviderInfo) : IO Provider :=
  createProvider
    { id := info.id
      name := some info.name
      baseUrl := some info.baseUrl
      auth := authForProviderInfo info
      models := info.models
      apis :=
        #[ { api := "openai-completions", streams := openAICompatibleStreams }
         , { api := "openai-responses", streams := openAIResponsesStreams }
         , { api := LeanAgent.AI.Api.OpenAICodexResponses.api, streams := openAICodexResponsesStreams }
         , { api := LeanAgent.AI.Api.AnthropicMessages.api, streams := anthropicMessagesStreams }
         , { api := LeanAgent.AI.Api.GoogleGenerativeAI.api, streams := googleGenerativeAIStreams }
         , { api := LeanAgent.AI.Api.GoogleVertex.api, streams := googleVertexStreams }
         , { api := LeanAgent.AI.Api.MistralConversations.api, streams := mistralConversationsStreams }
         ]
    }

def streamHeaderNames (headers : Array (String × Option String)) : Array String :=
  headers.map Prod.fst

def authHeadersToStreamHeaders
    (authHeaders : LeanAgent.AI.Auth.ProviderHeaders)
    (requestHeaders : Array (String × Option String)) : Array (String × Option String) :=
  let requestNames := streamHeaderNames requestHeaders
  let inherited := authHeaders.filterMap fun (name, value) =>
    if requestNames.contains name then none else some (name, some value)
  inherited ++ requestHeaders

structure Collection where
  providersRef : IO.Ref (Array Provider)
  credentials : LeanAgent.AI.Auth.CredentialStore
  authContext : LeanAgent.AI.Auth.AuthContext

def createModels
    (credentials : Option LeanAgent.AI.Auth.CredentialStore := none)
    (authContext : LeanAgent.AI.Auth.AuthContext := LeanAgent.AI.Auth.defaultProviderAuthContext) :
    IO Collection := do
  let credentials ←
    match credentials with
    | some credentials => pure credentials
    | none => LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let providersRef ← IO.mkRef (Array.empty : Array Provider)
  pure { providersRef := providersRef, credentials := credentials, authContext := authContext }

def Collection.getProviders (collection : Collection) : IO (Array Provider) :=
  collection.providersRef.get

def Collection.getProvider? (collection : Collection) (id : String) : IO (Option Provider) := do
  let providers ← collection.getProviders
  pure (providers.find? fun provider => provider.id == id)

def Collection.setProvider (collection : Collection) (provider : Provider) : IO Unit := do
  collection.providersRef.modify fun providers =>
    (providers.filter fun current => current.id != provider.id).push provider

def createDefaultModels
    (credentials : Option LeanAgent.AI.Auth.CredentialStore := none)
    (authContext : LeanAgent.AI.Auth.AuthContext := LeanAgent.AI.Auth.defaultProviderAuthContext) :
    IO Collection := do
  let collection ← createModels credentials authContext
  for info in defaultCatalog.providers do
    let provider ← createCatalogProvider info
    collection.setProvider provider
  pure collection

def Collection.deleteProvider (collection : Collection) (id : String) : IO Unit := do
  collection.providersRef.modify fun providers => providers.filter fun provider => provider.id != id

def Collection.clearProviders (collection : Collection) : IO Unit :=
  collection.providersRef.set #[]

def providerModelsOrEmpty (provider : Provider) : IO (Array ModelInfo) := do
  try
    provider.getModels
  catch _ =>
    pure #[]

def Collection.getModels (collection : Collection) (providerId : Option String := none) : IO (Array ModelInfo) := do
  match providerId with
  | some id =>
      match ← collection.getProvider? id with
      | some provider => providerModelsOrEmpty provider
      | none => pure #[]
  | none =>
      let providers ← collection.getProviders
      let mut models := #[]
      for provider in providers do
        models := models ++ (← providerModelsOrEmpty provider)
      pure models

def Collection.getModel? (collection : Collection) (providerId modelId : String) : IO (Option ModelInfo) := do
  let models ← collection.getModels (some providerId)
  pure (models.find? fun model => model.id == modelId)

def Collection.refresh (collection : Collection) (providerId : Option String := none) : IO Unit := do
  match providerId with
  | some id =>
      match ← collection.getProvider? id with
      | some provider =>
          match provider.refreshModels with
          | some refresh => refresh
          | none => pure ()
      | none => pure ()
  | none =>
      let providers ← collection.getProviders
      for provider in providers do
        match provider.refreshModels with
        | some refresh =>
            try
              refresh
            catch _ =>
              pure ()
        | none => pure ()

def Collection.getAuth (collection : Collection) (model : ModelInfo) : IO (Option LeanAgent.AI.Auth.AuthResult) := do
  match ← collection.getProvider? model.provider with
  | some provider =>
      LeanAgent.AI.Auth.resolveProviderAuth provider.id provider.auth collection.credentials collection.authContext
  | none => pure none

def Collection.requireProvider (collection : Collection) (model : ModelInfo) : IO Provider := do
  match ← collection.getProvider? model.provider with
  | some provider => pure provider
  | none => throw (modelsError .provider s!"Unknown provider: {model.provider}")

def Collection.applyAuth
    (collection : Collection)
    (provider : Provider)
    (model : ModelInfo)
    (options : LeanAgent.AI.SimpleStreamOptions) :
    IO (ModelInfo × LeanAgent.AI.SimpleStreamOptions) := do
  let resolution ←
    LeanAgent.AI.Auth.resolveProviderAuth provider.id provider.auth collection.credentials collection.authContext
      { apiKey := options.apiKey, env := options.env }
      (some model.baseUrl)
  match resolution with
  | none => pure (model, options)
  | some resolution =>
      let requestModel :=
        match resolution.auth.baseUrl with
        | some baseUrl => { model with baseUrl := baseUrl }
        | none => model
      let apiKey :=
        match options.apiKey with
        | some value => some value
        | none => resolution.auth.apiKey
      let requestOptions :=
        { options with
          apiKey := apiKey
          headers := authHeadersToStreamHeaders resolution.auth.headers options.headers
          env := LeanAgent.AI.Auth.providerEnvMerge resolution.env options.env
        }
      pure (requestModel, requestOptions)

def Collection.streamSimple
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  let provider ← collection.requireProvider model
  let (requestModel, requestOptions) ← collection.applyAuth provider model options
  provider.streamSimple requestModel context requestOptions

def Collection.completeSimple
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) : IO LeanAgent.AI.AssistantMessage := do
  let stream ← collection.streamSimple model context options
  pure stream.result

structure SelectionOptions where
  model : Option String := none
  baseUrl : Option String := none
  apiKeyEnv : Option String := none

structure ProviderSelection where
  providerInfo : ProviderInfo
  model : String
  baseUrl : String
  apiKeyEnv : String
  apiKey : String
  noProxy : Option String := none

def leanAgentNoProxyEnv : String := "LEAN_AGENT_NO_PROXY"

def envValue (name : String) : IO (Option String) := do
  match ← IO.getEnv name with
  | some value =>
      let trimmed := value.trimAscii.toString
      pure (if trimmed.isEmpty then none else some trimmed)
  | none => pure none

def envIsSet (name : String) : IO Bool := do
  pure (Option.isSome (← envValue name))

def envOrDefault (name fallback : String) : IO String := do
  match ← envValue name with
  | some value => pure value
  | none => pure fallback

def resolveApiKeyEnv (opts : SelectionOptions) (catalog : ProviderCatalog := defaultCatalog) : IO String := do
  match opts.apiKeyEnv with
  | some name => pure name
  | none =>
      let mut selected := none
      for provider in catalog.providers do
        if selected.isNone then
          if provider.supportsApi "openai-completions" then
            for apiKeyEnv in provider.authEnvs do
              if selected.isNone then
                if ← envIsSet apiKeyEnv then
                  selected := some apiKeyEnv
      pure (selected.getD openAIKeyEnv)

def resolveProviderForApiKeyEnv
    (apiKeyEnv : String)
    (catalog : ProviderCatalog := defaultCatalog) : ProviderInfo :=
  match catalog.providerByApiKeyEnv? apiKeyEnv with
  | some provider => provider
  | none => openAIProviderInfo

def resolveBaseUrl (opts : SelectionOptions) (provider : ProviderInfo) : String :=
  match opts.baseUrl with
  | some baseUrl => baseUrl
  | none => provider.baseUrl

def resolveModel (opts : SelectionOptions) (provider : ProviderInfo) : IO String := do
  match opts.model with
  | some model => pure model
  | none =>
      match provider.modelEnv with
      | some modelEnv => envOrDefault modelEnv provider.defaultModel
      | none => pure provider.defaultModel

def resolveNoProxy (baseUrl : String) : IO (Option String) := do
  match ← envValue leanAgentNoProxyEnv with
  | some value => pure (some value)
  | none =>
      if baseUrl.startsWith deepSeekBaseUrl then
        pure (some "api.deepseek.com")
      else
        pure none

def resolveSelection
    (opts : SelectionOptions)
    (catalog : ProviderCatalog := defaultCatalog) : IO (Except String ProviderSelection) := do
  let apiKeyEnv ← resolveApiKeyEnv opts catalog
  let provider := resolveProviderForApiKeyEnv apiKeyEnv catalog
  if !provider.supportsApi "openai-completions" then
    let providerApi := (provider.models[0]?.map (fun model => model.api)).getD "unknown"
    return (.error
      s!"provider {provider.id} uses {providerApi}; the legacy CLI path currently supports only openai-completions")
  let baseUrl := resolveBaseUrl opts provider
  let model ← resolveModel opts provider
  let noProxy ← resolveNoProxy baseUrl
  match ← envValue apiKeyEnv with
  | some apiKey =>
      pure (.ok
        { providerInfo := provider
          model := model
          baseUrl := baseUrl
          apiKeyEnv := apiKeyEnv
          apiKey := apiKey
          noProxy := noProxy
        })
  | none =>
      pure (.error s!"missing API key: set {apiKeyEnv} or pass --api-key-env")

def legacyProviderFromSelection (selection : ProviderSelection) : ModelProvider :=
  provider selection.baseUrl selection.apiKey selection.noProxy

end LeanAgent.Models
