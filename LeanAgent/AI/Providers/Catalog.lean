import LeanAgent.AI.Auth.OAuthBridge
import LeanAgent.AI.Api.AnthropicMessages
import LeanAgent.AI.Api.BedrockConverseStream
import LeanAgent.AI.Api.GoogleGenerativeAI
import LeanAgent.AI.Api.GoogleVertex
import LeanAgent.AI.Api.MistralConversations
import LeanAgent.AI.Api.OpenAICodexResponses
import LeanAgent.AI.Providers.Streams
import LeanAgent.Models

namespace LeanAgent.AI.Providers.Catalog

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
    resolve := fun _model ctx credential => do
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
          match ← ctx.env LeanAgent.Models.googleVertexApiKeyEnv with
          | some key =>
              pure (some
                { auth := { apiKey := some key }
                  env := credentialEnv
                  source := some LeanAgent.Models.googleVertexApiKeyEnv
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
  LeanAgent.AI.Auth.OAuthBridge.oauthAuthForRegisteredProvider
    LeanAgent.Models.openAICodexProviderId
    "OpenAI (ChatGPT Plus/Pro)"

def anthropicOAuthAuth : LeanAgent.AI.Auth.OAuthAuth :=
  LeanAgent.AI.Auth.OAuthBridge.oauthAuthForRegisteredProvider
    LeanAgent.Models.anthropicProviderId
    "Anthropic (Claude Pro/Max)"

def githubCopilotOAuthAuth : LeanAgent.AI.Auth.OAuthAuth :=
  LeanAgent.AI.Auth.OAuthBridge.oauthAuthForRegisteredProvider
    LeanAgent.Models.githubCopilotProviderId
    "GitHub Copilot"

def amazonBedrockAmbientAuthSource?
    (ctx : LeanAgent.AI.Auth.AuthContext) :
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
    resolve := fun _model ctx credential => do
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

def authForProviderInfo (info : LeanAgent.Models.ProviderInfo) : LeanAgent.AI.Auth.ProviderAuth :=
  if info.id == LeanAgent.Models.googleVertexProviderId then
    { apiKey := some googleVertexApiKeyAuth }
  else if info.id == LeanAgent.Models.openAICodexProviderId then
    { oauth := some openAICodexOAuthAuth }
  else if info.id == LeanAgent.Models.githubCopilotProviderId then
    { apiKey :=
        some
          (LeanAgent.AI.Auth.envApiKeyAuth
            "GitHub Copilot token"
            #[LeanAgent.Models.githubCopilotApiKeyEnv])
      oauth := some githubCopilotOAuthAuth
    }
  else if info.id == LeanAgent.Models.anthropicProviderId then
    { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth (info.name ++ " API key") info.authEnvs)
      oauth := some anthropicOAuthAuth
    }
  else if info.id == LeanAgent.Models.amazonBedrockProviderId then
    { apiKey := some amazonBedrockApiKeyAuth }
  else
    { apiKey := some (LeanAgent.AI.Auth.envApiKeyAuth (info.name ++ " API key") info.authEnvs) }

def createCatalogProvider (info : LeanAgent.Models.ProviderInfo) : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createProvider
    { id := info.id
      name := some info.name
      baseUrl := some info.baseUrl
      headers := info.headers
      auth := authForProviderInfo info
      models := info.models
      apis :=
        #[ { api := "openai-completions", streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }
         , { api := "openai-responses", streams := LeanAgent.AI.Providers.Streams.openAIResponsesStreams }
         , { api := LeanAgent.AI.Api.OpenAICodexResponses.api
             , streams := LeanAgent.AI.Providers.Streams.openAICodexResponsesStreams
             }
         , { api := LeanAgent.AI.Api.AnthropicMessages.api
             , streams := LeanAgent.AI.Providers.Streams.anthropicMessagesStreams
             }
         , { api := LeanAgent.AI.Api.GoogleGenerativeAI.api
             , streams := LeanAgent.AI.Providers.Streams.googleGenerativeAIStreams
             }
         , { api := LeanAgent.AI.Api.GoogleVertex.api
             , streams := LeanAgent.AI.Providers.Streams.googleVertexStreams
             }
         , { api := LeanAgent.AI.Api.MistralConversations.api
             , streams := LeanAgent.AI.Providers.Streams.mistralConversationsStreams
             }
         , { api := LeanAgent.AI.Api.BedrockConverseStream.api
             , streams := LeanAgent.AI.Providers.Streams.bedrockConverseStreamStreams
             }
         ]
    }

end LeanAgent.AI.Providers.Catalog
