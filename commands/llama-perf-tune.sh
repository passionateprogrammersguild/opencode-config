#!/bin/bash
# llama-perf-tune.sh - Performance tuning toolkit for llama.cpp on Mac mini
# Usage: llama-perf-tune [option]
# Options:
#   status    - Show current server status and throughput
#   bench     - Run a quick benchmark of prompt processing + generation
#   tune      - Calculate optimal --threads and --parallel settings
#   kill-procs - Kill non-essential processes consuming CPU
#   restart   - Restart llama-server with optimized settings
#   help      - Show this help message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat << HELP
llama-perf-tune - Performance tuning tools for llama.cpp on Mac mini

Usage: /llama-perf-tune <command>

Commands:
  status     - Show current server status, throughput, and bottlenecks
  bench      - Run a quick benchmark (prompt + generation throughput)
  tune       - Calculate optimal --threads and --parallel settings
  kill-procs - Kill non-essential processes consuming CPU
  restart    - Restart llama-server with optimized settings
  help       - Show this help message

Examples:
  /llama-perf-tune status
  /llama-perf-tune bench
  /llama-perf-tune tune
  /llama-perf-tune kill-procs
HELP
}

do_status() {
    echo "============================================================"
    echo "📊 LLAMA.PERF STATUS — Current Performance Snapshot"
    echo "============================================================"
    echo ""

    LLAMA_PID=$(pgrep -f 'llama-server.*8080' | head -1)
    if [ -n "$LLAMA_PID" ]; then
        echo "Server: ✅ RUNNING (PID=$LLAMA_PID)"
        ps -p $LLAMA_PID -o pid,%cpu,%mem,etime,command 2>/dev/null | tail -1

        # Check if parallel > 1 using pgrep output
        PARALLEL=$(ps -p $LLAMA_PID -o command= 2>/dev/null | grep -oE '\-\-parallel [0-9]+' | awk '{print $2}')
        if [ "$PARALLEL" = "4" ]; then
            echo "✅ parallel=4 (optimized)"
        elif [ "$PARALLEL" = "1" ]; then
            echo "❌ parallel=1 (not optimized — restart with parallel=4)"
        else
            echo "parallel=$PARALLEL"
        fi

        # Check server health
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:8080/v1/models 2>/dev/null || echo "timeout")
        if [ "$CODE" = "200" ]; then
            echo "✅ Server responding on port 8080"
        else
            echo "❌ Server not responding (HTTP $CODE)"
        fi

        echo ""
        echo "--- Recent Throughput ---"
        tail -20 ~/llama-server.log 2>/dev/null | grep "slot print_timing" | grep -E "prompt eval time|eval time" | tail -2 || echo "(no recent generations)"
    else
        echo "Server: 🔴 NOT RUNNING"
        echo "Start with: /llama-switch <number>"
    fi

    echo ""
    echo "--- System Load ---"
    LOAD1=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
    : "${LOAD1:=N/A}"
    NCPUS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "4")
    echo "Load avg (1m): ${LOAD1} | Cores: $NCPUS"

    if [ "$LOAD1" != "N/A" ] && [ -n "$LOAD1" ]; then
        LOAD_INT=${LOAD1%.*}
        if [ "$LOAD_INT" -gt "$NCPUS" ] 2>/dev/null; then
            echo "❌ System OVERLOADED — load avg $LOAD1 > $NCPUS"
        else
            echo "✅ Load within acceptable range"
        fi
    fi

    echo ""
}

do_bench() {
    LLAMA_PID=$(pgrep -f 'llama-server.*8080' | head -1)
    if [ -z "$LLAMA_PID" ]; then
        echo "❌ llama-server is NOT running. Start with /llama-switch 1"
        exit 1
    fi

    echo "============================================================"
    echo "🏃 LLAMA.PERF BENCH — Quick Performance Test"
    echo "============================================================"
    echo ""

    # Read the loaded model id from the server (matches whatever /llama-switch loaded)
    MODEL_ID=$(curl -s -m 3 http://127.0.0.1:8080/v1/models 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null)
    if [ -z "$MODEL_ID" ]; then
        echo "❌ Could not read the loaded model from the server"
        exit 1
    fi

    # Test: Generate response and measure throughput
    echo "Test: Generating response (20 tokens) on $MODEL_ID ..."
    START=$(date +%s)
    RESULT=$(curl -s -m 300 "http://127.0.0.1:8080/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$MODEL_ID\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello, optimize this response for speed\"}],\"max_tokens\":20,\"temperature\":0.7}")
    END=$(date +%s)

    if [ -z "$RESULT" ]; then
        echo "❌ No response from the server (request failed or timed out)"
        exit 1
    fi

    if ! python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception as e:
    print('❌ Invalid response from server:', e)
    raise SystemExit(1)
t = d.get('timings', {})
gen_tps = t.get('predicted_per_second', 0) or 0
pp_tps = t.get('prompt_per_second', 0) or 0
total_ms = (t.get('prompt_ms', 0) or 0) + (t.get('predicted_ms', 0) or 0)
print(f'Total time: {total_ms/1000:.1f}s')
print(f'Generation: {gen_tps:.1f} t/s')
print(f'Prompt: {pp_tps:.1f} t/s')
" <<< "$RESULT"; then
        exit 1
    fi

    ELAPSED=$((END - START))
    echo ""
    echo "✅ Benchmark complete"
    echo "   Total response time: ${ELAPSED}s"
    echo "   If generation < 5 t/s: server needs tuning"
    echo "   If generation > 10 t/s: performance is good"
    echo "   If generation > 20 t/s: performance is excellent"
}

do_tune() {
    echo "============================================================"
    echo "⚙️  LLAMA.PERF TUNE — Optimal Configuration Calculator"
    echo "============================================================"
    echo ""
    echo "System: $(sysctl -n machdep.cpu.brand_string)"
    PHYSICAL=$(sysctl -n hw.physicalcpu)
    LOGICAL=$(sysctl -n hw.logicalcpu)
    echo "Physical cores: $PHYSICAL"
    echo "Logical cores: $LOGICAL"
    TOTAL_MEM=$(sysctl -n hw.memsize | awk '{printf "%.1f", $1/1024/1024/1024}')
    echo "RAM: ${TOTAL_MEM}GB"
    echo ""

    echo "--threads recommendations:"
    echo "  For llama.cpp on Intel Haswell:"
    echo "  Recommended: $LOGICAL threads (all logical cores)"
    echo "  AVX2 is available on this CPU — native builds use it"
    echo ""

    echo "--parallel recommendations:"
    echo "  --parallel=1  (single request, lowest latency)"
    echo "  --parallel=2  (balanced)"
    echo "  --parallel=4  (maximum concurrency, matches core count)"
    echo "  Current config: parallel=4 (from llama.md)"
    echo ""

    echo "Memory model sizing for ${TOTAL_MEM}GB system:"
    echo "  <500MB → ✅ No issues"
    echo "  500MB-1.5GB → ✅ Good performance"
    echo "  1.5GB-3GB → ⚠️ Monitor memory"
    echo "  >3GB → ❌ Risk of swap thrashing"
}

do_kill_procs() {
    echo "============================================================"
    echo "💥 LLAMA.PERF KILL — CPU Process Cleanup"
    echo "============================================================"
    echo ""

    echo "--- Processes consuming >5% CPU (excluding system) ---"
    ps aux | grep -v grep | grep -vE 'llama-server|_windowserver|launchd|kernel|opencode|zsh|bash|top|ps|grep' | \
    awk '$3 > 5 {printf "  PID=%-6s CPU=%5s%% MEM=%5s%%  %s\n", $2, $3, $4, $11}'

    echo ""
    echo "⚠️  Check for any unexpected high-CPU processes above."
    echo "   The system load of $(sysctl -n vm.loadavg | awk '{print $2}') may be from:"
    echo "   - Terminal.app, WindowServer, or other UI processes"
    echo "   - Background macOS services"
    echo "   - llama-server itself (normal to consume ~15-25% CPU)"
}

do_restart() {
    echo "============================================================"
    echo "🔄 LLAMA.PERF RESTART — Optimized Server Restart"
    echo "============================================================"
    echo ""

    # Stop existing server
    echo "Stopping current llama-server..."
    pkill -f 'llama-server.*8080' 2>/dev/null && echo "  Stopped" || echo "  Not running"
    sleep 2

    # Resolve the model: prefer the configured enabled model, else the first available .gguf
    MODEL_FILE=$(python3 -c "
import json, os, glob
cfg = os.path.expanduser('~/.config/opencode/opencode.json')
try:
    with open(cfg) as f: data = json.load(f)
except Exception:
    data = {}
models = data.get('providers', {}).get('llama.cpp', {}).get('models', {})
def norm(name):
    key = name[:-5] if name.endswith('.gguf') else name
    return ''.join(c if c.isalnum() or c in '._-' else '-' for c in key).lower()
enabled = {k for k, v in models.items() if not v.get('disabled')}
for f in sorted(glob.glob(os.path.expanduser('~/models/*.gguf'))):
    if norm(os.path.basename(f)) in enabled:
        print(f)
        break
else:
    files = sorted(glob.glob(os.path.expanduser('~/models/*.gguf')))
    if files:
        print(files[0])
" 2>/dev/null)

    if [ -z "$MODEL_FILE" ]; then
        echo "❌ No model files found in ~/models"
        exit 1
    fi

    MODEL_NAME=$(basename "$MODEL_FILE")
    echo "Starting with optimized settings..."

    if [ -x "$HOME/tools/llama.cpp/build/bin/llama-server" ]; then
        LLAMA_BIN="$HOME/tools/llama.cpp/build/bin/llama-server"
    else
        LLAMA_BIN=/opt/local/bin/llama-server
    fi

    KEY=$(echo "$MODEL_NAME" | sed -E 's/\.gguf$//; s/[^A-Za-z0-9._-]+/-/g' | tr 'A-Z' 'a-z')

    nohup "$LLAMA_BIN" -m "$MODEL_FILE" --host 127.0.0.1 --port 8080 \
      --ctx-size 32768 --parallel 4 --threads 4 --jinja --alias "$KEY" \
      > ~/llama-server.log 2>&1 </dev/null &

    PID=$!
    echo "Started llama-server (PID=$PID)"

    echo "Waiting for server to be ready..."
    for i in $(seq 1 30); do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:8080/v1/models 2>/dev/null || echo "000")
        if [ "$CODE" = "200" ]; then
            echo "✅ Server ready after ${i}s"
            break
        fi
        sleep 2
    done

    echo ""
    echo "✅ Server restarted with optimized settings"
    echo "   Model: $MODEL_NAME"
    echo "   parallel=4 (was 1)"
    echo "   threads=4 (matches logical cores)"
    echo ""
    echo "Run '/llama-perf-tune bench' to verify throughput"
}

# Main
case "${1:-help}" in
    status)  do_status ;;
    bench)   do_bench ;;
    tune)    do_tune ;;
    kill-procs) do_kill_procs ;;
    restart) do_restart ;;
    help)    show_help ;;
    *)       show_help ;;
esac