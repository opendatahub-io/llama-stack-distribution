# Live Tests Guide

This guide explains how to run live tests and generate recordings for supported providers (VLLM and Vertex AI).

## Supported Providers

- **vllm** - VLLM inference server (default, requires local container)
- **vertex** - Google Cloud Vertex AI

The script auto-detects the provider from environment variables. If no provider is specified, it defaults to vllm.

## Local Testing

### Prerequisites

1. **Podman** - Required for building and running containers (including vllm container)
2. **gcloud CLI** - For GCP authentication (if using Vertex AI provider)
3. **Git** - For cloning repositories
4. **Python 3.12+** - For running tests

### Quick Start: Using the Script (Recommended)

The easiest way to generate recordings locally is using the provided script:

#### Using VLLM (Default)

```bash
# Start the vllm container (required before running tests)
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

# Run the script (defaults to vllm provider)
./scripts/run-live-tests-local.sh

# Clean up vllm container when done
podman rm -f vllm
```

#### Using Vertex AI

```bash
# Set your GCP project
export VERTEX_AI_PROJECT=your-gcp-project-id
export VERTEX_AI_LOCATION=us-central1  # Optional, defaults to us-central1

# Authenticate with gcloud (creates application_default_credentials.json)
gcloud auth application-default login

# Run the script (it will automatically create podman secret if needed)
./scripts/run-live-tests-local.sh
```

**Note**: The script automatically creates a podman secret named `gcp-credentials` from your `~/.config/gcloud/application_default_credentials.json` file if it doesn't already exist.

The script will:
- Build the container image
- Start the Llama Stack container with the selected provider
- Run integration tests in live mode
- Extract recordings to `tests/integration/recordings/` in this repository
- Clean up the container

### Provider Requirements

#### VLLM (Default)
- **Local vllm container** - Must be running before executing the test script
- The container should be accessible at `http://localhost:8000`
- Default model: `Qwen/Qwen3-0.6B`
- You can customize the model by setting `INFERENCE_MODEL` environment variable

**Important**: The vllm container must be started separately before running the test script. The script does not start the vllm container automatically. Use the commands shown in the Quick Start section above.

#### Vertex AI
- `VERTEX_AI_PROJECT` - GCP project ID (required)
- `VERTEX_AI_LOCATION` - GCP region (optional, defaults to us-central1)
- GCP authentication via `gcloud auth application-default login`

### Troubleshooting

#### Tests fail with authentication errors

```bash
# Verify gcloud authentication
gcloud auth list
gcloud auth application-default login

# Verify project is set
echo $VERTEX_AI_PROJECT
```

#### Container fails to start

```bash
# Check container logs
podman logs llama-stack-vertex  # For Vertex AI
podman logs llama-stack-vllm    # For VLLM

# Verify image was built correctly
podman images | grep llama-stack
```

#### VLLM container not accessible

```bash
# Check if vllm container is running
podman ps | grep vllm

# Check vllm health endpoint
curl http://localhost:8000/health

# Check vllm container logs
podman logs vllm

# Restart vllm container if needed
podman rm -f vllm
# Then restart using the commands from Quick Start section
```

#### Recordings not generated

- Ensure `LLAMA_STACK_TEST_INFERENCE_MODE=live` is set
- Check that tests actually ran (look for test output)
- Verify recordings directory exists: `/tmp/llama-stack-integration-tests/tests/integration/recordings/`
- Check if pytest recorded the responses (some test frameworks require specific configuration)

#### Finding recordings location

After running the script, recordings are automatically copied to:
```
tests/integration/recordings/
```

Look for files with "vertex" or "vertexai" in their names or paths (for Vertex AI), or "vllm" or "vllm-inference" (for VLLM).

## CI/CD Workflow

The workflow `.github/workflows/live-tests.yml` runs tests for supported providers automatically.

### Scheduled Runs

The workflow runs on a schedule (Mondays at 2 AM UTC).

### Manual Trigger

```bash
# Via GitHub UI or CLI
gh workflow run live-tests.yml
```

### Required Secrets

Configure these secrets in GitHub:

**Vertex AI:**
- `VERTEX_AI_PROJECT` - GCP project ID
- `VERTEX_AI_LOCATION` - GCP region (optional, defaults to us-central1)
- `GCP_WORKLOAD_IDENTITY_PROVIDER` - For OIDC authentication
- `GCP_SERVICE_ACCOUNT` - For OIDC authentication

### How it Works

1. **Authentication**: Uses OIDC (Workload Identity Federation) to authenticate to GCP
2. **Build & Run**: Builds the Llama Stack container image and starts it with the Vertex AI provider
3. **Live Tests**: Runs integration tests in `live` mode, generating new recordings
4. **PR Creation**: If tests pass, extracts Vertex AI recordings and creates a Pull Request to the `llamastack/llama-stack` repository with the updated recordings

## Adding New Providers

To add a new provider in the future:

1. **Update `scripts/run-live-tests-local.sh`:**
   - Add provider detection in the auto-detect section
   - Add provider-specific environment variables and volumes
   - Add provider-specific recording patterns

2. **Update `tests/run_integration_tests.sh`:**
   - Add provider detection logic
   - Set appropriate model for the provider

3. **Update `.github/workflows/live-tests.yml`:**
   - Add provider-specific authentication steps if needed
   - Add provider-specific container setup

4. **Update `distribution/run.yaml`:**
   - Ensure provider configuration is present

## Recordings

Recordings are automatically:
- Generated during live tests (when `LLAMA_STACK_TEST_INFERENCE_MODE=live`)
- Extracted to `tests/integration/recordings/` in this repository
- Pushed to llama-stack repository via PR (in CI)

Recordings follow the upstream structure: `tests/integration/recordings/`

### Including Recordings in Your PR

After running the script, recordings are automatically updated in `tests/integration/recordings/`. You can review, commit, and push the changes as needed.
