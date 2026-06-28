import Lake
open Lake DSL System

def homebrewCurlPrefix : String :=
  if System.Platform.target.startsWith "x86_64" then
    "/usr/local/opt/curl"
  else
    "/opt/homebrew/opt/curl"

def libcurlIncludeArgs : Array String :=
  if System.Platform.isOSX then
    #["-I", homebrewCurlPrefix ++ "/include"]
  else
    #[]

def libcurlLinkArgs : Array String :=
  if System.Platform.isOSX then
    #["-L" ++ homebrewCurlPrefix ++ "/lib", "-lcurl"]
  else
    #["-lcurl"]

package lean_agent where
  version := v!"0.1.0"
  moreLinkArgs := libcurlLinkArgs

input_file http_client.c where
  path := "native" / "http_client.c"
  text := true

target httpClient.o pkg : FilePath := do
  let srcJob ← http_client.c.fetch
  let oFile := pkg.buildDir / "native" / "http_client.o"
  let weakArgs := #["-I", (← getLeanIncludeDir).toString] ++ libcurlIncludeArgs
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
