---
description: Rebuild the model list from ~/models/*.gguf and sync opencode.json (V2 format)
---
!`set -e
if [ -n "$ZSH_VERSION" ]; then unsetopt bgnice; fi
setopt nullglob 2>/dev/null || true
if [ -x "$HOME/tools/llama.cpp/build/bin/llama-server" ]; then
    LLAMA_BIN="$HOME/tools/llama.cpp/build/bin/llama-server"
else
    LLAMA_BIN=/opt/local/bin/llama-server
fi
CTX=32768
THREADS=4
PARALLEL=4

echo "Rebuilding model list from ~/models/*.gguf ..."
MODELS=$(for f in "$HOME"/models/*.gguf; do [ -f "$f" ] && basename "$f"; done)
if [ -z "$MODELS" ]; then
    echo "No .gguf files in $HOME/models"
    exit 1
fi

# Sync opencode.json — OpenCode V2 provider format
python3 << 'PYEOF'
import json, os, glob

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
llama["package"] = "@opencode/ai/providers/openai-compatible"
llama["settings"] = {"baseURL": "http://127.0.0.1:8080/v1"}
llama.pop("npm", None)
llama.pop("options", None)

models = llama.setdefault("models", {})
for f in sorted(glob.glob(os.path.expanduser("~/models/*.gguf"))):
    fname = os.path.basename(f)
    key = fname.replace(".gguf", "")
    key = "".join(c if c.isalnum() or c in "._-" else "-" for c in key).lower()
    models[key] = {
        "name": fname + " (local)",
        "modelID": key,
        "capabilities": {"tools": True, "input": ["text"], "output": ["text"]},
        "limit": {"context": 32768, "output": 8192},
        "disabled": False,
    }
provs["llama.cpp"] = llama
with open(cfg, "w") as f: json.dump(data, f, indent=2)
print("Synced opencode.json (V2 package format) for:", len(models), "models")
PYEOF

# Update models/index.json
python3 << 'PYEOF'
import json, os, glob, subprocess
idx = os.path.expanduser("~/models/index.json")
data = {
    "registry_version": 2,
    "models": []
}
try:
    running = subprocess.run(["pgrep", "-fl", "llama-server.*8080"], capture_output=True, text=True).stdout
except Exception:
    running = ""
for f in sorted(glob.glob(os.path.expanduser("~/models/*.gguf"))):
    fname = os.path.basename(f)
    data["models"].append({
        "file": fname,
        "provider": "llama.cpp",
        "tags": [],
        "loaded": fname in running,
    })
with open(idx, "w") as f: json.dump(data, f, indent=2)
print("Updated models/index.json with", len(data["models"]), "entries")
PYEOF

echo "✅ Model registry synced."
`