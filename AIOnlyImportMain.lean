import LeanAgent.AI

def main : IO Unit := do
  let _ : LeanAgent.AI.Api.OpenAIResponses.OpenAIResponsesOptions := {}
  let _ : LeanAgent.AI.Api.OpenAICompletions.OpenAICompletionsOptions := {}
  let _ : LeanAgent.AI.Api.OpenAICodexResponses.OpenAICodexResponsesOptions := {}
  let _ : LeanAgent.AI.Api.AnthropicMessages.AnthropicMessagesOptions := {}
  let _ : LeanAgent.AI.Api.AzureOpenAIResponses.AzureOpenAIResponsesOptions := {}
  let _ : LeanAgent.AI.Api.BedrockConverseStream.BedrockOptions := {}
  let _ : LeanAgent.AI.Api.GoogleGenerativeAI.GoogleGenerativeAIOptions := {}
  let _ : LeanAgent.AI.Api.GoogleVertex.GoogleVertexOptions := {}
  let _ : LeanAgent.AI.Api.MistralConversations.MistralOptions := {}
  let _ : LeanAgent.AI.OAuth.OAuthProviderInfo :=
    { id := "test", name := "Test", available := true }
  let _ : LeanAgent.AI.OAuth.OAuthProvider :=
    { id := "test"
      name := "Test"
      login := fun _ => throw (IO.userError "unused")
      refreshToken := fun credential => pure credential
      getApiKey := fun credential => credential.access
      toAuth := fun credential => { apiKey := some credential.access }
    }
  let _ ← LeanAgent.AI.SessionResources.registerSessionResourceCleanup (fun _ => pure ())
  let collection ← LeanAgent.Models.createModels
  let staticProvider? := LeanAgent.Models.defaultCatalog.provider? LeanAgent.Models.openAIProviderId
  if staticProvider?.isNone then
    throw (IO.userError "missing static model catalog surface after LeanAgent.AI import")
  let provider ←
    LeanAgent.Models.createProvider
      { id := "test"
        auth := {}
        models :=
          #[ { id := "model"
               name := "Model"
               provider := "test"
               api := "openai-responses"
               baseUrl := "https://example.invalid"
             } ]
        apis :=
          #[ { api := "openai-responses"
               streams :=
                 { streamSimple := fun model _context _options =>
                     pure <|
                       LeanAgent.AI.fromMessage
                         { content := #[LeanAgent.AI.text "ok"]
                           api := model.api
                           provider := model.provider
                           model := model.id
                           timestamp := 0
                         }
                 } } ]
      }
  collection.setProvider provider
  let models ← collection.getModels
  if models.size != 1 then
    throw (IO.userError "missing runtime model collection surface after LeanAgent.AI import")
  let _ := LeanAgent.AI.fromMessage
    { content := #[LeanAgent.AI.text "ok"]
      api := "openai-responses"
      provider := "test"
      model := "model"
      timestamp := 0
    }
  IO.println "ai-import-ok"
