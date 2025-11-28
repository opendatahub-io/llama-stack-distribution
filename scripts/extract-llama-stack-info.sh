#!/usr/bin/env bash
# Extract llama-stack repository and version from Containerfile
# Usage: source scripts/extract-llama-stack-info.sh
# Sets: LLAMA_STACK_REPO and LLAMA_STACK_VERSION

set -euo pipefail

# Get script directory to find Containerfile relative to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONTAINERFILE="${1:-$REPO_ROOT/distribution/Containerfile}"
GIT_URL=$(grep -o 'git+https://github\.com/[^/]\+/llama-stack[^.]*\.git@v\?[0-9.+a-z]\+' "$CONTAINERFILE")

if [ -z "$GIT_URL" ]; then
    echo "Error: Could not extract llama-stack git URL from Containerfile" >&2
    exit 1
fi

LLAMA_STACK_REPO="${GIT_URL#git+}"
LLAMA_STACK_REPO="${LLAMA_STACK_REPO%%@*}"
LLAMA_STACK_VERSION="${GIT_URL##*@}"
LLAMA_STACK_VERSION="${LLAMA_STACK_VERSION#v}"

if [ -z "$LLAMA_STACK_VERSION" ]; then
    echo "Error: Could not extract llama-stack version from Containerfile" >&2
    exit 1
fi
