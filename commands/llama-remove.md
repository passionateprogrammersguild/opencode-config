---
description: Remove a model from ~/models and sync opencode.json
---
!`setopt nullglob 2>/dev/null || true  # bash/zsh-safe: empty ~/models globs expand to nothing
if [ -z "$1" ]; then
    echo "Usage: /llama-remove <number> | /llama-remove <filename>"
    echo "Available models:"
    for f in "$HOME"/models/*.gguf; do [ -f "$f" ] && echo "  $(basename "$f")"; done
    exit 1
fi

MODELS=$(for f in "$HOME"/models/*.gguf; do [ -f "$f" ] && basename "$f"; done)
case "$1" in
    *[!0-9]*) MODEL_NAME="$1" ;;
    *) MODEL_NAME=$(echo "$MODELS" | sed -n "$1p") ;;
esac

MODEL_FILE="$HOME/models/$MODEL_NAME"
if [ -z "$MODEL_NAME" ] || [ ! -f "$MODEL_FILE" ]; then
    echo "Model not found: $MODEL_FILE"
    exit 1
fi

echo "Removing $MODEL_FILE ..."
rm -f "$MODEL_FILE"

# Sync opencode.json — remove the model entry keyed by the same canonical id used by /llama-switch and /llama-sync
export MODEL_NAME
python3 << 'PYEOF'
import json, os
cfg = os.path.expanduser("~/.config/opencode/opencode.json")
key = os.environ.get("MODEL_NAME", "").replace(".gguf", "")
key = "".join(c if c.isalnum() or c in "._-" else "-" for c in key).lower()
with open(cfg) as f: data = json.load(f)
llama = data.get("providers", {}).get("llama.cpp", {})
models = llama.get("models", {})
removed = models.pop(key, None)
with open(cfg, "w") as f: json.dump(data, f, indent=2)
print("Synced opencode.json (" + ("removed " if removed else "no entry for ") + key + ")")
PYEOF

echo "✅ Removed $MODEL_NAME"
`