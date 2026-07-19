namespace LeanAgent.AI.Util.Headers

abbrev Header := String × String
abbrev ProviderHeader := String × Option String

def nameEq (a b : String) : Bool :=
  a.toLower == b.toLower

def insert (headers : Array Header) (header : Header) : Array Header :=
  (headers.filter fun (name, _) => !nameEq name header.fst).push header

def erase (headers : Array Header) (name : String) : Array Header :=
  headers.filter fun (headerName, _) => !nameEq headerName name

def merge (base override : Array Header) : Array Header :=
  override.foldl insert base

def mergeProvider (base : Array Header) (override : Array ProviderHeader) : Array Header :=
  override.foldl
    (fun headers (name, value) =>
      match value with
      | some value => insert headers (name, value)
      | none => erase headers name)
    base

def providerHeadersToArray (headers : Array ProviderHeader) : Array Header :=
  headers.filterMap fun (name, value) =>
    match value with
    | some value => some (name, value)
    | none => none

def providerHeadersToArray? (headers : Array ProviderHeader) : Option (Array Header) :=
  let result := providerHeadersToArray headers
  if result.isEmpty then none else some result

def headersToArray (headers : Array Header) : Array Header :=
  headers

/-- Case-insensitive lookup of a single header value (Pi Headers.get subset). -/
def get? (headers : Array Header) (name : String) : Option String :=
  headers.findSome? fun (headerName, value) =>
    if nameEq headerName name then some value else none

/-- All values for a header name (case-insensitive). -/
def getAll (headers : Array Header) (name : String) : Array String :=
  headers.filterMap fun (headerName, value) =>
    if nameEq headerName name then some value else none

/-- True when a header name is present (case-insensitive). -/
def has (headers : Array Header) (name : String) : Bool :=
  (get? headers name).isSome

end LeanAgent.AI.Util.Headers
