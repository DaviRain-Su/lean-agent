import LeanAgent.AI.Api.Cloudflare
import LeanAgent.AI.Providers.CloudflareAuth
import LeanAgent.Models

namespace LeanAgent.AI.Providers.CloudflareWorkersAI

def providerId : String := "cloudflare-workers-ai"
def providerName : String := "Cloudflare Workers AI"

def workersAICompat : LeanAgent.Models.ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
  }

def gptOss120B : LeanAgent.Models.ModelInfo :=
  { id := "@cf/openai/gpt-oss-120b"
    name := "GPT OSS 120B"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 0.35 0.75 0.0 0.0
    contextWindow := 128000
    maxTokens := 16384
  }

def llama3370B : LeanAgent.Models.ModelInfo :=
  { id := "@cf/meta/llama-3.3-70b-instruct-fp8-fast"
    name := "Llama 3.3 70B Instruct fp8 Fast"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    input := #["text"]
    cost := LeanAgent.Models.cost 0.293 2.253 0.0 0.0
    contextWindow := 24000
    maxTokens := 24000
  }

def models : Array LeanAgent.Models.ModelInfo :=
  #[gptOss120B, llama3370B]

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createProvider
    { id := providerId
      name := some providerName
      auth := { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareWorkersAIAuth }
      models := models
      apis := #[{ api := "openai-completions", streams := LeanAgent.Models.openAICompatibleStreams }]
    }

end LeanAgent.AI.Providers.CloudflareWorkersAI
