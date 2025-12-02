#!/bin/bash
# Run live integration tests (Vertex AI preferred) against the current tree.
# Usage: VERTEX_AI_PROJECT=your-project ./scripts/run-live-tests-local.sh

set -euo pipefail

# Configuration
# REGISTRY is not used directly but kept for consistency with other scripts
# shellcheck disable=SC2034
REGISTRY="quay.io"
IMAGE_BASE="quay.io/opendatahub/llama-stack"
WORK_DIR="/tmp/llama-stack-integration-tests"
# Force live inference mode; other inference modes are disabled.
LLAMA_STACK_TEST_INFERENCE_MODE="${LLAMA_STACK_TEST_INFERENCE_MODE:-live}"
echo "LLAMA_STACK_TEST_INFERENCE_MODE: $LLAMA_STACK_TEST_INFERENCE_MODE"

# Generate image tag from git SHA or timestamp
generate_image_tag() {
  if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
    GIT_SHA=$(git rev-parse --short HEAD)
    IMAGE_TAG="${GIT_SHA}"
  else
    IMAGE_TAG="$(date +%s)"
  fi
  echo "$IMAGE_TAG"
}

# Auto-detect provider from environment variables
detect_provider() {
  if [ -n "${VERTEX_AI_PROJECT:-}" ]; then
    PROVIDER="vertex"
    CONTAINER_NAME="llama-stack-${PROVIDER}"
    INFERENCE_MODEL="google/gemini-2.0-flash"
    PROVIDER_MODEL="${VERTEX_AI_MODEL:-google/gemini-2.0-flash}"
    VERTEX_AI_LOCATION="${VERTEX_AI_LOCATION:-us-central1}"
    echo "Using Vertex AI provider with model: $PROVIDER_MODEL"
  else
    # Default to vllm provider
    PROVIDER="vllm"
    CONTAINER_NAME="llama-stack-vllm"
    INFERENCE_MODEL="${INFERENCE_MODEL:-Qwen/Qwen3-0.6B}"
    PROVIDER_MODEL="vllm-inference/$INFERENCE_MODEL"
    echo "Using default vllm provider with model: $PROVIDER_MODEL"
  fi
}

# Ensure Containerfile exists (generate if needed)
ensure_containerfile() {
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
}

# Verify GCP authentication for Vertex AI
verify_gcp_credentials() {
  if [ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
    echo "Error: GCP credentials file not found at $HOME/.config/gcloud/application_default_credentials.json"
    echo "Please run: gcloud auth application-default login"
    exit 1
  fi
}

# Prepare podman secret for GCP credentials
prepare_podman_secret() {
  if ! podman secret exists gcp-credentials 2>/dev/null; then
    echo "Creating podman secret 'gcp-credentials'..."
    podman secret create gcp-credentials "$HOME/.config/gcloud/application_default_credentials.json" >/dev/null
  fi
}

# Prepare container environment and secrets based on provider
prepare_container_env() {
  case "$PROVIDER" in
    vertex)
      verify_gcp_credentials
      ENV_ARGS="-e VERTEX_AI_PROJECT=\"$VERTEX_AI_PROJECT\" -e VERTEX_AI_LOCATION=\"$VERTEX_AI_LOCATION\" -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/gcp-credentials -e GOOGLE_CLOUD_PROJECT=\"$VERTEX_AI_PROJECT\" -e INFERENCE_MODEL=\"$INFERENCE_MODEL\""
      prepare_podman_secret
      SECRET_ARGS="--secret gcp-credentials"
      ;;
    vllm)
      VLLM_URL="${VLLM_URL:-http://localhost:8000}"
      ENV_ARGS="-e VLLM_URL=\"$VLLM_URL\" -e INFERENCE_MODEL=\"$INFERENCE_MODEL\""
      SECRET_ARGS=""
      ;;
    # Add other providers here in the future
  esac
}

# Export provider-specific environment variables
export_provider_env() {
  case "$PROVIDER" in
    vertex)
      export VERTEX_AI_PROJECT VERTEX_AI_LOCATION
      ;;
    vllm)
      export VLLM_URL="${VLLM_URL:-http://localhost:8000}"
      ;;
    # Add other providers here in the future
  esac
}


# Main execution flow starts here

# Generate image tag and name
IMAGE_TAG=$(generate_image_tag)
IMAGE_NAME="${IMAGE_BASE}:${IMAGE_TAG}"

# Auto-detect provider
detect_provider

# Ensure Containerfile exists
ensure_containerfile

# Build container image from current codebase
echo "Building container image from current codebase (tag: ${IMAGE_TAG})..."
podman build -f distribution/Containerfile -t "$IMAGE_NAME" . >/dev/null

# Prepare container environment and secrets
prepare_container_env

# Start Llama Stack container
echo "Starting Llama Stack container with $PROVIDER provider..."
podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
eval "podman run -d --net=host -p 8321:8321 $SECRET_ARGS $ENV_ARGS -e LLAMA_STACK_TEST_INFERENCE_MODE=\"record\" --name $CONTAINER_NAME $IMAGE_NAME" >/dev/null 2>&1

# Wait for server to be ready
echo "Waiting for server..."
for i in {1..60}; do
  curl -fsS http://127.0.0.1:8321/v1/health 2>/dev/null | grep -q '"status":"OK"' && break
  [ "$i" -eq 60 ] && { podman logs "$CONTAINER_NAME"; podman rm -f "$CONTAINER_NAME"; exit 1; }
  sleep 1
done

sleep 10000

# Export environment variables for test script
export_provider_env
export INFERENCE_MODEL
export LLAMA_STACK_TEST_INFERENCE_MODE
export PROVIDER_MODEL
export LLAMA_STACK_TEST_RECORDING_DIR="$WORK_DIR/tests/integration/recordings/new_recordings"

# Set skip tests (same as in run_integration_tests.sh)
# TODO: enable these when we have a stable version of llama-stack client and server versions are aligned
RC2_SKIP_TESTS=" or test_openai_completion_logprobs or test_openai_completion_logprobs_streaming or test_openai_chat_completion_structured_output or test_multiple_tools_with_different_schemas or test_mcp_tools_in_inference or test_tool_with_complex_schema or test_tool_without_schema"
# TODO: re-enable the 2 chat_completion_non_streaming tests once they contain include max tokens (to prevent them from rambling)
SKIP_TESTS="test_mcp_tools_in_inference or test_text_chat_completion_tool_calling_tools_not_in_request or test_text_chat_completion_structured_output or test_text_chat_completion_non_streaming or test_openai_chat_completion_non_streaming$RC2_SKIP_TESTS"
export SKIP_TESTS
# Run integration tests in live mode
echo "Running integration tests..."
./tests/run_integration_tests.sh

# Cleanup
podman rm -f "$CONTAINER_NAME" >/dev/null
