---
description: Benchmark llama-server performance
---
!`if [ -z "$1" ]; then
    echo "Usage: /llama-bench <prompt>"
    echo "Example: /llama-bench 'Explain quantum computing in 3 sentences'"
    exit 1
fi

export BENCH_PROMPT="$1"
python3 << 'PYEOF'
import json, os, urllib.request, time

prompt = os.environ.get("BENCH_PROMPT", "").strip()
if not prompt:
    print("Empty prompt")
    raise SystemExit(1)

try:
    with urllib.request.urlopen("http://127.0.0.1:8080/v1/models", timeout=5) as r:
        model_id = json.load(r)["data"][0]["id"]
except Exception as e:
    print("❌ llama-server not reachable:", e)
    raise SystemExit(1)

payload = json.dumps({
    "model": model_id,
    "messages": [{"role": "user", "content": prompt}],
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
    print(f"❌ HTTP {e.code}:", e.read().decode()[:500])
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
print(f"=== Benchmark Results ===")
print(f"Model: {model_id}")
print(f"Total time: {elapsed:.1f}s")
print(f"Prompt tokens: {t.get('prompt_n', '?')} | Prompt eval: {pp_tps if pp_tps else '?'} t/s")
print(f"Generation tokens: {t.get('predicted_n', '?')} | Generation: {gen_tps if gen_tps else '?'} t/s")
print(f"Prompt+Gen tokens: {t.get('prompt_n', 0) + t.get('predicted_n', 0)}")
PYEOF
`