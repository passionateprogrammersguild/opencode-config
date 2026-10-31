---
description: Validate llama-server vs opencode.json — check model, context, and template compatibility
---
!`set -e
echo "=== llama-server status ==="
if curl -s -m 3 http://127.0.0.1:8080/v1/models > /dev/null 2>&1; then
    echo "✅ Server responding on port 8080"
    MODEL_ID=$(curl -s http://127.0.0.1:8080/v1/models | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "?")
    echo "   Model: $MODEL_ID"
    # Check context
    CTX=$(curl -s http://127.0.0.1:8080/v1/models | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['meta'].get('n_ctx','?'))" 2>/dev/null || echo "?")
    echo "   Context: $CTX"
else
    echo "❌ Server not responding on port 8080"
    echo "   Start it with /llama-switch <number>"
    exit 1
fi

echo ""
echo "=== opencode.json check ==="
CFG="$HOME/.config/opencode/opencode.json"
if [ ! -f "$CFG" ]; then
    echo "❌ opencode.json not found at $CFG"
    exit 1
fi
python3 << 'PYEOF'
import json, os
cfg = os.path.expanduser("~/.config/opencode/opencode.json")
with open(cfg) as f: data = json.load(f)
llama = data.get("providers", {}).get("llama.cpp", {})
if not llama:
    print("❌ llama.cpp provider not configured")
    exit(1)
print("✅ llama.cpp provider configured")
print("   package:", llama.get("package"))
print("   baseURL:", llama.get("settings", {}).get("baseURL"))
models = llama.get("models", {})
print(f"   Models: {len(models)} registered")
for k, v in models.items():
    status = "✅ enabled" if not v.get("disabled") else "❌ disabled"
    print(f"     - {k}: {status}")
PYEOF

echo ""
echo "=== Template compatibility check ==="
# Test a simple prompt to see if the template works
TEST_PROMPT="Hello"
RESP=$(curl -s -m 30 -X POST http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL_ID\",\"messages\":[{\"role\":\"user\",\"content\":\"$TEST_PROMPT\"}],\"max_tokens\":5}" 2>&1 || true)
if [ -z "$RESP" ]; then
    echo "⚠️  No response from server (request timed out)"
elif echo "$RESP" | grep -q "Conversation roles must alternate"; then
    echo "❌ Template error: Mistral-style role alternation required"
    echo "   Use /llama-chat with --history to fix this"
elif echo "$RESP" | grep -q "error"; then
    echo "⚠️  Server returned error response"
    echo "$RESP" | head -c 200
    echo
else
    echo "✅ Template works correctly"
fi
`