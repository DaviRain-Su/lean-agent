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

def gw_claude_3_5_haiku : LeanAgent.Models.ModelInfo :=
  { id := "claude-3-5-haiku"
    name := "Claude Haiku 3.5 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.8 4.0 0.08 1.0
    contextWindow := 200000
    maxTokens := 8192
  }

def gw_claude_3_haiku : LeanAgent.Models.ModelInfo :=
  { id := "claude-3-haiku"
    name := "Claude Haiku 3"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.25 1.25 0.03 0.3
    contextWindow := 200000
    maxTokens := 4096
  }

def gw_claude_3_opus : LeanAgent.Models.ModelInfo :=
  { id := "claude-3-opus"
    name := "Claude Opus 3"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 15.0 75.0 1.5 18.75
    contextWindow := 200000
    maxTokens := 4096
  }

def gw_claude_3_sonnet : LeanAgent.Models.ModelInfo :=
  { id := "claude-3-sonnet"
    name := "Claude Sonnet 3"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 3.0 15.0 0.3 0.3
    contextWindow := 200000
    maxTokens := 4096
  }

def gw_claude_3p5_haiku : LeanAgent.Models.ModelInfo :=
  { id := "claude-3.5-haiku"
    name := "Claude Haiku 3.5 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.8 4.0 0.08 1.0
    contextWindow := 200000
    maxTokens := 8192
  }

def gw_claude_3p5_sonnet : LeanAgent.Models.ModelInfo :=
  { id := "claude-3.5-sonnet"
    name := "Claude Sonnet 3.5 v2"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 3.0 15.0 0.3 3.75
    contextWindow := 200000
    maxTokens := 8192
  }

def gw_claude_fable_5 : LeanAgent.Models.ModelInfo :=
  { id := "claude-fable-5"
    name := "Claude Fable 5"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 10.0 50.0 1.0 12.5
    contextWindow := 1000000
    maxTokens := 128000
  }

def gw_claude_haiku_4_5 : LeanAgent.Models.ModelInfo :=
  { id := "claude-haiku-4-5"
    name := "Claude Haiku 4.5 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 1.0 5.0 0.1 1.25
    contextWindow := 200000
    maxTokens := 64000
  }

def gw_claude_opus_4 : LeanAgent.Models.ModelInfo :=
  { id := "claude-opus-4"
    name := "Claude Opus 4 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 15.0 75.0 1.5 18.75
    contextWindow := 200000
    maxTokens := 32000
  }

def gw_claude_opus_4_1 : LeanAgent.Models.ModelInfo :=
  { id := "claude-opus-4-1"
    name := "Claude Opus 4.1 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 15.0 75.0 1.5 18.75
    contextWindow := 200000
    maxTokens := 32000
  }

def gw_claude_opus_4_5 : LeanAgent.Models.ModelInfo :=
  { id := "claude-opus-4-5"
    name := "Claude Opus 4.5 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 5.0 25.0 0.5 6.25
    contextWindow := 200000
    maxTokens := 64000
  }

def gw_claude_opus_4_6 : LeanAgent.Models.ModelInfo :=
  { id := "claude-opus-4-6"
    name := "Claude Opus 4.6 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "max" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 5.0 25.0 0.5 6.25
    contextWindow := 1000000
    maxTokens := 128000
  }

def gw_claude_opus_4_7 : LeanAgent.Models.ModelInfo :=
  { id := "claude-opus-4-7"
    name := "Claude Opus 4.7"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 5.0 25.0 0.5 6.25
    contextWindow := 1000000
    maxTokens := 128000
  }

def gw_claude_opus_4_8 : LeanAgent.Models.ModelInfo :=
  { id := "claude-opus-4-8"
    name := "Claude Opus 4.8"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 5.0 25.0 0.5 6.25
    contextWindow := 1000000
    maxTokens := 128000
  }

def gw_claude_sonnet_4 : LeanAgent.Models.ModelInfo :=
  { id := "claude-sonnet-4"
    name := "Claude Sonnet 4 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 3.0 15.0 0.3 3.75
    contextWindow := 200000
    maxTokens := 64000
  }

def gw_claude_sonnet_4_5 : LeanAgent.Models.ModelInfo :=
  { id := "claude-sonnet-4-5"
    name := "Claude Sonnet 4.5 (latest)"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 3.0 15.0 0.3 3.75
    contextWindow := 200000
    maxTokens := 64000
  }

def gw_claude_sonnet_4_6 : LeanAgent.Models.ModelInfo :=
  { id := "claude-sonnet-4-6"
    name := "Claude Sonnet 4.6"
    provider := providerId
    api := "anthropic-messages"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayAnthropicBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 3.0 15.0 0.3 3.75
    contextWindow := 1000000
    maxTokens := 64000
  }

def gw_gpt_4 : LeanAgent.Models.ModelInfo :=
  { id := "gpt-4"
    name := "GPT-4"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    input := #["text"]
    cost := LeanAgent.Models.cost 30.0 60.0 0.0 0.0
    contextWindow := 8192
    maxTokens := 8192
  }

def gw_gpt_4_turbo : LeanAgent.Models.ModelInfo :=
  { id := "gpt-4-turbo"
    name := "GPT-4 Turbo"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 10.0 30.0 0.0 0.0
    contextWindow := 128000
    maxTokens := 4096
  }

def gw_gpt_4o : LeanAgent.Models.ModelInfo :=
  { id := "gpt-4o"
    name := "GPT-4o"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 2.5 10.0 1.25 0.0
    contextWindow := 128000
    maxTokens := 16384
  }

def gw_gpt_4o_mini : LeanAgent.Models.ModelInfo :=
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

def gw_gpt_5p1 : LeanAgent.Models.ModelInfo :=
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

def gw_gpt_5p1_codex : LeanAgent.Models.ModelInfo :=
  { id := "gpt-5.1-codex"
    name := "GPT-5.1 Codex"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 1.25 10.0 0.125 0.0
    contextWindow := 400000
    maxTokens := 128000
  }

def gw_gpt_5p2 : LeanAgent.Models.ModelInfo :=
  { id := "gpt-5.2"
    name := "GPT-5.2"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 1.75 14.0 0.175 0.0
    contextWindow := 400000
    maxTokens := 128000
  }

def gw_gpt_5p2_codex : LeanAgent.Models.ModelInfo :=
  { id := "gpt-5.2-codex"
    name := "GPT-5.2 Codex"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 1.75 14.0 0.175 0.0
    contextWindow := 400000
    maxTokens := 128000
  }

def gw_gpt_5p3_codex : LeanAgent.Models.ModelInfo :=
  { id := "gpt-5.3-codex"
    name := "GPT-5.3 Codex"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 1.75 14.0 0.175 0.0
    contextWindow := 400000
    maxTokens := 128000
  }

def gw_gpt_5p4 : LeanAgent.Models.ModelInfo :=
  { id := "gpt-5.4"
    name := "GPT-5.4"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 2.5 15.0 0.25 0.0
    contextWindow := 1050000
    maxTokens := 128000
  }

def gw_gpt_5p5 : LeanAgent.Models.ModelInfo :=
  { id := "gpt-5.5"
    name := "GPT-5.5"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    thinkingLevelMap := #[{ level := .off, mapped := none }, { level := .level .xhigh, mapped := some "xhigh" }]
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 5.0 30.0 0.5 0.0
    contextWindow := 1050000
    maxTokens := 128000
  }

def gw_o1 : LeanAgent.Models.ModelInfo :=
  { id := "o1"
    name := "o1"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 15.0 60.0 7.5 0.0
    contextWindow := 200000
    maxTokens := 100000
  }

def gw_o3 : LeanAgent.Models.ModelInfo :=
  { id := "o3"
    name := "o3"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 2.0 8.0 0.5 0.0
    contextWindow := 200000
    maxTokens := 100000
  }

def gw_o3_mini : LeanAgent.Models.ModelInfo :=
  { id := "o3-mini"
    name := "o3-mini"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 1.1 4.4 0.55 0.0
    contextWindow := 200000
    maxTokens := 100000
  }

def gw_o3_pro : LeanAgent.Models.ModelInfo :=
  { id := "o3-pro"
    name := "o3-pro"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 20.0 80.0 0.0 0.0
    contextWindow := 200000
    maxTokens := 100000
  }

def gw_o4_mini : LeanAgent.Models.ModelInfo :=
  { id := "o4-mini"
    name := "o4-mini"
    provider := providerId
    api := "openai-responses"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayOpenAIBaseUrl
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 1.1 4.4 0.28 0.0
    contextWindow := 200000
    maxTokens := 100000
  }

def gw_workers_ai_cf_moonshotai_kimi_k2p5 : LeanAgent.Models.ModelInfo :=
  { id := "workers-ai/@cf/moonshotai/kimi-k2.5"
    name := "Kimi K2.5"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayCompatBaseUrl
    compat := gatewayCompat
    reasoning := true
    input := #["text", "image"]
    cost := LeanAgent.Models.cost 0.6 3.0 0.1 0.0
    contextWindow := 256000
    maxTokens := 256000
  }

def gw_workers_ai_cf_moonshotai_kimi_k2p6 : LeanAgent.Models.ModelInfo :=
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

def gw_workers_ai_cf_nvidia_nemotron_3_120b_a12b : LeanAgent.Models.ModelInfo :=
  { id := "workers-ai/@cf/nvidia/nemotron-3-120b-a12b"
    name := "Nemotron 3 Super 120B"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayCompatBaseUrl
    compat := gatewayCompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 0.5 1.5 0.0 0.0
    contextWindow := 256000
    maxTokens := 256000
  }

def gw_workers_ai_cf_zai_org_glm_4p7_flash : LeanAgent.Models.ModelInfo :=
  { id := "workers-ai/@cf/zai-org/glm-4.7-flash"
    name := "GLM-4.7-Flash"
    provider := providerId
    api := "openai-completions"
    baseUrl := LeanAgent.AI.Api.Cloudflare.aiGatewayCompatBaseUrl
    compat := gatewayCompat
    reasoning := true
    input := #["text"]
    cost := LeanAgent.Models.cost 0.06 0.4 0.0 0.0
    contextWindow := 131072
    maxTokens := 131072
  }


/-- Legacy aliases kept for existing tests/call sites. -/
def workersAIKimiK26 : LeanAgent.Models.ModelInfo := gw_workers_ai_cf_moonshotai_kimi_k2p6
def gpt4oMini : LeanAgent.Models.ModelInfo := gw_gpt_4o_mini
def gpt51 : LeanAgent.Models.ModelInfo := gw_gpt_5p1

def models : Array LeanAgent.Models.ModelInfo :=
  #[gw_claude_3_5_haiku, gw_claude_3_haiku, gw_claude_3_opus, gw_claude_3_sonnet, gw_claude_3p5_haiku, gw_claude_3p5_sonnet, gw_claude_fable_5, gw_claude_haiku_4_5, gw_claude_opus_4, gw_claude_opus_4_1, gw_claude_opus_4_5, gw_claude_opus_4_6, gw_claude_opus_4_7, gw_claude_opus_4_8, gw_claude_sonnet_4, gw_claude_sonnet_4_5, gw_claude_sonnet_4_6, gw_gpt_4, gw_gpt_4_turbo, gw_gpt_4o, gw_gpt_4o_mini, gw_gpt_5p1, gw_gpt_5p1_codex, gw_gpt_5p2, gw_gpt_5p2_codex, gw_gpt_5p3_codex, gw_gpt_5p4, gw_gpt_5p5, gw_o1, gw_o3, gw_o3_mini, gw_o3_pro, gw_o4_mini, gw_workers_ai_cf_moonshotai_kimi_k2p5, gw_workers_ai_cf_moonshotai_kimi_k2p6, gw_workers_ai_cf_nvidia_nemotron_3_120b_a12b, gw_workers_ai_cf_zai_org_glm_4p7_flash]

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createProvider
    { id := providerId
      name := some providerName
      auth := { apiKey := some LeanAgent.AI.Providers.CloudflareAuth.cloudflareAIGatewayAuth }
      models := models
      apis :=
        #[ { api := "openai-completions", streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }
         , { api := "openai-responses", streams := LeanAgent.AI.Providers.Streams.openAIResponsesStreams }
         , { api := "anthropic-messages", streams := LeanAgent.AI.Providers.Streams.anthropicMessagesStreams }
         ]
    }

end LeanAgent.AI.Providers.CloudflareAIGateway
