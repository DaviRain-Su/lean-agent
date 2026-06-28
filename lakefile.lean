import Lake
open Lake DSL

package lean_agent where
  version := v!"0.1.0"

lean_lib LeanAgent where

@[default_target]
lean_exe «lean-agent» where
  root := `Main

@[test_driver]
lean_exe «lean-agent-test» where
  root := `Tests
