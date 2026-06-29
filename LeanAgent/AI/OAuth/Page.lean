namespace LeanAgent.AI.OAuth

private def oauthLogoSvg : String :=
  "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 800 800\" aria-hidden=\"true\"><path fill=\"#fff\" fill-rule=\"evenodd\" d=\"M165.29 165.29 H517.36 V400 H400 V517.36 H282.65 V634.72 H165.29 Z M282.65 282.65 V400 H400 V282.65 Z\"/><path fill=\"#fff\" d=\"M517.36 400 H634.72 V634.72 H517.36 Z\"/></svg>"

private def replaceAll (text old replacement : String) : String :=
  String.intercalate replacement (text.splitOn old)

private def escapeHtml (value : String) : String :=
  replaceAll (replaceAll (replaceAll (replaceAll (replaceAll value
    "&" "&amp;")
    "<" "&lt;")
    ">" "&gt;")
    "\"" "&quot;")
    "'" "&#39;"

private structure OAuthPageOptions where
  title : String
  heading : String
  message : String
  details : Option String := none

private def renderOAuthPage (options : OAuthPageOptions) : String :=
  let title := escapeHtml options.title
  let heading := escapeHtml options.heading
  let message := escapeHtml options.message
  let details? := options.details.map escapeHtml
  let detailsHtml :=
    match details? with
    | some details => s!"    <div class=\"details\">{details}</div>"
    | none => ""
  String.intercalate "\n"
    [ "<!doctype html>"
    , "<html lang=\"en\">"
    , "<head>"
    , "  <meta charset=\"utf-8\" />"
    , "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />"
    , s!"  <title>{title}</title>"
    , "  <style>"
    , "    :root {"
    , "      --text: #fafafa;"
    , "      --text-dim: #a1a1aa;"
    , "      --page-bg: #09090b;"
    , "      --font-sans: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, \"Noto Sans\", sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\", \"Segoe UI Symbol\", \"Noto Color Emoji\";"
    , "      --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace;"
    , "    }"
    , "    * { box-sizing: border-box; }"
    , "    html { color-scheme: dark; }"
    , "    body {"
    , "      margin: 0;"
    , "      min-height: 100vh;"
    , "      display: flex;"
    , "      align-items: center;"
    , "      justify-content: center;"
    , "      padding: 24px;"
    , "      background: var(--page-bg);"
    , "      color: var(--text);"
    , "      font-family: var(--font-sans);"
    , "      text-align: center;"
    , "    }"
    , "    main {"
    , "      width: 100%;"
    , "      max-width: 560px;"
    , "      display: flex;"
    , "      flex-direction: column;"
    , "      align-items: center;"
    , "      justify-content: center;"
    , "    }"
    , "    .logo {"
    , "      width: 72px;"
    , "      height: 72px;"
    , "      display: block;"
    , "      margin-bottom: 24px;"
    , "    }"
    , "    h1 {"
    , "      margin: 0 0 10px;"
    , "      font-size: 28px;"
    , "      line-height: 1.15;"
    , "      font-weight: 650;"
    , "      color: var(--text);"
    , "    }"
    , "    p {"
    , "      margin: 0;"
    , "      line-height: 1.7;"
    , "      color: var(--text-dim);"
    , "      font-size: 15px;"
    , "    }"
    , "    .details {"
    , "      margin-top: 16px;"
    , "      font-family: var(--font-mono);"
    , "      font-size: 13px;"
    , "      color: var(--text-dim);"
    , "      white-space: pre-wrap;"
    , "      word-break: break-word;"
    , "    }"
    , "  </style>"
    , "</head>"
    , "<body>"
    , "  <main>"
    , s!"    <div class=\"logo\">{oauthLogoSvg}</div>"
    , s!"    <h1>{heading}</h1>"
    , s!"    <p>{message}</p>"
    , detailsHtml
    , "  </main>"
    , "</body>"
    , "</html>"
    ]

def oauthSuccessHtml (message : String) : String :=
  renderOAuthPage
    { title := "Authentication successful"
      heading := "Authentication successful"
      message }

def oauthErrorHtml (message : String) (details : Option String := none) : String :=
  renderOAuthPage
    { title := "Authentication failed"
      heading := "Authentication failed"
      message
      details }

end LeanAgent.AI.OAuth
