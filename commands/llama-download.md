---
description: Download a GGUF model from HuggingFace and validate it (with resume support)
---
!`if [ -z "$2" ]; then
    echo "Usage: /llama-download <org/repo> <filename.gguf>"
    echo "Example: /llama-download bartowski/Qwen2.5-3B-Instruct-GGUF Qwen2.5-3B-Instruct-Q4_K_M.gguf"
    exit 1
fi
mkdir -p ~/models
AUTH=""; [ -n "$HF_TOKEN" ] && AUTH="-H Authorization: Bearer $HF_TOKEN"
OUT=~/models/$2
# Resume interrupted downloads with curl --continue-at
curl -L $AUTH --fail --continue-at - -o "$OUT" "https://huggingface.co/$1/resolve/main/$2" 2>&1 | tail -3

# Validate: real GGUF files start with the magic bytes "GGUF" and are >100MB
if [ ! -f "$OUT" ]; then
    echo "❌ Download failed — no file written"
    exit 1
fi
MAGIC=$(head -c 4 "$OUT")
SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")
if [ "$MAGIC" != "GGUF" ] || [ "$SIZE" -lt 100000000 ]; then
    echo "❌ Invalid download (magic='$MAGIC', size=$SIZE bytes) — removing $OUT"
    echo "   Check the repo name and filename. Note: Qwen GGUFs usually live in"
    echo "   community repos like bartowski/<model>-GGUF, not the official Qwen repos."
    rm -f "$OUT"
    exit 1
fi
echo "✅ Downloaded and validated $OUT ($(awk -v n="$SIZE" 'BEGIN{printf "%.1f GB", n/1073741824}'))"
echo "   Load it with /llama-switch <number>"
`