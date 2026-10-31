# Model Cache Hygiene

The plan agent and build agent use different models. Every switch between them
discards the prompt cache and re-bills the entire conversation at the cache-write
rate (1.25x base input on Anthropic). Keep the number of switches as low as
possible.

## Rules

1. **Do not alternate between plan and build inside a single task.** Complete the
   whole planning pass first, then hand off to build once. If a second planning
   pass is genuinely required, batch all open questions and finish with a single
   switch back.

2. **Finish the plan before switching.** Do not toggle to build to "check
   something" and return to plan afterwards. Use read-only tools in plan mode
   instead.

3. **Never change `opencode.json`, MCP config, or installed skills during a long
   session.** Those edits change the system prompt and invalidate the cache for
   every message before them. Make config changes before starting a session, or
   start a new session immediately after.

4. **After a compaction, a server restart, or an idle gap of more than ~5
   minutes, expect a cold cache.** Prefer starting a new session over continuing
   a stale one when the remaining work is separable.

5. **Do not switch to ad-hoc router models** such as `openrouter/free` mid
   session. They do not preserve a cache and re-bill the full context on every
   request.

6. **JEV System One is cache-stable.** `openrouter/typesafe/jev-1.13` (routed through
   OpenRouter) uses structured outputs (not autoregressive strings) and can be used for
   decision-routing without invalidating the conversation cache, because it operates as a
   statistical classifier rather than a context-writing LLM. Use it for tier routing,
   quality gates, and independence checks without switching back to string-generation
   agents.
