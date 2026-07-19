import Lean
import LeanAgent.Models

/-!
# Provider attribution headers (Pi `provider-attribution.ts` subset)

Host/provider matching + default attribution headers when telemetry is enabled.
-/

namespace LeanAgent.CodingAgent.ProviderAttribution

def openRouterHost : String := "openrouter.ai"
def nvidiaNimHost : String := "integrate.api.nvidia.com"
def cloudflareApiHost : String := "api.cloudflare.com"
def cloudflareAiGatewayHost : String := "gateway.ai.cloudflare.com"
def vercelGatewayHost : String := "ai-gateway.vercel.sh"

/-- Hostname match against baseUrl (Pi `matchesHost`). -/
def matchesHost (baseUrl : String) (expectedHost : String) : Bool :=
  -- crude parse: strip scheme, take up to first /
  let withoutScheme :=
    if baseUrl.startsWith "https://" then (baseUrl.drop 8).toString
    else if baseUrl.startsWith "http://" then (baseUrl.drop 7).toString
    else baseUrl
  let host :=
    match withoutScheme.splitOn "/" with
    | h :: _ =>
        match h.splitOn ":" with
        | hostOnly :: _ => hostOnly
        | [] => h
    | [] => withoutScheme
  host == expectedHost

def isOpenRouterModel (provider : String) (baseUrl : String) : Bool :=
  provider == "openrouter" || matchesHost baseUrl openRouterHost

def isNvidiaNimModel (provider : String) (baseUrl : String) : Bool :=
  provider == "nvidia" || matchesHost baseUrl nvidiaNimHost

def isCloudflareModel (provider : String) (baseUrl : String) : Bool :=
  provider == "cloudflare-workers-ai" ||
    provider == "cloudflare-ai-gateway" ||
    matchesHost baseUrl cloudflareApiHost ||
    matchesHost baseUrl cloudflareAiGatewayHost

def isVercelGatewayModel (provider : String) (baseUrl : String) : Bool :=
  provider == "vercel-ai-gateway" || matchesHost baseUrl vercelGatewayHost

/-- Pi default attribution headers (telemetry on). -/
def getDefaultAttributionHeaders
    (provider : String)
    (baseUrl : String)
    (telemetryEnabled : Bool := true) : List (String × String) :=
  if !telemetryEnabled then
    []
  else if isOpenRouterModel provider baseUrl then
    [ ("HTTP-Referer", "https://pi.dev")
    , ("X-OpenRouter-Title", "pi")
    , ("X-OpenRouter-Categories", "cli-agent")
    ]
  else if isNvidiaNimModel provider baseUrl then
    [ ("X-BILLING-INVOKE-ORIGIN", "Pi") ]
  else if isCloudflareModel provider baseUrl then
    [ ("User-Agent", "pi-coding-agent") ]
  else if isVercelGatewayModel provider baseUrl then
    [ ("http-referer", "https://pi.dev")
    , ("x-title", "pi")
    ]
  else
    []

/-- Session id header when present (Pi subset). -/
def getSessionHeaders
    (sessionId : Option String) : List (String × String) :=
  match sessionId with
  | some id => [ ("X-Session-Id", id) ]
  | none => []

/-- Merge attribution + session headers for a model id/provider/baseUrl. -/
def getProviderHeaders
    (provider : String)
    (baseUrl : String)
    (sessionId : Option String := none)
    (telemetryEnabled : Bool := true) : List (String × String) :=
  getDefaultAttributionHeaders provider baseUrl telemetryEnabled ++
    getSessionHeaders sessionId

/-- Host match (Pi subset). -/
def hostMatch (provider : String) (baseUrl : String) (host : String) : Bool := baseUrl.contains host

/-- Is OpenCode (Pi subset). -/
def isOpenCode (p : ProviderAttribution) (host : String) : Bool := host.contains "opencode"

end LeanAgent.CodingAgent.ProviderAttribution
