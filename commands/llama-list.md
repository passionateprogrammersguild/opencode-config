---
description: List available models in ~/models with status
---
!`setopt nullglob 2>/dev/null || true
echo "=== Available models in $HOME/models ==="
for f in "$HOME"/models/*.gguf; do
    [ -f "$f" ] || continue
    NAME=$(basename "$f")
    SIZE=$(du -h "$f" | cut -f1)
    # Check if this is the currently loaded model
    LOADED=""
    if pgrep -f "llama-server.*$NAME" > /dev/null 2>&1; then
        LOADED=" ✅ (loaded)"
    fi
    echo "  $NAME  (${SIZE})${LOADED}"
done
echo ""
echo "=== Currently running llama-server ==="
PIDS=$(pgrep -f 'llama-server.*8080' | tr '\n' ' ')
if [ -n "$PIDS" ]; then
    ps -o pid=,command= -p ${PIDS} 2>/dev/null | while read -r pid rest; do
        MODEL=$(echo "$rest" | grep -oE '\-m [^ ]+' | cut -d' ' -f2)
        echo "  PID: $pid  Model: $(basename "$MODEL")"
    done
else
    echo "  (not running)"
fi
`