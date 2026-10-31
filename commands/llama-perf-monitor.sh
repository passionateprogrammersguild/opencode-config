#!/bin/bash
# llama-perf-monitor.sh - Real-time performance dashboard for llama-server + Mac system
# Usage: llama-perf-monitor [interval_seconds]
#
# Displays:
#   - System load average (1/5/15 min)
#   - CPU utilization breakdown
#   - Memory (RAM) usage and pressure
#   - Swap usage (critical for performance)
#   - llama-server CPU/mem per-process and per-thread
#   - Top CPU-consuming processes

INTERVAL=${1:-5}

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "============================================================"
echo "⚡ LLAMA.PERF — Real-time Performance Monitor"
echo "   $(date '+%Y-%m-%d %H:%M:%S') | Refresh: ${INTERVAL}s"
echo "============================================================"
echo ""

while true; do
    # System metrics
    LOAD=$(sysctl -n vm.loadavg 2>/dev/null)
    LOAD1=$(echo "$LOAD" | awk '{print $2}')
    LOAD5=$(echo "$LOAD" | awk '{print $3}')
    LOAD15=$(echo "$LOAD" | awk '{print $4}')
    : "${LOAD1:=0}" : "${LOAD5:=0}" : "${LOAD15:=0}"
    NCPUS=$(getconf _NPROCESSORS_ONLN)

    # CPU usage (user/sys/idle) — macOS top
    CPU_LINE=$(top -l 1 | grep "CPU usage:")
    CPU_USER=$(echo "$CPU_LINE" | grep -oE '[0-9.]+% user' | grep -oE '[0-9.]+')
    CPU_SYS=$(echo "$CPU_LINE" | grep -oE '[0-9.]+% sys' | grep -oE '[0-9.]+')
    CPU_IDLE=$(echo "$CPU_LINE" | grep -oE '[0-9.]+% idle' | grep -oE '[0-9.]+')
    : "${CPU_USER:=0}" : "${CPU_SYS:=0}" : "${CPU_IDLE:=0}"

    # Memory (macOS vm_stat)
    MEM_SUMMARY=$(vm_stat | awk -v page=4096 '
        /^Pages free:/       {gsub(/\./,"",$3); free=$3}
        /^Pages active:/     {gsub(/\./,"",$3); active=$3}
        /^Pages inactive:/   {gsub(/\./,"",$3); inactive=$3}
        /^Pages speculative:/{gsub(/\./,"",$3); spec=$3}
        /^Pages wired down:/ {gsub(/\./,"",$4); wired=$4}
        END {
            printf "%s|%s|%s|%s",
                (active+wired)*page/1073741824,
                inactive*page/1073741824,
                wired*page/1073741824,
                (free+inactive+spec)*page/1073741824
        }')
    MEM_USED=$(echo "$MEM_SUMMARY" | cut -d'|' -f1)
    MEM_INACTIVE=$(echo "$MEM_SUMMARY" | cut -d'|' -f2)
    MEM_WIRED=$(echo "$MEM_SUMMARY" | cut -d'|' -f3)
    MEM_AVAILABLE=$(echo "$MEM_SUMMARY" | cut -d'|' -f4)
    : "${MEM_USED:=0}" : "${MEM_INACTIVE:=0}" : "${MEM_WIRED:=0}" : "${MEM_AVAILABLE:=0}"

    TOTAL_MEM_GB=$(sysctl -n hw.memsize | awk '{printf "%.1f", $1/1024/1024/1024}')

    # llama-server process
    LLAMA_PID=$(pgrep -f 'llama-server.*8080' | head -1)

    printf "🔷 %s | LOAD: %.2f/%.2f/%.2f (cores=%s)\n" "$(date '+%H:%M:%S')" "$LOAD1" "$LOAD5" "$LOAD15" "$NCPUS"

    if [ -n "$LLAMA_PID" ]; then
        # Process CPU and mem
        PROCS=$(ps -o pid,ppid,%cpu,%mem,command -p $LLAMA_PID | tail -1)
        LLAMA_CPU=$(echo "$PROCS" | awk '{print $3}')
        LLAMA_MEM=$(echo "$PROCS" | awk '{print $4}')

        # Sum all threads' CPU: main line (%CPU = field 4), thread lines (field 3)
        THREAD_CPU=$(ps -M -p $LLAMA_PID | awk 'NR>1 { if (NF > 8) c=$4; else c=$3; gsub(/%/,"",c); sum+=c } END {printf "%.1f", sum}')

        printf "🐫 llama-server (PID=%s): CPU=%s%% | MEM=%s%% | thread_total=%s%%\n" "$LLAMA_PID" "$LLAMA_CPU" "$LLAMA_MEM" "$THREAD_CPU"

        # Check server health
        HEALTH=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:8080/v1/models 2>/dev/null || echo "timeout")
        if [ "$HEALTH" = "200" ]; then
            printf "✅ %-20s Server healthy (HTTP 200)\n" ""
        else
            printf "⚠️  %-22s Server unreachable (HTTP %s)\n" "" "$HEALTH"
        fi

        # Check throughput from last print_timing line in the log
        LAST_TG=$(tail -30 ~/llama-server.log 2>/dev/null | grep "print_timing" | grep -v "prompt eval time" | grep "eval time" | tail -1)
        if [ -n "$LAST_TG" ]; then
            TG_TPS=$(echo "$LAST_TG" | grep -oE '[0-9.]+ tokens per second' | tail -1 | awk '{print $1}')
            TG_TOKENS=$(echo "$LAST_TG" | grep -oE '[0-9]+ tokens' | head -1)
            printf "📊 %-20s generation %s t/s (%s, last batch)\n" "" "${TG_TPS:-?}" "${TG_TOKENS:-?}"
        fi
    else
        printf "🔴 %-22s llama-server NOT RUNNING\n" ""
    fi

    printf "💾 %-20s Used: %.1fGB | Inactive: %.1fGB | Wired: %.1fGB | Available: ~%.1fGB (of %sGB)\n" "" "$MEM_USED" "$MEM_INACTIVE" "$MEM_WIRED" "$MEM_AVAILABLE" "$TOTAL_MEM_GB"

    printf "🖥️  %-22s CPU: %s%% user / %s%% sys / %s%% idle\n" "" "$CPU_USER" "$CPU_SYS" "$CPU_IDLE"

    echo ""
    sleep "$INTERVAL"
done
