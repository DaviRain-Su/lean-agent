import LeanAgent.AI.Images.Registry
import LeanAgent.AI.Auth

namespace LeanAgent.AI.Images

def imagesModelsError (code message : String) : IO.Error :=
  IO.userError s!"ModelsError({code}): {message}"

def isImagesModelsError (err : IO.Error) : Bool :=
  err.toString.startsWith "ModelsError("

def resolveImagesApiProvider (api : LeanAgent.AI.ImagesApi) :
    IO ImagesApiProvider := do
  match ← getImagesApiProvider? api with
  | some provider => pure provider
  | none => throw (IO.userError s!"No API provider registered for api: {api}")

def abortedImages (model : LeanAgent.AI.ImagesModel) : IO LeanAgent.AI.AssistantImages := do
  let timestamp ← IO.monoMsNow
  pure
    { api := model.api
      provider := model.provider
      model := model.id
      output := #[]
      stopReason := .aborted
      errorMessage := some LeanAgent.AI.Util.Abort.requestAbortedMessage
      timestamp := timestamp
    }

def generateImagesWithApi
    (api : LeanAgent.AI.ImagesApi)
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) :
    IO LeanAgent.AI.AssistantImages := do
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return ← abortedImages model
  let provider ← resolveImagesApiProvider api
  try
    provider.generateImages model context options
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      abortedImages model
    else
      throw err

def generateImages
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) :
    IO LeanAgent.AI.AssistantImages :=
  generateImagesWithApi model.api model context options

structure ProviderImages where
  generateImages :
    LeanAgent.AI.ImagesModel →
    LeanAgent.AI.ImagesContext →
    LeanAgent.AI.ImagesOptions →
    IO LeanAgent.AI.AssistantImages

structure ImagesProvider where
  id : String
  name : String
  auth : LeanAgent.AI.Auth.ProviderAuth
  getModels : IO (Array LeanAgent.AI.ImagesModel)
  refreshModels : Option (IO Unit) := none
  generateImages :
    LeanAgent.AI.ImagesModel →
    LeanAgent.AI.ImagesContext →
    LeanAgent.AI.ImagesOptions →
    IO LeanAgent.AI.AssistantImages

structure CreateImagesProviderOptions where
  id : String
  name : Option String := none
  auth : LeanAgent.AI.Auth.ProviderAuth
  models : Array LeanAgent.AI.ImagesModel := #[]
  refreshModels : Option (IO (Array LeanAgent.AI.ImagesModel)) := none
  api : ProviderImages

def createImagesProvider (input : CreateImagesProviderOptions) : IO ImagesProvider := do
  let modelsRef ← IO.mkRef input.models
  let inflightRefresh ← Std.Mutex.new (none : Option (Task (Except IO.Error Unit)))
  let refreshModels :=
    input.refreshModels.map fun refresh => do
      let task ←
        inflightRefresh.atomically fun ref => do
          match ← ref.get with
          | some task => pure task
          | none =>
              let task ← IO.asTask do
                try
                  let refreshed ← refresh
                  modelsRef.set refreshed
                finally
                  inflightRefresh.atomically fun clearRef => do
                    clearRef.set none
              ref.set (some task)
              pure task
      match ← IO.wait task with
      | .ok _ => pure ()
      | .error err => throw err
  pure
    { id := input.id
      name := input.name.getD input.id
      auth := input.auth
      getModels := modelsRef.get
      refreshModels := refreshModels
      generateImages := fun model context options =>
        input.api.generateImages model context options
    }

structure Collection where
  providersRef : IO.Ref (Array ImagesProvider)
  credentials : LeanAgent.AI.Auth.CredentialStore
  authContext : LeanAgent.AI.Auth.AuthContext

def createImagesModels
    (credentials : Option LeanAgent.AI.Auth.CredentialStore := none)
    (authContext : LeanAgent.AI.Auth.AuthContext := LeanAgent.AI.Auth.defaultProviderAuthContext) :
    IO Collection := do
  let credentials ←
    match credentials with
    | some credentials => pure credentials
    | none => LeanAgent.AI.Auth.InMemoryCredentialStore.mk
  let providersRef ← IO.mkRef (Array.empty : Array ImagesProvider)
  pure { providersRef := providersRef, credentials := credentials, authContext := authContext }

def Collection.getProviders (collection : Collection) : IO (Array ImagesProvider) :=
  collection.providersRef.get

def Collection.getProvider? (collection : Collection) (id : String) : IO (Option ImagesProvider) := do
  let providers ← collection.getProviders
  pure (providers.find? fun provider => provider.id == id)

def Collection.getProvider (collection : Collection) (id : String) : IO (Option ImagesProvider) :=
  collection.getProvider? id

def Collection.setProvider (collection : Collection) (provider : ImagesProvider) : IO Unit := do
  collection.providersRef.modify fun providers =>
    (providers.filter fun current => current.id != provider.id).push provider

def Collection.deleteProvider (collection : Collection) (id : String) : IO Unit := do
  collection.providersRef.modify fun providers => providers.filter fun provider => provider.id != id

def Collection.clearProviders (collection : Collection) : IO Unit :=
  collection.providersRef.set #[]

def providerModelsOrEmpty (provider : ImagesProvider) : IO (Array LeanAgent.AI.ImagesModel) := do
  try
    provider.getModels
  catch _ =>
    pure #[]

def Collection.getModels
    (collection : Collection)
    (providerId : Option String := none) : IO (Array LeanAgent.AI.ImagesModel) := do
  match providerId with
  | some id =>
      match ← collection.getProvider? id with
      | some provider => providerModelsOrEmpty provider
      | none => pure #[]
  | none =>
      let providers ← collection.getProviders
      let mut models := #[]
      for provider in providers do
        models := models ++ (← providerModelsOrEmpty provider)
      pure models

def Collection.getModel?
    (collection : Collection)
    (providerId modelId : String) : IO (Option LeanAgent.AI.ImagesModel) := do
  let models ← collection.getModels (some providerId)
  pure (models.find? fun model => model.id == modelId)

def Collection.getModel
    (collection : Collection)
    (providerId modelId : String) : IO (Option LeanAgent.AI.ImagesModel) :=
  collection.getModel? providerId modelId

def Collection.refresh (collection : Collection) (providerId : Option String := none) : IO Unit := do
  match providerId with
  | some id =>
      match ← collection.getProvider? id with
      | some provider =>
          match provider.refreshModels with
          | some refresh =>
              try
                refresh
              catch err =>
                if isImagesModelsError err then
                  throw err
                else
                  throw (imagesModelsError "model_source" s!"Model refresh failed for {id}: {err}")
          | none => pure ()
      | none => pure ()
  | none =>
      let providers ← collection.getProviders
      let mut tasks := #[]
      for provider in providers do
        match provider.refreshModels with
        | some refresh => tasks := tasks.push (← IO.asTask refresh)
        | none => pure ()
      for task in tasks do
        match ← IO.wait task with
        | .ok _ => pure ()
        | .error _ => pure ()

def Collection.getAuth
    (collection : Collection)
    (model : LeanAgent.AI.ImagesModel) : IO (Option LeanAgent.AI.Auth.AuthResult) := do
  match ← collection.getProvider? model.provider with
  | some provider =>
      LeanAgent.AI.Auth.resolveProviderAuthForModel
        model.toModelRef
        provider.id
        provider.auth
        collection.credentials
        collection.authContext
        {}
  | none => pure none

def imageHeaderNames (headers : Array (String × Option String)) : Array String :=
  headers.map Prod.fst

def authHeadersToImageHeaders
    (authHeaders : LeanAgent.AI.Auth.ProviderHeaders)
    (requestHeaders : Array (String × Option String)) : Array (String × Option String) :=
  let requestNames := imageHeaderNames requestHeaders
  let inherited := authHeaders.filterMap fun (name, value) =>
    if requestNames.contains name then none else some (name, some value)
  inherited ++ requestHeaders

def Collection.applyAuth
    (collection : Collection)
    (provider : ImagesProvider)
    (model : LeanAgent.AI.ImagesModel)
    (options : LeanAgent.AI.ImagesOptions) :
    IO (LeanAgent.AI.ImagesModel × LeanAgent.AI.ImagesOptions) := do
  let resolution ←
    LeanAgent.AI.Auth.resolveProviderAuthForModel
      model.toModelRef
      provider.id
      provider.auth
      collection.credentials
      collection.authContext
      { apiKey := options.apiKey, env := options.env }
  match resolution with
  | none => pure (model, options)
  | some resolution =>
      let requestModel :=
        match resolution.auth.baseUrl with
        | some baseUrl => { model with baseUrl := baseUrl }
        | none => model
      let apiKey :=
        match options.apiKey with
        | some value => some value
        | none => resolution.auth.apiKey
      let requestOptions :=
        { options with
          apiKey := apiKey
          headers := authHeadersToImageHeaders resolution.auth.headers options.headers
          env := LeanAgent.AI.Auth.providerEnvMerge resolution.env options.env
        }
      pure (requestModel, requestOptions)

def errorImages
    (model : LeanAgent.AI.ImagesModel)
    (message : String) : IO LeanAgent.AI.AssistantImages := do
  let timestamp ← IO.monoMsNow
  pure
    { api := model.api
      provider := model.provider
      model := model.id
      output := #[]
      stopReason := .error
      errorMessage := some message
      timestamp := timestamp
    }

def ProviderImages.lazy (load : IO ProviderImages) : ProviderImages :=
  { generateImages := fun model context options => do
      let provider ←
        try
          load
        catch err =>
          return ← errorImages model err.toString
      provider.generateImages model context options
  }

def Collection.requireProvider (collection : Collection) (model : LeanAgent.AI.ImagesModel) :
    IO ImagesProvider := do
  match ← collection.getProvider? model.provider with
  | some provider => pure provider
  | none => throw (imagesModelsError "provider" s!"Unknown provider: {model.provider}")

def Collection.generateImages
    (collection : Collection)
    (model : LeanAgent.AI.ImagesModel)
    (context : LeanAgent.AI.ImagesContext)
    (options : LeanAgent.AI.ImagesOptions := {}) : IO LeanAgent.AI.AssistantImages := do
  if ← LeanAgent.AI.Util.Abort.isAborted options.signal then
    return ← abortedImages model
  try
    let provider ← collection.requireProvider model
    let (requestModel, requestOptions) ← collection.applyAuth provider model options
    provider.generateImages requestModel context requestOptions
  catch err =>
    if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
      abortedImages model
    else
      errorImages model err.toString

end LeanAgent.AI.Images
