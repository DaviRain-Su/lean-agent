import LeanAgent.AI.Auth

namespace LeanAgent.AI.EnvApiKeys

def apiKeyEnvVars? : String → Option (Array String)
  | "github-copilot" => some #["COPILOT_GITHUB_TOKEN"]
  | "anthropic" => some #["ANTHROPIC_OAUTH_TOKEN", "ANTHROPIC_API_KEY"]
  | "ant-ling" => some #["ANT_LING_API_KEY"]
  | "openai" => some #["OPENAI_API_KEY"]
  | "azure-openai-responses" => some #["AZURE_OPENAI_API_KEY"]
  | "nvidia" => some #["NVIDIA_API_KEY"]
  | "deepseek" => some #["DEEPSEEK_API_KEY"]
  | "google" => some #["GEMINI_API_KEY"]
  | "google-vertex" => some #["GOOGLE_CLOUD_API_KEY"]
  | "groq" => some #["GROQ_API_KEY"]
  | "cerebras" => some #["CEREBRAS_API_KEY"]
  | "xai" => some #["XAI_API_KEY"]
  | "openrouter" => some #["OPENROUTER_API_KEY"]
  | "vercel-ai-gateway" => some #["AI_GATEWAY_API_KEY"]
  | "zai" => some #["ZAI_API_KEY"]
  | "zai-coding-cn" => some #["ZAI_CODING_CN_API_KEY"]
  | "mistral" => some #["MISTRAL_API_KEY"]
  | "minimax" => some #["MINIMAX_API_KEY"]
  | "minimax-cn" => some #["MINIMAX_CN_API_KEY"]
  | "moonshotai" => some #["MOONSHOT_API_KEY"]
  | "moonshotai-cn" => some #["MOONSHOT_API_KEY"]
  | "huggingface" => some #["HF_TOKEN"]
  | "fireworks" => some #["FIREWORKS_API_KEY"]
  | "together" => some #["TOGETHER_API_KEY"]
  | "opencode" => some #["OPENCODE_API_KEY"]
  | "opencode-go" => some #["OPENCODE_API_KEY"]
  | "kimi-coding" => some #["KIMI_API_KEY"]
  | "cloudflare-workers-ai" => some #["CLOUDFLARE_API_KEY"]
  | "cloudflare-ai-gateway" => some #["CLOUDFLARE_API_KEY"]
  | "xiaomi" => some #["XIAOMI_API_KEY"]
  | "xiaomi-token-plan-cn" => some #["XIAOMI_TOKEN_PLAN_CN_API_KEY"]
  | "xiaomi-token-plan-ams" => some #["XIAOMI_TOKEN_PLAN_AMS_API_KEY"]
  | "xiaomi-token-plan-sgp" => some #["XIAOMI_TOKEN_PLAN_SGP_API_KEY"]
  | _ => none

def envValue? (env : LeanAgent.AI.Auth.ProviderEnv) (name : String) : IO (Option String) := do
  match LeanAgent.AI.Auth.providerEnvGet? env name with
  | some value => pure (some value)
  | none =>
      match ← IO.getEnv name with
      | some value =>
          let trimmed := value.trimAscii.toString
          pure (if trimmed.isEmpty then none else some trimmed)
      | none => pure none

def findEnvKeys (provider : String) (env : LeanAgent.AI.Auth.ProviderEnv := #[]) :
    IO (Option (Array String)) := do
  match apiKeyEnvVars? provider with
  | none => pure none
  | some vars =>
      let mut found := #[]
      for var in vars do
        if (← envValue? env var).isSome then
          found := found.push var
      pure (if found.isEmpty then none else some found)

def hasBedrockAmbientCredentials (env : LeanAgent.AI.Auth.ProviderEnv) : IO Bool := do
  let profile ← envValue? env "AWS_PROFILE"
  let defaultProfile ← envValue? env "AWS_DEFAULT_PROFILE"
  let accessKey ← envValue? env "AWS_ACCESS_KEY_ID"
  let secretKey ← envValue? env "AWS_SECRET_ACCESS_KEY"
  let bearer ← envValue? env "AWS_BEARER_TOKEN_BEDROCK"
  let ecsRelative ← envValue? env "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
  let ecsFull ← envValue? env "AWS_CONTAINER_CREDENTIALS_FULL_URI"
  let webIdentity ← envValue? env "AWS_WEB_IDENTITY_TOKEN_FILE"
  pure
    (profile.isSome ||
      defaultProfile.isSome ||
      (accessKey.isSome && secretKey.isSome) ||
      bearer.isSome ||
      ecsRelative.isSome ||
      ecsFull.isSome ||
      webIdentity.isSome)

def hasVertexAmbientCredentials (env : LeanAgent.AI.Auth.ProviderEnv) : IO Bool := do
  let credentials ← envValue? env "GOOGLE_APPLICATION_CREDENTIALS"
  let credentialsOk ←
    match credentials with
    | some path =>
        let resolved ← LeanAgent.AI.Auth.expandHomePath path
        resolved.pathExists
    | none => do
        match ← IO.getEnv "HOME" with
        | some home =>
            let path := System.FilePath.mk home / ".config" / "gcloud" / "application_default_credentials.json"
            path.pathExists
        | none => pure false
  let project ←
    match ← envValue? env "GOOGLE_CLOUD_PROJECT" with
    | some value => pure (some value)
    | none => envValue? env "GCLOUD_PROJECT"
  let location ← envValue? env "GOOGLE_CLOUD_LOCATION"
  pure (credentialsOk && project.isSome && location.isSome)

def getEnvApiKey (provider : String) (env : LeanAgent.AI.Auth.ProviderEnv := #[]) :
    IO (Option String) := do
  match ← findEnvKeys provider env with
  | some keys =>
      match keys[0]? with
      | some key => envValue? env key
      | none => pure none
  | none =>
      if provider == "google-vertex" then
        if ← hasVertexAmbientCredentials env then pure (some "<authenticated>") else pure none
      else if provider == "amazon-bedrock" then
        if ← hasBedrockAmbientCredentials env then pure (some "<authenticated>") else pure none
      else
        pure none

end LeanAgent.AI.EnvApiKeys
