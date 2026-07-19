import LeanAgent.AI.Util.Abort

namespace LeanAgent.Http

/--
POST a JSON payload to an HTTPS endpoint using the native libcurl C API.

This is intentionally a small transport boundary: Lean code owns request JSON and
response parsing, while native code owns TLS, proxy handling, and HTTP transport.
It does not execute the `curl` command-line program.
-/
@[extern "lean_agent_http_request"]
opaque requestRaw
  (method url authorization body noProxy userAgent extraHeaders abortFlagPath : @& String)
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
  (method url authorization body noProxy userAgent extraHeaders abortFlagPath : @& String)
  (timeoutSeconds connectTimeoutSeconds : UInt32)
  (maxResponseBytes : UInt64)
  : IO String

/-- Poll an abort signal and write `1` to `path` when aborted (for native XFERINFO). -/
partial def watchAbortFlag
    (signal : LeanAgent.AI.Util.Abort.AbortSignal)
    (path : System.FilePath)
    (remaining : Nat := 12000) : IO Unit := do
  if ← signal.isAborted then
    IO.FS.writeFile path "1"
  else
    match remaining with
    | 0 => pure ()
    | n + 1 =>
        IO.sleep 10
        watchAbortFlag signal path n

/-- Run an HTTP call with optional cooperative mid-transfer abort via flag file. -/
def withAbortFlagPath
    {α : Type}
    (signal? : Option LeanAgent.AI.Util.Abort.AbortSignal)
    (action : String → IO α) : IO α := do
  match signal? with
  | none => action ""
  | some signal =>
      if ← signal.isAborted then
        throw (IO.userError LeanAgent.AI.Util.Abort.requestAbortedMessage)
      let (_handle, path) ← IO.FS.createTempFile
      try
        IO.FS.writeFile path "0"
        let task ← IO.asTask (watchAbortFlag signal path)
        try
          action path.toString
        finally
          -- Best-effort stop: flip flag so watcher exits soon if still looping after request.
          try IO.FS.writeFile path "1" catch _ => pure ()
          let _ ← IO.wait task
      finally
        try IO.FS.removeFile path catch _ => pure ()

structure RequestConfig where
  method : String := "GET"
  url : String
  authorization : Option String := none
  body : Option String := none
  signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none
  timeoutSeconds : UInt32 := 120
  connectTimeoutSeconds : UInt32 := 30
  maxResponseBytes : UInt64 := 33554432
  noProxy : Option String := none
  userAgent : String := "lean-agent/0.1.0"
  headers : Array (String × String) := #[]

structure JsonPostConfig where
  url : String
  apiKey : String
  signal : Option LeanAgent.AI.Util.Abort.AbortSignal := none
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

def rethrowUnlessAbort (err : IO.Error) : IO α := do
  if LeanAgent.AI.Util.Abort.isAbortErrorMessage err.toString then
    throw (IO.userError LeanAgent.AI.Util.Abort.requestAbortedMessage)
  else
    throw err

def requestResponse (config : RequestConfig) : IO JsonPostResponse := do
  LeanAgent.AI.Util.Abort.throwIfAborted config.signal
  try
    withAbortFlagPath config.signal fun abortFlagPath => do
      let raw ← requestRaw
        config.method
        config.url
        (config.authorization.getD "")
        (config.body.getD "")
        (config.noProxy.getD "")
        config.userAgent
        (encodeHeaders config.headers)
        abortFlagPath
        config.timeoutSeconds
        config.connectTimeoutSeconds
        config.maxResponseBytes
      match parseStatusEnvelope raw with
      | .ok response => pure response
      | .error err =>
          if LeanAgent.AI.Util.Abort.isAbortErrorMessage err then
            throw (IO.userError LeanAgent.AI.Util.Abort.requestAbortedMessage)
          else
            throw (IO.userError err)
  catch err =>
    rethrowUnlessAbort err

def requestAwsEventStreamJsonResponse (config : RequestConfig) : IO JsonPostResponse := do
  LeanAgent.AI.Util.Abort.throwIfAborted config.signal
  try
    withAbortFlagPath config.signal fun abortFlagPath => do
      let raw ← requestAwsEventStreamJsonRaw
        config.method
        config.url
        (config.authorization.getD "")
        (config.body.getD "")
        (config.noProxy.getD "")
        config.userAgent
        (encodeHeaders config.headers)
        abortFlagPath
        config.timeoutSeconds
        config.connectTimeoutSeconds
        config.maxResponseBytes
      match parseStatusEnvelope raw with
      | .ok response => pure response
      | .error err =>
          if LeanAgent.AI.Util.Abort.isAbortErrorMessage err then
            throw (IO.userError LeanAgent.AI.Util.Abort.requestAbortedMessage)
          else
            throw (IO.userError err)
  catch err =>
    rethrowUnlessAbort err

def hasHeaderNameCI (headers : Array (String × String)) (name : String) : Bool :=
  headers.any fun (headerName, _) => headerName.toLower == name.toLower

def withDefaultHeader
    (headers : Array (String × String))
    (name value : String) : Array (String × String) :=
  if hasHeaderNameCI headers name then
    headers
  else
    headers.push (name, value)

def jsonPostRequestConfig (config : JsonPostConfig) (payload : String) : RequestConfig :=
  let headers :=
    withDefaultHeader
      (withDefaultHeader config.headers "Content-Type" "application/json")
      "Accept"
      "application/json"
  { method := "POST"
    url := config.url
    authorization :=
      if hasHeaderNameCI config.headers "Authorization" || config.apiKey.isEmpty then
        none
      else
        some ("Bearer " ++ config.apiKey)
    body := some payload
    signal := config.signal
    timeoutSeconds := config.timeoutSeconds
    connectTimeoutSeconds := config.connectTimeoutSeconds
    maxResponseBytes := config.maxResponseBytes
    noProxy := config.noProxy
    userAgent := config.userAgent
    headers := headers
  }

def postJsonResponse (config : JsonPostConfig) (payload : String) : IO JsonPostResponse := do
  requestResponse (jsonPostRequestConfig config payload)

def postJson (config : JsonPostConfig) (payload : String) : IO String := do
  pure (← postJsonResponse config payload).body

/-! Progressive HTTP (Lean-driven curl multi pump). Yields body chunks while in flight. -/

@[extern "lean_agent_http_progressive_start"]
opaque progressiveStartRaw
  (method url authorization body noProxy userAgent extraHeaders abortFlagPath : @& String)
  (timeoutSeconds connectTimeoutSeconds : UInt32)
  (maxResponseBytes : UInt64)
  (awsEventStreamMode : UInt8)
  : IO USize

@[extern "lean_agent_http_progressive_pump"]
opaque progressivePumpRaw (session : USize) : IO String

@[extern "lean_agent_http_progressive_close"]
opaque progressiveCloseRaw (session : USize) : IO Unit

inductive ProgressiveStep where
  | pending (chunk : String)
  | done (response : JsonPostResponse)
  | error (message : String)

def parseProgressivePump (raw : String) : Except String ProgressiveStep := do
  if raw.startsWith "P\n" then
    pure (.pending (raw.drop 2).toString)
  else if raw.startsWith "D\n" then
    match parseStatusEnvelope (raw.drop 2).toString with
    | .ok response => pure (.done response)
    | .error err => throw err
  else if raw.startsWith "E\n" then
    pure (.error (raw.drop 2).toString)
  else
    throw s!"unknown progressive pump payload prefix: {raw.take 8}"

/--
Run an HTTP request with progressive body callbacks.

`onChunk` receives newly arrived body bytes (may be empty on idle pumps).
When the native multi pump finishes in the same step as the last body bytes,
those trailing bytes are still delivered to `onChunk` before returning (the
native `D` envelope alone would otherwise skip them).

Mid-transfer abort via `config.signal` is supported. Final response includes
status, headers, and the full assembled body.
-/
def requestResponseProgressive
    (config : RequestConfig)
    (onChunk : String → IO Unit := fun _ => pure ())
    (awsEventStreamMode : Bool := false) : IO JsonPostResponse := do
  LeanAgent.AI.Util.Abort.throwIfAborted config.signal
  withAbortFlagPath config.signal fun abortFlagPath => do
    let session ← progressiveStartRaw
      config.method
      config.url
      (config.authorization.getD "")
      (config.body.getD "")
      (config.noProxy.getD "")
      config.userAgent
      (encodeHeaders config.headers)
      abortFlagPath
      config.timeoutSeconds
      config.connectTimeoutSeconds
      config.maxResponseBytes
      (if awsEventStreamMode then (1 : UInt8) else (0 : UInt8))
    let emittedLenRef ← IO.mkRef (0 : Nat)
    try
      let rec loop (guard : Nat) : IO JsonPostResponse := do
        LeanAgent.AI.Util.Abort.throwIfAborted config.signal
        match guard with
        | 0 => throw (IO.userError "progressive HTTP pump exceeded iteration budget")
        | n + 1 =>
            let raw ← progressivePumpRaw session
            match parseProgressivePump raw with
            | .error err => throw (IO.userError err)
            | .ok (.error msg) =>
                if LeanAgent.AI.Util.Abort.isAbortErrorMessage msg then
                  throw (IO.userError LeanAgent.AI.Util.Abort.requestAbortedMessage)
                else
                  throw (IO.userError msg)
            | .ok (.pending chunk) =>
                if !chunk.isEmpty then
                  emittedLenRef.modify (· + chunk.length)
                  onChunk chunk
                loop n
            | .ok (.done response) =>
                -- Non-AWS: deliver trailing raw body bytes only present in the final envelope.
                -- AWS mode already delivered NDJSON events via pending pumps; body is full JSON array.
                if !awsEventStreamMode then
                  let emitted ← emittedLenRef.get
                  if response.body.length > emitted then
                    let rest := response.body.drop emitted |>.toString
                    if !rest.isEmpty then
                      onChunk rest
                pure response
      loop 100000
    finally
      progressiveCloseRaw session

/-- JSON POST using the progressive multi pump (SSE / streaming protocols). -/
def postJsonResponseProgressive
    (config : JsonPostConfig)
    (payload : String)
    (onChunk : String → IO Unit := fun _ => pure ()) : IO JsonPostResponse := do
  requestResponseProgressive (jsonPostRequestConfig config payload) onChunk

/--
Progressive AWS event-stream request.

`onEventJson` receives complete event objects as NDJSON lines (one JSON object per line)
as frames finish decoding mid-transfer. Final `response.body` is the full JSON array.
-/
def requestAwsEventStreamJsonResponseProgressive
    (config : RequestConfig)
    (onEventJson : String → IO Unit := fun _ => pure ()) : IO JsonPostResponse := do
  requestResponseProgressive config
    (fun chunk => do
      -- Chunk is NDJSON: one complete JSON object per line.
      for line in chunk.splitOn "\n" do
        let line := line.trimAscii.toString
        if !line.isEmpty then
          onEventJson line)
    (awsEventStreamMode := true)

end LeanAgent.Http
