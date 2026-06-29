import Std.Http
import LeanAgent.AI.OAuth.Page
import LeanAgent.AI.Util.ProviderEnv

open Std Async Http

namespace LeanAgent.AI.OAuth.LocalCallback

inductive ListenErrorBehavior where
  | throw
  | disable
deriving BEq

structure CallbackResult where
  code : String
  state : Option String := none
deriving BEq

structure Config where
  redirectUri : String
  expectedState : Option String := none
  bindHost : Option String := none
  successMessage : String
  callbackErrorMessage : String := "Authentication did not complete."
  invalidPathMessage : String := "Callback route not found."
  missingCodeMessage : String := "Missing authorization code."
  missingStateMessage : String := "Missing state parameter."
  missingCodeOrStateMessage : Option String := none
  stateMismatchMessage : String := "State mismatch."
  internalErrorMessage : String := "Internal error while processing OAuth callback."
  listenErrorBehavior : ListenErrorBehavior := .throw

structure CallbackServer where
  redirectUri : String
  available : Bool := true
  waitForCode : IO (Option CallbackResult)
  cancelWait : IO Unit
  close : IO Unit

private def parseRedirectUri (redirectUri : String) : IO (UInt16 × String) := do
  let uri ←
    match Std.Http.URI.parse? redirectUri with
    | some uri => pure uri
    | none => throw (IO.userError s!"Invalid OAuth redirect URI: {redirectUri}")
  let authority ←
    match uri.authority with
    | some authority => pure authority
    | none => throw (IO.userError s!"OAuth redirect URI is missing an authority: {redirectUri}")
  let port ←
    match authority.port with
    | .value port => pure port
    | .omitted => pure uri.scheme.defaultPort
    | .empty =>
        throw (IO.userError s!"OAuth redirect URI has an empty port: {redirectUri}")
  let path := toString uri.path
  pure (port, if path.isEmpty then "/" else path)

private def bindHostFor (config : Config) : IO String := do
  match config.bindHost with
  | some host =>
      let trimmed := host.trimAscii.toString
      if trimmed.isEmpty then
        pure "127.0.0.1"
      else
        pure trimmed
  | none =>
      match ← LeanAgent.AI.Util.ProviderEnv.getProviderEnvValue "PI_OAUTH_CALLBACK_HOST" with
      | some host =>
          let trimmed := host.trimAscii.toString
          if trimmed.isEmpty then
            pure "127.0.0.1"
          else
            pure trimmed
      | none => pure "127.0.0.1"

private def bindAddress (host : String) (port : UInt16) : IO Net.SocketAddress := do
  let normalized :=
    let trimmed := host.trimAscii.toString
    if trimmed == "localhost" then "127.0.0.1" else trimmed
  match Net.IPv4Addr.ofString normalized with
  | some addr => pure (.v4 { addr := addr, port := port })
  | none =>
      match Net.IPv6Addr.ofString normalized with
      | some addr => pure (.v6 { addr := addr, port := port })
      | none =>
          throw (IO.userError s!"Unsupported OAuth callback bind host: {host}")

private def disabled (redirectUri : String) : CallbackServer :=
  { redirectUri := redirectUri
    available := false
    waitForCode := pure none
    cancelWait := pure ()
    close := pure ()
  }

private def readQueryParam (request : Request Body.Stream) (name : String) : Option String :=
  request.line.uri.query.get name

private def serveHtml
    (builder : Response.Builder)
    (html : String) : ContextAsync (Response Body.Any) := do
  let response ← builder.html html
  pure response

private def startCore (config : Config) : IO CallbackServer := Async.block do
  let (port, callbackPath) ← parseRedirectUri config.redirectUri
  let host ← bindHostFor config
  let addr ← bindAddress host port
  let resultPromise ← IO.Promise.new
  let handler := Std.Http.Server.Handler.ofFn fun request => do
    try
      let requestPath := toString request.line.uri.path
      if requestPath != callbackPath then
        serveHtml Response.notFound (LeanAgent.AI.OAuth.oauthErrorHtml config.invalidPathMessage)
      else
        match readQueryParam request "error" with
        | some errorCode =>
            serveHtml
              Response.badRequest
              (LeanAgent.AI.OAuth.oauthErrorHtml
                config.callbackErrorMessage
                (some s!"Error: {errorCode}"))
        | none =>
            let code? := readQueryParam request "code"
            let state? := readQueryParam request "state"
            match code? with
            | none =>
                let message :=
                  match config.expectedState, config.missingCodeOrStateMessage with
                  | some _, some message => message
                  | _, _ => config.missingCodeMessage
                serveHtml Response.badRequest (LeanAgent.AI.OAuth.oauthErrorHtml message)
            | some code =>
                match config.expectedState with
                | some expectedState =>
                    match state? with
                    | none =>
                        let message := config.missingCodeOrStateMessage.getD config.missingStateMessage
                        serveHtml Response.badRequest (LeanAgent.AI.OAuth.oauthErrorHtml message)
                    | some state =>
                        if state != expectedState then
                          serveHtml
                            Response.badRequest
                            (LeanAgent.AI.OAuth.oauthErrorHtml config.stateMismatchMessage)
                        else
                          let _ ← resultPromise.resolve (some { code := code, state := some state })
                          serveHtml
                            Response.ok
                            (LeanAgent.AI.OAuth.oauthSuccessHtml config.successMessage)
                | none =>
                    let _ ← resultPromise.resolve (some { code := code, state := state? })
                    serveHtml
                      Response.ok
                      (LeanAgent.AI.OAuth.oauthSuccessHtml config.successMessage)
    catch _ =>
      serveHtml
        Response.internalServerError
        (LeanAgent.AI.OAuth.oauthErrorHtml config.internalErrorMessage)
  let server ← Std.Http.Server.serve addr handler
  pure
    { redirectUri := config.redirectUri
      waitForCode := Async.block (Async.ofPurePromise (pure resultPromise))
      cancelWait := resultPromise.resolve none
      close := do
        resultPromise.resolve none
        IO.sleep 100
        Async.block server.shutdownAndWait
    }

def start (config : Config) : IO CallbackServer := do
  try
    startCore config
  catch err =>
    match config.listenErrorBehavior with
    | .throw => throw err
    | .disable => pure (disabled config.redirectUri)

end LeanAgent.AI.OAuth.LocalCallback
