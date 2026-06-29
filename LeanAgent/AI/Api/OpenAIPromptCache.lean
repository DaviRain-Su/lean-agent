namespace LeanAgent.AI.Api.OpenAIPromptCache

def maxKeyLength : Nat := 64

def clampKey (key : Option String) : Option String :=
  key.map fun value => String.ofList (value.toList.take maxKeyLength)

end LeanAgent.AI.Api.OpenAIPromptCache
