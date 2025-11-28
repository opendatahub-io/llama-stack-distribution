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
# Temporary directory for this run's recordings only
RUN_RECORDINGS_DIR=""

# Set inference mode to live by default
# can be set to record to generate recordings, or record-if-missing to generate recordings only if they don't exist
LLAMA_STACK_TEST_INFERENCE_MODE="${LLAMA_STACK_TEST_INFERENCE_MODE:-live}"

# Check if in record mode
is_record_mode() {
  [ "$LLAMA_STACK_TEST_INFERENCE_MODE" = "record" ] || [ "$LLAMA_STACK_TEST_INFERENCE_MODE" = "record-if-missing" ]
}

# Check if in replay mode
is_replay_mode() {
  [ "$LLAMA_STACK_TEST_INFERENCE_MODE" = "replay" ]
}

# Validate recordings exist when in replay mode
validate_replay_recordings() {
  if is_replay_mode; then
    if [ ! -d "$RECORDINGS_DIR" ]; then
      echo "Error: Recordings directory not found: $RECORDINGS_DIR"
      echo "collect recordings first or run live mode"
      exit 1
    fi

    # Check if there are any recording JSON files
    RECORDING_FILES=$(find "$RECORDINGS_DIR" -type f -name "*.json" 2>/dev/null || true)
    if [ -z "$RECORDING_FILES" ]; then
      echo "Error: No recording files found in $RECORDINGS_DIR"
      echo "collect recordings first or run live mode"
      exit 1
    fi

    RECORDING_COUNT=$(echo "$RECORDING_FILES" | grep -c . || echo "0")
    echo "Found $RECORDING_COUNT recording file(s) for replay mode"
  fi
}

echo "LLAMA_STACK_TEST_INFERENCE_MODE: $LLAMA_STACK_TEST_INFERENCE_MODE"

# Validate recordings exist if in replay mode (before starting any containers)
validate_replay_recordings

# Setup recordings collection: create temp dir and clear existing recordings
setup_recordings_collection() {
  RUN_RECORDINGS_DIR=$(mktemp -d -t llama-stack-recordings-XXXXXX)
  echo "Created temporary recordings directory: $RUN_RECORDINGS_DIR"

  # Clear existing recordings directory to ensure we only collect new recordings
  if [ -d "$SOURCE_RECORDINGS" ]; then
    echo "Clearing existing recordings directory to collect only new recordings..."
    rm -rf "$SOURCE_RECORDINGS"
  fi
  mkdir -p "$SOURCE_RECORDINGS"
}

# Collect recordings from this run to temporary directory
collect_recordings() {
  # Copy recordings from this run to the temporary directory
  # Since we cleared the directory before running tests, all files here are from this run
  if [ ! -d "$SOURCE_RECORDINGS" ]; then
    echo "Error: Recordings directory not found: $SOURCE_RECORDINGS"
    echo "No recordings were generated during the test run."
    podman rm -f "$CONTAINER_NAME" >/dev/null
    exit 1
  fi

  echo "Collecting recordings from this run to temporary directory..."
  # Preserve directory structure when copying
  RECORDING_FILES=$(find "$SOURCE_RECORDINGS" -type f -name "*.json" 2>/dev/null || true)

  if [ -z "$RECORDING_FILES" ]; then
    echo "Error: No recording files found in $SOURCE_RECORDINGS"
    echo "No recordings were generated during the test run."
    podman rm -f "$CONTAINER_NAME" >/dev/null
    exit 1
  fi

  echo "$RECORDING_FILES" | while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] && {
      relative_path="${file#"$SOURCE_RECORDINGS"/}"
      relative_path="${relative_path#/}"
      mkdir -p "$RUN_RECORDINGS_DIR/$(dirname "$relative_path")"
      cp "$file" "$RUN_RECORDINGS_DIR/$relative_path"
    }
  done

  RECORDING_COUNT=$(echo "$RECORDING_FILES" | grep -c . || echo "0")
  echo "Collected $RECORDING_COUNT recording file(s) from this run"
}

# Function to update recordings from container to repository
update_recordings() {
  # Use the temporary directory for this run's recordings
  local source_dir="$RUN_RECORDINGS_DIR"

  # Check if recordings were generated
  [ ! -d "$source_dir" ] && { echo "No recordings found"; podman rm -f "$CONTAINER_NAME"; exit 1; }

  # Find all recording JSON files (flexible approach - no provider-specific filtering)
  RECORDING_FILES=$(find "$source_dir" -type f -name "*.json" 2>/dev/null || true)

  [ -z "$RECORDING_FILES" ] && { echo "No recordings found"; podman rm -f "$CONTAINER_NAME"; exit 1; }

  RECORDING_COUNT=$(echo "$RECORDING_FILES" | grep -c . || echo "0")
  echo "Found $RECORDING_COUNT recording file(s) from this run"

  # Copy all recordings to this repository (preserving directory structure)
  echo "Updating recordings in $RECORDINGS_DIR..."
  mkdir -p "$RECORDINGS_DIR"
  echo "$RECORDING_FILES" | while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] && {
      relative_path="${file#"$source_dir"/}"
      # Remove leading slash if present
      relative_path="${relative_path#/}"
      mkdir -p "$RECORDINGS_DIR/$(dirname "$relative_path")"
      cp "$file" "$RECORDINGS_DIR/$relative_path"
    }
  done
  echo "Recordings copied to $RECORDINGS_DIR"

  # Normalize recordings to reduce git diff noise
  # Use the normalization script from the cloned llama-stack repository
  # The script searches for recordings relative to its location, so we create a temporary
  # symlink in our local repo so it can find our local recordings
  NORMALIZE_SCRIPT="$WORK_DIR/scripts/normalize_recordings.py"
  if [ -f "$NORMALIZE_SCRIPT" ]; then
    echo "Normalizing recordings..."
    # Create temporary symlink so the script can find our local tests/ directory
    TEMP_NORMALIZE_LINK="scripts/normalize_recordings.py"
    ln -sf "$NORMALIZE_SCRIPT" "$TEMP_NORMALIZE_LINK"
    python3 "$TEMP_NORMALIZE_LINK" || echo "Warning: Normalization script failed, continuing anyway..."
    rm -f "$TEMP_NORMALIZE_LINK"
  else
    echo "Warning: Normalization script not found at $NORMALIZE_SCRIPT"
  fi
  echo "Recordings updated in $RECORDINGS_DIR"
}

# Cleanup temporary recordings directory
cleanup_recordings() {
  if [ -n "$RUN_RECORDINGS_DIR" ] && [ -d "$RUN_RECORDINGS_DIR" ]; then
    rm -rf "$RUN_RECORDINGS_DIR"
    echo "Cleaned up temporary recordings directory"
  fi
}

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
eval "podman run -d --net=host -p 8321:8321 $SECRET_ARGS $ENV_ARGS --name $CONTAINER_NAME $IMAGE_NAME" >/dev/null 2>&1

# Wait for server to be ready
echo "Waiting for server..."
for i in {1..60}; do
  curl -fsS http://127.0.0.1:8321/v1/health 2>/dev/null | grep -q '"status":"OK"' && break
  [ "$i" -eq 60 ] && { podman logs "$CONTAINER_NAME"; podman rm -f "$CONTAINER_NAME"; exit 1; }
  sleep 1
done

# Export environment variables for test script
export_provider_env
export INFERENCE_MODEL
export LLAMA_STACK_TEST_INFERENCE_MODE
export PROVIDER_MODEL

# Set skip tests (same as in run_integration_tests.sh)
# TODO: enable these when we have a stable version of llama-stack client and server versions are aligned
RC2_SKIP_TESTS=" or test_openai_completion_logprobs or test_openai_completion_logprobs_streaming or test_openai_chat_completion_structured_output or test_multiple_tools_with_different_schemas or test_mcp_tools_in_inference or test_tool_with_complex_schema or test_tool_without_schema"
# TODO: re-enable the 2 chat_completion_non_streaming tests once they contain include max tokens (to prevent them from rambling)
SKIP_TESTS="test_mcp_tools_in_inference or test_text_chat_completion_tool_calling_tools_not_in_request or test_text_chat_completion_structured_output or test_text_chat_completion_non_streaming or test_openai_chat_completion_non_streaming$RC2_SKIP_TESTS"
export SKIP_TESTS
# Set recording directory to WORK_DIR location where tests actually write recordings
export LLAMA_STACK_TEST_RECORDING_DIR="$SOURCE_RECORDINGS"

# Setup recordings collection if in record mode
is_record_mode && setup_recordings_collection

# Run integration tests in live mode to generate recordings
echo "Running integration tests..."
./tests/run_integration_tests.sh
# ./tests/run_integration_tests.sh || { podman logs "$CONTAINER_NAME"; podman rm -f "$CONTAINER_NAME"; exit 1; }

# Update recordings only if in record mode
if is_record_mode; then
  collect_recordings
  update_recordings
  cleanup_recordings
fi

# Cleanup
podman rm -f "$CONTAINER_NAME" >/dev/null
