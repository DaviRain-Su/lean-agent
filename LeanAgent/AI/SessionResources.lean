namespace LeanAgent.AI.SessionResources

abbrev SessionResourceCleanup := Option String → IO Unit

structure RegisteredCleanup where
  id : Nat
  cleanup : SessionResourceCleanup

initialize cleanupRegistry : IO.Ref (Array RegisteredCleanup) ← IO.mkRef #[]
initialize nextCleanupId : IO.Ref Nat ← IO.mkRef 0

def registerSessionResourceCleanup (cleanup : SessionResourceCleanup) : IO (IO Unit) := do
  let id ← nextCleanupId.get
  nextCleanupId.set (id + 1)
  cleanupRegistry.modify (fun cleanups => cleanups.push { id := id, cleanup := cleanup })
  pure (cleanupRegistry.modify (fun cleanups => cleanups.filter (fun registered => registered.id != id)))

def renderCleanupErrors (errors : Array IO.Error) : String :=
  let messages := errors.map (fun err => err.toString)
  "Failed to cleanup session resources:\n" ++ String.intercalate "\n" messages.toList

def cleanupSessionResources (sessionId : Option String := none) : IO Unit := do
  let cleanups ← cleanupRegistry.get
  let mut errors := #[]
  for registered in cleanups do
    try
      registered.cleanup sessionId
    catch err =>
      errors := errors.push err
  if !errors.isEmpty then
    throw (IO.userError (renderCleanupErrors errors))

end LeanAgent.AI.SessionResources
