import LeanAgent.AI.Api.Cloudflare
import LeanAgent.AI.Providers.CloudflareAuth
import LeanAgent.AI.Providers.Streams
import LeanAgent.Models

namespace LeanAgent.AI.Providers.CloudflareWorkersAI

def providerId : String := "cloudflare-workers-ai"
def providerName : String := "Cloudflare Workers AI"

def workersAICompat : LeanAgent.Models.ModelCompat :=
  { supportsStore := false
    supportsDeveloperRole := false
    supportsLongCacheRetention := false
    sendSessionAffinityHeaders := true
  }

def google_gemma_4_26b_a4b_it : LeanAgent.Models.ModelInfo :=
  { id := "@cf/google/gemma-4-26b-a4b-it"
    name := "Gemma 4 26B A4B IT"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.1 0.3 0.0 0.0
    contextWindow := 256000
    maxTokens := 16384
  }

def ibm_granite_granite_4p0_h_micro : LeanAgent.Models.ModelInfo :=
  { id := "@cf/ibm-granite/granite-4.0-h-micro"
    name := "Granite 4.0 H Micro"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    input := #["text"]
    cost := LeanAgent.Models.cost 0.017 0.112 0.0 0.0
    contextWindow := 131000
    maxTokens := 131000
  }

def meta_llama_3p3_70b_instruct_fp8_fast : LeanAgent.Models.ModelInfo :=
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

def meta_llama_4_scout_17b_16e_instruct : LeanAgent.Models.ModelInfo :=
  { id := "@cf/meta/llama-4-scout-17b-16e-instruct"
    name := "Llama 4 Scout 17B 16E Instruct"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.27 0.85 0.0 0.0
    contextWindow := 131000
    maxTokens := 16384
  }

def mistralai_mistral_small_3p1_24b_instruct : LeanAgent.Models.ModelInfo :=
  { id := "@cf/mistralai/mistral-small-3.1-24b-instruct"
    name := "Mistral Small 3.1 24B Instruct"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    input := #["text"]
    cost := LeanAgent.Models.cost 0.351 0.555 0.0 0.0
    contextWindow := 128000
    maxTokens := 128000
  }

def moonshotai_kimi_k2p6 : LeanAgent.Models.ModelInfo :=
  { id := "@cf/moonshotai/kimi-k2.6"
    name := "Kimi K2.6"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.95 4.0 0.16 0.0
    contextWindow := 262144
    maxTokens := 256000
  }

def moonshotai_kimi_k2p7_code : LeanAgent.Models.ModelInfo :=
  { id := "@cf/moonshotai/kimi-k2.7-code"
    name := "Kimi K2.7 Code"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.95 4.0 0.19 0.0
    contextWindow := 262144
    maxTokens := 262144
  }

def nvidia_nemotron_3_120b_a12b : LeanAgent.Models.ModelInfo :=
  { id := "@cf/nvidia/nemotron-3-120b-a12b"
    name := "Nemotron 3 Super 120B"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 0.5 1.5 0.0 0.0
    contextWindow := 256000
    maxTokens := 256000
  }

def openai_gpt_oss_120b : LeanAgent.Models.ModelInfo :=
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

def openai_gpt_oss_20b : LeanAgent.Models.ModelInfo :=
  { id := "@cf/openai/gpt-oss-20b"
    name := "GPT OSS 20B"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 0.2 0.3 0.0 0.0
    contextWindow := 128000
    maxTokens := 16384
  }

def qwen_qwen3_30b_a3b_fp8 : LeanAgent.Models.ModelInfo :=
  { id := "@cf/qwen/qwen3-30b-a3b-fp8"
    name := "Qwen3 30B A3b fp8"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 0.0509 0.335 0.0 0.0
    contextWindow := 32768
    maxTokens := 32768
  }

def zai_org_glm_4p7_flash : LeanAgent.Models.ModelInfo :=
  { id := "@cf/zai-org/glm-4.7-flash"
    name := "GLM-4.7-Flash"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 0.0605 0.4 0.0 0.0
    contextWindow := 131072
    maxTokens := 131072
  }

def zai_org_glm_5p2 : LeanAgent.Models.ModelInfo :=
  { id := "@cf/zai-org/glm-5.2"
    name := "Glm 5.2"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.workersAIBaseUrl
    compat := workersAICompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 1.4 4.4 0.26 0.0
    contextWindow := 262144
    maxTokens := 262144
  }

def models : Array LeanAgent.Models.ModelInfo :=
  #[google_gemma_4_26b_a4b_it, ibm_granite_granite_4p0_h_micro, meta_llama_3p3_70b_instruct_fp8_fast, meta_llama_4_scout_17b_16e_instruct, mistralai_mistral_small_3p1_24b_instruct, moonshotai_kimi_k2p6, moonshotai_kimi_k2p7_code, nvidia_nemotron_3_120b_a12b, openai_gpt_oss_120b, openai_gpt_oss_20b, qwen_qwen3_30b_a3b_fp8, zai_org_glm_4p7_flash, zai_org_glm_5p2]

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createProvider
    { id := providerId
      name := some providerName
      auth := { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareWorkersAIAuth }
      models := models
      apis := #[{ api := "openai-completions", streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }]
    }

end LeanAgent.AI.Providers.CloudflareWorkersAI
