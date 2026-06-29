import LeanAgent.AI.Images.Registry

namespace LeanAgent.AI.Images

def resolveImagesApiProvider (api : LeanAgent.AI.ImagesApi) :
    IO ImagesApiProvider := do
  match ← getImagesApiProvider? api with
  | some provider => pure provider
  | none => throw (IO.userError s!"No API provider registered for api: {api}")

def generateImagesWithApi
    (api : LeanAgent.AI.ImagesApi)
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) :
    IO LeanAgent.AI.AssistantImages := do
  let provider ← resolveImagesApiProvider api
  provider.generateImages model context options

def generateImages
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) :
    IO LeanAgent.AI.AssistantImages :=
  generateImagesWithApi model.api model context options

end LeanAgent.AI.Images
