import LeanAgent.AI.OAuth.Types

namespace LeanAgent.AI.OAuth

structure OAuthApiKeyResult where
  newCredentials : OAuthCredentials
  apiKey : String
deriving BEq

def cancelMessage : String := "Login cancelled"
def timeoutMessage : String := "Device flow timed out"
def slowDownTimeoutMessage : String :=
  "Device flow timed out after one or more slow_down responses. This is often caused by clock drift in WSL or VM environments. Please sync or restart the VM clock and try again."
def minimumIntervalMs : Nat := 1000
def defaultPollIntervalSeconds : Nat := 5
def slowDownIntervalIncrementMs : Nat := 5000

inductive OAuthDeviceCodePollResult (α : Type) where
  | pending
  | slowDown
  | failed (message : String)
  | complete (value : α)
deriving BEq

structure OAuthDeviceCodePollOptions (α : Type) where
  intervalSeconds : Option Nat := none
  expiresInSeconds : Option Nat := none
  poll : IO (OAuthDeviceCodePollResult α)
  nowMs : IO Nat := LeanAgent.AI.Auth.epochMsNow
  sleepMs : Nat → IO Unit := fun ms => IO.sleep (UInt32.ofNat ms)
  isCancelled : IO Bool := pure false
  signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none

structure RegisteredOAuthProvider where
  provider : OAuthProviderInterface

initialize oauthProviderRegistry : IO.Ref (Array RegisteredOAuthProvider) ← IO.mkRef #[]
initialize builtInOAuthProviders : IO.Ref (Array OAuthProviderInterface) ← IO.mkRef #[]

def initialDeviceCodeIntervalMs (intervalSeconds : Option Nat) : Nat :=
  Nat.max minimumIntervalMs ((intervalSeconds.getD defaultPollIntervalSeconds) * 1000)

def deviceCodeDeadline? (nowMs : Nat) (expiresInSeconds : Option Nat) : Option Nat :=
  expiresInSeconds.map fun seconds => nowMs + seconds * 1000

def deviceCodeTimeoutError (slowDownResponses : Nat) : IO α :=
  if slowDownResponses > 0 then
    throw (IO.userError slowDownTimeoutMessage)
  else
    throw (IO.userError timeoutMessage)

def deviceCodeAbortSignal (options : OAuthDeviceCodePollOptions α) :
    Option LeanAgent.AI.Util.Abort.AbortSignal :=
  options.signal.map fun signal => { signal with message := cancelMessage }

def sleepUntilNextDevicePoll
    (options : OAuthDeviceCodePollOptions α)
    (intervalMs : Nat)
    (deadline? : Option Nat)
    (slowDownResponses : Nat) : IO Unit := do
  let signal? := deviceCodeAbortSignal options
  match deadline? with
  | none => LeanAgent.AI.Util.Abort.sleep options.sleepMs intervalMs signal? 50 (some cancelMessage)
  | some deadline =>
      let now ← options.nowMs
      if now >= deadline then
        deviceCodeTimeoutError slowDownResponses
      else
        LeanAgent.AI.Util.Abort.sleep
          options.sleepMs
          (Nat.min intervalMs (deadline - now))
          signal?
          50
          (some cancelMessage)

partial def pollOAuthDeviceCodeLoop
    (options : OAuthDeviceCodePollOptions α)
    (deadline? : Option Nat)
    (intervalMs : Nat)
    (slowDownResponses : Nat) : IO α := do
  if ← options.isCancelled then
    throw (IO.userError cancelMessage)
  LeanAgent.AI.Util.Abort.throwIfAborted (deviceCodeAbortSignal options) (some cancelMessage)
  match deadline? with
  | some deadline =>
      if (← options.nowMs) >= deadline then
        deviceCodeTimeoutError slowDownResponses
  | none => pure ()
  match ← options.poll with
  | .complete value => pure value
  | .failed message => throw (IO.userError message)
  | .pending =>
      sleepUntilNextDevicePoll options intervalMs deadline? slowDownResponses
      pollOAuthDeviceCodeLoop options deadline? intervalMs slowDownResponses
  | .slowDown =>
      let slowDownResponses := slowDownResponses + 1
      let intervalMs := Nat.max minimumIntervalMs (intervalMs + slowDownIntervalIncrementMs)
      sleepUntilNextDevicePoll options intervalMs deadline? slowDownResponses
      pollOAuthDeviceCodeLoop options deadline? intervalMs slowDownResponses

def pollOAuthDeviceCodeFlow (options : OAuthDeviceCodePollOptions α) : IO α := do
  let now ← options.nowMs
  let deadline? := deviceCodeDeadline? now options.expiresInSeconds
  pollOAuthDeviceCodeLoop options deadline? (initialDeviceCodeIntervalMs options.intervalSeconds) 0

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

def oauthModelsError (message : String) : IO.Error :=
  IO.userError s!"ModelsError(oauth): {message}"

def refreshOAuthToken
    (providerId : OAuthProviderId)
    (credentials : OAuthCredentials) : IO OAuthCredentials := do
  match ← getOAuthProvider? providerId with
  | some provider => provider.refreshToken credentials
  | none => throw (oauthModelsError s!"Unknown OAuth provider: {providerId}")

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
  | none => throw (oauthModelsError s!"Unknown OAuth provider: {providerId}")
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
                throw (oauthModelsError s!"Failed to refresh OAuth token for {providerId}")
            else
              pure credential
          pure (some { newCredentials := credential, apiKey := provider.getApiKey credential })

end LeanAgent.AI.OAuth
