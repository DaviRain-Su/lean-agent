import LeanAgent.AI.Types

namespace LeanAgent.AI.Images

abbrev ImagesApiFunction :=
  LeanAgent.AI.ImagesModel →
  LeanAgent.AI.ImagesContext →
  LeanAgent.AI.ImagesOptions →
  IO LeanAgent.AI.AssistantImages

structure ImagesApiProvider where
  api : LeanAgent.AI.ImagesApi
  generateImages : ImagesApiFunction

structure RegisteredImagesApiProvider where
  provider : ImagesApiProvider
  sourceId : Option String := none

initialize imagesApiProviderRegistry : IO.Ref (Array RegisteredImagesApiProvider) ← IO.mkRef #[]

def ensureApiMatches
    (api : LeanAgent.AI.ImagesApi)
    (model : LeanAgent.AI.ImagesModel) : IO Unit :=
  if model.api == api then
    pure ()
  else
    throw (IO.userError s!"Mismatched api: {model.api} expected {api}")

def wrapGenerateImages
    (api : LeanAgent.AI.ImagesApi)
    (generateImages : ImagesApiFunction) : ImagesApiFunction :=
  fun model context options => do
    ensureApiMatches api model
    generateImages model context options

def registerImagesApiProvider
    (provider : ImagesApiProvider)
    (sourceId : Option String := none) : IO Unit := do
  let wrappedProvider : ImagesApiProvider :=
    { api := provider.api
      generateImages := wrapGenerateImages provider.api provider.generateImages
    }
  imagesApiProviderRegistry.modify fun providers =>
    (providers.filter fun entry => entry.provider.api != provider.api).push
      { provider := wrappedProvider, sourceId := sourceId }

def getImagesApiProvider? (api : LeanAgent.AI.ImagesApi) :
    IO (Option ImagesApiProvider) := do
  let providers ← imagesApiProviderRegistry.get
  pure (providers.findSome? fun entry =>
    if entry.provider.api == api then some entry.provider else none)

def getImagesApiProviders : IO (Array ImagesApiProvider) := do
  let providers ← imagesApiProviderRegistry.get
  pure (providers.map (fun entry => entry.provider))

def unregisterImagesApiProviders (sourceId : String) : IO Unit :=
  imagesApiProviderRegistry.modify fun providers =>
    providers.filter fun entry => entry.sourceId != some sourceId

def clearImagesApiProviders : IO Unit :=
  imagesApiProviderRegistry.set #[]

def registerBuiltInImagesApiProviders : IO Unit :=
  pure ()

def resetImagesApiProviders : IO Unit := do
  clearImagesApiProviders
  registerBuiltInImagesApiProviders

initialize registerBuiltInImagesProviders : Unit ← registerBuiltInImagesApiProviders

end LeanAgent.AI.Images
