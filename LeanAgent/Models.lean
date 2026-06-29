import LeanAgent.Core
import LeanAgent.AI.Auth
import LeanAgent.AI.Api.AnthropicMessages
import LeanAgent.AI.Api.AzureOpenAIResponses
import LeanAgent.AI.Api.BedrockConverseStream
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

def kimiCodingProviderId : String := "kimi-coding"
def kimiCodingApiKeyEnv : String := "KIMI_API_KEY"
def kimiCodingDefaultModel : String := "k2p7"
def kimiCodingBaseUrl : String := "https://api.kimi.com/coding"
def kimiCodingHeaders : LeanAgent.AI.Auth.ProviderHeaders :=
  #[("User-Agent", "KimiCLI/1.5")]

def minimaxProviderId : String := "minimax"
def minimaxApiKeyEnv : String := "MINIMAX_API_KEY"
def minimaxDefaultModel : String := "MiniMax-M2.7"
def minimaxBaseUrl : String := "https://api.minimax.io/anthropic"

def minimaxCNProviderId : String := "minimax-cn"
def minimaxCNApiKeyEnv : String := "MINIMAX_CN_API_KEY"
def minimaxCNDefaultModel : String := "MiniMax-M2.7"
def minimaxCNBaseUrl : String := "https://api.minimaxi.com/anthropic"

def vercelAIGatewayProviderId : String := "vercel-ai-gateway"
def vercelAIGatewayApiKeyEnv : String := "AI_GATEWAY_API_KEY"
def vercelAIGatewayDefaultModel : String := "alibaba/qwen-3-14b"
def vercelAIGatewayBaseUrl : String := "https://ai-gateway.vercel.sh"

def opencodeProviderId : String := "opencode"
def opencodeApiKeyEnv : String := "OPENCODE_API_KEY"
def opencodeDefaultModel : String := "big-pickle"
def opencodeBaseUrl : String := "https://opencode.ai/zen"

def opencodeGoProviderId : String := "opencode-go"
def opencodeGoApiKeyEnv : String := opencodeApiKeyEnv
def opencodeGoDefaultModel : String := "deepseek-v4-flash"
def opencodeGoBaseUrl : String := "https://opencode.ai/zen/go"

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

def amazonBedrockProviderId : String := "amazon-bedrock"
def amazonBedrockDefaultModel : String := "us.anthropic.claude-opus-4-6-v1"
def amazonBedrockBaseUrl : String := LeanAgent.AI.Api.BedrockConverseStream.defaultBaseUrl
def amazonBedrockAuthEnvs : Array String :=
  #[ "AWS_BEARER_TOKEN_BEDROCK"
   , "AWS_PROFILE"
   , "AWS_ACCESS_KEY_ID"
   , "AWS_SECRET_ACCESS_KEY"
   , "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
   , "AWS_CONTAINER_CREDENTIALS_FULL_URI"
   , "AWS_WEB_IDENTITY_TOKEN_FILE"
   ]

def antLingProviderId : String := "ant-ling"
def antLingApiKeyEnv : String := "ANT_LING_API_KEY"
def antLingDefaultModel : String := "Ling-2.6-1T"
def antLingBaseUrl : String := "https://api.ant-ling.com/v1"

def huggingFaceProviderId : String := "huggingface"
def huggingFaceApiKeyEnv : String := "HF_TOKEN"
def huggingFaceDefaultModel : String := "MiniMaxAI/MiniMax-M2"
def huggingFaceBaseUrl : String := "https://router.huggingface.co/v1"

def moonshotAIProviderId : String := "moonshotai"
def moonshotAIApiKeyEnv : String := "MOONSHOT_API_KEY"
def moonshotAIDefaultModel : String := "kimi-k2-0711-preview"
def moonshotAIBaseUrl : String := "https://api.moonshot.ai/v1"

def moonshotAICNProviderId : String := "moonshotai-cn"
def moonshotAICNApiKeyEnv : String := "MOONSHOT_API_KEY"
def moonshotAICNDefaultModel : String := "kimi-k2-0711-preview"
def moonshotAICNBaseUrl : String := "https://api.moonshot.cn/v1"

def nvidiaProviderId : String := "nvidia"
def nvidiaApiKeyEnv : String := "NVIDIA_API_KEY"
def nvidiaDefaultModel : String := "meta/llama-3.1-70b-instruct"
def nvidiaBaseUrl : String := "https://integrate.api.nvidia.com/v1"

def xiaomiProviderId : String := "xiaomi"
def xiaomiApiKeyEnv : String := "XIAOMI_API_KEY"
def xiaomiDefaultModel : String := "mimo-v2-flash"
def xiaomiBaseUrl : String := "https://api.xiaomimimo.com/v1"

def xiaomiTokenPlanAMSProviderId : String := "xiaomi-token-plan-ams"
def xiaomiTokenPlanAMSApiKeyEnv : String := "XIAOMI_TOKEN_PLAN_AMS_API_KEY"
def xiaomiTokenPlanAMSDefaultModel : String := "mimo-v2-omni"
def xiaomiTokenPlanAMSBaseUrl : String := "https://token-plan-ams.xiaomimimo.com/v1"

def xiaomiTokenPlanCNProviderId : String := "xiaomi-token-plan-cn"
def xiaomiTokenPlanCNApiKeyEnv : String := "XIAOMI_TOKEN_PLAN_CN_API_KEY"
def xiaomiTokenPlanCNDefaultModel : String := "mimo-v2-omni"
def xiaomiTokenPlanCNBaseUrl : String := "https://token-plan-cn.xiaomimimo.com/v1"

def xiaomiTokenPlanSGPProviderId : String := "xiaomi-token-plan-sgp"
def xiaomiTokenPlanSGPApiKeyEnv : String := "XIAOMI_TOKEN_PLAN_SGP_API_KEY"
def xiaomiTokenPlanSGPDefaultModel : String := "mimo-v2-omni"
def xiaomiTokenPlanSGPBaseUrl : String := "https://token-plan-sgp.xiaomimimo.com/v1"

def zaiProviderId : String := "zai"
def zaiApiKeyEnv : String := "ZAI_API_KEY"
def zaiDefaultModel : String := "glm-4.5-air"
def zaiBaseUrl : String := "https://api.z.ai/api/coding/paas/v4"

def zaiCodingCNProviderId : String := "zai-coding-cn"
def zaiCodingCNApiKeyEnv : String := "ZAI_CODING_CN_API_KEY"
def zaiCodingCNDefaultModel : String := "glm-4.5-air"
def zaiCodingCNBaseUrl : String := "https://open.bigmodel.cn/api/coding/paas/v4"

structure ModelCompat where
  supportsStore : Bool := true
  supportsDeveloperRole : Bool := true
  requiresReasoningContentOnAssistantMessages : Bool := false
  thinkingFormat : Option String := none
  supportsReasoningEffort : Bool := true
  maxTokensField : String := "max_tokens"
  supportsLongCacheRetention : Bool := true
  sendSessionAffinityHeaders : Bool := false
  supportsTemperature : Bool := true
  supportsEagerToolInputStreaming : Bool := true
  supportsCacheControlOnTools : Bool := true
  allowEmptySignature : Bool := false
  forceAdaptiveThinking : Bool := false
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
  headers : LeanAgent.AI.Auth.ProviderHeaders := #[]
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

def catalogOpenAICompatibleModel
    (providerId baseUrl id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := false)
    (compat : ModelCompat := {})
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[])
    (input : Array String := #["text"]) : ModelInfo :=
  { id := id
    name := name
    provider := providerId
    api := "openai-completions"
    baseUrl := baseUrl
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
    reasoning := reasoning
    compat := compat
    thinkingLevelMap := thinkingLevelMap
    input := input
  }

def catalogAnthropicMessagesModel
    (providerId baseUrl id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := true)
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[])
    (input : Array String := #["text"]) : ModelInfo :=
  { id := id
    name := name
    provider := providerId
    api := LeanAgent.AI.Api.AnthropicMessages.api
    baseUrl := baseUrl
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
    reasoning := reasoning
    thinkingLevelMap := thinkingLevelMap
    input := input
  }

def catalogModel
    (providerId id name api baseUrl : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := true)
    (compat : ModelCompat := {})
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[])
    (input : Array String := #["text"]) : ModelInfo :=
  { id := id
    name := name
    provider := providerId
    api := api
    baseUrl := baseUrl
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
    reasoning := reasoning
    compat := compat
    thinkingLevelMap := thinkingLevelMap
    input := input
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

def antLingCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    thinkingFormat := some "ant-ling"
  }

def huggingFaceCompat : ModelCompat :=
  { supportsDeveloperRole := false
  }

def moonshotAICompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    thinkingFormat := some "deepseek"
  }

def nvidiaCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
  }

def nvidiaModelHeaders : LeanAgent.AI.Auth.ProviderHeaders :=
  #[("NVCF-POLL-SECONDS", "3600")]

def xiaomiCompat : ModelCompat :=
  { requiresReasoningContentOnAssistantMessages := true
    thinkingFormat := some "deepseek"
  }

def zaiCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    thinkingFormat := some "zai"
  }

def antLingModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel antLingProviderId antLingBaseUrl "Ling-2.6-1T" "Ling 2.6 1T" 0.06 0.25 0.0 0.0 262144 65536 false antLingCompat #[] #["text"]
   , catalogOpenAICompatibleModel antLingProviderId antLingBaseUrl "Ling-2.6-flash" "Ling 2.6 Flash" 0.01 0.02 0.0 0.0 262144 65536 false antLingCompat #[] #["text"]
   , catalogOpenAICompatibleModel antLingProviderId antLingBaseUrl "Ring-2.6-1T" "Ring 2.6 1T" 0.06 0.25 0.0 0.0 262144 65536 true antLingCompat #[ { level := .off, mapped := none }
   , { level := .level .minimal, mapped := none }
   , { level := .level .low, mapped := none }
   , { level := .level .medium, mapped := none }
   , { level := .level .high, mapped := some "high" }
   , { level := .level .xhigh, mapped := some "xhigh" }
   ] #["text"]
   ]

def huggingFaceModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "MiniMaxAI/MiniMax-M2" "MiniMax-M2" 0.3 1.2 0.0 0.0 204800 128000 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "MiniMaxAI/MiniMax-M2.1" "MiniMax-M2.1" 0.3 1.2 0.0 0.0 204800 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "MiniMaxAI/MiniMax-M2.5" "MiniMax-M2.5" 0.3 1.2 0.03 0.0 204800 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "MiniMaxAI/MiniMax-M2.7" "MiniMax-M2.7" 0.3 1.2 0.06 0.0 204800 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "MiniMaxAI/MiniMax-M3" "MiniMax-M3" 0.3 1.2 0.0 0.0 524288 128000 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-235B-A22B" "Qwen3 235B-A22B" 0.2 0.8 0.0 0.0 40960 16384 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-235B-A22B-Thinking-2507" "Qwen3-235B-A22B-Thinking-2507" 0.3 3.0 0.0 0.0 262144 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-32B" "Qwen3 32B" 0.29 0.59 0.0 0.0 131072 16384 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-Coder-30B-A3B-Instruct" "Qwen3-Coder 30B-A3B Instruct" 0.07 0.26 0.0 0.0 262144 65536 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-Coder-480B-A35B-Instruct" "Qwen3-Coder-480B-A35B-Instruct" 2.0 2.0 0.0 0.0 262144 66536 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-Coder-Next" "Qwen3-Coder-Next" 0.2 1.5 0.0 0.0 262144 65536 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-Next-80B-A3B-Instruct" "Qwen3-Next-80B-A3B-Instruct" 0.25 1.0 0.0 0.0 262144 66536 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3-Next-80B-A3B-Thinking" "Qwen3-Next-80B-A3B-Thinking" 0.3 2.0 0.0 0.0 262144 131072 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3.5-122B-A10B" "Qwen3.5 122B-A10B" 0.4 3.2 0.0 0.0 262144 65536 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3.5-27B" "Qwen3.5 27B" 0.3 2.4 0.0 0.0 262144 65536 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3.5-35B-A3B" "Qwen3.5 35B-A3B" 0.25 2.0 0.0 0.0 262144 65536 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3.5-397B-A17B" "Qwen3.5-397B-A17B" 0.6 3.6 0.0 0.0 262144 32768 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3.5-9B" "Qwen3.5 9B" 0.17 0.25 0.0 0.0 262144 65536 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3.6-27B" "Qwen3.6 27B" 0.47 3.19 0.0 0.0 262144 65536 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "Qwen/Qwen3.6-35B-A3B" "Qwen3.6 35B-A3B" 0.15 0.95 0.0 0.0 262144 65536 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "XiaomiMiMo/MiMo-V2-Flash" "MiMo-V2-Flash" 0.1 0.3 0.0 0.0 262144 4096 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "XiaomiMiMo/MiMo-V2.5-Pro" "MiMo-V2.5-Pro" 1.0 3.0 0.0 0.0 1048576 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "deepseek-ai/DeepSeek-R1" "DeepSeek-R1" 0.7 2.5 0.0 0.0 64000 32768 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "deepseek-ai/DeepSeek-R1-0528" "DeepSeek-R1-0528" 3.0 5.0 0.0 0.0 163840 163840 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "deepseek-ai/DeepSeek-V3.2" "DeepSeek-V3.2" 0.28 0.4 0.0 0.0 163840 65536 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "deepseek-ai/DeepSeek-V4-Flash" "DeepSeek V4 Flash" 0.14 0.28 0.0 0.0 1048576 384000 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "deepseek-ai/DeepSeek-V4-Pro" "DeepSeek V4 Pro" 0.435 0.87 0.003625 0.0 1048576 393216 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "google/gemma-4-26B-A4B-it" "Gemma 4 26B A4B IT" 0.13 0.4 0.0 0.0 262144 32768 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "google/gemma-4-31B-it" "Gemma 4 31B IT" 0.14 0.4 0.0 0.0 262144 32768 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "meta-llama/Llama-3.3-70B-Instruct" "Llama-3.3-70B-Instruct" 0.59 0.79 0.0 0.0 131072 4096 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "moonshotai/Kimi-K2-Instruct" "Kimi-K2-Instruct" 1.0 3.0 0.0 0.0 131072 16384 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "moonshotai/Kimi-K2-Instruct-0905" "Kimi-K2-Instruct-0905" 1.0 3.0 0.0 0.0 262144 16384 false huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "moonshotai/Kimi-K2-Thinking" "Kimi-K2-Thinking" 0.6 2.5 0.15 0.0 262144 262144 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "moonshotai/Kimi-K2.5" "Kimi-K2.5" 0.6 3.0 0.1 0.0 262144 262144 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "moonshotai/Kimi-K2.6" "Kimi-K2.6" 0.95 4.0 0.16 0.0 262144 262144 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "moonshotai/Kimi-K2.7-Code" "Kimi K2.7 Code" 0.95 4.0 0.0 0.0 262144 262144 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "stepfun-ai/Step-3.5-Flash" "Step 3.5 Flash" 0.1 0.3 0.0 0.0 262144 256000 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "stepfun-ai/Step-3.7-Flash" "Step 3.7 Flash" 0.2 1.15 0.0 0.0 262144 256000 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-4.5" "GLM-4.5" 0.6 2.2 0.0 0.0 131072 98304 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-4.5-Air" "GLM-4.5-Air" 0.13 0.85 0.0 0.0 131072 98304 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-4.5V" "GLM-4.5V" 0.6 1.8 0.0 0.0 65536 16384 true huggingFaceCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-4.6" "GLM-4.6" 0.55 2.2 0.0 0.0 204800 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-4.7" "GLM-4.7" 0.6 2.2 0.11 0.0 204800 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-4.7-Flash" "GLM-4.7-Flash" 0.0 0.0 0.0 0.0 200000 128000 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-5" "GLM-5" 1.0 3.2 0.2 0.0 202752 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-5.1" "GLM-5.1" 1.0 3.2 0.2 0.0 202752 131072 true huggingFaceCompat #[] #["text"]
   , catalogOpenAICompatibleModel huggingFaceProviderId huggingFaceBaseUrl "zai-org/GLM-5.2" "GLM-5.2" 1.4 4.4 0.0 0.0 262144 131072 true huggingFaceCompat #[] #["text"]
   ]

def moonshotAIModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2-0711-preview" "Kimi K2 0711" 0.6 2.5 0.15 0.0 131072 16384 false moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2-0905-preview" "Kimi K2 0905" 0.6 2.5 0.15 0.0 262144 262144 false moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2-thinking" "Kimi K2 Thinking" 0.6 2.5 0.15 0.0 262144 262144 true moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2-thinking-turbo" "Kimi K2 Thinking Turbo" 1.15 8.0 0.15 0.0 262144 262144 true moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2-turbo-preview" "Kimi K2 Turbo" 2.4 10.0 0.6 0.0 262144 262144 false moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2.5" "Kimi K2.5" 0.6 3.0 0.1 0.0 262144 262144 true moonshotAICompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2.6" "Kimi K2.6" 0.95 4.0 0.16 0.0 262144 262144 true moonshotAICompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2.7-code" "Kimi K2.7 Code" 0.95 4.0 0.19 0.0 262144 262144 true moonshotAICompat #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogOpenAICompatibleModel moonshotAIProviderId moonshotAIBaseUrl "kimi-k2.7-code-highspeed" "Kimi K2.7 Code HighSpeed" 1.9 8.0 0.38 0.0 262144 262144 true moonshotAICompat #[{ level := .off, mapped := none }] #["text", "image"]
   ]

def moonshotAICNModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2-0711-preview" "Kimi K2 0711" 0.6 2.5 0.15 0.0 131072 16384 false moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2-0905-preview" "Kimi K2 0905" 0.6 2.5 0.15 0.0 262144 262144 false moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2-thinking" "Kimi K2 Thinking" 0.6 2.5 0.15 0.0 262144 262144 true moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2-thinking-turbo" "Kimi K2 Thinking Turbo" 1.15 8.0 0.15 0.0 262144 262144 true moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2-turbo-preview" "Kimi K2 Turbo" 2.4 10.0 0.6 0.0 262144 262144 false moonshotAICompat #[] #["text"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2.5" "Kimi K2.5" 0.6 3.0 0.1 0.0 262144 262144 true moonshotAICompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2.6" "Kimi K2.6" 0.95 4.0 0.16 0.0 262144 262144 true moonshotAICompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2.7-code" "Kimi K2.7 Code" 0.95 4.0 0.19 0.0 262144 262144 true moonshotAICompat #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogOpenAICompatibleModel moonshotAICNProviderId moonshotAICNBaseUrl "kimi-k2.7-code-highspeed" "Kimi K2.7 Code HighSpeed" 1.9 8.0 0.38 0.0 262144 262144 true moonshotAICompat #[{ level := .off, mapped := none }] #["text", "image"]
   ]

def nvidiaModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "meta/llama-3.1-70b-instruct" "Llama 3.1 70b Instruct" 0.0 0.0 0.0 0.0 128000 4096 false nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "meta/llama-3.1-8b-instruct" "Llama 3.1 8B Instruct" 0.0 0.0 0.0 0.0 16000 4096 false nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "meta/llama-3.2-11b-vision-instruct" "Llama 3.2 11b Vision Instruct" 0.0 0.0 0.0 0.0 128000 4096 false nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "meta/llama-3.2-90b-vision-instruct" "Llama-3.2-90B-Vision-Instruct" 0.0 0.0 0.0 0.0 128000 8192 false nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "meta/llama-3.3-70b-instruct" "Llama 3.3 70b Instruct" 0.0 0.0 0.0 0.0 128000 4096 false nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "mistralai/mistral-large-3-675b-instruct-2512" "Mistral Large 3 675B Instruct 2512" 0.0 0.0 0.0 0.0 262144 262144 false nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "mistralai/mistral-small-4-119b-2603" "mistral-small-4-119b-2603" 0.0 0.0 0.0 0.0 128000 8192 true nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "moonshotai/kimi-k2.6" "Kimi K2.6" 0.0 0.0 0.0 0.0 262144 262144 true nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "nvidia/nemotron-3-nano-30b-a3b" "nemotron-3-nano-30b-a3b" 0.0 0.0 0.0 0.0 131072 131072 true nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning" "Nemotron 3 Nano Omni" 0.0 0.0 0.0 0.0 256000 65536 true nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "nvidia/nemotron-3-super-120b-a12b" "Nemotron 3 Super" 0.2 0.8 0.0 0.0 262144 262144 true nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "nvidia/nemotron-3-ultra-550b-a55b" "Nemotron 3 Ultra 550B A55B" 0.5 2.5 0.15 0.0 1000000 65536 true nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "nvidia/nvidia-nemotron-nano-9b-v2" "nvidia-nemotron-nano-9b-v2" 0.0 0.0 0.0 0.0 131072 131072 true nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "openai/gpt-oss-120b" "GPT-OSS-120B" 0.0 0.0 0.0 0.0 128000 8192 true nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "openai/gpt-oss-20b" "GPT OSS 20B" 0.0 0.0 0.0 0.0 131072 32768 true nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "qwen/qwen3.5-122b-a10b" "Qwen3.5 122B-A10B" 0.0 0.0 0.0 0.0 262144 65536 true nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "stepfun-ai/step-3.5-flash" "Step 3.5 Flash" 0.0 0.0 0.0 0.0 256000 16384 true nvidiaCompat #[] #["text"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "stepfun-ai/step-3.7-flash" "Step 3.7 Flash" 0.0 0.0 0.0 0.0 256000 16384 true nvidiaCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel nvidiaProviderId nvidiaBaseUrl "z-ai/glm-5.1" "GLM-5.1" 0.0 0.0 0.0 0.0 131072 131072 true nvidiaCompat #[] #["text"]
   ].map fun model => { model with headers := nvidiaModelHeaders }

def xiaomiModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel xiaomiProviderId xiaomiBaseUrl "mimo-v2-flash" "MiMo-V2-Flash" 0.1 0.3 0.01 0.0 262144 65536 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiProviderId xiaomiBaseUrl "mimo-v2-omni" "MiMo-V2-Omni" 0.4 2.0 0.08 0.0 262144 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiProviderId xiaomiBaseUrl "mimo-v2-pro" "MiMo-V2-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiProviderId xiaomiBaseUrl "mimo-v2.5" "MiMo-V2.5" 0.4 2.0 0.08 0.0 1048576 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiProviderId xiaomiBaseUrl "mimo-v2.5-pro" "MiMo-V2.5-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiProviderId xiaomiBaseUrl "mimo-v2.5-pro-ultraspeed" "MiMo-V2.5-Pro-UltraSpeed" 1.305 2.61 0.0108 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   ]

def xiaomiTokenPlanAMSModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel xiaomiTokenPlanAMSProviderId xiaomiTokenPlanAMSBaseUrl "mimo-v2-omni" "MiMo-V2-Omni" 0.4 2.0 0.08 0.0 262144 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanAMSProviderId xiaomiTokenPlanAMSBaseUrl "mimo-v2-pro" "MiMo-V2-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanAMSProviderId xiaomiTokenPlanAMSBaseUrl "mimo-v2.5" "MiMo-V2.5" 0.4 2.0 0.08 0.0 1048576 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanAMSProviderId xiaomiTokenPlanAMSBaseUrl "mimo-v2.5-pro" "MiMo-V2.5-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanAMSProviderId xiaomiTokenPlanAMSBaseUrl "mimo-v2.5-pro-ultraspeed" "MiMo-V2.5-Pro-UltraSpeed" 1.305 2.61 0.0108 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   ]

def xiaomiTokenPlanCNModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel xiaomiTokenPlanCNProviderId xiaomiTokenPlanCNBaseUrl "mimo-v2-omni" "MiMo-V2-Omni" 0.4 2.0 0.08 0.0 262144 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanCNProviderId xiaomiTokenPlanCNBaseUrl "mimo-v2-pro" "MiMo-V2-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanCNProviderId xiaomiTokenPlanCNBaseUrl "mimo-v2.5" "MiMo-V2.5" 0.4 2.0 0.08 0.0 1048576 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanCNProviderId xiaomiTokenPlanCNBaseUrl "mimo-v2.5-pro" "MiMo-V2.5-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanCNProviderId xiaomiTokenPlanCNBaseUrl "mimo-v2.5-pro-ultraspeed" "MiMo-V2.5-Pro-UltraSpeed" 1.305 2.61 0.0108 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   ]

def xiaomiTokenPlanSGPModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel xiaomiTokenPlanSGPProviderId xiaomiTokenPlanSGPBaseUrl "mimo-v2-omni" "MiMo-V2-Omni" 0.4 2.0 0.08 0.0 262144 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanSGPProviderId xiaomiTokenPlanSGPBaseUrl "mimo-v2-pro" "MiMo-V2-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanSGPProviderId xiaomiTokenPlanSGPBaseUrl "mimo-v2.5" "MiMo-V2.5" 0.4 2.0 0.08 0.0 1048576 131072 true xiaomiCompat #[] #["text", "image"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanSGPProviderId xiaomiTokenPlanSGPBaseUrl "mimo-v2.5-pro" "MiMo-V2.5-Pro" 1.0 3.0 0.2 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   , catalogOpenAICompatibleModel xiaomiTokenPlanSGPProviderId xiaomiTokenPlanSGPBaseUrl "mimo-v2.5-pro-ultraspeed" "MiMo-V2.5-Pro-UltraSpeed" 1.305 2.61 0.0108 0.0 1048576 131072 true xiaomiCompat #[] #["text"]
   ]

def zaiModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel zaiProviderId zaiBaseUrl "glm-4.5-air" "GLM-4.5-Air" 0.0 0.0 0.0 0.0 131072 98304 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiProviderId zaiBaseUrl "glm-4.7" "GLM-4.7" 0.0 0.0 0.0 0.0 204800 131072 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiProviderId zaiBaseUrl "glm-5-turbo" "GLM-5-Turbo" 0.0 0.0 0.0 0.0 200000 131072 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiProviderId zaiBaseUrl "glm-5.1" "GLM-5.1" 0.0 0.0 0.0 0.0 200000 131072 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiProviderId zaiBaseUrl "glm-5.2" "GLM-5.2" 0.0 0.0 0.0 0.0 1000000 131072 true zaiCompat #[ { level := .level .minimal, mapped := none }
   , { level := .level .low, mapped := some "high" }
   , { level := .level .medium, mapped := some "high" }
   , { level := .level .high, mapped := some "high" }
   , { level := .level .xhigh, mapped := some "max" }
   ] #["text"]
   , catalogOpenAICompatibleModel zaiProviderId zaiBaseUrl "glm-5v-turbo" "GLM-5V-Turbo" 0.0 0.0 0.0 0.0 200000 131072 true zaiCompat #[] #["text", "image"]
   ]

def zaiCodingCNModels : Array ModelInfo :=
  #[ catalogOpenAICompatibleModel zaiCodingCNProviderId zaiCodingCNBaseUrl "glm-4.5-air" "GLM-4.5-Air" 0.0 0.0 0.0 0.0 131072 98304 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiCodingCNProviderId zaiCodingCNBaseUrl "glm-4.7" "GLM-4.7" 0.0 0.0 0.0 0.0 204800 131072 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiCodingCNProviderId zaiCodingCNBaseUrl "glm-5-turbo" "GLM-5-Turbo" 0.0 0.0 0.0 0.0 200000 131072 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiCodingCNProviderId zaiCodingCNBaseUrl "glm-5.1" "GLM-5.1" 0.0 0.0 0.0 0.0 200000 131072 true zaiCompat #[] #["text"]
   , catalogOpenAICompatibleModel zaiCodingCNProviderId zaiCodingCNBaseUrl "glm-5.2" "GLM-5.2" 0.0 0.0 0.0 0.0 1000000 131072 true zaiCompat #[ { level := .level .minimal, mapped := none }
   , { level := .level .low, mapped := some "high" }
   , { level := .level .medium, mapped := some "high" }
   , { level := .level .high, mapped := some "high" }
   , { level := .level .xhigh, mapped := some "max" }
   ] #["text"]
   , catalogOpenAICompatibleModel zaiCodingCNProviderId zaiCodingCNBaseUrl "glm-5v-turbo" "GLM-5V-Turbo" 0.0 0.0 0.0 0.0 200000 131072 true zaiCompat #[] #["text", "image"]
   ]

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

def kimiCodingModels : Array ModelInfo :=
  #[ catalogAnthropicMessagesModel kimiCodingProviderId kimiCodingBaseUrl "k2p7" "Kimi K2.7 Code" 0.0 0.0 0.0 0.0 262144 32768 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel kimiCodingProviderId kimiCodingBaseUrl "kimi-for-coding" "Kimi For Coding" 0.0 0.0 0.0 0.0 262144 32768 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel kimiCodingProviderId kimiCodingBaseUrl "kimi-k2-thinking" "Kimi K2 Thinking" 0.0 0.0 0.0 0.0 262144 32768 true #[] #["text"]
   ]

def minimaxModels : Array ModelInfo :=
  #[ catalogAnthropicMessagesModel minimaxProviderId minimaxBaseUrl "MiniMax-M2.7" "MiniMax-M2.7" 0.3 1.2 0.06 0.375 204800 131072 true #[] #["text"]
   , catalogAnthropicMessagesModel minimaxProviderId minimaxBaseUrl "MiniMax-M2.7-highspeed" "MiniMax-M2.7-highspeed" 0.6 2.4 0.06 0.375 204800 131072 true #[] #["text"]
   , catalogAnthropicMessagesModel minimaxProviderId minimaxBaseUrl "MiniMax-M3" "MiniMax-M3" 0.6 2.4 0.12 0.0 512000 128000 true #[] #["text", "image"]
   ]

def minimaxCNModels : Array ModelInfo :=
  #[ catalogAnthropicMessagesModel minimaxCNProviderId minimaxCNBaseUrl "MiniMax-M2.7" "MiniMax-M2.7" 0.3 1.2 0.06 0.375 204800 131072 true #[] #["text"]
   , catalogAnthropicMessagesModel minimaxCNProviderId minimaxCNBaseUrl "MiniMax-M2.7-highspeed" "MiniMax-M2.7-highspeed" 0.6 2.4 0.06 0.375 204800 131072 true #[] #["text"]
   , catalogAnthropicMessagesModel minimaxCNProviderId minimaxCNBaseUrl "MiniMax-M3" "MiniMax-M3" 0.6 2.4 0.12 0.0 512000 128000 true #[] #["text", "image"]
   ]

def vercelAIGatewayModels : Array ModelInfo :=
  #[
   catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen-3-14b" "Qwen3-14B" 0.12 0.24 0.0 0.0 40960 16384 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen-3-235b" "Qwen3 235B A22B" 0.22 0.88 0.0 0.0 262144 16384 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen-3-30b" "Qwen3-30B-A3B" 0.12 0.5 0.0 0.0 40960 16384 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen-3-32b" "Qwen 3 32B" 0.16 0.64 0.0 0.0 128000 8192 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen-3.6-max-preview" "Qwen 3.6 Max Preview" 1.3 7.8 0.26 1.625 240000 64000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-235b-a22b-thinking" "Qwen3 VL 235B A22B Thinking" 0.4 4.0 0.0 0.0 131072 32768 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-coder" "Qwen3 Coder 480B A35B Instruct" 1.5 7.5 0.3 0.0 262144 65536 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-coder-30b-a3b" "Qwen 3 Coder 30B A3B Instruct" 0.15 0.6 0.0 0.0 262144 8192 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-coder-next" "Qwen3 Coder Next" 0.5 1.2 0.0 0.0 256000 256000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-coder-plus" "Qwen3 Coder Plus" 1.0 5.0 0.2 0.0 1000000 65536 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-max" "Qwen3 Max" 1.2 6.0 0.24 0.0 262144 32768 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-max-preview" "Qwen3 Max Preview" 1.2 6.0 0.24 0.0 262144 32768 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-max-thinking" "Qwen 3 Max Thinking" 1.2 6.0 0.24 0.0 256000 65536 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-next-80b-a3b-instruct" "Qwen3 Next 80B A3B Instruct" 0.15 1.2 0.0 0.0 131072 32768 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-next-80b-a3b-thinking" "Qwen3 Next 80B A3B Thinking" 0.15 1.2 0.0 0.0 131072 32768 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-vl-235b-a22b-instruct" "Qwen3 VL 235B A22B Instruct" 0.4 1.6 0.0 0.0 131072 129024 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-vl-instruct" "Qwen3 VL 235B A22B Instruct" 0.4 1.6 0.0 0.0 131072 129024 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3-vl-thinking" "Qwen3 VL 235B A22B Thinking" 0.4 4.0 0.0 0.0 131072 32768 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3.5-flash" "Qwen 3.5 Flash" 0.1 0.4 0.001 0.125 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3.5-plus" "Qwen 3.5 Plus" 0.4 2.4 0.04 0.5 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3.6-27b" "Qwen 3.6 27B" 0.6 3.6 0.0 0.0 256000 256000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3.6-plus" "Qwen 3.6 Plus" 0.5 3.0 0.1 0.625 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3.7-max" "Qwen 3.7 Max" 1.25 3.75 0.25 1.5625 991000 64000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "alibaba/qwen3.7-plus" "Qwen 3.7 Plus" 0.4 1.6 0.08 0.5 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "amazon/nova-2-lite" "Nova 2 Lite" 0.3 2.5 0.075 0.0 1000000 1000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "amazon/nova-lite" "Nova Lite" 0.06 0.24 0.0 0.0 300000 8192 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "amazon/nova-micro" "Nova Micro" 0.035 0.14 0.0 0.0 128000 8192 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "amazon/nova-pro" "Nova Pro" 0.8 3.2 0.0 0.0 300000 8192 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-3-haiku" "Claude 3 Haiku" 0.25 1.25 0.03 0.3 200000 4096 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-3.5-haiku" "Claude 3.5 Haiku" 0.8 4.0 0.08 1.0 200000 8192 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-haiku-4.5" "Claude Haiku 4.5" 1.0 5.0 0.1 1.25 200000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-opus-4" "Claude Opus 4" 15.0 75.0 1.5 18.75 200000 32000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-opus-4.1" "Claude Opus 4.1" 15.0 75.0 1.5 18.75 200000 32000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-opus-4.5" "Claude Opus 4.5" 5.0 25.0 0.5 6.25 200000 64000 true #[] #["text", "image"]
   , { (catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-opus-4.6" "Claude Opus 4.6" 5.0 25.0 0.5 6.25 1000000 128000 true #[{ level := .level .xhigh, mapped := some "max" }] #["text", "image"]) with compat := { forceAdaptiveThinking := true } }
   , { (catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-opus-4.7" "Claude Opus 4.7" 5.0 25.0 0.5 6.25 1000000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]) with compat := { supportsTemperature := false, forceAdaptiveThinking := true } }
   , { (catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-opus-4.8" "Claude Opus 4.8" 5.0 25.0 0.5 6.25 1000000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]) with compat := { supportsTemperature := false, forceAdaptiveThinking := true } }
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-sonnet-4" "Claude Sonnet 4" 3.0 15.0 0.3 3.75 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-sonnet-4.5" "Claude Sonnet 4.5" 3.0 15.0 0.3 3.75 1000000 64000 true #[] #["text", "image"]
   , { (catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "anthropic/claude-sonnet-4.6" "Claude Sonnet 4.6" 3.0 15.0 0.3 3.75 1000000 128000 true #[] #["text", "image"]) with compat := { forceAdaptiveThinking := true } }
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "arcee-ai/trinity-large-preview" "Trinity Large Preview" 0.25 1.0 0.0 0.0 131000 131000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "arcee-ai/trinity-large-thinking" "Trinity Large Thinking" 0.25 0.9 0.0 0.0 262100 80000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "arcee-ai/trinity-mini" "Trinity Mini" 0.045 0.15 0.0 0.0 131072 131072 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "bytedance/seed-1.6" "Seed 1.6" 0.25 2.0 0.05 0.0 256000 32000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "bytedance/seed-1.8" "Bytedance Seed 1.8" 0.25 2.0 0.05 0.0 256000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "cohere/command-a" "Command A" 2.5 10.0 0.0 0.0 256000 8000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-r1" "DeepSeek-R1" 1.35 5.4 0.0 0.0 128000 8192 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-v3" "DeepSeek V3 0324" 0.27 1.12 0.135 0.0 163840 163840 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-v3.1" "DeepSeek V3.1" 0.56 1.68 0.28 0.0 163840 8192 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-v3.1-terminus" "DeepSeek V3.1 Terminus" 0.27 1.0 0.135 0.0 131072 65536 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-v3.2" "DeepSeek V3.2" 0.28 0.42 0.028 0.0 128000 8000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-v3.2-thinking" "DeepSeek V3.2 Thinking" 0.62 1.85 0.0 0.0 128000 8000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-v4-flash" "DeepSeek V4 Flash" 0.14 0.28 0.0028 0.0 1000000 384000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "deepseek/deepseek-v4-pro" "DeepSeek V4 Pro" 0.435 0.87 0.0036 0.0 1000000 384000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-2.5-flash" "Gemini 2.5 Flash" 0.3 2.5 0.03 0.0 1000000 65536 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-2.5-flash-lite" "Gemini 2.5 Flash Lite" 0.1 0.4 0.01 0.0 1048576 65536 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-2.5-pro" "Gemini 2.5 Pro" 1.25 10.0 0.125 0.0 1048576 65536 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-3-flash" "Gemini 3 Flash" 0.5 3.0 0.05 0.0 1000000 65000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-3-pro-preview" "Gemini 3 Pro Preview" 2.0 12.0 0.2 0.0 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-3.1-flash-lite" "Gemini 3.1 Flash Lite" 0.25 1.5 0.03 0.0 1000000 65000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-3.1-flash-lite-preview" "Gemini 3.1 Flash Lite Preview" 0.25 1.5 0.03 0.0 1000000 65000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-3.1-pro-preview" "Gemini 3.1 Pro Preview" 2.0 12.0 0.2 0.0 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemini-3.5-flash" "Gemini 3.5 Flash" 1.5 9.0 0.15 0.0 1000000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemma-4-26b-a4b-it" "Gemma 4 26B A4B IT" 0.15 0.6 0.015 0.0 262144 131072 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "google/gemma-4-31b-it" "Gemma 4 31B IT" 0.14 0.4 0.0 0.0 262144 131072 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "inception/mercury-2" "Mercury 2" 0.25 0.75 0.025 0.0 128000 128000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "inception/mercury-coder-small" "Mercury Coder Small Beta" 0.25 1.0 0.0 0.0 32000 16384 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "interfaze/interfaze-beta" "Interfaze Beta" 1.5 3.5 0.0 0.0 1000000 32000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "kwaipilot/kat-coder-pro-v1" "KAT-Coder-Pro V1" 0.3 1.2 0.06 0.0 256000 32000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "kwaipilot/kat-coder-pro-v2" "Kat Coder Pro V2" 0.3 1.2 0.06 0.0 256000 256000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meituan/longcat-flash-chat" "LongCat Flash Chat" 0.0 0.0 0.0 0.0 128000 100000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meituan/longcat-flash-thinking-2601" "LongCat Flash Thinking 2601" 0.0 0.0 0.0 0.0 32768 32768 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meta/llama-3.1-70b" "Llama 3.1 70B Instruct" 0.72 0.72 0.0 0.0 128000 8192 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meta/llama-3.1-8b" "Llama 3.1 8B Instruct" 0.22 0.22 0.0 0.0 128000 8192 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meta/llama-3.2-11b" "Llama 3.2 11B Vision Instruct" 0.16 0.16 0.0 0.0 128000 8192 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meta/llama-3.2-90b" "Llama 3.2 90B Vision Instruct" 0.72 0.72 0.0 0.0 128000 8192 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meta/llama-3.3-70b" "Llama 3.3 70B Instruct" 0.72 0.72 0.0 0.0 128000 8192 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meta/llama-4-maverick" "Llama 4 Maverick 17B Instruct" 0.24 0.97 0.0 0.0 128000 8192 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "meta/llama-4-scout" "Llama 4 Scout 17B Instruct" 0.17 0.66 0.0 0.0 128000 8192 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m2" "MiniMax M2" 0.3 1.2 0.03 0.375 205000 205000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m2.1" "MiniMax M2.1" 0.3 1.2 0.03 0.375 204800 131072 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m2.1-lightning" "MiniMax M2.1 Lightning" 0.3 2.4 0.03 0.375 204800 131072 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m2.5" "MiniMax M2.5" 0.3 1.2 0.03 0.375 204800 131000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m2.5-highspeed" "MiniMax M2.5 High Speed" 0.6 2.4 0.03 0.375 204800 131000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m2.7" "MiniMax M2.7" 0.3 1.2 0.06 0.375 204800 131000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m2.7-highspeed" "MiniMax M2.7 High Speed" 0.6 2.4 0.06 0.375 204800 131100 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "minimax/minimax-m3" "MiniMax M3" 0.3 1.2 0.06 0.0 1000000 1000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/codestral" "Mistral Codestral" 0.3 0.9 0.0 0.0 128000 4000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/devstral-2" "Devstral 2" 0.4 2.0 0.0 0.0 256000 256000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/devstral-small" "Devstral Small 1.1" 0.1 0.3 0.0 0.0 128000 64000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/devstral-small-2" "Devstral Small 2" 0.1 0.3 0.0 0.0 256000 256000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/magistral-medium" "Magistral Medium 2509" 2.0 5.0 0.0 0.0 128000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/magistral-small" "Magistral Small 2509" 0.5 1.5 0.0 0.0 128000 64000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/ministral-14b" "Ministral 14B" 0.2 0.2 0.0 0.0 256000 256000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/ministral-3b" "Ministral 3B" 0.1 0.1 0.0 0.0 128000 4000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/ministral-8b" "Ministral 8B" 0.15 0.15 0.0 0.0 128000 4000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/mistral-large-3" "Mistral Large 3" 0.5 1.5 0.0 0.0 256000 256000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/mistral-medium" "Mistral Medium 3.1" 0.4 2.0 0.0 0.0 128000 64000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/mistral-medium-3.5" "Mistral Medium Latest" 1.5 7.5 0.0 0.0 256000 256000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/mistral-nemo" "Mistral Nemo 12B" 0.15 0.15 0.0 0.0 128000 128000 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/mistral-small" "Mistral Small" 0.1 0.3 0.0 0.0 32000 4000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/pixtral-12b" "Pixtral 12B 2409" 0.15 0.15 0.0 0.0 128000 4000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "mistral/pixtral-large" "Pixtral Large" 2.0 6.0 0.0 0.0 128000 4000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "moonshotai/kimi-k2" "Kimi K2 Instruct" 0.57 2.3 0.0 0.0 131072 131072 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "moonshotai/kimi-k2-thinking" "Kimi K2 Thinking" 0.6 2.5 0.15 0.0 262114 262114 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "moonshotai/kimi-k2.5" "Kimi K2.5" 0.6 3.0 0.1 0.0 262114 262114 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "moonshotai/kimi-k2.6" "Kimi K2.6" 0.95 4.0 0.16 0.0 262000 262000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "moonshotai/kimi-k2.7-code" "Kimi K2.7 Code" 0.95 4.0 0.19 0.0 256000 32768 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "moonshotai/kimi-k2.7-code-highspeed" "Kimi K2.7 Code High Speed" 1.9 8.0 0.38 0.0 262144 32768 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "nvidia/nemotron-3-nano-30b-a3b" "Nemotron 3 Nano 30B A3B" 0.05 0.24 0.0 0.0 262144 262144 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "nvidia/nemotron-3-super-120b-a12b" "NVIDIA Nemotron 3 Super 120B A12B" 0.15 0.65 0.0 0.0 256000 32000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "nvidia/nemotron-3-ultra-550b-a55b" "Nemotron 3 Ultra" 0.6 2.4 0.12 0.0 1000000 65000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "nvidia/nemotron-nano-12b-v2-vl" "Nvidia Nemotron Nano 12B V2 VL" 0.2 0.6 0.0 0.0 131072 131072 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "nvidia/nemotron-nano-9b-v2" "Nvidia Nemotron Nano 9B V2" 0.06 0.23 0.0 0.0 131072 131072 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-3.5-turbo" "GPT-3.5 Turbo" 0.5 1.5 0.0 0.0 16385 4096 false #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-4-turbo" "GPT-4 Turbo" 10.0 30.0 0.0 0.0 128000 4096 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-4.1" "GPT-4.1" 2.0 8.0 0.5 0.0 1047576 32768 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-4.1-mini" "GPT-4.1 mini" 0.4 1.6 0.1 0.0 1047576 32768 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-4.1-nano" "GPT-4.1 nano" 0.1 0.4 0.025 0.0 1047576 32768 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-4o" "GPT-4o" 2.5 10.0 1.25 0.0 128000 16384 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-4o-mini" "GPT-4o mini" 0.15 0.6 0.075 0.0 128000 16384 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5" "GPT-5" 1.25 10.0 0.125 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5-chat" "GPT 5 Chat" 1.25 10.0 0.125 0.0 128000 16384 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5-codex" "GPT-5-Codex" 1.25 10.0 0.125 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5-mini" "GPT-5 mini" 0.25 2.0 0.025 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5-nano" "GPT-5 nano" 0.05 0.4 0.005 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5-pro" "GPT-5 pro" 15.0 120.0 0.0 0.0 400000 272000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.1-codex" "GPT-5.1-Codex" 1.25 10.0 0.125 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.1-codex-max" "GPT 5.1 Codex Max" 1.25 10.0 0.125 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.1-codex-mini" "GPT 5.1 Codex Mini" 0.25 2.0 0.025 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.1-instant" "GPT-5.1 Instant" 1.25 10.0 0.125 0.0 128000 16384 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.1-thinking" "GPT 5.1 Thinking" 1.25 10.0 0.125 0.0 400000 128000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.2" "GPT 5.2" 1.75 14.0 0.175 0.0 400000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.2-chat" "GPT 5.2 Chat" 1.75 14.0 0.175 0.0 128000 16384 false #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.2-codex" "GPT 5.2 Codex" 1.75 14.0 0.175 0.0 400000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.2-pro" "GPT 5.2 " 21.0 168.0 0.0 0.0 400000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.3-chat" "GPT-5.3 Chat" 1.75 14.0 0.175 0.0 128000 16384 false #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.3-codex" "GPT 5.3 Codex" 1.75 14.0 0.175 0.0 400000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.4" "GPT 5.4" 2.5 15.0 0.25 0.0 1050000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.4-mini" "GPT 5.4 Mini" 0.75 4.5 0.075 0.0 400000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.4-nano" "GPT 5.4 Nano" 0.2 1.25 0.02 0.0 400000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.4-pro" "GPT 5.4 Pro" 30.0 180.0 0.0 0.0 1050000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.5" "GPT 5.5" 5.0 30.0 0.5 0.0 1000000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-5.5-pro" "GPT 5.5 Pro" 30.0 180.0 0.0 0.0 1000000 128000 true #[{ level := .level .xhigh, mapped := some "xhigh" }, { level := .off, mapped := none }, { level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-oss-120b" "GPT OSS 120B" 0.35 0.75 0.25 0.0 131072 131000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-oss-20b" "GPT OSS 20B" 0.05 0.2 0.0 0.0 131072 8192 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/gpt-oss-safeguard-20b" "GPT OSS Safeguard 20B" 0.075 0.3 0.037 0.0 131072 65536 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/o1" "o1" 15.0 60.0 7.5 0.0 200000 100000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/o3" "o3" 2.0 8.0 0.5 0.0 200000 100000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/o3-deep-research" "o3-deep-research" 10.0 40.0 2.5 0.0 200000 100000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/o3-mini" "o3-mini" 1.1 4.4 0.55 0.0 200000 100000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/o3-pro" "o3 Pro" 20.0 80.0 0.0 0.0 200000 100000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "openai/o4-mini" "o4-mini" 1.1 4.4 0.275 0.0 200000 100000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "sakana/fugu-ultra" "Fugu Ultra" 5.0 30.0 0.5 0.0 1000000 1000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "stepfun/step-3.5-flash" "StepFun 3.5 Flash" 0.09 0.3 0.02 0.0 262114 262114 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "stepfun/step-3.7-flash" "Step 3.7 Flash" 0.2 1.15 0.04 0.0 256000 256000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.1-fast-non-reasoning" "Grok 4.1 Fast Non-Reasoning" 0.2 0.5 0.05 0.0 1000000 1000000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.1-fast-reasoning" "Grok 4.1 Fast Reasoning" 0.2 0.5 0.05 0.0 1000000 1000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.20-multi-agent" "Grok 4.20 Multi-Agent" 1.25 2.5 0.2 0.0 2000000 2000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.20-multi-agent-beta" "Grok 4.20 Multi Agent Beta" 1.25 2.5 0.2 0.0 2000000 2000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.20-non-reasoning" "Grok 4.20 Non-Reasoning" 1.25 2.5 0.2 0.0 2000000 2000000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.20-non-reasoning-beta" "Grok 4.20 Beta Non-Reasoning" 1.25 2.5 0.2 0.0 2000000 2000000 false #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.20-reasoning" "Grok 4.20 Reasoning" 1.25 2.5 0.2 0.0 2000000 2000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.20-reasoning-beta" "Grok 4.20 Beta Reasoning" 1.25 2.5 0.2 0.0 2000000 2000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-4.3" "Grok 4.3" 1.25 2.5 0.2 0.0 1000000 1000000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xai/grok-build-0.1" "Grok Build 0.1" 1.0 2.0 0.2 0.0 256000 256000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xiaomi/mimo-v2-flash" "MiMo V2 Flash" 0.1 0.3 0.01 0.0 262144 32000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xiaomi/mimo-v2-pro" "MiMo V2 Pro" 1.0 3.0 0.2 0.0 1000000 128000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xiaomi/mimo-v2.5" "MiMo M2.5" 0.14 0.28 0.0028 0.0 1050000 131100 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "xiaomi/mimo-v2.5-pro" "MiMo V2.5 Pro" 0.435 0.87 0.0036 0.0 1050000 131000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.5" "GLM-4.5" 0.6 2.2 0.11 0.0 128000 96000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.5-air" "GLM 4.5 Air" 0.2 1.1 0.03 0.0 128000 96000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.5v" "GLM 4.5V" 0.6 1.8 0.11 0.0 66000 16000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.6" "GLM 4.6" 0.6 2.2 0.11 0.0 200000 96000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.6v" "GLM-4.6V" 0.3 0.9 0.05 0.0 128000 24000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.6v-flash" "GLM-4.6V-Flash" 0.0 0.0 0.0 0.0 128000 24000 true #[] #["text", "image"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.7" "GLM 4.7" 2.25 2.75 2.25 0.0 131000 40000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.7-flash" "GLM 4.7 Flash" 0.07 0.4 0.0 0.0 200000 131000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-4.7-flashx" "GLM 4.7 FlashX" 0.06 0.4 0.01 0.0 200000 128000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-5" "GLM 5" 1.0 3.2 0.2 0.0 202800 131100 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-5-turbo" "GLM 5 Turbo" 1.2 4.0 0.24 0.0 202800 131100 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-5.1" "GLM 5.1" 1.4 4.4 0.26 0.0 202800 64000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-5.2" "GLM 5.2" 1.5 4.5 0.3 0.0 1000000 128000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-5.2-fast" "GLM 5.2 Fast" 3.0 10.25 0.5 0.0 1000000 128000 true #[] #["text"]
   , catalogAnthropicMessagesModel vercelAIGatewayProviderId vercelAIGatewayBaseUrl "zai/glm-5v-turbo" "GLM 5V Turbo" 1.2 4.0 0.24 0.0 200000 128000 true #[] #["text", "image"]
   ]

def opencodeModels : Array ModelInfo :=
  #[
   catalogModel opencodeProviderId "big-pickle" "Big Pickle" "openai-completions" "https://opencode.ai/zen/v1" 0.0 0.0 0.0 0.0 200000 32000 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeProviderId "claude-haiku-4-5" "Claude Haiku 4.5" "anthropic-messages" "https://opencode.ai/zen" 1.0 5.0 0.1 1.25 200000 64000 true {} #[] #["text", "image"]
   , catalogModel opencodeProviderId "claude-opus-4-1" "Claude Opus 4.1" "anthropic-messages" "https://opencode.ai/zen" 15.0 75.0 1.5 18.75 200000 32000 true {} #[] #["text", "image"]
   , catalogModel opencodeProviderId "claude-opus-4-5" "Claude Opus 4.5" "anthropic-messages" "https://opencode.ai/zen" 5.0 25.0 0.5 6.25 200000 64000 true {} #[] #["text", "image"]
   , catalogModel opencodeProviderId "claude-opus-4-6" "Claude Opus 4.6" "anthropic-messages" "https://opencode.ai/zen" 5.0 25.0 0.5 6.25 1000000 128000 true { forceAdaptiveThinking := true } #[{ level := .level .xhigh, mapped := some "max" }] #["text", "image"]
   , catalogModel opencodeProviderId "claude-opus-4-7" "Claude Opus 4.7" "anthropic-messages" "https://opencode.ai/zen" 5.0 25.0 0.5 6.25 1000000 128000 true { supportsTemperature := false, forceAdaptiveThinking := true } #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "claude-opus-4-8" "Claude Opus 4.8" "anthropic-messages" "https://opencode.ai/zen" 5.0 25.0 0.5 6.25 1000000 128000 true { supportsTemperature := false, forceAdaptiveThinking := true } #[{ level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "claude-sonnet-4" "Claude Sonnet 4" "anthropic-messages" "https://opencode.ai/zen" 3.0 15.0 0.3 3.75 200000 64000 true {} #[] #["text", "image"]
   , catalogModel opencodeProviderId "claude-sonnet-4-5" "Claude Sonnet 4.5" "anthropic-messages" "https://opencode.ai/zen" 3.0 15.0 0.3 3.75 200000 64000 true {} #[] #["text", "image"]
   , catalogModel opencodeProviderId "claude-sonnet-4-6" "Claude Sonnet 4.6" "anthropic-messages" "https://opencode.ai/zen" 3.0 15.0 0.3 3.75 1000000 64000 true { forceAdaptiveThinking := true } #[] #["text", "image"]
   , catalogModel opencodeProviderId "deepseek-v4-flash" "DeepSeek V4 Flash" "openai-completions" "https://opencode.ai/zen/v1" 0.14 0.28 0.028 0.0 1000000 384000 true { supportsStore := false, supportsDeveloperRole := false, requiresReasoningContentOnAssistantMessages := true, supportsLongCacheRetention := false } #[{ level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }, { level := .level .high, mapped := some "high" }, { level := .level .xhigh, mapped := some "max" }] #["text"]
   , catalogModel opencodeProviderId "deepseek-v4-flash-free" "DeepSeek V4 Flash Free" "openai-completions" "https://opencode.ai/zen/v1" 0.0 0.0 0.0 0.0 200000 128000 true { supportsStore := false, supportsDeveloperRole := false, requiresReasoningContentOnAssistantMessages := true } #[{ level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }, { level := .level .high, mapped := some "high" }, { level := .level .xhigh, mapped := some "max" }] #["text"]
   , catalogModel opencodeProviderId "deepseek-v4-pro" "DeepSeek V4 Pro" "openai-completions" "https://opencode.ai/zen/v1" 1.74 3.84 0.145 0.0 1000000 384000 true { supportsStore := false, supportsDeveloperRole := false, requiresReasoningContentOnAssistantMessages := true, supportsLongCacheRetention := false } #[{ level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }, { level := .level .high, mapped := some "high" }, { level := .level .xhigh, mapped := some "max" }] #["text"]
   , catalogModel opencodeProviderId "gemini-3-flash" "Gemini 3 Flash" "google-generative-ai" "https://opencode.ai/zen/v1" 0.5 3.0 0.05 0.0 1048576 65536 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gemini-3.1-pro" "Gemini 3.1 Pro Preview" "google-generative-ai" "https://opencode.ai/zen/v1" 2.0 12.0 0.2 0.0 1048576 65536 true {} #[{ level := .off, mapped := none }, { level := .level .minimal, mapped := none }, { level := .level .low, mapped := some "LOW" }, { level := .level .medium, mapped := none }, { level := .level .high, mapped := some "HIGH" }] #["text", "image"]
   , catalogModel opencodeProviderId "gemini-3.5-flash" "Gemini 3.5 Flash" "google-generative-ai" "https://opencode.ai/zen/v1" 1.5 9.0 0.15 0.0 1048576 65536 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "glm-5" "GLM-5" "openai-completions" "https://opencode.ai/zen/v1" 1.0 3.2 0.2 0.0 204800 131072 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeProviderId "glm-5.1" "GLM-5.1" "openai-completions" "https://opencode.ai/zen/v1" 1.4 4.4 0.26 0.0 204800 131072 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeProviderId "glm-5.2" "GLM-5.2" "openai-completions" "https://opencode.ai/zen/v1" 1.4 4.4 0.26 0.0 1000000 131072 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeProviderId "gpt-5" "GPT-5" "openai-responses" "https://opencode.ai/zen/v1" 1.07 8.5 0.107 0.0 400000 128000 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5-codex" "GPT-5 Codex" "openai-responses" "https://opencode.ai/zen/v1" 1.07 8.5 0.107 0.0 400000 128000 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5-nano" "GPT-5 Nano" "openai-responses" "https://opencode.ai/zen/v1" 0.05 0.4 0.005 0.0 400000 128000 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.1" "GPT-5.1" "openai-responses" "https://opencode.ai/zen/v1" 1.07 8.5 0.107 0.0 400000 128000 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.1-codex" "GPT-5.1 Codex" "openai-responses" "https://opencode.ai/zen/v1" 1.07 8.5 0.107 0.0 400000 128000 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.1-codex-max" "GPT-5.1 Codex Max" "openai-responses" "https://opencode.ai/zen/v1" 1.25 10.0 0.125 0.0 400000 128000 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.1-codex-mini" "GPT-5.1 Codex Mini" "openai-responses" "https://opencode.ai/zen/v1" 0.25 2.0 0.025 0.0 400000 128000 true {} #[{ level := .off, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.2" "GPT-5.2" "openai-responses" "https://opencode.ai/zen/v1" 1.75 14.0 0.175 0.0 400000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.2-codex" "GPT-5.2 Codex" "openai-responses" "https://opencode.ai/zen/v1" 1.75 14.0 0.175 0.0 400000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.3-codex" "GPT-5.3 Codex" "openai-responses" "https://opencode.ai/zen/v1" 1.75 14.0 0.175 0.0 400000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.4" "GPT-5.4" "openai-responses" "https://opencode.ai/zen/v1" 2.5 15.0 0.25 0.0 1000000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.4-mini" "GPT-5.4 mini" "openai-responses" "https://opencode.ai/zen/v1" 0.75 4.5 0.075 0.0 400000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.4-nano" "GPT-5.4 nano" "openai-responses" "https://opencode.ai/zen/v1" 0.2 1.25 0.02 0.0 400000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.4-pro" "GPT-5.4 Pro" "openai-responses" "https://opencode.ai/zen/v1" 30.0 180.0 30.0 0.0 1050000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.5" "GPT-5.5" "openai-responses" "https://opencode.ai/zen/v1" 5.0 30.0 0.5 0.0 1000000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }] #["text", "image"]
   , catalogModel opencodeProviderId "gpt-5.5-pro" "GPT-5.5 Pro" "openai-responses" "https://opencode.ai/zen/v1" 30.0 180.0 30.0 0.0 1050000 128000 true {} #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }, { level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "grok-build-0.1" "Grok Build 0.1" "openai-completions" "https://opencode.ai/zen/v1" 1.0 2.0 0.2 0.0 256000 256000 true { supportsStore := false, supportsDeveloperRole := false, supportsReasoningEffort := false } #[{ level := .off, mapped := none }, { level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }] #["text", "image"]
   , catalogModel opencodeProviderId "kimi-k2.5" "Kimi K2.5" "openai-completions" "https://opencode.ai/zen/v1" 0.6 3.0 0.08 0.0 262144 65536 true { supportsStore := false, supportsDeveloperRole := false, supportsLongCacheRetention := false } #[] #["text", "image"]
   , catalogModel opencodeProviderId "kimi-k2.6" "Kimi K2.6" "openai-completions" "https://opencode.ai/zen/v1" 0.95 4.0 0.16 0.0 262144 65536 true { supportsStore := false, supportsDeveloperRole := false, thinkingFormat := some "deepseek", supportsReasoningEffort := false, supportsLongCacheRetention := false } #[] #["text", "image"]
   , catalogModel opencodeProviderId "mimo-v2.5-free" "MiMo V2.5 Free" "openai-completions" "https://opencode.ai/zen/v1" 0.0 0.0 0.0 0.0 200000 32000 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text", "image"]
   , catalogModel opencodeProviderId "minimax-m2.5" "MiniMax M2.5" "openai-completions" "https://opencode.ai/zen/v1" 0.3 1.2 0.06 0.0 204800 131072 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeProviderId "minimax-m2.7" "MiniMax M2.7" "openai-completions" "https://opencode.ai/zen/v1" 0.3 1.2 0.06 0.0 204800 131072 true { supportsStore := false, supportsDeveloperRole := false, supportsLongCacheRetention := false } #[] #["text"]
   , catalogModel opencodeProviderId "nemotron-3-ultra-free" "Nemotron 3 Ultra Free" "openai-completions" "https://opencode.ai/zen/v1" 0.0 0.0 0.0 0.0 1000000 128000 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeProviderId "north-mini-code-free" "North Mini Code Free" "openai-completions" "https://opencode.ai/zen/v1" 0.0 0.0 0.0 0.0 256000 64000 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeProviderId "qwen3.5-plus" "Qwen3.5 Plus" "anthropic-messages" "https://opencode.ai/zen" 0.2 1.2 0.02 0.25 262144 65536 true {} #[] #["text", "image"]
   , catalogModel opencodeProviderId "qwen3.6-plus" "Qwen3.6 Plus" "anthropic-messages" "https://opencode.ai/zen" 0.5 3.0 0.05 0.625 262144 65536 true {} #[] #["text", "image"]
   ]

def opencodeGoModels : Array ModelInfo :=
  #[
   catalogModel opencodeGoProviderId "deepseek-v4-flash" "DeepSeek V4 Flash" "openai-completions" "https://opencode.ai/zen/go/v1" 0.14 0.28 0.0028 0.0 1000000 384000 true { supportsStore := false, supportsDeveloperRole := false, requiresReasoningContentOnAssistantMessages := true, thinkingFormat := some "deepseek" } #[{ level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }, { level := .level .high, mapped := some "high" }, { level := .level .xhigh, mapped := some "max" }] #["text"]
   , catalogModel opencodeGoProviderId "deepseek-v4-pro" "DeepSeek V4 Pro" "openai-completions" "https://opencode.ai/zen/go/v1" 1.74 3.48 0.0145 0.0 1000000 384000 true { supportsStore := false, supportsDeveloperRole := false, requiresReasoningContentOnAssistantMessages := true, thinkingFormat := some "deepseek" } #[{ level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }, { level := .level .high, mapped := some "high" }, { level := .level .xhigh, mapped := some "max" }] #["text"]
   , catalogModel opencodeGoProviderId "glm-5.1" "GLM-5.1" "openai-completions" "https://opencode.ai/zen/go/v1" 1.4 4.4 0.26 0.0 202752 32768 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeGoProviderId "glm-5.2" "GLM-5.2" "openai-completions" "https://opencode.ai/zen/go/v1" 1.4 4.4 0.26 0.0 1000000 131072 true { supportsStore := false, supportsDeveloperRole := false } #[{ level := .off, mapped := none }, { level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }, { level := .level .high, mapped := some "high" }, { level := .level .xhigh, mapped := some "max" }] #["text"]
   , catalogModel opencodeGoProviderId "kimi-k2.6" "Kimi K2.6" "openai-completions" "https://opencode.ai/zen/go/v1" 0.95 4.0 0.16 0.0 262144 65536 true { supportsStore := false, supportsDeveloperRole := false, thinkingFormat := some "deepseek", supportsReasoningEffort := false, supportsLongCacheRetention := false } #[{ level := .level .minimal, mapped := none }, { level := .level .low, mapped := none }, { level := .level .medium, mapped := none }] #["text", "image"]
   , catalogModel opencodeGoProviderId "kimi-k2.7-code" "Kimi K2.7 Code" "openai-completions" "https://opencode.ai/zen/go/v1" 0.95 4.0 0.19 0.0 262144 262144 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text", "image"]
   , catalogModel opencodeGoProviderId "mimo-v2.5" "MiMo V2.5" "openai-completions" "https://opencode.ai/zen/go/v1" 0.14 0.28 0.0028 0.0 1000000 128000 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text", "image"]
   , catalogModel opencodeGoProviderId "mimo-v2.5-pro" "MiMo V2.5 Pro" "openai-completions" "https://opencode.ai/zen/go/v1" 1.74 3.48 0.0145 0.0 1048576 128000 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeGoProviderId "minimax-m2.7" "MiniMax M2.7" "openai-completions" "https://opencode.ai/zen/go/v1" 0.3 1.2 0.06 0.0 204800 131072 true { supportsStore := false, supportsDeveloperRole := false } #[] #["text"]
   , catalogModel opencodeGoProviderId "minimax-m3" "MiniMax M3 (3x usage)" "anthropic-messages" "https://opencode.ai/zen/go" 0.1 0.4 0.02 0.0 512000 131072 true {} #[] #["text", "image"]
   , catalogModel opencodeGoProviderId "qwen3.6-plus" "Qwen3.6 Plus" "openai-completions" "https://opencode.ai/zen/go/v1" 0.5 3.0 0.05 0.625 1000000 65536 true { supportsStore := false, supportsDeveloperRole := false, thinkingFormat := some "qwen" } #[] #["text", "image"]
   , catalogModel opencodeGoProviderId "qwen3.7-max" "Qwen3.7 Max" "anthropic-messages" "https://opencode.ai/zen/go" 2.5 7.5 0.5 3.125 1000000 65536 true {} #[] #["text"]
   , catalogModel opencodeGoProviderId "qwen3.7-plus" "Qwen3.7 Plus" "anthropic-messages" "https://opencode.ai/zen/go" 0.4 1.6 0.04 0.5 1000000 65536 true {} #[] #["text", "image"]
   ]

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

def bedrockModel
    (id name : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := false)
    (input : Array String := #["text"]) : ModelInfo :=
  { id := id
    name := name
    provider := amazonBedrockProviderId
    api := LeanAgent.AI.Api.BedrockConverseStream.api
    baseUrl := amazonBedrockBaseUrl
    reasoning := reasoning
    input := input
    cost := cost inputCost outputCost cacheReadCost cacheWriteCost
    contextWindow := contextWindow
    maxTokens := maxTokens
  }

def amazonBedrockModels : Array ModelInfo :=
  #[ bedrockModel "amazon.nova-2-lite-v1:0" "Nova 2 Lite" 0.33 2.75 0.0 0.0 128000 4096 true #["text", "image"]
   , bedrockModel "amazon.nova-lite-v1:0" "Nova Lite" 0.06 0.24 0.015 0.0 300000 8192 false #["text", "image"]
   , bedrockModel "amazon.nova-micro-v1:0" "Nova Micro" 0.035 0.14 0.00875 0.0 128000 8192 false #["text"]
   , bedrockModel "amazon.nova-pro-v1:0" "Nova Pro" 0.8 3.2 0.2 0.0 300000 8192 false #["text", "image"]
   , bedrockModel "anthropic.claude-haiku-4-5-20251001-v1:0" "Claude Haiku 4.5" 1.0 5.0 0.1 1.25 200000 64000 true #["text", "image"]
   , bedrockModel "anthropic.claude-opus-4-1-20250805-v1:0" "Claude Opus 4.1" 15.0 75.0 1.5 18.75 200000 32000 true #["text", "image"]
   , bedrockModel "anthropic.claude-opus-4-5-20251101-v1:0" "Claude Opus 4.5" 5.0 25.0 0.5 6.25 200000 64000 true #["text", "image"]
   , bedrockModel "anthropic.claude-opus-4-6-v1" "Claude Opus 4.6" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "anthropic.claude-opus-4-7" "Claude Opus 4.7" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "anthropic.claude-opus-4-8" "Claude Opus 4.8" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "anthropic.claude-sonnet-4-5-20250929-v1:0" "Claude Sonnet 4.5" 3.0 15.0 0.3 3.75 200000 64000 true #["text", "image"]
   , bedrockModel "anthropic.claude-sonnet-4-6" "Claude Sonnet 4.6" 3.0 15.0 0.3 3.75 1000000 64000 true #["text", "image"]
   , bedrockModel "au.anthropic.claude-haiku-4-5-20251001-v1:0" "Claude Haiku 4.5 (AU)" 1.0 5.0 0.1 1.25 200000 64000 true #["text", "image"]
   , bedrockModel "au.anthropic.claude-opus-4-6-v1" "AU Anthropic Claude Opus 4.6" 16.5 82.5 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "au.anthropic.claude-opus-4-8" "Claude Opus 4.8 (AU)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "au.anthropic.claude-sonnet-4-5-20250929-v1:0" "Claude Sonnet 4.5 (AU)" 3.0 15.0 0.3 3.75 200000 64000 true #["text", "image"]
   , bedrockModel "au.anthropic.claude-sonnet-4-6" "AU Anthropic Claude Sonnet 4.6" 3.3 16.5 0.33 4.125 1000000 128000 true #["text", "image"]
   , bedrockModel "deepseek.r1-v1:0" "DeepSeek-R1" 1.35 5.4 0.0 0.0 128000 32768 true #["text"]
   , bedrockModel "deepseek.v3-v1:0" "DeepSeek-V3.1" 0.58 1.68 0.0 0.0 163840 81920 true #["text"]
   , bedrockModel "deepseek.v3.2" "DeepSeek-V3.2" 0.62 1.85 0.0 0.0 163840 81920 true #["text"]
   , bedrockModel "eu.anthropic.claude-fable-5" "Claude Fable 5 (EU)" 11.0 55.0 1.1 13.75 1000000 128000 true #["text", "image"]
   , bedrockModel "eu.anthropic.claude-haiku-4-5-20251001-v1:0" "Claude Haiku 4.5 (EU)" 1.0 5.0 0.1 1.25 200000 64000 true #["text", "image"]
   , bedrockModel "eu.anthropic.claude-opus-4-5-20251101-v1:0" "Claude Opus 4.5 (EU)" 5.0 25.0 0.5 6.25 200000 64000 true #["text", "image"]
   , bedrockModel "eu.anthropic.claude-opus-4-6-v1" "Claude Opus 4.6 (EU)" 5.5 27.5 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "eu.anthropic.claude-opus-4-7" "Claude Opus 4.7 (EU)" 5.5 27.5 0.55 6.875 1000000 128000 true #["text", "image"]
   , bedrockModel "eu.anthropic.claude-opus-4-8" "Claude Opus 4.8 (EU)" 5.5 27.5 0.55 6.875 1000000 128000 true #["text", "image"]
   , bedrockModel "eu.anthropic.claude-sonnet-4-5-20250929-v1:0" "Claude Sonnet 4.5 (EU)" 3.3 16.5 0.33 4.125 200000 64000 true #["text", "image"]
   , bedrockModel "eu.anthropic.claude-sonnet-4-6" "Claude Sonnet 4.6 (EU)" 3.3 16.5 0.33 4.125 1000000 64000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-fable-5" "Claude Fable 5 (Global)" 10.0 50.0 1.0 12.5 1000000 128000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-haiku-4-5-20251001-v1:0" "Claude Haiku 4.5 (Global)" 1.0 5.0 0.1 1.25 200000 64000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-opus-4-5-20251101-v1:0" "Claude Opus 4.5 (Global)" 5.0 25.0 0.5 6.25 200000 64000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-opus-4-6-v1" "Claude Opus 4.6 (Global)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-opus-4-7" "Claude Opus 4.7 (Global)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-opus-4-8" "Claude Opus 4.8 (Global)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-sonnet-4-5-20250929-v1:0" "Claude Sonnet 4.5 (Global)" 3.0 15.0 0.3 3.75 200000 64000 true #["text", "image"]
   , bedrockModel "global.anthropic.claude-sonnet-4-6" "Claude Sonnet 4.6 (Global)" 3.0 15.0 0.3 3.75 1000000 64000 true #["text", "image"]
   , bedrockModel "google.gemma-3-27b-it" "Google Gemma 3 27B Instruct" 0.12 0.2 0.0 0.0 202752 8192 false #["text", "image"]
   , bedrockModel "google.gemma-3-4b-it" "Gemma 3 4B IT" 0.04 0.08 0.0 0.0 128000 4096 false #["text", "image"]
   , bedrockModel "jp.anthropic.claude-opus-4-7" "Claude Opus 4.7 (JP)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "jp.anthropic.claude-opus-4-8" "Claude Opus 4.8 (JP)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "jp.anthropic.claude-sonnet-4-5-20250929-v1:0" "Claude Sonnet 4.5 (JP)" 3.0 15.0 0.3 3.75 200000 64000 true #["text", "image"]
   , bedrockModel "jp.anthropic.claude-sonnet-4-6" "Claude Sonnet 4.6 (JP)" 3.0 15.0 0.3 3.75 1000000 64000 true #["text", "image"]
   , bedrockModel "meta.llama3-1-70b-instruct-v1:0" "Llama 3.1 70B Instruct" 0.72 0.72 0.0 0.0 128000 4096 false #["text"]
   , bedrockModel "meta.llama3-1-8b-instruct-v1:0" "Llama 3.1 8B Instruct" 0.22 0.22 0.0 0.0 128000 4096 false #["text"]
   , bedrockModel "meta.llama3-3-70b-instruct-v1:0" "Llama 3.3 70B Instruct" 0.72 0.72 0.0 0.0 128000 4096 false #["text"]
   , bedrockModel "meta.llama4-maverick-17b-instruct-v1:0" "Llama 4 Maverick 17B Instruct" 0.24 0.97 0.0 0.0 1000000 16384 false #["text", "image"]
   , bedrockModel "meta.llama4-scout-17b-instruct-v1:0" "Llama 4 Scout 17B Instruct" 0.17 0.66 0.0 0.0 3500000 16384 false #["text", "image"]
   , bedrockModel "minimax.minimax-m2" "MiniMax M2" 0.3 1.2 0.0 0.0 204608 128000 true #["text"]
   , bedrockModel "minimax.minimax-m2.1" "MiniMax M2.1" 0.3 1.2 0.0 0.0 204800 131072 true #["text"]
   , bedrockModel "minimax.minimax-m2.5" "MiniMax M2.5" 0.3 1.2 0.0 0.0 196608 98304 true #["text"]
   , bedrockModel "mistral.devstral-2-123b" "Devstral 2 123B" 0.4 2.0 0.0 0.0 256000 8192 false #["text"]
   , bedrockModel "mistral.magistral-small-2509" "Magistral Small 1.2" 0.5 1.5 0.0 0.0 128000 40000 true #["text", "image"]
   , bedrockModel "mistral.ministral-3-14b-instruct" "Ministral 14B 3.0" 0.2 0.2 0.0 0.0 128000 4096 false #["text"]
   , bedrockModel "mistral.ministral-3-3b-instruct" "Ministral 3 3B" 0.1 0.1 0.0 0.0 256000 8192 false #["text", "image"]
   , bedrockModel "mistral.ministral-3-8b-instruct" "Ministral 3 8B" 0.15 0.15 0.0 0.0 128000 4096 false #["text"]
   , bedrockModel "mistral.mistral-large-3-675b-instruct" "Mistral Large 3" 0.5 1.5 0.0 0.0 256000 8192 false #["text", "image"]
   , bedrockModel "mistral.pixtral-large-2502-v1:0" "Pixtral Large (25.02)" 2.0 6.0 0.0 0.0 128000 8192 false #["text", "image"]
   , bedrockModel "mistral.voxtral-mini-3b-2507" "Voxtral Mini 3B 2507" 0.04 0.04 0.0 0.0 128000 4096 false #["text"]
   , bedrockModel "mistral.voxtral-small-24b-2507" "Voxtral Small 24B 2507" 0.15 0.35 0.0 0.0 32000 8192 false #["text"]
   , bedrockModel "moonshot.kimi-k2-thinking" "Kimi K2 Thinking" 0.6 2.5 0.0 0.0 262143 16000 true #["text"]
   , bedrockModel "moonshotai.kimi-k2.5" "Kimi K2.5" 0.6 3.0 0.0 0.0 262143 16000 true #["text", "image"]
   , bedrockModel "nvidia.nemotron-nano-12b-v2" "NVIDIA Nemotron Nano 12B v2 VL BF16" 0.2 0.6 0.0 0.0 128000 4096 false #["text", "image"]
   , bedrockModel "nvidia.nemotron-nano-3-30b" "NVIDIA Nemotron Nano 3 30B" 0.06 0.24 0.0 0.0 128000 4096 true #["text"]
   , bedrockModel "nvidia.nemotron-nano-9b-v2" "NVIDIA Nemotron Nano 9B v2" 0.06 0.23 0.0 0.0 128000 4096 false #["text"]
   , bedrockModel "nvidia.nemotron-super-3-120b" "NVIDIA Nemotron 3 Super 120B A12B" 0.15 0.65 0.0 0.0 262144 131072 true #["text"]
   , bedrockModel "openai.gpt-5.4" "GPT-5.4" 2.75 16.5 0.275 0.0 272000 128000 true #["text", "image"]
   , bedrockModel "openai.gpt-5.5" "GPT-5.5" 5.5 33.0 0.55 0.0 272000 128000 true #["text", "image"]
   , bedrockModel "openai.gpt-oss-120b" "gpt-oss-120b" 0.15 0.6 0.0 0.0 128000 16384 true #["text"]
   , bedrockModel "openai.gpt-oss-120b-1:0" "gpt-oss-120b" 0.15 0.6 0.0 0.0 128000 16384 true #["text"]
   , bedrockModel "openai.gpt-oss-20b" "gpt-oss-20b" 0.07 0.3 0.0 0.0 128000 16384 true #["text"]
   , bedrockModel "openai.gpt-oss-20b-1:0" "gpt-oss-20b" 0.07 0.3 0.0 0.0 128000 16384 true #["text"]
   , bedrockModel "openai.gpt-oss-safeguard-120b" "GPT OSS Safeguard 120B" 0.15 0.6 0.0 0.0 128000 16384 false #["text"]
   , bedrockModel "openai.gpt-oss-safeguard-20b" "GPT OSS Safeguard 20B" 0.07 0.2 0.0 0.0 128000 16384 false #["text"]
   , bedrockModel "qwen.qwen3-235b-a22b-2507-v1:0" "Qwen3 235B A22B 2507" 0.22 0.88 0.0 0.0 262144 131072 false #["text"]
   , bedrockModel "qwen.qwen3-32b-v1:0" "Qwen3 32B (dense)" 0.15 0.6 0.0 0.0 16384 16384 true #["text"]
   , bedrockModel "qwen.qwen3-coder-30b-a3b-v1:0" "Qwen3 Coder 30B A3B Instruct" 0.15 0.6 0.0 0.0 262144 131072 false #["text"]
   , bedrockModel "qwen.qwen3-coder-480b-a35b-v1:0" "Qwen3 Coder 480B A35B Instruct" 0.22 1.8 0.0 0.0 131072 65536 false #["text"]
   , bedrockModel "qwen.qwen3-coder-next" "Qwen3 Coder Next" 0.22 1.8 0.0 0.0 131072 65536 true #["text"]
   , bedrockModel "qwen.qwen3-next-80b-a3b" "Qwen/Qwen3-Next-80B-A3B-Instruct" 0.14 1.4 0.0 0.0 262000 262000 false #["text"]
   , bedrockModel "qwen.qwen3-vl-235b-a22b" "Qwen/Qwen3-VL-235B-A22B-Instruct" 0.3 1.5 0.0 0.0 262000 262000 false #["text", "image"]
   , bedrockModel "us.anthropic.claude-fable-5" "Claude Fable 5 (US)" 10.0 50.0 1.0 12.5 1000000 128000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-haiku-4-5-20251001-v1:0" "Claude Haiku 4.5 (US)" 1.0 5.0 0.1 1.25 200000 64000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-opus-4-1-20250805-v1:0" "Claude Opus 4.1 (US)" 15.0 75.0 1.5 18.75 200000 32000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-opus-4-5-20251101-v1:0" "Claude Opus 4.5 (US)" 5.0 25.0 0.5 6.25 200000 64000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-opus-4-6-v1" "Claude Opus 4.6 (US)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-opus-4-7" "Claude Opus 4.7 (US)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-opus-4-8" "Claude Opus 4.8 (US)" 5.0 25.0 0.5 6.25 1000000 128000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-sonnet-4-5-20250929-v1:0" "Claude Sonnet 4.5 (US)" 3.0 15.0 0.3 3.75 200000 64000 true #["text", "image"]
   , bedrockModel "us.anthropic.claude-sonnet-4-6" "Claude Sonnet 4.6 (US)" 3.0 15.0 0.3 3.75 1000000 64000 true #["text", "image"]
   , bedrockModel "us.deepseek.r1-v1:0" "DeepSeek-R1 (US)" 1.35 5.4 0.0 0.0 128000 32768 true #["text"]
   , bedrockModel "us.meta.llama4-maverick-17b-instruct-v1:0" "Llama 4 Maverick 17B Instruct (US)" 0.24 0.97 0.0 0.0 1000000 16384 false #["text", "image"]
   , bedrockModel "us.meta.llama4-scout-17b-instruct-v1:0" "Llama 4 Scout 17B Instruct (US)" 0.17 0.66 0.0 0.0 3500000 16384 false #["text", "image"]
   , bedrockModel "writer.palmyra-x4-v1:0" "Palmyra X4" 2.5 10.0 0.0 0.0 122880 8192 true #["text"]
   , bedrockModel "writer.palmyra-x5-v1:0" "Palmyra X5" 0.6 6.0 0.0 0.0 1040000 8192 true #["text"]
   , bedrockModel "zai.glm-4.7" "GLM-4.7" 0.6 2.2 0.0 0.0 204800 131072 true #["text"]
   , bedrockModel "zai.glm-4.7-flash" "GLM-4.7-Flash" 0.07 0.4 0.0 0.0 200000 131072 true #["text"]
   , bedrockModel "zai.glm-5" "GLM-5" 1.0 3.2 0.0 0.0 202752 101376 true #["text"]
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
  headers : LeanAgent.AI.Auth.ProviderHeaders := #[]
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

def antLingProviderInfo : ProviderInfo :=
  { id := antLingProviderId
    name := "Ant Ling"
    baseUrl := antLingBaseUrl
    apiKeyEnv := antLingApiKeyEnv
    defaultModel := antLingDefaultModel
    models := antLingModels
  }

def huggingFaceProviderInfo : ProviderInfo :=
  { id := huggingFaceProviderId
    name := "Hugging Face"
    baseUrl := huggingFaceBaseUrl
    apiKeyEnv := huggingFaceApiKeyEnv
    defaultModel := huggingFaceDefaultModel
    models := huggingFaceModels
  }

def moonshotAIProviderInfo : ProviderInfo :=
  { id := moonshotAIProviderId
    name := "Moonshot AI"
    baseUrl := moonshotAIBaseUrl
    apiKeyEnv := moonshotAIApiKeyEnv
    defaultModel := moonshotAIDefaultModel
    models := moonshotAIModels
  }

def moonshotAICNProviderInfo : ProviderInfo :=
  { id := moonshotAICNProviderId
    name := "Moonshot AI CN"
    baseUrl := moonshotAICNBaseUrl
    apiKeyEnv := moonshotAICNApiKeyEnv
    defaultModel := moonshotAICNDefaultModel
    models := moonshotAICNModels
  }

def nvidiaProviderInfo : ProviderInfo :=
  { id := nvidiaProviderId
    name := "NVIDIA"
    baseUrl := nvidiaBaseUrl
    apiKeyEnv := nvidiaApiKeyEnv
    defaultModel := nvidiaDefaultModel
    models := nvidiaModels
  }

def xiaomiProviderInfo : ProviderInfo :=
  { id := xiaomiProviderId
    name := "Xiaomi"
    baseUrl := xiaomiBaseUrl
    apiKeyEnv := xiaomiApiKeyEnv
    defaultModel := xiaomiDefaultModel
    models := xiaomiModels
  }

def xiaomiTokenPlanAMSProviderInfo : ProviderInfo :=
  { id := xiaomiTokenPlanAMSProviderId
    name := "Xiaomi Token Plan AMS"
    baseUrl := xiaomiTokenPlanAMSBaseUrl
    apiKeyEnv := xiaomiTokenPlanAMSApiKeyEnv
    defaultModel := xiaomiTokenPlanAMSDefaultModel
    models := xiaomiTokenPlanAMSModels
  }

def xiaomiTokenPlanCNProviderInfo : ProviderInfo :=
  { id := xiaomiTokenPlanCNProviderId
    name := "Xiaomi Token Plan CN"
    baseUrl := xiaomiTokenPlanCNBaseUrl
    apiKeyEnv := xiaomiTokenPlanCNApiKeyEnv
    defaultModel := xiaomiTokenPlanCNDefaultModel
    models := xiaomiTokenPlanCNModels
  }

def xiaomiTokenPlanSGPProviderInfo : ProviderInfo :=
  { id := xiaomiTokenPlanSGPProviderId
    name := "Xiaomi Token Plan SGP"
    baseUrl := xiaomiTokenPlanSGPBaseUrl
    apiKeyEnv := xiaomiTokenPlanSGPApiKeyEnv
    defaultModel := xiaomiTokenPlanSGPDefaultModel
    models := xiaomiTokenPlanSGPModels
  }

def zaiProviderInfo : ProviderInfo :=
  { id := zaiProviderId
    name := "Z.AI"
    baseUrl := zaiBaseUrl
    apiKeyEnv := zaiApiKeyEnv
    defaultModel := zaiDefaultModel
    models := zaiModels
  }

def zaiCodingCNProviderInfo : ProviderInfo :=
  { id := zaiCodingCNProviderId
    name := "Z.AI Coding CN"
    baseUrl := zaiCodingCNBaseUrl
    apiKeyEnv := zaiCodingCNApiKeyEnv
    defaultModel := zaiCodingCNDefaultModel
    models := zaiCodingCNModels
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

def kimiCodingProviderInfo : ProviderInfo :=
  { id := kimiCodingProviderId
    name := "Kimi For Coding"
    baseUrl := kimiCodingBaseUrl
    headers := kimiCodingHeaders
    apiKeyEnv := kimiCodingApiKeyEnv
    defaultModel := kimiCodingDefaultModel
    models := kimiCodingModels
  }

def minimaxProviderInfo : ProviderInfo :=
  { id := minimaxProviderId
    name := "MiniMax"
    baseUrl := minimaxBaseUrl
    apiKeyEnv := minimaxApiKeyEnv
    defaultModel := minimaxDefaultModel
    models := minimaxModels
  }

def minimaxCNProviderInfo : ProviderInfo :=
  { id := minimaxCNProviderId
    name := "MiniMax CN"
    baseUrl := minimaxCNBaseUrl
    apiKeyEnv := minimaxCNApiKeyEnv
    defaultModel := minimaxCNDefaultModel
    models := minimaxCNModels
  }

def vercelAIGatewayProviderInfo : ProviderInfo :=
  { id := vercelAIGatewayProviderId
    name := "Vercel AI Gateway"
    baseUrl := vercelAIGatewayBaseUrl
    apiKeyEnv := vercelAIGatewayApiKeyEnv
    defaultModel := vercelAIGatewayDefaultModel
    models := vercelAIGatewayModels
  }

def opencodeProviderInfo : ProviderInfo :=
  { id := opencodeProviderId
    name := "OpenCode Zen"
    baseUrl := opencodeBaseUrl
    apiKeyEnv := opencodeApiKeyEnv
    defaultModel := opencodeDefaultModel
    models := opencodeModels
  }

def opencodeGoProviderInfo : ProviderInfo :=
  { id := opencodeGoProviderId
    name := "OpenCode Zen Go"
    baseUrl := opencodeGoBaseUrl
    apiKeyEnv := opencodeGoApiKeyEnv
    defaultModel := opencodeGoDefaultModel
    models := opencodeGoModels
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

def amazonBedrockProviderInfo : ProviderInfo :=
  { id := amazonBedrockProviderId
    name := "Amazon Bedrock"
    baseUrl := amazonBedrockBaseUrl
    apiKeyEnv := ""
    apiKeyEnvs := amazonBedrockAuthEnvs
    defaultModel := amazonBedrockDefaultModel
    models := amazonBedrockModels
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
     , antLingProviderInfo
     , huggingFaceProviderInfo
     , moonshotAIProviderInfo
     , moonshotAICNProviderInfo
     , nvidiaProviderInfo
     , xiaomiProviderInfo
     , xiaomiTokenPlanAMSProviderInfo
     , xiaomiTokenPlanCNProviderInfo
     , xiaomiTokenPlanSGPProviderInfo
     , zaiProviderInfo
     , zaiCodingCNProviderInfo
     , anthropicProviderInfo
     , kimiCodingProviderInfo
     , minimaxProviderInfo
     , minimaxCNProviderInfo
     , vercelAIGatewayProviderInfo
     , opencodeProviderInfo
     , opencodeGoProviderInfo
     , googleProviderInfo
     , googleVertexProviderInfo
     , mistralProviderInfo
     , amazonBedrockProviderInfo
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
  | oauth
deriving BEq

def ModelsErrorCode.toString : ModelsErrorCode → String
  | .modelSource => "model_source"
  | .modelValidation => "model_validation"
  | .provider => "provider"
  | .stream => "stream"
  | .auth => "auth"
  | .oauth => "oauth"

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

def anthropicThinkingEffort (model : ModelInfo) (level : LeanAgent.AI.ThinkingLevel) : String :=
  match thinkingLevelMapValue? model (.level level) with
  | some (some mapped) => mapped
  | _ =>
      match level with
      | .minimal => "low"
      | .low => "low"
      | .medium => "medium"
      | .high => "high"
      | .xhigh => "high"

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
    supportsReasoningEffort := model.compat.supportsReasoningEffort
    maxTokensField := model.compat.maxTokensField
    supportsLongCacheRetention := model.compat.supportsLongCacheRetention
    sendSessionAffinityHeaders := model.compat.sendSessionAffinityHeaders
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
      | none => throw (modelsError .oauth s!"missing OAuth access token for provider {model.provider}")
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
  let base :=
    { LeanAgent.AI.Api.AnthropicMessages.optionsFromSimple options with
      supportsTemperature := model.compat.supportsTemperature
      sendSessionAffinityHeaders := model.compat.sendSessionAffinityHeaders
      supportsLongCacheRetention := model.compat.supportsLongCacheRetention
      supportsEagerToolInputStreaming := model.compat.supportsEagerToolInputStreaming
      supportsCacheControlOnTools := model.compat.supportsCacheControlOnTools
      allowEmptySignature := model.compat.allowEmptySignature
      forceAdaptiveThinking := model.compat.forceAdaptiveThinking
    }
  match options.reasoning with
  | none =>
      { base with thinkingEnabled := some false }
  | some level =>
      let maxTokens := (resolvedMaxTokens? model context options).getD model.maxTokens
      if model.compat.forceAdaptiveThinking then
        { base with
          maxTokens := some maxTokens
          thinkingEnabled := some true
          thinkingEffort := some (anthropicThinkingEffort model level)
        }
      else
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

def placeholderAuthToken (value : String) : Bool :=
  value.startsWith "<" && value.endsWith ">"

def bedrockOptionsFromSimple (options : LeanAgent.AI.SimpleStreamOptions) :
    LeanAgent.AI.Api.BedrockConverseStream.BedrockOptions :=
  let base := LeanAgent.AI.Api.BedrockConverseStream.optionsFromSimple options
  let bearerToken :=
    match options.apiKey with
    | some key =>
        let key := key.trimAscii.toString
        if key.isEmpty || placeholderAuthToken key then none else some key
    | none => none
  { base with bearerToken := bearerToken }

def bedrockConverseStreamStreams : ProviderStreams :=
  { streamSimple := fun model context options => do
      let options := clampSimpleOptionsToContext model context options
      let config : LeanAgent.AI.Api.BedrockConverseStream.BedrockConverseStreamConfig :=
        { baseUrl := model.baseUrl }
      let stream ← LeanAgent.AI.Api.BedrockConverseStream.completeStreamWithOptions
        config
        model.toModelRef
        model.input
        model.name
        model.thinkingLevelMap
        model.reasoning
        context
        (bedrockOptionsFromSimple options)
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

def amazonBedrockAmbientAuthSource? (ctx : LeanAgent.AI.Auth.AuthContext) :
    IO (Option String) := do
  match ← ctx.env "AWS_BEARER_TOKEN_BEDROCK" with
  | some _ => pure (some "AWS_BEARER_TOKEN_BEDROCK")
  | none =>
      match ← ctx.env "AWS_PROFILE" with
      | some _ => pure (some "AWS_PROFILE")
      | none =>
          let accessKey ← ctx.env "AWS_ACCESS_KEY_ID"
          let secretKey ← ctx.env "AWS_SECRET_ACCESS_KEY"
          if accessKey.isSome && secretKey.isSome then
            pure (some "AWS access keys")
          else
            match ← ctx.env "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" with
            | some _ => pure (some "ECS task role")
            | none =>
                match ← ctx.env "AWS_CONTAINER_CREDENTIALS_FULL_URI" with
                | some _ => pure (some "ECS task role")
                | none =>
                    match ← ctx.env "AWS_WEB_IDENTITY_TOKEN_FILE" with
                    | some _ => pure (some "web identity token")
                    | none => pure none

def amazonBedrockApiKeyAuth : LeanAgent.AI.Auth.ApiKeyAuth :=
  { name := "AWS credentials"
    resolve := fun ctx credential _modelBaseUrl => do
      let credentialEnv := credential.map (fun value => value.env) |>.getD #[]
      match credential.bind (fun value => value.key) with
      | some key =>
          if key.trimAscii.toString.isEmpty then
            pure none
          else
            pure
              (some
                { auth := { apiKey := some key }
                  env := credentialEnv
                  source := some "stored credential"
                })
      | none =>
          let ctx :=
            match credential with
            | some value => LeanAgent.AI.Auth.overlayEnvAuthContext ctx value.env
            | none => ctx
          match ← amazonBedrockAmbientAuthSource? ctx with
          | some source =>
              pure
                (some
                  { auth := {}
                    env := credentialEnv
                    source := some source
                  })
          | none => pure none
  }

def authForProviderInfo (info : ProviderInfo) : LeanAgent.AI.Auth.ProviderAuth :=
  if info.id == googleVertexProviderId then
    { apiKey := some googleVertexApiKeyAuth }
  else if info.id == openAICodexProviderId then
    { oauth := some openAICodexOAuthAuth }
  else if info.id == amazonBedrockProviderId then
    { apiKey := some amazonBedrockApiKeyAuth }
  else
    { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth (info.name ++ " API key") info.authEnvs) }

def createCatalogProvider (info : ProviderInfo) : IO Provider :=
  createProvider
    { id := info.id
      name := some info.name
      baseUrl := some info.baseUrl
      headers := info.headers
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
         , { api := LeanAgent.AI.Api.BedrockConverseStream.api, streams := bedrockConverseStreamStreams }
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
  let providerModelHeaders :=
    authHeadersToStreamHeaders provider.headers
      (authHeadersToStreamHeaders model.headers options.headers)
  match resolution with
  | none =>
      pure (model, { options with headers := providerModelHeaders })
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
          headers :=
            authHeadersToStreamHeaders provider.headers
              (authHeadersToStreamHeaders model.headers
                (authHeadersToStreamHeaders resolution.auth.headers options.headers))
          env := LeanAgent.AI.Auth.providerEnvMerge resolution.env options.env
        }
      pure (requestModel, requestOptions)

def abortedAssistantMessage (model : ModelInfo) (timestamp : Nat) : LeanAgent.AI.AssistantMessage :=
  { content := #[]
    api := model.api
    provider := model.provider
    model := model.id
    stopReason := .aborted
    errorMessage := some LeanAgent.AI.Util.Abort.requestAbortedMessage
    timestamp := timestamp
  }

def abortedEventStream (model : ModelInfo) (timestamp : Nat) : LeanAgent.AI.AssistantMessageEventStream :=
  LeanAgent.AI.fromMessage (abortedAssistantMessage model timestamp)

def Collection.streamSimple
    (collection : Collection)
    (model : ModelInfo)
    (context : LeanAgent.AI.Context)
    (options : LeanAgent.AI.SimpleStreamOptions := {}) :
    IO LeanAgent.AI.AssistantMessageEventStream := do
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return abortedEventStream model (← IO.monoMsNow)
  let provider ← collection.requireProvider model
  let (requestModel, requestOptions) ← collection.applyAuth provider model options
  try
    provider.streamSimple requestModel context requestOptions
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      pure (abortedEventStream requestModel (← IO.monoMsNow))
    else
      throw err

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
