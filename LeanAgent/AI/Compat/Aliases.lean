import LeanAgent.AI.Compat

namespace LeanAgent.AI.Compat.Aliases

abbrev AliasStream :=
  LeanAgent.Models.ModelInfo → LeanAgent.AI.Context → LeanAgent.AI.SimpleStreamOptions →
    IO LeanAgent.AI.AssistantMessageEventStream

def streamForApi (api : String) : AliasStream :=
  fun model context options => LeanAgent.AI.Compat.streamSimpleWithApi api model context options

def streamAnthropic : AliasStream :=
  streamForApi "anthropic-messages"

def streamSimpleAnthropic : AliasStream :=
  streamAnthropic

def streamAzureOpenAIResponses : AliasStream :=
  streamForApi "azure-openai-responses"

def streamSimpleAzureOpenAIResponses : AliasStream :=
  streamAzureOpenAIResponses

def streamGoogle : AliasStream :=
  streamForApi "google-generative-ai"

def streamSimpleGoogle : AliasStream :=
  streamGoogle

def streamGoogleVertex : AliasStream :=
  streamForApi "google-vertex"

def streamSimpleGoogleVertex : AliasStream :=
  streamGoogleVertex

def streamMistral : AliasStream :=
  streamForApi "mistral-conversations"

def streamSimpleMistral : AliasStream :=
  streamMistral

def streamOpenAICodexResponses : AliasStream :=
  streamForApi "openai-codex-responses"

def streamSimpleOpenAICodexResponses : AliasStream :=
  streamOpenAICodexResponses

def streamOpenAICompletions : AliasStream :=
  streamForApi "openai-completions"

def streamSimpleOpenAICompletions : AliasStream :=
  streamOpenAICompletions

def streamOpenAIResponses : AliasStream :=
  streamForApi "openai-responses"

def streamSimpleOpenAIResponses : AliasStream :=
  streamOpenAIResponses

end LeanAgent.AI.Compat.Aliases
