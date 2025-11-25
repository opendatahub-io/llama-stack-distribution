#!/bin/bash
# Run live tests and update recordings in this repository
# Auto-detects provider from environment variables
# Usage: VERTEX_AI_PROJECT=your-project ./scripts/run-live-tests-local.sh

set -euo pipefail

# Configuration
# REGISTRY is not used directly but kept for consistency with other scripts
# shellcheck disable=SC2034
REGISTRY="quay.io"
IMAGE_BASE="quay.io/opendatahub/llama-stack"
RECORDINGS_DIR="tests/integration/recordings"
WORK_DIR="/tmp/llama-stack-integration-tests"
SOURCE_RECORDINGS="$WORK_DIR/tests/integration/recordings"

# Generate image tag from current git SHA (similar to CI approach)
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  GIT_SHA=$(git rev-parse --short HEAD)
  IMAGE_TAG="${GIT_SHA}"
else
  IMAGE_TAG="$(date +%s)"
fi
IMAGE_NAME="${IMAGE_BASE}:${IMAGE_TAG}"

# Auto-detect provider from environment variables
if [ -n "${VERTEX_AI_PROJECT:-}" ]; then
  PROVIDER="vertex"
  CONTAINER_NAME="llama-stack-vertex"
  PROVIDER_MODEL="vertexai/gemini-2.0-flash"
  VERTEX_AI_LOCATION="${VERTEX_AI_LOCATION:-us-central1}"
else
  # Default to vllm provider
  PROVIDER="vllm"
  CONTAINER_NAME="llama-stack-vllm"
  INFERENCE_MODEL="${INFERENCE_MODEL:-Qwen/Qwen3-0.6B}"
  PROVIDER_MODEL="vllm-inference/$INFERENCE_MODEL"
  echo "Using default vllm provider with model: $PROVIDER_MODEL"
fi

# Ensure Containerfile exists (generate if needed)
if [ ! -f "distribution/Containerfile" ]; then
  echo "Containerfile not found. Generating it..."
  if command -v pre-commit &> /dev/null; then
    pre-commit run --all-files >/dev/null 2>&1 || true
  elif [ -f "distribution/build.py" ]; then
    python3 distribution/build.py
  else
    echo "Error: Cannot generate Containerfile. Please run 'pre-commit run --all-files' first."
    exit 1
  fi
fi

# Build container image from current codebase
echo "Building container image from current codebase (tag: ${IMAGE_TAG})..."
podman build -f distribution/Containerfile -t "$IMAGE_NAME" . >/dev/null

# Prepare container environment and secrets
case "$PROVIDER" in
  vertex)
    ENV_ARGS="-e VERTEX_AI_PROJECT=\"$VERTEX_AI_PROJECT\" -e VERTEX_AI_LOCATION=\"$VERTEX_AI_LOCATION\" -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/gcp-credentials -e GOOGLE_CLOUD_PROJECT=\"$VERTEX_AI_PROJECT\""
    # Check if podman secret exists, create if not
    if ! podman secret exists gcp-credentials 2>/dev/null; then
      if [ -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
        echo "Creating podman secret 'gcp-credentials'..."
        podman secret create gcp-credentials "$HOME/.config/gcloud/application_default_credentials.json" >/dev/null
      else
        echo "Error: GCP credentials file not found at $HOME/.config/gcloud/application_default_credentials.json"
        echo "Please run: gcloud auth application-default login"
        exit 1
      fi
    fi
    SECRET_ARGS="--secret gcp-credentials"
    ;;
  vllm)
    VLLM_URL="${VLLM_URL:-http://localhost:8000}"
    ENV_ARGS="-e VLLM_URL=\"$VLLM_URL\" -e INFERENCE_MODEL=\"$INFERENCE_MODEL\""
    SECRET_ARGS=""
    ;;
  # Add other providers here in the future
esac

# Start Llama Stack container
echo "Starting Llama Stack container with $PROVIDER provider..."
podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
eval "podman run -d --net=host -p 8321:8321 $SECRET_ARGS $ENV_ARGS --name $CONTAINER_NAME $IMAGE_NAME" >/dev/null 2>&1

# Wait for server to be ready
echo "Waiting for server..."
for i in {1..60}; do
  curl -fsS http://127.0.0.1:8321/v1/health 2>/dev/null | grep -q '"status":"OK"' && break
  [ "$i" -eq 60 ] && { podman logs "$CONTAINER_NAME"; podman rm -f "$CONTAINER_NAME"; exit 1; }
  sleep 1
done

# Export environment variables for test script
case "$PROVIDER" in
  vertex)
    export VERTEX_AI_PROJECT VERTEX_AI_LOCATION
    ;;
  vllm)
    export INFERENCE_MODEL
    export VLLM_URL="${VLLM_URL:-http://localhost:8000}"
    ;;
  # Add other providers here in the future
esac
export LLAMA_STACK_TEST_INFERENCE_MODE=live
export PROVIDER_MODEL

# Set skip tests (same as in run_integration_tests.sh)
# TODO: enable these when we have a stable version of llama-stack client and server versions are aligned
RC2_SKIP_TESTS=" or test_openai_completion_logprobs or test_openai_completion_logprobs_streaming or test_openai_chat_completion_structured_output or test_multiple_tools_with_different_schemas or test_mcp_tools_in_inference or test_tool_with_complex_schema or test_tool_without_schema"
# TODO: re-enable the 2 chat_completion_non_streaming tests once they contain include max tokens (to prevent them from rambling)
SKIP_TESTS="test_text_chat_completion_tool_calling_tools_not_in_request or test_text_chat_completion_structured_output or test_text_chat_completion_non_streaming or test_openai_chat_completion_non_streaming$RC2_SKIP_TESTS"
export SKIP_TESTS

# Run integration tests in live mode to generate recordings
echo "Running integration tests..."
./tests/run_integration_tests.sh || { podman logs "$CONTAINER_NAME"; podman rm -f "$CONTAINER_NAME"; exit 1; }

# Check if recordings were generated
[ ! -d "$SOURCE_RECORDINGS" ] && { echo "No recordings found"; podman rm -f "$CONTAINER_NAME"; exit 1; }

# Find provider-specific recordings
case "$PROVIDER" in
  vertex)
    PROVIDER_FILES=$(find "$SOURCE_RECORDINGS" -type f \( -name "*vertex*" -o -name "*vertexai*" -o -path "*vertex*" \) 2>/dev/null || true)
    ;;
  vllm)
    PROVIDER_FILES=$(find "$SOURCE_RECORDINGS" -type f \( -name "*vllm*" -o -name "*vllm-inference*" -o -path "*vllm*" \) 2>/dev/null || true)
    ;;
  # Add other providers here in the future
esac

[ -z "$PROVIDER_FILES" ] && { echo "No $PROVIDER recordings found"; podman rm -f "$CONTAINER_NAME"; exit 1; }

# Copy recordings to this repository
echo "Updating recordings in $RECORDINGS_DIR..."
mkdir -p "$RECORDINGS_DIR"
echo "$PROVIDER_FILES" | while IFS= read -r file; do
  [ -n "$file" ] && [ -f "$file" ] && {
    relative_path="${file#"$SOURCE_RECORDINGS"/}"
    mkdir -p "$RECORDINGS_DIR/$(dirname "$relative_path")"
    cp "$file" "$RECORDINGS_DIR/$relative_path"
  }
done

# Cleanup
podman rm -f "$CONTAINER_NAME" >/dev/null
echo "Recordings updated in $RECORDINGS_DIR"
