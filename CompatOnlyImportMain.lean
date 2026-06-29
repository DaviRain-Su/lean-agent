import LeanAgent.AI.Compat

def main : IO Unit := do
  LeanAgent.AI.Compat.resetApiProviders
  let apiProviders ← LeanAgent.AI.Compat.getApiProviders
  if !apiProviders.any (·.api == "openai-responses") then
    throw (IO.userError "missing OpenAI Responses API provider after LeanAgent.AI.Compat import")
  let providers := LeanAgent.AI.Compat.getProviders
  if !providers.contains LeanAgent.Models.openAIProviderId then
    throw (IO.userError "missing built-in provider helpers after LeanAgent.AI.Compat import")
  let models := LeanAgent.AI.Compat.getModels LeanAgent.Models.openAIProviderId
  if models.isEmpty then
    throw (IO.userError "missing built-in model helpers after LeanAgent.AI.Compat import")
  let envKeys? := LeanAgent.AI.EnvApiKeys.apiKeyEnvVars? LeanAgent.Models.openAIProviderId
  if envKeys? != some #["OPENAI_API_KEY"] then
    throw (IO.userError "missing env-api-keys surface after LeanAgent.AI.Compat import")
  let imageProviders := LeanAgent.AI.Images.Models.getImageProviders
  if !imageProviders.contains "openrouter" then
    throw (IO.userError "missing image model surface after LeanAgent.AI.Compat import")
  LeanAgent.AI.Compat.clearImagesApiProviders
  LeanAgent.AI.Compat.registerBuiltInImagesApiProviders
  if (← LeanAgent.AI.Compat.getImagesApiProvider? LeanAgent.AI.Api.OpenRouterImages.api).isNone then
    throw (IO.userError "missing built-in image re-registration hook after LeanAgent.AI.Compat import")
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.anthropicMessagesApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.azureOpenAIResponsesApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.googleGenerativeAIApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.googleVertexApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.mistralConversationsApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.openAICompletionsApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.openAIResponsesApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.openAICodexResponsesApi
  let _ : LeanAgent.Models.ProviderStreams :=
    LeanAgent.AI.Compat.bedrockConverseStreamApi
  let _ ← LeanAgent.AI.Compat.setBedrockProviderModule
    LeanAgent.AI.Providers.Streams.bedrockConverseStreamStreams
  let _ ← LeanAgent.AI.Compat.resetBedrockProviderModule
  let _ : LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions := {}
  let _ ← LeanAgent.AI.SessionResources.registerSessionResourceCleanup (fun _ => pure ())
  let _ : LeanAgent.AI.Compat.Aliases.AliasStream :=
    LeanAgent.AI.Compat.Aliases.streamSimpleOpenAIResponses
  let _ : LeanAgent.AI.Compat.Aliases.OpenAIResponsesStream :=
    LeanAgent.AI.Compat.Aliases.streamOpenAIResponses
  let _ : LeanAgent.AI.Compat.AliasStream :=
    LeanAgent.AI.Compat.streamSimpleOpenAIResponses
  let _ : LeanAgent.AI.Compat.OpenAIResponsesStream :=
    LeanAgent.AI.Compat.streamOpenAIResponses
  let _ : LeanAgent.AI.Compat.AnthropicMessagesStream :=
    LeanAgent.AI.Compat.streamAnthropic
  IO.println (String.intercalate "," (apiProviders.map (·.api)).toList)
