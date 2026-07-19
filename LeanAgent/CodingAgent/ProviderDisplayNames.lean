import Lean

/-!
# Provider display names (Pi `provider-display-names.ts`)
-/

namespace LeanAgent.CodingAgent.ProviderDisplayNames

/-- Pi `BUILT_IN_PROVIDER_DISPLAY_NAMES`. -/
def builtInProviderDisplayNames : List (String × String) :=
  [ ("anthropic", "Anthropic")
  , ("amazon-bedrock", "Amazon Bedrock")
  , ("ant-ling", "Ant Ling")
  , ("azure-openai-responses", "Azure OpenAI Responses")
  , ("cerebras", "Cerebras")
  , ("cloudflare-ai-gateway", "Cloudflare AI Gateway")
  , ("cloudflare-workers-ai", "Cloudflare Workers AI")
  , ("deepseek", "DeepSeek")
  , ("fireworks", "Fireworks")
  , ("google", "Google Gemini")
  , ("google-vertex", "Google Vertex AI")
  , ("groq", "Groq")
  , ("huggingface", "Hugging Face")
  , ("kimi-coding", "Kimi For Coding")
  , ("mistral", "Mistral")
  , ("minimax", "MiniMax")
  , ("minimax-cn", "MiniMax (China)")
  , ("moonshotai", "Moonshot AI")
  , ("moonshotai-cn", "Moonshot AI (China)")
  , ("nvidia", "NVIDIA NIM")
  , ("opencode", "OpenCode Zen")
  , ("opencode-go", "OpenCode Go")
  , ("openai", "OpenAI")
  , ("openrouter", "OpenRouter")
  , ("together", "Together AI")
  , ("vercel-ai-gateway", "Vercel AI Gateway")
  , ("xai", "xAI")
  , ("zai", "ZAI Coding Plan (Global)")
  , ("zai-coding-cn", "ZAI Coding Plan (China)")
  , ("xiaomi", "Xiaomi MiMo")
  , ("xiaomi-token-plan-cn", "Xiaomi MiMo Token Plan (China)")
  , ("xiaomi-token-plan-ams", "Xiaomi MiMo Token Plan (Amsterdam)")
  , ("xiaomi-token-plan-sgp", "Xiaomi MiMo Token Plan (Singapore)")
  ]

/-- Lookup display name; falls back to the raw provider id. -/
def getProviderDisplayName (providerId : String) : String :=
  match builtInProviderDisplayNames.find? (fun p => p.1 == providerId) with
  | some (_, name) => name
  | none => providerId

end LeanAgent.CodingAgent.ProviderDisplayNames
