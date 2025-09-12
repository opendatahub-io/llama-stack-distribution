#!/usr/bin/env bash

set -euo pipefail

# Configuration
LLAMA_STACK_REPO="https://github.com/meta-llama/llama-stack.git"
WORK_DIR="/tmp/llama-stack-integration-tests"
INFERENCE_MODEL="${INFERENCE_MODEL:-meta-llama/Llama-3.2-1B-Instruct}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get version dynamically from Containerfile.in (look in parent directory)
CONTAINERFILE_IN="$SCRIPT_DIR/../distribution/Containerfile.in"
LLAMA_STACK_VERSION=$(grep -o 'llama-stack==[0-9]\+\.[0-9]\+\.[0-9]\+' "$CONTAINERFILE_IN" | cut -d'=' -f3)
if [ -z "$LLAMA_STACK_VERSION" ]; then
    echo "Error: Could not extract llama-stack version from Containerfile.in"
    exit 1
fi

function clone_llama_stack() {
    # Clone the repository if it doesn't exist
    if [ ! -d "$WORK_DIR" ]; then
        git clone "$LLAMA_STACK_REPO" "$WORK_DIR"
    fi

    # Checkout the specific tag
    cd "$WORK_DIR"
    # fetch origin incase we didn't clone a fresh repo
    git fetch origin
    if ! git checkout "v$LLAMA_STACK_VERSION"; then
        echo "Error: Could not checkout tag v$LLAMA_STACK_VERSION"
        echo "Available tags:"
        git tag | grep "^v" | tail -10
        exit 1
    fi
}

function run_integration_tests() {
    echo "Running integration tests..."

    cd "$WORK_DIR"

    # Test to skip
    SKIP_TESTS="test_text_chat_completion_tool_calling_tools_not_in_request or test_inference_store_tool_calls"

    # Dynamically determine the path to run.yaml from the original script directory
    STACK_CONFIG_PATH="$SCRIPT_DIR/../distribution/run.yaml"
    if [ ! -f "$STACK_CONFIG_PATH" ]; then
        echo "Error: Could not find stack config at $STACK_CONFIG_PATH"
        exit 1
    fi

    uv run pytest -s -v tests/integration/inference/ \
        --stack-config=server:"$STACK_CONFIG_PATH" \
        --text-model=vllm-inference/"$INFERENCE_MODEL" \
        -k "not ($SKIP_TESTS)"
}

function main() {
    echo "Starting llama-stack integration tests"
    echo "Configuration:"
    echo "  LLAMA_STACK_VERSION: $LLAMA_STACK_VERSION"
    echo "  LLAMA_STACK_REPO: $LLAMA_STACK_REPO"
    echo "  WORK_DIR: $WORK_DIR"
    echo "  INFERENCE_MODEL: $INFERENCE_MODEL"

    clone_llama_stack
    run_integration_tests

    echo "Integration tests completed successfully!"
}


main "$@"
exit 0
