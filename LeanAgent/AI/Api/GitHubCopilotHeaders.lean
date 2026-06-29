import LeanAgent.AI.Types

namespace LeanAgent.AI.Api.GitHubCopilotHeaders

def isUserMessage : LeanAgent.AI.Message → Bool
  | .user _ => true
  | _ => false

def inferCopilotInitiator (messages : Array LeanAgent.AI.Message) : String :=
  match messages.back? with
  | some message => if isUserMessage message then "user" else "agent"
  | none => "user"

def contentHasImage (content : Array LeanAgent.AI.ContentBlock) : Bool :=
  content.any fun
    | .image _ => true
    | _ => false

def hasCopilotVisionInput (messages : Array LeanAgent.AI.Message) : Bool :=
  messages.any fun
    | .user message => contentHasImage message.content
    | .toolResult message => contentHasImage message.content
    | .assistant _ => false

def buildCopilotDynamicHeaders
    (messages : Array LeanAgent.AI.Message)
    (hasImages : Bool) : Array (String × String) :=
  let base :=
    #[ ("X-Initiator", inferCopilotInitiator messages)
     , ("Openai-Intent", "conversation-edits")
     ]
  if hasImages then
    base.push ("Copilot-Vision-Request", "true")
  else
    base

end LeanAgent.AI.Api.GitHubCopilotHeaders
