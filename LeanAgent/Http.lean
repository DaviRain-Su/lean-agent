namespace LeanAgent.Http

/--
POST a JSON payload to an HTTPS endpoint using the native libcurl C API.

This is intentionally a small transport boundary: Lean code owns request JSON and
response parsing, while native code owns TLS, proxy handling, and HTTP transport.
It does not execute the `curl` command-line program.
-/
@[extern "lean_agent_http_request"]
opaque requestRaw
  (method url authorization body noProxy userAgent extraHeaders : @& String)
  (timeoutSeconds connectTimeoutSeconds : UInt32)
  (maxResponseBytes : UInt64)
  : IO String

/--
POST/GET helper for APIs that return AWS event-stream binary frames.

The native boundary unwraps the event-stream payload into a JSON array of event
objects so Lean can keep using string-based parsing without shelling out to
external tools or carrying raw binary through Lean `String`.
-/
@[extern "lean_agent_http_request_aws_eventstream_json"]
opaque requestAwsEventStreamJsonRaw
  (method url authorization body noProxy userAgent extraHeaders : @& String)
  (timeoutSeconds connectTimeoutSeconds : UInt32)
  (maxResponseBytes : UInt64)
  : IO String

structure RequestConfig where
  method : String := "GET"
  url : String
  authorization : Option String := none
  body : Option String := none
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"
  headers : Array (String × String) := #[]

structure JsonPostConfig where
  url : String
  apiKey : String
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"
  headers : Array (String × String) := #[]

structure JsonPostResponse where
  status : Nat
  headers : Array (String × String) := #[]
  body : String

def envelopeMagic : String := "LAHTTP2\n"

def splitFirstLine? (raw : String) : Option (String × String) :=
  match raw.splitOn "\n" with
  | [] => none
  | line :: rest => some (line, String.intercalate "\n" rest)

def takeChars (raw : String) (count : Nat) : String :=
  String.ofList (raw.toList.take count)

def dropChars (raw : String) (count : Nat) : String :=
  String.ofList (raw.toList.drop count)

def stripTrailingCR (line : String) : String :=
  match line.toList.reverse with
  | '\r' :: rest => String.ofList rest.reverse
  | _ => line

def parseHeaderLine? (rawLine : String) : Option (String × String) :=
  let line := stripTrailingCR rawLine
  if line.isEmpty || line.startsWith "HTTP/" then
    none
  else
    match line.splitOn ":" with
    | [] => none
    | _ :: [] => none
    | name :: valueParts =>
        let name := name.trimAscii.toString.toLower
        if name.isEmpty then
          none
        else
          some (name, (String.intercalate ":" valueParts).trimAscii.toString)

def insertHeader (headers : Array (String × String)) (header : String × String) :
    Array (String × String) :=
  (headers.filter fun (name, _) => name != header.fst).push header

def parseRawHeaders (rawHeaders : String) : Array (String × String) :=
  rawHeaders.splitOn "\n" |>.foldl
    (fun headers line =>
      match parseHeaderLine? line with
      | some header => insertHeader headers header
      | none => headers)
    #[]

def parseLegacyEnvelope (raw : String) : Except String JsonPostResponse := do
  let (statusLine, body) ←
    match splitFirstLine? raw with
    | some value => pure value
    | none => throw "HTTP response envelope was empty"
  let status ←
    match statusLine.toNat? with
    | some status => pure status
    | none => throw s!"invalid HTTP status in response envelope: {statusLine}"
  pure { status := status, body := body }

def parseVersionedEnvelope (raw : String) : Except String JsonPostResponse := do
  let raw := (raw.drop envelopeMagic.length).toString
  let (statusLine, rest) ←
    match splitFirstLine? raw with
    | some value => pure value
    | none => throw "HTTP response envelope was missing status"
  let status ←
    match statusLine.toNat? with
    | some status => pure status
    | none => throw s!"invalid HTTP status in response envelope: {statusLine}"
  let (headerLengthLine, rest) ←
    match splitFirstLine? rest with
    | some value => pure value
    | none => throw "HTTP response envelope was missing header length"
  let headerLength ←
    match headerLengthLine.toNat? with
    | some length => pure length
    | none => throw s!"invalid HTTP header length in response envelope: {headerLengthLine}"
  if rest.length < headerLength then
    throw "HTTP response envelope header block was truncated"
  let rawHeaders := takeChars rest headerLength
  let body := dropChars rest headerLength
  pure { status := status, headers := parseRawHeaders rawHeaders, body := body }

def parseStatusEnvelope (raw : String) : Except String JsonPostResponse :=
  if raw.startsWith envelopeMagic then
    parseVersionedEnvelope raw
  else
    parseLegacyEnvelope raw

def headerHasLineBreak (value : String) : Bool :=
  value.contains "\n" || value.contains "\r"

def encodeHeader? (header : String × String) : Option String :=
  let name := header.fst.trimAscii.toString
  let value := header.snd
  if name.isEmpty || headerHasLineBreak name || headerHasLineBreak value then
    none
  else
    some (name ++ ": " ++ value)

def encodeHeaders (headers : Array (String × String)) : String :=
  String.intercalate "\n" (headers.toList.filterMap encodeHeader?)

def requestResponse (config : RequestConfig) : IO JsonPostResponse := do
  let raw ← requestRaw
    config.method
    config.url
    (config.authorization.getD "")
    (config.body.getD "")
    (config.noProxy.getD "")
    config.userAgent
    (encodeHeaders config.headers)
    config.timeoutSeconds
    config.connectTimeoutSeconds
    config.maxResponseBytes
  match parseStatusEnvelope raw with
  | .ok response => pure response
  | .error err => throw (IO.userError err)

def requestAwsEventStreamJsonResponse (config : RequestConfig) : IO JsonPostResponse := do
  let raw ← requestAwsEventStreamJsonRaw
    config.method
    config.url
    (config.authorization.getD "")
    (config.body.getD "")
    (config.noProxy.getD "")
    config.userAgent
    (encodeHeaders config.headers)
    config.timeoutSeconds
    config.connectTimeoutSeconds
    config.maxResponseBytes
  match parseStatusEnvelope raw with
  | .ok response => pure response
  | .error err => throw (IO.userError err)

def hasHeaderNameCI (headers : Array (String × String)) (name : String) : Bool :=
  headers.any fun (headerName, _) => headerName.toLower == name.toLower

def withDefaultHeader
    (headers : Array (String × String))
    (name value : String) : Array (String × String) :=
  if hasHeaderNameCI headers name then
    headers
  else
    headers.push (name, value)

def postJsonResponse (config : JsonPostConfig) (payload : String) : IO JsonPostResponse := do
  let headers :=
    withDefaultHeader
      (withDefaultHeader config.headers "Content-Type" "application/json")
      "Accept"
      "application/json"
  requestResponse
    { method := "POST"
      url := config.url
      authorization :=
        if hasHeaderNameCI config.headers "Authorization" || config.apiKey.isEmpty then
          none
        else
          some ("Bearer " ++ config.apiKey)
      body := some payload
      timeoutSeconds := config.timeoutSeconds
      connectTimeoutSeconds := config.connectTimeoutSeconds
      maxResponseBytes := config.maxResponseBytes
      noProxy := config.noProxy
      userAgent := config.userAgent
      headers := headers
    }

def postJson (config : JsonPostConfig) (payload : String) : IO String := do
  pure (← postJsonResponse config payload).body

end LeanAgent.Http
