#!/usr/bin/env bash

set -exuo pipefail

# Configuration
WORK_DIR="/tmp/llama-stack-integration-tests"
INFERENCE_MODEL="${INFERENCE_MODEL:-Qwen/Qwen3-0.6B}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get repository and version dynamically from Containerfile
# Look for git URL format: git+https://github.com/*/llama-stack.git@vVERSION or @VERSION
CONTAINERFILE="$SCRIPT_DIR/../distribution/Containerfile"
GIT_URL=$(grep -o 'git+https://github\.com/[^/]\+/llama-stack\.git@v\?[0-9.+a-z]\+' "$CONTAINERFILE")
if [ -z "$GIT_URL" ]; then
    echo "Error: Could not extract llama-stack git URL from Containerfile"
    exit 1
fi

# Extract repo URL (remove git+ prefix and @version suffix)
LLAMA_STACK_REPO=${GIT_URL#git+}
LLAMA_STACK_REPO=${LLAMA_STACK_REPO%%@*}
# Extract version (remove git+ prefix and everything before @, and optional v prefix)
LLAMA_STACK_VERSION=${GIT_URL##*@}
LLAMA_STACK_VERSION=${LLAMA_STACK_VERSION#v}
if [ -z "$LLAMA_STACK_VERSION" ]; then
    echo "Error: Could not extract llama-stack version from Containerfile"
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
    # TODO: enable these when we have a stable version of llama-stack client and server versions are aligned
    RC2_SKIP_TESTS=" or test_openai_completion_logprobs or test_openai_completion_logprobs_streaming or test_openai_chat_completion_structured_output or test_multiple_tools_with_different_schemas or test_mcp_tools_in_inference or test_tool_with_complex_schema or test_tool_without_schema"
    # TODO: re-enable the 2 chat_completion_non_streaming tests once they contain include max tokens (to prevent them from rambling)
    SKIP_TESTS="test_text_chat_completion_tool_calling_tools_not_in_request or test_text_chat_completion_structured_output or test_text_chat_completion_non_streaming or test_openai_chat_completion_non_streaming$RC2_SKIP_TESTS"

    # Dynamically determine the path to run.yaml from the original script directory
    STACK_CONFIG_PATH="$SCRIPT_DIR/../distribution/run.yaml"
    if [ ! -f "$STACK_CONFIG_PATH" ]; then
        echo "Error: Could not find stack config at $STACK_CONFIG_PATH"
        exit 1
    fi

    # Determine provider and model based on environment variables
    if [ -n "${PROVIDER_MODEL:-}" ]; then
        # Use provider model from environment (set by live test scripts)
        TEXT_MODEL="$PROVIDER_MODEL"
        echo "Using provider model: $TEXT_MODEL"
    elif [ -n "${VERTEX_AI_PROJECT:-}" ]; then
        # Use Vertex AI provider
        TEXT_MODEL="vertexai/gemini-2.0-flash"
        echo "Using Vertex AI provider with project: $VERTEX_AI_PROJECT"
        echo "Using model: $TEXT_MODEL"
    else
        # Use vllm-inference provider (default)
        TEXT_MODEL="vllm-inference/$INFERENCE_MODEL"
        echo "Using vllm-inference provider with model: $TEXT_MODEL"
    fi
    # TODO: remove this once we have a stable version of llama-stack client
    # Currently, LLS client version is 0.3.0, while the server version is 0.3.0rc3+rhai0
    uv run --with llama-stack-client==0.3.0 pytest -s -v tests/integration/inference/ \
        --stack-config=server:"$STACK_CONFIG_PATH" \
        --text-model="$TEXT_MODEL" \
        --embedding-model=granite-embedding-125m \
        -k "not ($SKIP_TESTS)"
}

function main() {
    echo "Starting llama-stack integration tests"
    echo "Configuration:"
    echo "  LLAMA_STACK_VERSION: $LLAMA_STACK_VERSION"
    echo "  LLAMA_STACK_REPO: $LLAMA_STACK_REPO"
    echo "  WORK_DIR: $WORK_DIR"
    echo "  INFERENCE_MODEL: $INFERENCE_MODEL"
    echo "  VERTEX_AI_PROJECT: ${VERTEX_AI_PROJECT:-not set}"
    echo "  VERTEX_AI_LOCATION: ${VERTEX_AI_LOCATION:-not set}"

    clone_llama_stack
    run_integration_tests

    echo "Integration tests completed successfully!"
}


main "$@"
exit 0
