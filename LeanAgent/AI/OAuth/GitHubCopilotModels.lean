import LeanAgent.AI.OAuth.GitHubCopilot
import LeanAgent.Models

namespace LeanAgent.AI.OAuth.GitHubCopilot

def modifyModels
    (models : Array LeanAgent.Models.ModelInfo)
    (credential : LeanAgent.AI.Auth.OAuthCredential) : Array LeanAgent.Models.ModelInfo :=
  let baseUrl := getBaseUrl (some credential.access) (enterpriseDomain? credential)
  let availableModelIds? := extraStringArray? credential "availableModelIds"
  models.filterMap fun model =>
    if model.provider != providerId then
      some model
    else
      match availableModelIds? with
      | some ids =>
          if ids.contains model.id then
            some { model with baseUrl := baseUrl }
          else
            none
      | none => some { model with baseUrl := baseUrl }

end LeanAgent.AI.OAuth.GitHubCopilot
