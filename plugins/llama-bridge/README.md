# opencode-llama-bridge

Documentation plugin for the llama.cpp ↔ opencode integration. All functionality
lives in the `/llama*` commands; this plugin adds no hooks (it exists so the
bridge has a home and can gain V2 plugin hooks later).

## The one thing that matters (root cause of "invalid/unsupported package")

OpenCode **V2** requires the `package` field on custom providers:

```json
"providers": {
  "llama.cpp": {
    "package": "@opencode/ai/providers/openai-compatible",
    "settings": { "baseURL": "http://127.0.0.1:8080/v1" },
    "models": { "...": { "capabilities": { "tools": true } } }
  }
}
```

Do **not** use the V1 fields: `npm: "@ai-sdk/openai-compatible"` or
`npm: "@ai-sdk/openai"` — both raise `UnsupportedPackageError` in V2 even though
those strings appear inside the opencode binary. Also use `settings` (not
`options`) and `capabilities` (not `modalities`).

## Server flags that matter on this hardware (Intel i7-4578U, 2-core/4-thread, 16 GB)

- `--ctx-size 32768` — matches Qwen2.5-3B's native window. `--ctx-size 262144`
  allocates ~9 GB of KV cache on a 16 GB machine and collapses generation speed
  to ~2 t/s from swap thrashing.
- `--parallel 1` — one user, one slot; don't split the context window 4 ways.
- `--threads 4` — matches the 4 logical CPUs. 8 oversubscribes.
- `--jinja` — required for the model's real chat template, i.e. working tool
  calls for agentic use.
- `--alias <model-id>` — makes `/v1/models` report the same ID the opencode
  config uses.

## Tested and rejected on this hardware

- **Speculative decoding** (0.5B draft + 1.5B/3B main, `--spec-type draft-simple`): measured **0.7 t/s vs 10.05 t/s baseline** (14× slower) with `--spec-draft-n-max 16`; prompt processing also halved (30 → 9 t/s). The draft and main models compete for the same 2 cores and verification overhead dominates. Do not enable on this machine.
- **Metal / iGPU offload**: Intel Iris 5100 benched 1.37 t/s — no better than CPU. Left unused.

## Commands

| Command | Purpose |
| --- | --- |
| `/llama-switch <n\|filename>` | Restart server with a model + sync opencode.json (V2) |
| `/llama-sync` | Rebuild provider config from `~/models/*.gguf` |
| `/llama-evaluate` | Validate config ↔ server consistency + template compatibility |
| `/llama-chat <text>` | Direct prompt (with `--history` support for Mistral role alternation) |
| `/llama start/stop` | Raw server control without config sync |
| `/llama-list`, `/llama-download`, `/llama-remove`, `/llama-health`, `/llama-logs`, `/llama-bench` | Utilities |

## Mistral Role-Alternation Fix (Implemented)

Mistral-style GGUF templates enforce strict `user`/`assistant` alternation. If two user messages appear consecutively, or if the conversation starts with `assistant`, the Jinja template throws `Conversation roles must alternate`.

Fixes applied:
- **`~/bin/opencode_template_fix.py`**: Python helper that collapses consecutive same-role messages and inserts a placeholder when the conversation starts with `assistant`.
- **`/llama-chat.md`**: Uses `--history` JSON flag; automatically applies the `ensure_alternating()` transformation to the message list before sending.
- **`/llama-evaluate.md`**: Tests a sample prompt against the live server and reports if the alternation error occurs, suggesting `/llama-chat --history`.
- **`/llama-switch.md`**: After switching to a Mistral model, prints a reminder about role alternation.

Usage example:
```bash
/llama-chat --history '[{"role":"user","content":"hi"},{"role":"assistant","content":"hello"}]' "what next?"
```

## Model Registry (`~/models/index.json`)

Instead of hard-coding model IDs in `opencode.json`, `/llama-sync` writes a `index.json` that acts as the canonical registry. This makes it easier to add/remove models without touching the config file.