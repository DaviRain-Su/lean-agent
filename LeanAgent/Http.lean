namespace LeanAgent.Http

/--
POST a JSON payload to an HTTPS endpoint using the native libcurl C API.

This is intentionally a small transport boundary: Lean code owns request JSON and
response parsing, while native code owns TLS, proxy handling, and HTTP transport.
It does not execute the `curl` command-line program.
-/
@[extern "lean_agent_http_post_json"]
opaque postJsonRaw
  (url apiKey payload noProxy userAgent : @& String)
  (timeoutSeconds connectTimeoutSeconds : UInt32)
  (maxResponseBytes : UInt64)
  : IO String

structure JsonPostConfig where
  url : String
  apiKey : String
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"

structure JsonPostResponse where
  status : Nat
  body : String

def parseStatusEnvelope (raw : String) : Except String JsonPostResponse :=
  match raw.splitOn "\n" with
  | [] => throw "HTTP response envelope was empty"
  | statusLine :: bodyParts =>
      match statusLine.toNat? with
      | none => throw s!"invalid HTTP status in response envelope: {statusLine}"
      | some status =>
          pure
            { status := status
              body := String.intercalate "\n" bodyParts
            }

def postJsonResponse (config : JsonPostConfig) (payload : String) : IO JsonPostResponse := do
  let raw ← postJsonRaw
    config.url
    config.apiKey
    payload
    (config.noProxy.getD "")
    config.userAgent
    config.timeoutSeconds
    config.connectTimeoutSeconds
    config.maxResponseBytes
  match parseStatusEnvelope raw with
  | .ok response => pure response
  | .error err => throw (IO.userError err)

def postJson (config : JsonPostConfig) (payload : String) : IO String := do
  pure (← postJsonResponse config payload).body

end LeanAgent.Http
