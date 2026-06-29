import LeanAgent.AI.Api.OpenAICompletions

namespace LeanAgent.OpenAI

abbrev OpenAICompatibleConfig := LeanAgent.AI.Api.OpenAICompletions.OpenAICompatibleConfig
abbrev OpenAICompletionsOptions := LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions
abbrev ToolChoice := LeanAgent.AI.Api.OpenAICompletions.ToolChoice

def chatCompletionsUrl := LeanAgent.AI.Api.OpenAICompletions.chatCompletionsUrl
def toolCallToJson := LeanAgent.AI.Api.OpenAICompletions.toolCallToJson
def messageHasToolCall := LeanAgent.AI.Api.OpenAICompletions.messageHasToolCall
def hasToolHistory := LeanAgent.AI.Api.OpenAICompletions.hasToolHistory
def messageToJson := LeanAgent.AI.Api.OpenAICompletions.messageToJson
def toolToJson := LeanAgent.AI.Api.OpenAICompletions.toolToJson
def requestToolFields := LeanAgent.AI.Api.OpenAICompletions.requestToolFields
def requestOptionFields := LeanAgent.AI.Api.OpenAICompletions.requestOptionFields
def requestToJsonWithOptions := LeanAgent.AI.Api.OpenAICompletions.requestToJsonWithOptions
def requestToJson := LeanAgent.AI.Api.OpenAICompletions.requestToJson
def runHttpJson := LeanAgent.AI.Api.OpenAICompletions.runHttpJson
def parseMaybeContent := LeanAgent.AI.Api.OpenAICompletions.parseMaybeContent
def parseToolArguments := LeanAgent.AI.Api.OpenAICompletions.parseToolArguments
def parseToolCall := LeanAgent.AI.Api.OpenAICompletions.parseToolCall
def parseToolCalls := LeanAgent.AI.Api.OpenAICompletions.parseToolCalls
def parseChatCompletion := LeanAgent.AI.Api.OpenAICompletions.parseChatCompletion
def completeWithOptions := LeanAgent.AI.Api.OpenAICompletions.completeWithOptions
def provider := LeanAgent.AI.Api.OpenAICompletions.provider

end LeanAgent.OpenAI
