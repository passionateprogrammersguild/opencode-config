#!/bin/bash
# llama-perf-diagnose.sh - Diagnose performance bottlenecks on Mac mini for llama.cpp
# Usage: llama-perf-diagnose
#
# Checks for:
#   - System overload (high load average)
#   - Memory pressure (swap usage)
#   - CPU contention
#   - llama-server configuration issues
#   - Model size appropriateness

echo "============================================================"
echo "🔍 LLAMA.PERF DIAGNOSTIC — System Performance Analysis"
echo "   $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# System info
echo "--- System Info ---"
echo "Model:        $(sysctl -n hw.model)"
echo "CPU:          $(sysctl -n machdep.cpu.brand_string)"
echo "Cores (phys): $(sysctl -n hw.physicalcpu)"
echo "Cores (log):  $(sysctl -n hw.logicalcpu)"
echo "RAM:          $(sysctl -n hw.memsize | awk '{printf "%.1f GB", $1/1024/1024/1024}')"
echo ""

# Check system load (macOS: vm.loadavg)
echo "--- System Load ---"
LOAD=$(sysctl -n vm.loadavg 2>/dev/null)
LOAD1=$(echo "$LOAD" | awk '{print $2}')
LOAD5=$(echo "$LOAD" | awk '{print $3}')
LOAD15=$(echo "$LOAD" | awk '{print $4}')
: "${LOAD1:=N/A}" : "${LOAD5:=N/A}" : "${LOAD15:=N/A}"
NCPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "4")

echo "Load Average: 1m=${LOAD1} | 5m=${LOAD5} | 15m=${LOAD15}"
echo "Logical CPUs: $NCPUS"

if [ "$LOAD1" != "N/A" ] && [ -n "$LOAD1" ] && [ "$(echo "$LOAD1 > 0" | bc -l 2>/dev/null)" = "1" ]; then
    LOAD_INT=${LOAD1%.*}
    if [ "$LOAD_INT" -gt "$NCPUS" ] 2>/dev/null; then
        echo "❌ WARNING: Load average ($LOAD1) exceeds CPU count ($NCPUS) — system is OVERLOADED"
        echo "   Recommendation: Stop non-essential processes or reduce llama-server threads"
    elif [ -n "$LOAD5" ] && [ "$(echo "$LOAD5 > $(echo "$NCPUS * 0.8" | bc -l 2>/dev/null)" | bc -l 2>/dev/null)" = "1" ]; then
        echo "⚠️  CAUTION: Load average ($LOAD1) is high (>80% of CPU count)"
        echo "   Monitor closely; consider reducing thread count"
    else
        echo "✅ Load is within acceptable range"
    fi
else
    echo "⚠️  Load data unavailable"
fi
echo ""

# Check memory pressure (macOS-friendly, using vm_stat)
echo "--- Memory Pressure ---"
PAGES_FREE=$(vm_stat | awk '/^Pages free:/ {gsub(/\./,"",$3); print $3}')
PAGES_ACTIVE=$(vm_stat | awk '/^Pages active:/ {gsub(/\./,"",$3); print $3}')
PAGES_INACTIVE=$(vm_stat | awk '/^Pages inactive:/ {gsub(/\./,"",$3); print $3}')
PAGES_SPECULATIVE=$(vm_stat | awk '/^Pages speculative:/ {gsub(/\./,"",$3); print $3}')
PAGES_WIRED=$(vm_stat | awk '/^Pages wired down:/ {gsub(/\./,"",$4); print $4}')
: "${PAGES_ACTIVE:=0}" : "${PAGES_INACTIVE:=0}" : "${PAGES_WIRED:=0}" : "${PAGES_FREE:=0}" : "${PAGES_SPECULATIVE:=0}"

TOTAL_PAGES=$((PAGES_ACTIVE + PAGES_INACTIVE + PAGES_WIRED + PAGES_FREE + PAGES_SPECULATIVE))
TOTAL_MEM_GB=$((TOTAL_PAGES * 4096 / 1024 / 1024 / 1024))
USED_MEM_GB=$(( (PAGES_ACTIVE + PAGES_WIRED) * 4096 / 1024 / 1024 / 1024))
FREE_MEM_GB=$((PAGES_FREE * 4096 / 1024 / 1024 / 1024))

echo "Total RAM: ${TOTAL_MEM_GB} GB"
echo "Active+Wired: ${USED_MEM_GB} GB"
echo "Free: ${FREE_MEM_GB} GB"

if [ "$FREE_MEM_GB" -lt 2 ] 2>/dev/null; then
    echo "❌ CRITICAL: Free RAM < 2GB — risk of swap thrashing"
    echo "   Recommendation: Use smaller model or restart server"
elif [ "$FREE_MEM_GB" -lt 4 ] 2>/dev/null; then
    echo "⚠️  WARNING: Free RAM < 4GB — monitor memory usage"
else
    echo "✅ Sufficient free RAM"
fi

# Check swap usage
echo ""
echo "--- Swap Health ---"
SWAP_USAGE=$(sysctl -n vm.swapusage 2>/dev/null)
echo "vm.swapusage: $SWAP_USAGE"
if [ -n "$SWAP_USAGE" ]; then
    SWAP_USED_VAL=$(echo "$SWAP_USAGE" | grep -oE 'used = [0-9.]+M' | grep -oE '[0-9.]+')
    if [ -n "$SWAP_USED_VAL" ] && [ "$(echo "$SWAP_USED_VAL > 1024" | bc -l 2>/dev/null)" = "1" ] 2>/dev/null; then
        echo "❌ CRITICAL: Heavy swap usage (${SWAP_USED_VAL}MB) — will cause severe slowdown"
        echo "   Recommendation: Stop llama-server, close apps, restart with smaller model"
    else
        echo "✅ Minimal swap usage"
    fi
fi
echo ""

# Check llama-server process
echo "--- llama-server Process ---"
LLAMA_PID=$(pgrep -f 'llama-server.*8080' | head -1)
if [ -n "$LLAMA_PID" ]; then
    echo "✅ Running (PID=$LLAMA_PID)"
    ps -p $LLAMA_PID -o pid,%cpu,%mem,etime,command 2>/dev/null | tail -1
    # macOS: count threads with ps -M
    THREAD_COUNT=$(ps -M -p $LLAMA_PID 2>/dev/null | tail -n +2 | grep -c .)
    echo "Approximate thread count: $THREAD_COUNT"

    # Check if parallel > 1
    CMDLINE=$(ps -p $LLAMA_PID -o command= 2>/dev/null | grep -oE '\-\-parallel [0-9]+' | awk '{print $2}')
    echo "Parallel: ${CMDLINE:-not set}"

    # Check server health
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:8080/v1/models 2>/dev/null || echo "timeout")
    if [ "$CODE" = "200" ]; then
        echo "✅ Server responding on port 8080"
    else
        echo "❌ Server not responding (HTTP $CODE)"
    fi

    # Show throughput from last server log
    echo ""
    echo "--- Recent Throughput ---"
    tail -20 ~/llama-server.log 2>/dev/null | grep "slot print_timing" | grep -E "prompt eval time|eval time" | tail -2 || echo "(no recent generations in log)"
else
    echo "🔴 llama-server is NOT running"
    echo "   Start with: /llama-switch <number> or /llama start <number>"
fi
echo ""

# Model size assessment
echo "--- Model Size Assessment ---"
for f in "$HOME"/models/*.gguf; do
    [ -f "$f" ] || continue
    SIZE_GB=$(stat -f%z "$f" | awk '{printf "%.1f", $1/1024/1024/1024}')
    NAME=$(basename "$f")
    SIZE_MB=$(stat -f%z "$f" | awk '{printf "%.0f", $1/1024/1024}')
    if [ "$SIZE_MB" -lt 500 ]; then
        REC="OK"
    elif [ "$SIZE_MB" -lt 1500 ]; then
        REC="OK"
    elif [ "$SIZE_MB" -lt 3000 ]; then
        REC="⚠️ (may be slow on dual-core)"
    else
        REC="❌ (too large for this CPU)"
    fi
    printf "   %-50s %.1fGB %s\n" "$NAME" "$SIZE_GB" "$REC"
done
echo ""

# OpenCode provider config check
echo "--- OpenCode llama.cpp Provider Config ---"
if [ -f ~/.config/opencode/opencode.json ]; then
    python3 << 'PY'
import json, os
cfg = os.path.expanduser("~/.config/opencode/opencode.json")
with open(cfg) as f:
    c = json.load(f)
prov = c.get("providers", {}).get("llama.cpp", {})
pkg = prov.get("package")
if pkg == "@opencode/ai/providers/openai-compatible":
    print("✅ package: @opencode/ai/providers/openai-compatible (V2)")
else:
    print(f"❌ package: '{pkg}'")
    print("   Fix: Run /llama-sync to regenerate in V2 format")
base = prov.get("settings", {}).get("baseURL")
print(f"   baseURL: {base or 'MISSING'}")
models = prov.get("models", {})
enabled = [k for k,v in models.items() if not v.get("disabled")]
disabled = [k for k,v in models.items() if v.get("disabled")]
print(f"   Enabled models: {len(enabled)} | Disabled: {len(disabled)}")
for k in enabled:
    ctx = models[k].get("limit", {}).get("context", "unset")
    print(f"     • {k} (ctx={ctx})")
if disabled:
    print(f"   Disabled (likely >5GB): {', '.join(disabled[:3])}")
PY
else
    echo "❌ opencode.json not found"
fi
echo ""

echo "============================================================"
echo "📋 DIAGNOSIS SUMMARY"
echo "============================================================"
echo "If llama-server shows 0.53 t/s, primary causes are:"
echo "  1. --parallel=1 limits to single request (FIX: parallel=4)"
echo "  2. System overload from other processes (FIX: kill non-essentials)"
echo "  3. Memory pressure causing swap thrashing (FIX: use smaller model)"
echo "  4. Background processes competing for CPU (FIX: stop or nice them)"
echo ""
echo "Recommended fix: /llama-switch <number> (now starts with parallel=4)"
echo "Then run: /llama-perf to monitor throughput improvement"
echo "============================================================"