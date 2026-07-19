import Lean

/-!
# Coding-agent EventBus (Pi `packages/coding-agent/src/core/event-bus.ts`)

Synchronous channel pub/sub used by coding-agent runtime extensions.
Lean uses `IO.Ref` registries instead of Node `EventEmitter`.
Handlers that throw are swallowed (logged) so one bad listener cannot break emit.
-/

namespace LeanAgent.CodingAgent.EventBus

abbrev Handler := Lean.Json → IO Unit

structure HandlerEntry where
  active : IO.Ref Bool
  handler : Handler

structure EventBus where
  handlersRef : IO.Ref (Array (String × HandlerEntry))

/-- Pi `createEventBus`. -/
def createEventBus : IO EventBus := do
  pure { handlersRef := ← IO.mkRef #[] }

/-- Pi `emit(channel, data)`. -/
def EventBus.emit (bus : EventBus) (channel : String) (data : Lean.Json) : IO Unit := do
  let entries ← bus.handlersRef.get
  for (ch, entry) in entries do
    if ch == channel then
      if ← entry.active.get then
        try
          entry.handler data
        catch err =>
          IO.eprintln s!"Event handler error ({channel}): {err}"

/-- Pi `on(channel, handler)` — returns unsubscribe action. -/
def EventBus.on (bus : EventBus) (channel : String) (handler : Handler) : IO (IO Unit) := do
  let active ← IO.mkRef true
  let entry : HandlerEntry := { active := active, handler := handler }
  bus.handlersRef.modify (·.push (channel, entry))
  pure (active.set false)

/-- Pi `clear()` — remove all listeners. -/
def EventBus.clear (bus : EventBus) : IO Unit := do
  let entries ← bus.handlersRef.get
  for (_, entry) in entries do
    entry.active.set false
  bus.handlersRef.set #[]

/-- Active handler count on a channel (tests). -/
def EventBus.activeCount (bus : EventBus) (channel : String) : IO Nat := do
  let entries ← bus.handlersRef.get
  let mut n := 0
  for (ch, entry) in entries do
    if ch == channel && (← entry.active.get) then
      n := n + 1
  pure n

end LeanAgent.CodingAgent.EventBus
