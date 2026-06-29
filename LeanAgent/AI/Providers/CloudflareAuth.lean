import LeanAgent.AI.Api.Cloudflare
import LeanAgent.AI.Auth

namespace LeanAgent.AI.Providers.CloudflareAuth

def apiKeyEnv : String := "CLOUDFLARE_API_KEY"
def accountIdEnv : String := LeanAgent.AI.Api.Cloudflare.accountIdEnv
def gatewayIdEnv : String := LeanAgent.AI.Api.Cloudflare.gatewayIdEnv

inductive Kind where
  | workersAI
  | aiGateway
deriving BEq

def Kind.requiresGateway : Kind → Bool
  | .workersAI => false
  | .aiGateway => true

def resolveValue
    (name : String)
    (ctx : LeanAgent.AI.Auth.AuthContext)
    (credential : Option LeanAgent.AI.Auth.ApiKeyCredential) :
    IO (Option String) := do
  match credential with
  | some credential =>
      if name == apiKeyEnv then
        match credential.key with
        | some key =>
            let trimmed := key.trimAscii.toString
            pure (if trimmed.isEmpty then none else some trimmed)
        | none => pure none
      else
        pure (LeanAgent.AI.Auth.providerEnvGet? credential.env name)
  | none => ctx.env name

def replacePlaceholder (template name value : String) : String :=
  template.replace ("{" ++ name ++ "}") value

def resolveCloudflareBaseUrl (template accountId : String) (gatewayId : Option String := none) :
    String :=
  replacePlaceholder
    (replacePlaceholder template accountIdEnv accountId)
    gatewayIdEnv
    (gatewayId.getD "")

def resolvedEnv (accountId : String) (gatewayId : Option String) : LeanAgent.AI.Auth.ProviderEnv :=
  #[]
    |>.push (accountIdEnv, accountId)
    |> fun env =>
      match gatewayId with
      | some id => env.push (gatewayIdEnv, id)
      | none => env

def resolveCloudflareEnv
    (kind : Kind)
    (ctx : LeanAgent.AI.Auth.AuthContext)
    (credential : Option LeanAgent.AI.Auth.ApiKeyCredential)
    (modelBaseUrl : Option String) :
    IO (Option LeanAgent.AI.Auth.AuthResult) := do
  let apiKey? ← resolveValue apiKeyEnv ctx credential
  let accountId? ← resolveValue accountIdEnv ctx credential
  let gatewayId? ←
    if kind.requiresGateway then
      resolveValue gatewayIdEnv ctx credential
    else
      pure none
  match apiKey?, accountId? with
  | some apiKey, some accountId =>
      if kind.requiresGateway && gatewayId?.isNone then
        pure none
      else
        match modelBaseUrl with
        | none => pure none
        | some template =>
            let baseUrl := resolveCloudflareBaseUrl template accountId gatewayId?
            let env := resolvedEnv accountId gatewayId?
            let source :=
              match credential with
              | some _ => "stored credential"
              | none => apiKeyEnv
            let auth :=
              match kind with
              | .workersAI =>
                  { apiKey := some apiKey, baseUrl := some baseUrl }
              | .aiGateway =>
                  { apiKey := none
                    baseUrl := some baseUrl
                    headers :=
                      #[ ("cf-aig-authorization", "Bearer " ++ apiKey)
                       , ("Authorization", "")
                       , ("x-api-key", "")
                       ]
                  }
            pure (some { auth := auth, env := env, source := some source })
  | _, _ => pure none

def cloudflareWorkersAIAuth : LeanAgent.AI.Auth.ApiKeyAuth :=
  { name := "Cloudflare API key"
    resolve := fun ctx credential modelBaseUrl =>
      resolveCloudflareEnv .workersAI ctx credential modelBaseUrl
  }

def cloudflareAIGatewayAuth : LeanAgent.AI.Auth.ApiKeyAuth :=
  { name := "Cloudflare API key"
    resolve := fun ctx credential modelBaseUrl =>
      resolveCloudflareEnv .aiGateway ctx credential modelBaseUrl
  }

end LeanAgent.AI.Providers.CloudflareAuth
