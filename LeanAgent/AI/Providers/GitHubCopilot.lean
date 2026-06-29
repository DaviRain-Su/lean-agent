import LeanAgent.AI.OAuth.GitHubCopilot
import LeanAgent.AI.Providers.Catalog
import LeanAgent.AI.Providers.Streams
import LeanAgent.Models

namespace LeanAgent.AI.Providers.GitHubCopilot

def providerId : String := LeanAgent.Models.githubCopilotProviderId

def provider : IO LeanAgent.Models.Provider :=
  LeanAgent.Models.createProvider
    { id := providerId
      name := some "GitHub Copilot"
      baseUrl := some LeanAgent.Models.githubCopilotBaseUrl
      headers := LeanAgent.Models.githubCopilotHeaders
      auth :=
        { apiKey :=
            some
              (LeanAgent.AI.Auth.envApiKeyAuth
                "GitHub Copilot token"
                #[LeanAgent.Models.githubCopilotApiKeyEnv])
          oauth := some LeanAgent.AI.Providers.Catalog.githubCopilotOAuthAuth
        }
      models := LeanAgent.Models.githubCopilotModels
      apis :=
        #[ { api := "openai-completions", streams := LeanAgent.AI.Providers.Streams.openAICompatibleStreams }
         , { api := "openai-responses", streams := LeanAgent.AI.Providers.Streams.openAIResponsesStreams }
         , { api := LeanAgent.AI.Api.AnthropicMessages.api, streams := LeanAgent.AI.Providers.Streams.anthropicMessagesStreams }
         ]
    }

end LeanAgent.AI.Providers.GitHubCopilot
