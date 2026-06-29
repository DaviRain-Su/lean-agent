import LeanAgent.AI.Auth
import LeanAgent.AI.OAuth.Core

namespace LeanAgent.AI.Auth.OAuthBridge

private def authSelectOptions
    (options : Array LeanAgent.AI.OAuth.OAuthSelectOption) :
    Array LeanAgent.AI.Auth.AuthSelectOption :=
  options.map fun option =>
    { id := option.id
      label := option.label
    }

def toOAuthLoginCallbacks
    (callbacks : LeanAgent.AI.Auth.AuthLoginCallbacks) :
    LeanAgent.AI.OAuth.OAuthLoginCallbacks :=
  { onAuth := fun info =>
      callbacks.notify (.authUrl info.url info.instructions)
    onDeviceCode := fun info =>
      callbacks.notify
        (.deviceCode
          info.userCode
          info.verificationUri
          info.intervalSeconds
          info.expiresInSeconds)
    onPrompt := fun prompt =>
      callbacks.prompt (.text prompt.message prompt.placeholder prompt.signal)
    onProgress := some fun message =>
      callbacks.notify (.progress message)
    onManualCodeInput := some fun prompt =>
      callbacks.prompt (.manualCode prompt.message prompt.placeholder prompt.signal)
    onSelect := fun prompt => do
      let selected ←
        callbacks.prompt
          (.select prompt.message (authSelectOptions prompt.options) callbacks.signal)
      let trimmed := selected.trimAscii.toString
      pure (if trimmed.isEmpty then none else some selected)
    signal := callbacks.signal
  }

def loginWithOAuthProvider
    (provider : LeanAgent.AI.OAuth.OAuthProviderInterface)
    (callbacks : LeanAgent.AI.Auth.AuthLoginCallbacks) :
    IO LeanAgent.AI.Auth.OAuthCredential :=
  provider.login (toOAuthLoginCallbacks callbacks)

def requireRegisteredOAuthProvider
    (providerId : LeanAgent.AI.OAuth.OAuthProviderId) :
    IO LeanAgent.AI.OAuth.OAuthProviderInterface := do
  match ← LeanAgent.AI.OAuth.getOAuthProvider? providerId with
  | some provider => pure provider
  | none =>
      throw
        (IO.userError
          s!"Missing OAuth provider implementation for {providerId}. Import LeanAgent.AI.OAuth or the provider module.")

def oauthAuthForRegisteredProvider
    (providerId : LeanAgent.AI.OAuth.OAuthProviderId)
    (name : String) :
    LeanAgent.AI.Auth.OAuthAuth :=
  { name := name
    login := fun callbacks => do
      let provider ← requireRegisteredOAuthProvider providerId
      loginWithOAuthProvider provider callbacks
    refresh := fun credential => do
      let provider ← requireRegisteredOAuthProvider providerId
      provider.refreshToken credential
    toAuth := fun credential => do
      let provider ← requireRegisteredOAuthProvider providerId
      pure (provider.toAuth credential)
  }

end LeanAgent.AI.Auth.OAuthBridge
