import LeanAgent.Core
import LeanAgent.AI.Auth
import LeanAgent.AI.Auth.OAuthBridge
import LeanAgent.AI.OAuth.Core
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
import LeanAgent.Models.Core
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

def githubCopilotProviderId : String := "github-copilot"
def githubCopilotApiKeyEnv : String := "COPILOT_GITHUB_TOKEN"
def githubCopilotDefaultModel : String := "gpt-5-mini"
def githubCopilotBaseUrl : String := "https://api.individual.githubcopilot.com"
def githubCopilotHeaders : LeanAgent.AI.Auth.ProviderHeaders :=
  #[ ("User-Agent", "GitHubCopilotChat/0.35.0")
   , ("Editor-Version", "vscode/1.107.0")
   , ("Editor-Plugin-Version", "copilot-chat/0.35.0")
   , ("Copilot-Integration-Id", "vscode-chat")
   ]

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
   , "AWS_DEFAULT_PROFILE"
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

def githubCopilotModel
    (id name api : String)
    (inputCost outputCost cacheReadCost cacheWriteCost : Float)
    (contextWindow maxTokens : Nat)
    (reasoning : Bool := true)
    (compat : ModelCompat := {})
    (thinkingLevelMap : Array LeanAgent.AI.ThinkingLevelMapEntry := #[])
    (input : Array String := #["text", "image"]) : ModelInfo :=
  { (catalogModel githubCopilotProviderId id name api githubCopilotBaseUrl
      inputCost outputCost cacheReadCost cacheWriteCost
      contextWindow maxTokens reasoning compat thinkingLevelMap input) with
    headers := githubCopilotHeaders
  }

def githubCopilotModels : Array ModelInfo :=
  #[
    githubCopilotModel "claude-fable-5" "Claude Fable 5" "openai-completions" 10 50 1 12.5 1000000 128000 true
      { supportsStore := false, supportsDeveloperRole := false, supportsReasoningEffort := false } #[] #["text", "image"]
   , githubCopilotModel "claude-haiku-4.5" "Claude Haiku 4.5 (latest)" "anthropic-messages" 1 5 0.1 1.25 200000 64000 true
      { supportsEagerToolInputStreaming := false } #[] #["text", "image"]
   , githubCopilotModel "claude-opus-4.5" "Claude Opus 4.5 (latest)" "anthropic-messages" 5 25 0.5 6.25 200000 32000 true
      {} #[] #["text", "image"]
   , githubCopilotModel "claude-opus-4.6" "Claude Opus 4.6" "anthropic-messages" 5 25 0.5 6.25 1000000 32000 true
      { forceAdaptiveThinking := true }
      #[{ level := .level .xhigh, mapped := some "max" }]
      #["text", "image"]
   , githubCopilotModel "claude-opus-4.7" "Claude Opus 4.7" "anthropic-messages" 5 25 0.5 6.25 200000 32000 true
      { forceAdaptiveThinking := true, supportsTemperature := false }
      #[{ level := .level .minimal, mapped := some "low" }, { level := .level .xhigh, mapped := some "xhigh" }]
      #["text", "image"]
   , githubCopilotModel "claude-opus-4.8" "Claude Opus 4.8" "anthropic-messages" 5 25 0.5 6.25 200000 64000 true
      { forceAdaptiveThinking := true, supportsTemperature := false }
      #[{ level := .level .minimal, mapped := some "low" }, { level := .level .xhigh, mapped := some "xhigh" }]
      #["text", "image"]
   , githubCopilotModel "claude-sonnet-4" "Claude Sonnet 4 (latest)" "anthropic-messages" 3 15 0.3 3.75 216000 16000 true
      { supportsEagerToolInputStreaming := false } #[] #["text", "image"]
   , githubCopilotModel "claude-sonnet-4.5" "Claude Sonnet 4.5 (latest)" "anthropic-messages" 3 15 0.3 3.75 200000 32000 true
      { supportsEagerToolInputStreaming := false } #[] #["text", "image"]
   , githubCopilotModel "claude-sonnet-4.6" "Claude Sonnet 4.6" "anthropic-messages" 3 15 0.3 3.75 1000000 32000 true
      { forceAdaptiveThinking := true }
      #[{ level := .level .minimal, mapped := some "low" }, { level := .level .xhigh, mapped := some "max" }]
      #["text", "image"]
   , githubCopilotModel "gemini-2.5-pro" "Gemini 2.5 Pro" "openai-completions" 1.25 10 0.125 0 128000 64000 true
      { supportsStore := false, supportsDeveloperRole := false, supportsReasoningEffort := false } #[] #["text", "image"]
   , githubCopilotModel "gemini-3-flash-preview" "Gemini 3 Flash Preview" "openai-completions" 0.5 3 0.05 0 128000 64000 true
      { supportsStore := false, supportsDeveloperRole := false, supportsReasoningEffort := false } #[] #["text", "image"]
   , githubCopilotModel "gemini-3.1-pro-preview" "Gemini 3.1 Pro Preview" "openai-completions" 2 12 0.2 0 200000 64000 true
      { supportsStore := false, supportsDeveloperRole := false, supportsReasoningEffort := false } #[] #["text", "image"]
   , githubCopilotModel "gemini-3.5-flash" "Gemini 3.5 Flash" "openai-completions" 1.5 9 0.15 0 200000 64000 true
      { supportsStore := false, supportsDeveloperRole := false, supportsReasoningEffort := false } #[] #["text", "image"]
   , githubCopilotModel "gpt-4.1" "GPT-4.1" "openai-completions" 2 8 0.5 0 128000 16384 false
      { supportsStore := false, supportsDeveloperRole := false, supportsReasoningEffort := false } #[] #["text", "image"]
   , githubCopilotModel "gpt-5-mini" "GPT-5 Mini" "openai-responses" 0.25 2 0.025 0 264000 64000 true
      {}
      #[{ level := .off, mapped := none }, { level := .level .minimal, mapped := some "low" }]
      #["text", "image"]
   , githubCopilotModel "gpt-5.2" "GPT-5.2" "openai-responses" 1.75 14 0.175 0 400000 128000 true
      {}
      #[ { level := .off, mapped := none }
       , { level := .level .minimal, mapped := some "low" }
       , { level := .level .xhigh, mapped := some "xhigh" }
       ]
      #["text", "image"]
   , githubCopilotModel "gpt-5.2-codex" "GPT-5.2 Codex" "openai-responses" 1.75 14 0.175 0 400000 128000 true
      {}
      #[ { level := .off, mapped := none }
       , { level := .level .minimal, mapped := some "low" }
       , { level := .level .xhigh, mapped := some "xhigh" }
       ]
      #["text", "image"]
   , githubCopilotModel "gpt-5.3-codex" "GPT-5.3 Codex" "openai-responses" 1.75 14 0.175 0 400000 128000 true
      {}
      #[ { level := .off, mapped := none }
       , { level := .level .minimal, mapped := some "low" }
       , { level := .level .xhigh, mapped := some "xhigh" }
       ]
      #["text", "image"]
   , githubCopilotModel "gpt-5.4" "GPT-5.4" "openai-responses" 2.5 15 0.25 0 400000 128000 true
      {}
      #[ { level := .off, mapped := none }
       , { level := .level .minimal, mapped := some "low" }
       , { level := .level .xhigh, mapped := some "xhigh" }
       ]
      #["text", "image"]
   , githubCopilotModel "gpt-5.4-mini" "GPT-5.4 mini" "openai-responses" 0.75 4.5 0.075 0 400000 128000 true
      {}
      #[ { level := .off, mapped := none }
       , { level := .level .minimal, mapped := some "low" }
       , { level := .level .xhigh, mapped := some "xhigh" }
       ]
      #["text", "image"]
   , githubCopilotModel "gpt-5.4-nano" "GPT-5.4 nano" "openai-responses" 0.2 1.25 0.02 0 400000 128000 true
      {}
      #[ { level := .off, mapped := none }
       , { level := .level .minimal, mapped := some "low" }
       , { level := .level .xhigh, mapped := some "xhigh" }
       ]
      #["text", "image"]
   , githubCopilotModel "gpt-5.5" "GPT-5.5" "openai-responses" 5 30 0.5 0 400000 128000 true
      {}
      #[ { level := .off, mapped := none }
       , { level := .level .minimal, mapped := some "low" }
       , { level := .level .xhigh, mapped := some "xhigh" }
       ]
      #["text", "image"]
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
    supportsReasoningEffort := false
    maxTokensField := "max_tokens"
    thinkingFormat := some "openai"
    supportsStrictMode := false
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
    supportsReasoningEffort := false
    maxTokensField := "max_tokens"
    thinkingFormat := some "ant-ling"
    supportsLongCacheRetention := false
  }

def huggingFaceCompat : ModelCompat :=
  { supportsDeveloperRole := false
  }

def moonshotAICompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    supportsReasoningEffort := false
    maxTokensField := "max_tokens"
    thinkingFormat := some "deepseek"
    supportsStrictMode := false
  }

def nvidiaCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    supportsReasoningEffort := false
    maxTokensField := "max_tokens"
    supportsStrictMode := false
    supportsLongCacheRetention := false
  }

def nvidiaModelHeaders : LeanAgent.AI.Auth.ProviderHeaders :=
  #[("NVCF-POLL-SECONDS", "3600")]

def xiaomiCompat : ModelCompat :=
  { supportsDeveloperRole := false
    requiresReasoningContentOnAssistantMessages := true
    thinkingFormat := some "deepseek"
  }

def zaiCompat : ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    supportsReasoningEffort := false
    thinkingFormat := some "zai"
    zaiToolStream := true
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
   , catalogOpenAICompatibleModel zaiProviderId zaiBaseUrl "glm-5.2" "GLM-5.2" 0.0 0.0 0.0 0.0 1000000 131072 true { zaiCompat with supportsReasoningEffort := true } #[ { level := .level .minimal, mapped := none }
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
   , catalogOpenAICompatibleModel zaiCodingCNProviderId zaiCodingCNBaseUrl "glm-5.2" "GLM-5.2" 0.0 0.0 0.0 0.0 1000000 131072 true { zaiCompat with supportsReasoningEffort := true } #[ { level := .level .minimal, mapped := none }
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
deriving BEq

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

def githubCopilotProviderInfo : ProviderInfo :=
  { id := githubCopilotProviderId
    name := "GitHub Copilot"
    baseUrl := githubCopilotBaseUrl
    headers := githubCopilotHeaders
    apiKeyEnv := githubCopilotApiKeyEnv
    defaultModel := githubCopilotDefaultModel
    models := githubCopilotModels
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
deriving BEq

def defaultCatalog : ProviderCatalog :=
  { providers :=
    #[ deepSeekProviderInfo
     , openAIProviderInfo
     , openAICodexProviderInfo
     , githubCopilotProviderInfo
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
