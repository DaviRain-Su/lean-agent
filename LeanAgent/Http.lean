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

def postJson (config : JsonPostConfig) (payload : String) : IO String :=
  postJsonRaw
    config.url
    config.apiKey
    payload
    (config.noProxy.getD "")
    config.userAgent
    config.timeoutSeconds
    config.connectTimeoutSeconds
    config.maxResponseBytes

end LeanAgent.Http
