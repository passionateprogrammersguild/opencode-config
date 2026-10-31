# Plan to Spec Handoff

When the plan agent finishes a plan that spans more than one unit of work:

1. Save the final plan to `~/.opencode/plan/<topic>.md`. Include confirmed
   decisions and ground rules in the file itself. The spec-writer sees only this
   file, not the conversation.
2. Once the user confirms the plan is final, call the `spec-writer` subagent
   with only the plan path and a topic name. Do not paste the plan into the
   prompt.
3. Relay the spec-writer's summary and any open questions to the user. Answer
   open questions by updating the plan file, then call spec-writer again once.
4. Skip the handoff for single-file or trivial changes.
