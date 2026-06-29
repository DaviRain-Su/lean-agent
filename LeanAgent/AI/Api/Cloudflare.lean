namespace LeanAgent.AI.Api.Cloudflare

def accountIdEnv : String := "CLOUDFLARE_ACCOUNT_ID"
def gatewayIdEnv : String := "CLOUDFLARE_GATEWAY_ID"

def workersAIBaseUrl : String :=
  "https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/v1"

def aiGatewayCompatBaseUrl : String :=
  "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/compat"

def aiGatewayOpenAIBaseUrl : String :=
  "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/openai"

def aiGatewayAnthropicBaseUrl : String :=
  "https://gateway.ai.cloudflare.com/v1/{CLOUDFLARE_ACCOUNT_ID}/{CLOUDFLARE_GATEWAY_ID}/anthropic"

end LeanAgent.AI.Api.Cloudflare
