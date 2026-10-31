---
description: Switch the llama.cpp server to another local GGUF model and sync opencode.json (V2 format)
---
!`set -e
if [ -n "$ZSH_VERSION" ]; then unsetopt bgnice; fi  # zsh nices background jobs +5 by default — would cripple the server on this CPU
setopt nullglob 2>/dev/null || true  # bash/zsh-safe: empty ~/models globs expand to nothing
# Prefer the native AVX2 build (2-3x faster than the MacPorts baseline build on this Mac)
if [ -x "$HOME/tools/llama.cpp/build/bin/llama-server" ]; then
    LLAMA_BIN="$HOME/tools/llama.cpp/build/bin/llama-server"
else
    LLAMA_BIN=/opt/local/bin/llama-server
fi
CTX=32768
THREADS=4
PARALLEL=4

MODELS=$(for f in "$HOME"/models/*.gguf; do [ -f "$f" ] && basename "$f"; done)
if [ -z "$MODELS" ]; then
    echo "No .gguf files in $HOME/models"
    exit 1
fi
if [ -z "$1" ]; then
    echo "=== Available models in $HOME/models ==="
    echo "$MODELS" | nl -w4 -s') '
    echo ""
    echo "Usage: /llama-switch <number> | /llama-switch <filename>"
    exit 0
fi

case "$1" in
    *[!0-9]*) MODEL_NAME="$1" ;;
    *) MODEL_NAME=$(echo "$MODELS" | sed -n "$1p") ;;
esac

MODEL_FILE="$HOME/models/$MODEL_NAME"
if [ -z "$MODEL_NAME" ] || [ ! -f "$MODEL_FILE" ]; then
    echo "Model not found: $1 ($MODEL_FILE)"
    exit 1
fi

# Canonical model id (also used as the llama-server --alias and config modelID)
KEY=$(echo "$MODEL_NAME" | sed -E 's/\.gguf$//; s/[^A-Za-z0-9._-]+/-/g' | tr 'A-Z' 'a-z')

SIZE_BYTES=$(stat -f%z "$MODEL_FILE" 2>/dev/null)
SIZE_GB=$(awk -v n="${SIZE_BYTES:-0}" 'BEGIN{printf "%.1f", n/1073741824}')
if [ -n "$SIZE_GB" ] && [ 1 -eq "$(echo "$SIZE_GB > 5" | bc)" ] 2>/dev/null; then
    echo "⚠️  $MODEL_NAME is ${SIZE_GB}GB — likely too slow for interactive CPU use on this machine."
fi

echo "Stopping current llama-server..."
kill $(pgrep -f 'llama-server.*8080') 2>/dev/null || true
sleep 1

echo "Starting llama-server with $MODEL_NAME (ctx=$CTX, threads=$THREADS, parallel=$PARALLEL)..."
nohup "$LLAMA_BIN" -m "$MODEL_FILE" --host 127.0.0.1 --port 8080 \
  --ctx-size $CTX --parallel $PARALLEL --threads $THREADS --jinja --alias "$KEY" \
  > "$HOME"/llama-server.log 2>&1 </dev/null &
PID=$!

echo "Waiting for model to load..."
READY=0
for i in $(seq 1 120); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:8080/v1/models 2>/dev/null || true)
    if [ "$CODE" = "200" ]; then READY=1; echo "Model loaded (~$((i*2))s)"; break; fi
    if ! kill -0 $PID 2>/dev/null; then
        echo "❌ llama-server exited during startup. Last log lines:"
        tail -n 10 "$HOME"/llama-server.log
        exit 1
    fi
    sleep 2
done
if [ "$READY" != "1" ]; then
    echo "❌ Timeout waiting for server (240s). Check ~/llama-server.log"
    exit 1
fi

# Sync opencode.json — OpenCode V2 provider format
export MODEL_NAME KEY MODEL_FILE
python3 << 'PYEOF'
import json, os

cfg = os.path.expanduser("~/.config/opencode/opencode.json")
try:
    with open(cfg) as f: data = json.load(f)
except Exception:
    data = {}
provs = data.setdefault("providers", {})
llama = provs.get("llama.cpp") or {
    "name": "llama.cpp (local)",
    "package": "@opencode/ai/providers/openai-compatible",
    "settings": {"baseURL": "http://127.0.0.1:8080/v1"},
    "models": {},
}
# normalize any leftover V1 shape
llama["package"] = "@opencode/ai/providers/openai-compatible"
llama["settings"] = {"baseURL": "http://127.0.0.1:8080/v1"}
llama.pop("npm", None)
llama.pop("options", None)
models = llama.setdefault("models", {})
key = os.environ["KEY"]
models[key] = {
    "name": os.environ["MODEL_NAME"] + " (local)",
    "modelID": os.environ["KEY"],
    "capabilities": {"tools": True, "input": ["text"], "output": ["text"]},
    "limit": {"context": 32768, "output": 8192},
    "disabled": False,
}
provs["llama.cpp"] = llama
with open(cfg, "w") as f: json.dump(data, f, indent=2)
print("Synced opencode.json (V2 package format) for:", key)
PYEOF

# Also update the central model index
export MODEL_NAME
python3 << 'PYEOF'
import json, os
idx = os.path.expanduser("~/models/index.json")
try:
    with open(idx) as f: existing = json.load(f)
except Exception:
    existing = {}
existing["registry_version"] = 2
existing["models"] = [
    {"file": os.environ["MODEL_NAME"], "provider": "llama.cpp", "tags": [], "loaded": True}
]
with open(idx, "w") as f: json.dump(existing, f, indent=2)
print("Updated models/index.json")
PYEOF

# Template note for strict models (e.g. Mistral)
case "$KEY" in
    *mistral*)
        echo ""
        echo "ℹ️  Note: this model enforces strict user/assistant role alternation."
        echo "   Use /llama-chat --history '[{\"role\":\"user\",\"content\":\"...\"},{\"role\":\"assistant\",\"content\":\"...\"}]' '<text>'"
        echo "   or test with: /llama-evaluate"
        ;;
esac

echo "✅ Now serving: $MODEL_NAME  (model ref: llama.cpp/$KEY)"
echo "   Pick it in opencode with /models → llama.cpp/$KEY"
`