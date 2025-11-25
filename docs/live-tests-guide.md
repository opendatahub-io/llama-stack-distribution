# Live Tests Guide

This guide explains how to run live tests and generate recordings for supported providers.

## Supported Providers

- **vllm** - VLLM inference server (default, requires local container)
- **vertex** - Google Cloud Vertex AI

The script auto-detects the provider from environment variables. If no provider is specified, it defaults to vllm.

## Prerequisites

- **Podman** - For building and running containers
- **gcloud CLI** - For GCP authentication (Vertex AI only)

## Local Testing

### Using VLLM (Default)

```bash
# Start the vllm container
podman run -d \
  --name vllm \
  --privileged=true \
  --net=host \
  quay.io/higginsd/vllm-cpu:65393ee064-qwen3 \
  --host 0.0.0.0 \
  --port 8000 \
  --enable-auto-tool-choice \
  --tool-call-parser hermes \
  --model /root/.cache/Qwen3-0.6B \
  --served-model-name Qwen/Qwen3-0.6B \
  --max-model-len 8192

# Wait for vllm to be ready
timeout 900 bash -c 'until curl -fsS http://localhost:8000/health >/dev/null; do
  echo "Waiting for vllm..."
  sleep 5
done'

# Run the script
./scripts/run-live-tests-local.sh

# Clean up
podman rm -f vllm
```

### Using Vertex AI

```bash
# Set GCP project and authenticate
export VERTEX_AI_PROJECT=your-gcp-project-id
gcloud auth application-default login

# Run the script
./scripts/run-live-tests-local.sh
```

The script will:
- Build the container image
- Start the Llama Stack container with the selected provider
- Run integration tests in live mode
- Extract recordings to `tests/integration/recordings/`
- Clean up the container

**Note**: The script automatically creates a podman secret from your GCP credentials if needed.

## CI/CD Workflow

The workflow `.github/workflows/live-tests.yml` automatically runs live tests and updates recordings.

### Triggering

- **Scheduled**: Runs every Monday at 2 AM UTC
- **Manual**: `gh workflow run live-tests.yml` or via GitHub UI

### Required Secrets

- `VERTEX_AI_PROJECT` - GCP project ID
- `GCP_WORKLOAD_IDENTITY_PROVIDER` - For OIDC authentication

The workflow uses `us-central1` as the GCP region.

### How it Works

1. Authenticates to GCP using OIDC (Workload Identity Federation)
2. Builds and starts the Llama Stack container with Vertex AI provider
3. Runs integration tests in `live` mode to generate recordings
4. Creates a PR to `llamastack/llama-stack` with updated recordings (if tests pass)

## Recordings

Recordings are generated during live tests and saved to `tests/integration/recordings/`. Look for files with "vertex"/"vertexai" (Vertex AI) or "vllm"/"vllm-inference" (VLLM) in their names or paths.

- **Local**: Recordings are automatically extracted to `tests/integration/recordings/` after running the script
- **CI**: Recordings are pushed to `llamastack/llama-stack` via PR

To include recordings in your PR, commit and push the changes from `tests/integration/recordings/`.

## Adding New Providers

To add a new provider:

1. Update `scripts/run-live-tests-local.sh` - Add provider detection, environment variables, and recording patterns
2. Update `tests/run_integration_tests.sh` - Add provider detection and model selection
3. Update `.github/workflows/live-tests.yml` - Add authentication and container setup if needed
4. Update `distribution/run.yaml` - Ensure provider configuration is present
