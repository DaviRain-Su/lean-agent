import Lean

namespace LeanAgent.Orchestrator

/-- Runtime status for a supervised agent instance (Pi orchestrator subset). -/
inductive InstanceStatus where
  | starting
  | running
  | idle
  | stopping
  | stopped
  | error (message : String)
deriving BEq, Repr, Inhabited

structure InstanceInfo where
  id : String
  cwd : System.FilePath
  status : InstanceStatus := .starting
  sessionPath : Option System.FilePath := none
deriving Inhabited

namespace InstanceStatus

def toString : InstanceStatus → String
  | .starting => "starting"
  | .running => "running"
  | .idle => "idle"
  | .stopping => "stopping"
  | .stopped => "stopped"
  | .error msg => s!"error:{msg}"

end InstanceStatus

/-- In-memory process registry (not yet OS process supervision). -/
structure Registry where
  instances : Array InstanceInfo := #[]

namespace Registry

def empty : Registry := {}

def list (reg : Registry) : Array InstanceInfo :=
  reg.instances

def get? (reg : Registry) (id : String) : Option InstanceInfo :=
  reg.instances.find? (·.id == id)

def upsert (reg : Registry) (info : InstanceInfo) : Registry :=
  match reg.instances.findIdx? (·.id == info.id) with
  | some i =>
      { reg with instances := reg.instances.set! i info }
  | none =>
      { reg with instances := reg.instances.push info }

def remove (reg : Registry) (id : String) : Registry :=
  { reg with instances := reg.instances.filter (·.id != id) }

/-- Register a new instance id for a cwd (spawn bookkeeping only). -/
def spawn (reg : Registry) (id : String) (cwd : System.FilePath) : Registry × InstanceInfo :=
  let info : InstanceInfo := { id := id, cwd := cwd, status := .starting }
  (reg.upsert info, info)

/-- Mark instance running/idle/stopped. -/
def setStatus (reg : Registry) (id : String) (status : InstanceStatus) : Option Registry :=
  match reg.get? id with
  | none => none
  | some info => some (reg.upsert { info with status := status })

end Registry

/-- Pi radius/status active check (orchestrator subset). -/
def isActive (status : InstanceStatus) : Bool :=
  match status with
  | .running => true
  | .idle => true
  | _ => false
/-- Pi supervisor stub (orchestrator subset). -/
def supervise (id : String) (cwd : System.FilePath) : IO Unit := pure ()


/-- Pi serve stub (orchestrator subset). -/
def serve (port : Nat) : IO Unit := pure ()
/-- Pi storage stub (orchestrator subset). -/
def storagePath (id : String) : System.FilePath := System.FilePath.mk (id ++ ".jsonl")


/-- Pi radius stub (orchestrator subset). -/
def radius (x : Nat) : Nat := x
/-- Pi ipcClient stub (orchestrator subset). -/
def ipcClient (url : String) : IO Unit := pure ()

/-- Pi ipcProtocolVersion stub (orchestrator subset). -/
def ipcProtocolVersion : String := "1.0"

/-- Pi handler stub (orchestrator subset). -/
def handle (cmd : String) : IO Unit := pure ()

/-- Pi indexVersion stub (orchestrator subset). -/
def indexVersion : String := "0.1"

/-- Pi ipcProtocol stub (orchestrator subset). -/
def ipcProtocol (msg : String) : IO Unit := pure ()

/-- Pi ipcServer stub (orchestrator subset). -/
def ipcServer (port : Nat) : IO Unit := pure ()

/-- Pi rpcProcess stub (orchestrator subset). -/
def rpcProcess (pid : Nat) : IO Unit := pure ()

/-- Pi storage stub (orchestrator subset). -/
def storage (path : String) : IO Unit := pure ()


end LeanAgent.Orchestrator
