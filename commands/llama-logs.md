---
description: View llama-server log tail
---
!`LOG="$HOME/llama-server.log"
if [ ! -f "$LOG" ]; then
    echo "No log file found at $LOG"
    exit 1
fi
COUNT="$1"
COUNT="${COUNT:-50}"
case "$COUNT" in
    *[!0-9]*)
        echo "Invalid line count: $COUNT (must be a positive integer)"
        exit 1
        ;;
esac
if [ "$COUNT" -lt 1 ] 2>/dev/null; then
    echo "Invalid line count: $COUNT (must be >= 1)"
    exit 1
fi
echo "=== Last $COUNT lines of $LOG ==="
tail -n "$COUNT" "$LOG"
`