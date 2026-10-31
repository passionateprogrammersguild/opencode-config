---
description: Send a prompt directly to llama-server (bypasses opencode provider) — good for quick tests
---
!`INPUT_FILE=$(mktemp) || exit 1
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE" << 'LLAMA_CHAT_INPUT_EOF'
$ARGUMENTS
LLAMA_CHAT_INPUT_EOF
export LLAMA_INPUT_FILE="$INPUT_FILE"

python3 << 'PYEOF'
import json, os, shlex, urllib.request, urllib.error, time, sys

# --- Mistral role-alternation fix helper ---
def ensure_alternating(messages: list) -> list:
    """Remove consecutive same-role messages to satisfy Mistral's template."""
    cleaned: list = []
    last_role = None
    for msg in messages:
        role = msg.get("role")
        if not role or role == "system":
            if role == "system" and not cleaned:
                cleaned.append(msg)
            continue
        if role == last_role:
            cleaned[-1]["content"] = msg.get("content", "")
        else:
            cleaned.append(dict(msg))
        last_role = role
    if cleaned and cleaned[0].get("role") == "assistant":
        cleaned.insert(0, {"role": "user", "content": "Begin conversation."})
    return cleaned

raw = ""
try:
    with open(os.environ.get("LLAMA_INPUT_FILE", "")) as f:
        raw = f.read().strip()
except Exception:
    raw = ""
if not raw:
    print("Usage: /llama-chat <text>")
    print('Example: /llama-chat "Hello, how are you?"')
    print()
    print("With history (for Mistral role alternation fix):")
    print('  /llama-chat --history "[{\\"role\\":\\"user\\",\\"content\\":\\"hi\\"},{\\"role\\":\\"assistant\\",\\"content\\":\\"hello\\"}]" "next message"')
    raise SystemExit(1)

# Parse "--history <json> <prompt...>" while preserving quoting (shlex)
try:
    tokens = shlex.split(raw)
except Exception:
    tokens = raw.split()

history_json = None
if tokens and tokens[0] == "--history":
    if len(tokens) < 3:
        print("⚠️  --history requires: /llama-chat --history '<json>' <prompt>")
        raise SystemExit(1)
    history_json = tokens[1]
    prompt = " ".join(tokens[2:])
else:
    prompt = " ".join(tokens)

try:
    with urllib.request.urlopen("http://127.0.0.1:8080/v1/models", timeout=5) as r:
        model_id = json.load(r)["data"][0]["id"]
except Exception as e:
    print("❌ llama-server not reachable on port 8080:", e)
    print("   Start it with /llama-switch <number>")
    raise SystemExit(1)

# Build messages with role-alternation fix
if history_json:
    try:
        history = json.loads(history_json)
        messages = ensure_alternating(history) + [{"role": "user", "content": prompt}]
    except Exception as e:
        print("⚠️  Invalid history JSON:", e)
        messages = [{"role": "user", "content": prompt}]
else:
    messages = [{"role": "user", "content": prompt}]

payload = json.dumps({
    "model": model_id,
    "messages": messages,
    "temperature": 0.7,
    "max_tokens": 256,
    "stream": False,
}).encode()

req = urllib.request.Request(
    "http://127.0.0.1:8080/v1/chat/completions",
    data=payload,
    headers={"Content-Type": "application/json"},
    method="POST",
)

t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=300) as resp:
        d = json.load(resp)
except urllib.error.HTTPError as e:
    err_body = e.read().decode()[:500]
    print(f"❌ HTTP {e.code}:", err_body)
    if "Conversation roles must alternate" in err_body:
        print()
        print("💡 Fix: Use /llama-chat --history '<json>' to ensure alternating roles")
        print("   Example: /llama-chat --history '[{\"role\":\"user\",\"content\":\"hi\"},{\"role\":\"assistant\",\"content\":\"hello\"}]' 'next message'")
    raise SystemExit(1)

msg = d.get("choices", [{}])[0].get("message", {})
content = (msg.get("content") or "").strip()
reasoning = (msg.get("reasoning_content") or "").strip()
t = d.get("timings", {})
gen_tps = t.get("predicted_per_second")
pp_tps = t.get("prompt_per_second")
elapsed = time.time() - t0

if content:
    print(content)
elif reasoning:
    print("(reasoning model spent tokens on reasoning — no final answer)")
    print(reasoning[-500:])
else:
    print("(empty response)")
print()
if gen_tps:
    print(f"— {elapsed:.1f}s total | prompt {(pp_tps or 0):.1f} t/s | generation {gen_tps:.1f} t/s | model: {model_id}")
else:
    print(f"— {elapsed:.1f}s total | model: {model_id}")
PYEOF
PY_EXIT=$?
rm -f "$INPUT_FILE"
trap - EXIT
exit $PY_EXIT
`