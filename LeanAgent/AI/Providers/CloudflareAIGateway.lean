import LeanAgent.AI.Api.Cloudflare
import LeanAgent.AI.Providers.CloudflareAuth
import LeanAgent.AI.Providers.Streams
import LeanAgent.Models

namespace LeanAgent.AI.Providers.CloudflareAIGateway

def providerId : String := "cloudflare-ai-gateway"
def providerName : String := "Cloudflare AI Gateway"

def gatewayCompat : LeanAgent.Models.ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    supportsLongCacheRetention := false
    sendSessionAffinityHeaders := true
  }

def gpt4oMini : LeanAgent.Models.ModelInfo :=
  { id := "gpt-4o-mini"
    name := "GPT-4o mini"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.15 0.6 0.08 0.0
    contextWindow := 128000
    maxTokens := 16384
  }

def gpt51 : LeanAgent.Models.ModelInfo :=
  { id := "gpt-5.1"
    name := "GPT-5.1"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 1.25 10.0 0.13 0.0
    contextWindow := 400000
    maxTokens := 128000
  }

def workersAIKimiK26 : LeanAgent.Models.ModelInfo :=
  { id := "workers-ai/@cf/moonshotai/kimi-k2.6"
    name := "Kimi K2.6"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayCompatBaseUrl
    compat := gatewayCompat
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.95 4.0 0.16 0.0
    contextWindow := 256000
    maxTokens := 256000
  }

def models : Array LeanAgent.Models.ModelInfo :=
  #[gpt4oMini, gpt51, workersAIKimiK26]

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createProvider
    { id := providerId
      name := some providerName
      auth := { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareAIGatewayAuth }
      models := models
      apis :=
        #[ { api := "openai-completions", streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }
         , { api := "openai-responses", streams := LeanAgent.AI.Providers.Streams.openAIResponsesStreams }
         ]
    }

end LeanAgent.AI.Providers.CloudflareAIGateway
