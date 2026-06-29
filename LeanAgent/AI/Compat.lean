import LeanAgent.AI.Api.AnthropicMessagesLazy
import LeanAgent.AI.Api.AzureOpenAIResponsesLazy
import LeanAgent.AI.Api.BedrockConverseStreamLazy
import LeanAgent.AI.Api.GoogleGenerativeAILazy
import LeanAgent.AI.Api.GoogleVertexLazy
import LeanAgent.AI.Api.MistralConversationsLazy
import LeanAgent.AI.Api.OpenAICodexResponsesLazy
import LeanAgent.AI.Api.OpenAICompletionsLazy
import LeanAgent.AI.Api.OpenAIResponsesLazy
import LeanAgent.AI
import LeanAgent.AI.EnvApiKeys
import LeanAgent.AI.Compat.Core
import LeanAgent.AI.Compat.Aliases

namespace LeanAgent.AI.Compat

def anthropicMessagesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.AnthropicMessagesLazy.anthropicMessagesApi

def azureOpenAIResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.AzureOpenAIResponsesLazy.azureOpenAIResponsesApi

def bedrockConverseStreamApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.BedrockConverseStreamLazy.bedrockConverseStreamApi

def setBedrockProviderModule (streams : LeanAgent.Models.ProviderStreams) : IO Unit :=
  LeanAgent.AI.Api.BedrockConverseStreamLazy.setBedrockProviderModule streams

def resetBedrockProviderModule : IO Unit :=
  LeanAgent.AI.Api.BedrockConverseStreamLazy.resetBedrockProviderModule

def googleGenerativeAIApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.GoogleGenerativeAILazy.googleGenerativeAIApi

def googleVertexApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.GoogleVertexLazy.googleVertexApi

def mistralConversationsApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.MistralConversationsLazy.mistralConversationsApi

def openAICodexResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.OpenAICodexResponsesLazy.openAICodexResponsesApi

def openAICompletionsApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.OpenAICompletionsLazy.openAICompletionsApi

def openAIResponsesApi : LeanAgent.Models.ProviderStreams :=
  LeanAgent.AI.Api.OpenAIResponsesLazy.openAIResponsesApi

abbrev AliasStream := LeanAgent.AI.Compat.Aliases.AliasStream
abbrev AliasComplete := LeanAgent.AI.Compat.Aliases.AliasComplete
abbrev MistralStream := LeanAgent.AI.Compat.Aliases.MistralStream
abbrev MistralComplete := LeanAgent.AI.Compat.Aliases.MistralComplete
abbrev OpenAIResponsesStream := LeanAgent.AI.Compat.Aliases.OpenAIResponsesStream
abbrev OpenAIResponsesComplete := LeanAgent.AI.Compat.Aliases.OpenAIResponsesComplete
abbrev AzureOpenAIResponsesStream := LeanAgent.AI.Compat.Aliases.AzureOpenAIResponsesStream
abbrev AzureOpenAIResponsesComplete := LeanAgent.AI.Compat.Aliases.AzureOpenAIResponsesComplete
abbrev OpenAICodexResponsesStream := LeanAgent.AI.Compat.Aliases.OpenAICodexResponsesStream
abbrev OpenAICodexResponsesComplete := LeanAgent.AI.Compat.Aliases.OpenAICodexResponsesComplete
abbrev OpenAICompletionsStream := LeanAgent.AI.Compat.Aliases.OpenAICompletionsStream
abbrev OpenAICompletionsComplete := LeanAgent.AI.Compat.Aliases.OpenAICompletionsComplete
abbrev AnthropicMessagesStream := LeanAgent.AI.Compat.Aliases.AnthropicMessagesStream
abbrev AnthropicMessagesComplete := LeanAgent.AI.Compat.Aliases.AnthropicMessagesComplete
abbrev GoogleGenerativeAIStream := LeanAgent.AI.Compat.Aliases.GoogleGenerativeAIStream
abbrev GoogleGenerativeAIComplete := LeanAgent.AI.Compat.Aliases.GoogleGenerativeAIComplete
abbrev GoogleVertexStream := LeanAgent.AI.Compat.Aliases.GoogleVertexStream
abbrev GoogleVertexComplete := LeanAgent.AI.Compat.Aliases.GoogleVertexComplete
abbrev BedrockConverseStream := LeanAgent.AI.Compat.Aliases.BedrockConverseStream
abbrev BedrockConverseComplete := LeanAgent.AI.Compat.Aliases.BedrockConverseComplete

def streamAnthropic : AnthropicMessagesStream :=
  LeanAgent.AI.Compat.Aliases.streamAnthropic

def completeAnthropic : AnthropicMessagesComplete :=
  LeanAgent.AI.Compat.Aliases.completeAnthropic

def streamSimpleAnthropic : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleAnthropic

def completeSimpleAnthropic : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleAnthropic

def streamBedrockConverseStream : BedrockConverseStream :=
  LeanAgent.AI.Compat.Aliases.streamBedrockConverseStream

def completeBedrockConverseStream : BedrockConverseComplete :=
  LeanAgent.AI.Compat.Aliases.completeBedrockConverseStream

def streamSimpleBedrockConverseStream : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleBedrockConverseStream

def completeSimpleBedrockConverseStream : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleBedrockConverseStream

def streamAzureOpenAIResponses : AzureOpenAIResponsesStream :=
  LeanAgent.AI.Compat.Aliases.streamAzureOpenAIResponses

def completeAzureOpenAIResponses : AzureOpenAIResponsesComplete :=
  LeanAgent.AI.Compat.Aliases.completeAzureOpenAIResponses

def streamSimpleAzureOpenAIResponses : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleAzureOpenAIResponses

def completeSimpleAzureOpenAIResponses : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleAzureOpenAIResponses

def streamGoogle : GoogleGenerativeAIStream :=
  LeanAgent.AI.Compat.Aliases.streamGoogle

def completeGoogle : GoogleGenerativeAIComplete :=
  LeanAgent.AI.Compat.Aliases.completeGoogle

def streamSimpleGoogle : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleGoogle

def completeSimpleGoogle : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleGoogle

def streamGoogleVertex : GoogleVertexStream :=
  LeanAgent.AI.Compat.Aliases.streamGoogleVertex

def completeGoogleVertex : GoogleVertexComplete :=
  LeanAgent.AI.Compat.Aliases.completeGoogleVertex

def streamSimpleGoogleVertex : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleGoogleVertex

def completeSimpleGoogleVertex : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleGoogleVertex

def streamMistral : MistralStream :=
  LeanAgent.AI.Compat.Aliases.streamMistral

def completeMistral : MistralComplete :=
  LeanAgent.AI.Compat.Aliases.completeMistral

def streamSimpleMistral : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleMistral

def completeSimpleMistral : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleMistral

def streamOpenAICodexResponses : OpenAICodexResponsesStream :=
  LeanAgent.AI.Compat.Aliases.streamOpenAICodexResponses

def completeOpenAICodexResponses : OpenAICodexResponsesComplete :=
  LeanAgent.AI.Compat.Aliases.completeOpenAICodexResponses

def streamSimpleOpenAICodexResponses : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleOpenAICodexResponses

def completeSimpleOpenAICodexResponses : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleOpenAICodexResponses

def streamOpenAICompletions : OpenAICompletionsStream :=
  LeanAgent.AI.Compat.Aliases.streamOpenAICompletions

def completeOpenAICompletions : OpenAICompletionsComplete :=
  LeanAgent.AI.Compat.Aliases.completeOpenAICompletions

def streamSimpleOpenAICompletions : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleOpenAICompletions

def completeSimpleOpenAICompletions : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleOpenAICompletions

def streamOpenAIResponses : OpenAIResponsesStream :=
  LeanAgent.AI.Compat.Aliases.streamOpenAIResponses

def completeOpenAIResponses : OpenAIResponsesComplete :=
  LeanAgent.AI.Compat.Aliases.completeOpenAIResponses

def streamSimpleOpenAIResponses : AliasStream :=
  LeanAgent.AI.Compat.Aliases.streamSimpleOpenAIResponses

def completeSimpleOpenAIResponses : AliasComplete :=
  LeanAgent.AI.Compat.Aliases.completeSimpleOpenAIResponses

end LeanAgent.AI.Compat
