namespace LeanAgent.AI.Api.OpenAIPromptCache

/-- Pi `OPENAI_PROMPT_CACHE_KEY_MAX_LENGTH`. -/
def maxKeyLength : Nat := 64

/--
Pi `clampOpenAIPromptCacheKey`: keep at most 64 Unicode scalar values
(`Array.from(key).slice(0, 64).join("")` in JS).
-/
def clampKey (key : Option String) : Option String :=
  key.map fun value =>
    let scalars := value.toList
    if scalars.length ≤ maxKeyLength then
      value
    else
      String.ofList (scalars.take maxKeyLength)

end LeanAgent.AI.Api.OpenAIPromptCache
