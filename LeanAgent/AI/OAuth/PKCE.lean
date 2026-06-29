namespace LeanAgent.AI.OAuth.PKCE

@[extern "lean_agent_pkce_random_verifier"]
opaque randomVerifierRaw (byteCount : UInt32) : IO String

@[extern "lean_agent_pkce_code_challenge"]
opaque codeChallenge (verifier : @& String) : IO String

structure PKCE where
  verifier : String
  challenge : String
deriving BEq

def defaultVerifierByteCount : UInt32 := 32

def generatePKCE (byteCount : UInt32 := defaultVerifierByteCount) : IO PKCE := do
  let verifier ← randomVerifierRaw byteCount
  let challenge ← codeChallenge verifier
  pure { verifier, challenge }

def isBase64UrlChar (char : Char) : Bool :=
  ('A' <= char && char <= 'Z') ||
    ('a' <= char && char <= 'z') ||
    ('0' <= char && char <= '9') ||
    char == '-' ||
    char == '_'

def isBase64UrlNoPadding (value : String) : Bool :=
  !value.isEmpty && value.toList.all isBase64UrlChar

end LeanAgent.AI.OAuth.PKCE
