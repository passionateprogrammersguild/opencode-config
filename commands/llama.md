---
description: Start or stop the llama.cpp server with optional model selection
---
!`if [ -n "$ZSH_VERSION" ]; then unsetopt bgnice; fi  # zsh nices background jobs +5 by default — would cripple the server on this CPU
setopt nullglob 2>/dev/null || true  # bash/zsh-safe: empty ~/models globs expand to nothing
# Prefer the native AVX2 build (2-3x faster than the MacPorts baseline build on this Mac)
if [ -x "$HOME/tools/llama.cpp/build/bin/llama-server" ]; then
    LLAMA_BIN="$HOME/tools/llama.cpp/build/bin/llama-server"
else
    LLAMA_BIN=/opt/local/bin/llama-server
fi
CTX=32768
THREADS=4
PARALLEL=4  # Optimized from 1 to 4 — matches 4 logical cores for maximum throughput
MODELS=$(for f in "$HOME"/models/*.gguf; do [ -f "$f" ] && basename "$f"; done)
 
if [ "$1" = "start" ]; then
    if [ -z "$2" ]; then
        echo "=== Available models in $HOME/models ==="
        echo "$MODELS" | nl -w4 -s') '
        echo ""
        echo "Usage: /llama start <number> | /llama start <filename>"
        echo "       /llama start <filename> --ctx <size> | /llama start <filename> <ctx-size>"
        echo "  ctx-size: context size (default: $CTX, must be > 0)"
        exit 0
    fi

    # Parse optional context size override before model selection
    # Supports: /llama start <model> --ctx <size>, /llama start <model> <size>,
    #           /llama start --ctx <size> <model>, /llama start <size> <model>
    CTX_ACTUAL=$CTX
    MODEL_ARG=""
    POSITIONAL_COUNT=0
    i=2
    while [ $i -le $# ]; do
        eval "arg=\${$i}"
        case "$arg" in
            --ctx|-ctx)
                i=$((i + 1))
                eval "next=\${$i}"
                CTX_ACTUAL="$next"
                ;;
            --ctx=*|-ctx=*)
                CTX_ACTUAL="${arg#*=}"
                ;;
            *)
                POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
                if [ $POSITIONAL_COUNT -eq 1 ]; then
                    MODEL_ARG="$arg"
                elif [ $POSITIONAL_COUNT -eq 2 ]; then
                    # Second positional arg is context size (if numeric)
                    if echo "$arg" | grep -qE '^[0-9]+$'; then
                        CTX_ACTUAL="$arg"
                    else
                        echo "Error: invalid argument '$arg' - expected context size (number) or --ctx flag"
                        exit 1
                    fi
                else
                    echo "Error: too many arguments. Usage: /llama start <model> [--ctx <size>|<size>]"
                    exit 1
                fi
                ;;
        esac
        i=$((i + 1))
    done

    # Resolve model from the non-flag argument
    case "$MODEL_ARG" in
        *[!0-9]*) MODEL_NAME="$MODEL_ARG" ;;
        "") ;;
        *) MODEL_NAME=$(echo "$MODELS" | sed -n "${MODEL_ARG}p") ;;
    esac

    MODEL_FILE="$HOME/models/$MODEL_NAME"
    if [ -z "$MODEL_NAME" ] || [ ! -f "$MODEL_FILE" ]; then
        echo "Model not found: $MODEL_ARG ($MODEL_FILE)"
        echo "=== Available models ==="
        echo "$MODELS" | nl -w4 -s') '
        exit 1
    fi

    KEY=$(echo "$MODEL_NAME" | sed -E 's/\.gguf$//; s/[^A-Za-z0-9._-]+/-/g' | tr 'A-Z' 'a-z')

    # Validate context size: must be positive integer
    if ! echo "$CTX_ACTUAL" | grep -qE '^[0-9]+$'; then
        echo "Error: context size must be a positive integer, got: $CTX_ACTUAL"
        exit 1
    fi
    if [ "$CTX_ACTUAL" -le 0 ]; then
        echo "Error: context size must be greater than 0"
        exit 1
    fi

    # Stop any existing server first so the new one can bind port 8080
    kill $(pgrep -f 'llama-server.*8080') 2>/dev/null || true
    sleep 1
    nohup "$LLAMA_BIN" -m "$MODEL_FILE" --host 127.0.0.1 --port 8080 \
      --ctx-size $CTX_ACTUAL --parallel $PARALLEL --threads $THREADS --jinja --alias "$KEY" \
      --override-kv general.context_length=int:$CTX_ACTUAL
      -ngl 999 \
      > "$HOME"/llama-server.log 2>&1 </dev/null &
    echo "Started llama-server (PID $!) with model: $MODEL_NAME (ctx-size=$CTX_ACTUAL, parallel=$PARALLEL, threads=$THREADS)"
    echo "Note: use /llama-switch <n> instead to also sync opencode.json."

elif [ "$1" = "stop" ]; then
    kill $(pgrep -f 'llama-server.*8080') 2>/dev/null && echo "Stopped llama-server" || echo "Not running"
else
    echo "Usage:"
    echo "  /llama start              - List available models"
    echo "  /llama start <number>     - Start with model by index"
    echo "  /llama start <filename>    - Start with model by filename"
    echo "  /llama stop               - Stop llama-server"
    echo "  /llama-switch <n>         - Start + sync opencode.json (recommended)"
fi`