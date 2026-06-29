import LeanAgent.AI.Util.ProviderEnv

namespace LeanAgent.AI.Util.Proxy

abbrev ProviderEnv := LeanAgent.AI.Util.ProviderEnv.ProviderEnv

structure ParsedUrl where
  protocol : String
  hostname : String
  port : Nat
deriving Repr, BEq

def unsupportedProxyProtocolMessage : String :=
  "Unsupported proxy protocol. SOCKS and PAC proxy URLs are not supported; use an HTTP or HTTPS proxy URL."

def defaultProxyPort : String → Nat
  | "ftp" => 21
  | "gopher" => 70
  | "http" => 80
  | "https" => 443
  | "ws" => 80
  | "wss" => 443
  | _ => 0

def firstSegment (value separator : String) : String :=
  match value.splitOn separator with
  | [] => value
  | head :: _ => head

def lastSegment (value separator : String) : String :=
  match (value.splitOn separator).reverse with
  | [] => value
  | head :: _ => head

def stripUrlPath (value : String) : String :=
  firstSegment (firstSegment (firstSegment value "/") "?") "#"

def parseHostPort (host : String) : String × Option Nat :=
  let host := lastSegment host "@"
  match (host.splitOn ":").reverse with
  | [] => (host, none)
  | portPart :: rest =>
      match portPart.toNat? with
      | some port => (String.intercalate ":" rest.reverse, some port)
      | none => (host, none)

def parseTargetUrl? (targetUrl : String) : Option ParsedUrl :=
  match targetUrl.splitOn "://" with
  | protocol :: restParts =>
      let rest := String.intercalate "://" restParts
      let hostPart := stripUrlPath rest
      if protocol.isEmpty || hostPart.isEmpty then
        none
      else
        let (hostname, explicitPort) := parseHostPort hostPart
        if hostname.isEmpty then
          none
        else
          let protocol := protocol.toLower
          some
            { protocol := protocol
              hostname := hostname.toLower
              port := explicitPort.getD (defaultProxyPort protocol)
            }
  | _ => none

def normalizeEnvValue? (value : Option String) : Option String :=
  LeanAgent.AI.Util.ProviderEnv.normalizeValue? value

def getProxyEnvValueWith
    (ambient : String → IO (Option String))
    (key : String)
    (env : ProviderEnv := #[]) : IO String := do
  let lowercaseKey := key.toLower
  let uppercaseKey := key.toUpper
  match normalizeEnvValue? (LeanAgent.AI.Util.ProviderEnv.scopedValue? env lowercaseKey) with
  | some value => pure value
  | none =>
      match normalizeEnvValue? (LeanAgent.AI.Util.ProviderEnv.scopedValue? env uppercaseKey) with
      | some value => pure value
      | none =>
          match normalizeEnvValue? (← ambient lowercaseKey) with
          | some value => pure value
          | none =>
              match normalizeEnvValue? (← ambient uppercaseKey) with
              | some value => pure value
              | none => pure ""

def getProxyEnvValue (key : String) (env : ProviderEnv := #[]) : IO String :=
  getProxyEnvValueWith (fun name => do pure (← IO.getEnv name)) key env

def splitNoProxy (noProxy : String) : List String :=
  noProxy.toList.map
    (fun char =>
      if char == ',' || char == '\n' || char == '\r' || char == '\t' then
        ' '
      else
        char)
    |> String.ofList
    |>.splitOn " "
    |>.filter (fun item => !item.isEmpty)

def dropLeadingStar (value : String) : String :=
  if value.startsWith "*" then
    (value.drop 1).toString
  else
    value

def noProxyTokenAllowsProxy (hostname : String) (port : Nat) (token : String) : Bool :=
  let (proxyHostname, proxyPort) := parseHostPort token
  if proxyPort.isSome && proxyPort != some port then
    true
  else if !(proxyHostname.startsWith ".") && !(proxyHostname.startsWith "*") then
    hostname != proxyHostname
  else
    !hostname.endsWith (dropLeadingStar proxyHostname)

def shouldProxyHostnameWithNoProxy (hostname : String) (port : Nat) (noProxy : String) : Bool :=
  let noProxy := noProxy.toLower.trimAscii.toString
  if noProxy.isEmpty then
    true
  else if noProxy == "*" then
    false
  else
    splitNoProxy noProxy |>.all (noProxyTokenAllowsProxy hostname.toLower port)

def shouldProxyHostnameWith
    (ambient : String → IO (Option String))
    (hostname : String)
    (port : Nat)
    (env : ProviderEnv := #[]) : IO Bool := do
  let noProxy ← getProxyEnvValueWith ambient "no_proxy" env
  pure (shouldProxyHostnameWithNoProxy hostname port noProxy)

def addProtocolIfMissing (protocol proxy : String) : String :=
  if proxy.contains "://" then proxy else protocol ++ "://" ++ proxy

def getProxyForUrlWith
    (ambient : String → IO (Option String))
    (targetUrl : String)
    (env : ProviderEnv := #[]) : IO String := do
  match parseTargetUrl? targetUrl with
  | none => pure ""
  | some parsed =>
      if !(← shouldProxyHostnameWith ambient parsed.hostname parsed.port env) then
        pure ""
      else
        let protocolProxy ← getProxyEnvValueWith ambient (parsed.protocol ++ "_proxy") env
        let allProxy ← getProxyEnvValueWith ambient "all_proxy" env
        let proxy := if protocolProxy.isEmpty then allProxy else protocolProxy
        pure (if proxy.isEmpty then "" else addProtocolIfMissing parsed.protocol proxy)

def getProxyForUrl (targetUrl : String) (env : ProviderEnv := #[]) : IO String :=
  getProxyForUrlWith (fun name => do pure (← IO.getEnv name)) targetUrl env

def resolveHttpProxyUrlForTargetWith
    (ambient : String → IO (Option String))
    (targetUrl : String)
    (env : ProviderEnv := #[]) : IO (Option String) := do
  let proxy ← getProxyForUrlWith ambient targetUrl env
  if proxy.isEmpty then
    pure none
  else
    match parseTargetUrl? proxy with
    | none => throw (IO.userError s!"Invalid proxy URL {proxy}")
    | some parsed =>
        if parsed.protocol != "http" && parsed.protocol != "https" then
          throw (IO.userError s!"{unsupportedProxyProtocolMessage} Got {parsed.protocol}:")
        else
          pure (some proxy)

def resolveHttpProxyUrlForTarget
    (targetUrl : String)
    (env : ProviderEnv := #[]) : IO (Option String) :=
  resolveHttpProxyUrlForTargetWith (fun name => do pure (← IO.getEnv name)) targetUrl env

end LeanAgent.AI.Util.Proxy
