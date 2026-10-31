---
description: Check llama-server health and resource usage
---
!`echo "=== llama-server health ==="
if curl -s -m 3 http://127.0.0.1:8080/v1/models > /dev/null 2>&1; then
    echo "✅ Server responding on port 8080"
    MODEL_ID=$(curl -s http://127.0.0.1:8080/v1/models | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "?")
    echo "   Model: $MODEL_ID"
else
    echo "❌ Server not responding on port 8080"
    echo "   Start it with /llama-switch <number>"
    exit 1
fi

echo ""
echo "=== Resource usage ==="
PIDS=$(pgrep -f 'llama-server.*8080' | tr '\n' ' ')
if [ -n "$PIDS" ]; then
    ps -o pid=,%cpu=,%mem=,rss=,command= -p ${PIDS} 2>/dev/null | while read -r pid cpu mem rss rest; do
        RSS_MB=$(awk -v kb="$rss" 'BEGIN{printf "%.1f", kb/1024}')
        echo "  PID: $pid  CPU: ${cpu}%  MEM: ${mem}%  RSS: ${RSS_MB} MB"
    done
else
    echo "  (no llama-server process found on port 8080)"
fi

echo ""
echo "=== Context usage ==="
CTX=$(curl -s http://127.0.0.1:8080/v1/models | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['meta'].get('n_ctx','?'))" 2>/dev/null || echo "?")
echo "   Context: $CTX"

echo ""
echo "=== Disk usage ==="
du -sh ~/models/ 2>/dev/null || echo "  ~/models/ not found"
df -h / | tail -1 | { read -r fs size used avail use mount; echo "  Disk: $used used / $size total"; }
`