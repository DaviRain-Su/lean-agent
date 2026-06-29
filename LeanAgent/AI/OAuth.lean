import LeanAgent.AI.Auth

namespace LeanAgent.AI.OAuth

abbrev OAuthCredentials := LeanAgent.AI.Auth.OAuthCredential
abbrev OAuthProviderId := String

structure OAuthPrompt where
  message : String
  placeholder : Option String := none
  allowEmpty : Bool := false
deriving BEq

structure OAuthAuthInfo where
  url : String
  instructions : Option String := none
deriving BEq

structure OAuthDeviceCodeInfo where
  userCode : String
  verificationUri : String
  intervalSeconds : Option Nat := none
  expiresInSeconds : Option Nat := none
deriving BEq

structure OAuthSelectOption where
  id : String
  label : String
deriving BEq

structure OAuthSelectPrompt where
  message : String
  options : Array OAuthSelectOption
deriving BEq

structure OAuthLoginCallbacks where
  onAuth : OAuthAuthInfo → IO Unit
  onDeviceCode : OAuthDeviceCodeInfo → IO Unit
  onPrompt : OAuthPrompt → IO String
  onProgress : Option (String → IO Unit) := none
  onManualCodeInput : Option (IO String) := none
  onSelect : OAuthSelectPrompt → IO (Option String)

structure OAuthProviderInterface where
  id : OAuthProviderId
  name : String
  login : OAuthLoginCallbacks → IO OAuthCredentials
  usesCallbackServer : Bool := false
  refreshToken : OAuthCredentials → IO OAuthCredentials
  getApiKey : OAuthCredentials → String

structure OAuthProviderInfo where
  id : OAuthProviderId
  name : String
  available : Bool := true
deriving BEq

structure OAuthApiKeyResult where
  newCredentials : OAuthCredentials
  apiKey : String
deriving BEq

structure RegisteredOAuthProvider where
  provider : OAuthProviderInterface

initialize oauthProviderRegistry : IO.Ref (Array RegisteredOAuthProvider) ← IO.mkRef #[]
initialize builtInOAuthProviders : IO.Ref (Array OAuthProviderInterface) ← IO.mkRef #[]

def providerById? (providers : Array RegisteredOAuthProvider) (id : OAuthProviderId) :
    Option OAuthProviderInterface :=
  providers.findSome? fun entry =>
    if entry.provider.id == id then some entry.provider else none

def builtInProviderById? (providers : Array OAuthProviderInterface) (id : OAuthProviderId) :
    Option OAuthProviderInterface :=
  providers.findSome? fun provider =>
    if provider.id == id then some provider else none

def registerOAuthProvider (provider : OAuthProviderInterface) : IO Unit :=
  oauthProviderRegistry.modify fun providers =>
    (providers.filter fun entry => entry.provider.id != provider.id).push { provider := provider }

def registerBuiltInOAuthProvider (provider : OAuthProviderInterface) : IO Unit := do
  builtInOAuthProviders.modify fun providers =>
    (providers.filter fun entry => entry.id != provider.id).push provider
  registerOAuthProvider provider

def getOAuthProvider? (id : OAuthProviderId) : IO (Option OAuthProviderInterface) := do
  pure (providerById? (← oauthProviderRegistry.get) id)

def getOAuthProviders : IO (Array OAuthProviderInterface) := do
  let providers ← oauthProviderRegistry.get
  pure (providers.map (fun entry => entry.provider))

def unregisterOAuthProvider (id : OAuthProviderId) : IO Unit := do
  match builtInProviderById? (← builtInOAuthProviders.get) id with
  | some provider => registerOAuthProvider provider
  | none =>
      oauthProviderRegistry.modify fun providers =>
        providers.filter fun entry => entry.provider.id != id

def resetOAuthProviders : IO Unit := do
  oauthProviderRegistry.set #[]
  for provider in (← builtInOAuthProviders.get) do
    registerOAuthProvider provider

def getOAuthProviderInfoList : IO (Array OAuthProviderInfo) := do
  let providers ← getOAuthProviders
  pure (providers.map fun provider =>
    { id := provider.id, name := provider.name, available := true })

def refreshOAuthToken
    (providerId : OAuthProviderId)
    (credentials : OAuthCredentials) : IO OAuthCredentials := do
  match ← getOAuthProvider? providerId with
  | some provider => provider.refreshToken credentials
  | none => throw (IO.userError s!"Unknown OAuth provider: {providerId}")

def credentialForProvider?
    (providerId : OAuthProviderId)
    (credentials : Array (OAuthProviderId × OAuthCredentials)) :
    Option OAuthCredentials :=
  credentials.findSome? fun (id, credential) =>
    if id == providerId then some credential else none

def getOAuthApiKey
    (providerId : OAuthProviderId)
    (credentials : Array (OAuthProviderId × OAuthCredentials))
    (nowMs : IO Nat := LeanAgent.AI.Auth.epochMsNow) :
    IO (Option OAuthApiKeyResult) := do
  match ← getOAuthProvider? providerId with
  | none => throw (IO.userError s!"Unknown OAuth provider: {providerId}")
  | some provider =>
      match credentialForProvider? providerId credentials with
      | none => pure none
      | some credential =>
          let now ← nowMs
          let credential ←
            if now >= credential.expires then
              try
                provider.refreshToken credential
              catch _ =>
                throw (IO.userError s!"Failed to refresh OAuth token for {providerId}")
            else
              pure credential
          pure (some { newCredentials := credential, apiKey := provider.getApiKey credential })

end LeanAgent.AI.OAuth
