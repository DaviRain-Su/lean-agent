import LeanAgent.AI.Auth
import LeanAgent.AI.Types
import LeanAgent.AI.Util.Abort

namespace LeanAgent.AI.OAuth

abbrev OAuthCredentials := LeanAgent.AI.Auth.OAuthCredential
abbrev OAuthProviderId := String

structure OAuthPrompt where
  message : String
  placeholder : Option String := none
  allowEmpty : Bool := false
  signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none

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
  onManualCodeInput : Option (OAuthPrompt → IO String) := none
  onSelect : OAuthSelectPrompt → IO (Option String)
  signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none

structure OAuthProviderInterface where
  id : OAuthProviderId
  name : String
  login : OAuthLoginCallbacks → IO OAuthCredentials
  usesCallbackServer : Bool := false
  refreshToken : OAuthCredentials → IO OAuthCredentials
  getApiKey : OAuthCredentials → String
  toAuth : OAuthCredentials → LeanAgent.AI.Auth.ModelAuth
  modifyModels :
    Option (Array LeanAgent.AI.ModelRef → OAuthCredentials → Array LeanAgent.AI.ModelRef) := none

abbrev OAuthProvider := OAuthProviderInterface

structure OAuthProviderInfo where
  id : OAuthProviderId
  name : String
  available : Bool := true
deriving BEq

end LeanAgent.AI.OAuth
