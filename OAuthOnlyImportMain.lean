import LeanAgent.AI.OAuth

def main : IO Unit := do
  LeanAgent.AI.OAuth.resetOAuthProviders
  let providers ← LeanAgent.AI.OAuth.getOAuthProviders
  let ids := providers.map (·.id)
  let expected :=
    #["anthropic", "github-copilot", "openai-codex"]
  for providerId in expected do
    if !ids.contains providerId then
      throw (IO.userError s!"missing OAuth built-in provider after LeanAgent.AI.OAuth import: {providerId}")
  let successHtml := LeanAgent.AI.OAuth.oauthSuccessHtml "ok"
  if !successHtml.contains "Authentication successful" then
    throw (IO.userError "missing OAuth success page helper after LeanAgent.AI.OAuth import")
  if !LeanAgent.AI.OAuth.PKCE.isBase64UrlNoPadding "abcXYZ09-_" then
    throw (IO.userError "missing OAuth PKCE helper after LeanAgent.AI.OAuth import")
  let _ : LeanAgent.AI.OAuth.LocalCallback.ListenErrorBehavior := .disable
  IO.println (String.intercalate "," ids.toList)
