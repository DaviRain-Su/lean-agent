import Lake
open Lake DSL System

def homebrewCurlPrefix : String :=
  if System.Platform.target.startsWith "x86_64" then
    "/usr/local/opt/curl"
  else
    "/opt/homebrew/opt/curl"

def homebrewOpenSSLPrefix : String :=
  if System.Platform.target.startsWith "x86_64" then
    "/usr/local/opt/openssl@3"
  else
    "/opt/homebrew/opt/openssl@3"

def libcurlIncludeArgs : Array String :=
  if System.Platform.isOSX then
    #["-I", homebrewCurlPrefix ++ "/include"]
  else
    #[]

def opensslIncludeArgs : Array String :=
  if System.Platform.isOSX then
    #["-I", homebrewOpenSSLPrefix ++ "/include"]
  else
    #[]

def libcurlLinkArgs : Array String :=
  if System.Platform.isOSX then
    #["-L" ++ homebrewCurlPrefix ++ "/lib", "-lcurl"]
  else
    #["-lcurl"]

def opensslLinkArgs : Array String :=
  if System.Platform.isOSX then
    #["-L" ++ homebrewOpenSSLPrefix ++ "/lib", "-lcrypto"]
  else
    #["-lcrypto"]

package lean_agent where
  version := v!"0.1.0"
  moreLinkArgs := libcurlLinkArgs ++ opensslLinkArgs

input_file http_client.c where
  path := "native" / "http_client.c"
  text := true

target httpClient.o pkg : FilePath := do
  let srcJob ← http_client.c.fetch
  let oFile := pkg.buildDir / "native" / "http_client.o"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString] ++ libcurlIncludeArgs ++ opensslIncludeArgs
  buildO oFile srcJob weakArgs #["-fPIC"] "cc" getLeanTrace

target libleanagenthttp pkg : FilePath := do
  let ffiO ← httpClient.o.fetch
  let name := nameToStaticLib "leanagenthttp"
  buildStaticLib (pkg.staticLibDir / name) #[ffiO]

lean_lib LeanAgent where
  moreLinkObjs := #[libleanagenthttp]

@[default_target]
lean_exe «lean-agent» where
  root := `Main

@[test_driver]
lean_exe «lean-agent-test» where
  root := `Tests

lean_exe «ai-import-smoke» where
  root := `AIOnlyImportMain

lean_exe «compat-import-smoke» where
  root := `CompatOnlyImportMain

lean_exe «oauth-import-smoke» where
  root := `OAuthOnlyImportMain
