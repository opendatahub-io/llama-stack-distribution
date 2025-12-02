# Live Tests Guide

This guide explains how to run Llama Stack integration tests in live inference mode against both vLLM and Vertex AI providers.

## Supported Providers

- **vllm** – Local VLLM inference server (default)
- **vertex** – Google Cloud Vertex AI (when GCP secrets are configured)

The `scripts/run-live-tests-local.sh` helper auto-detects the provider based on environment variables. In CI, both providers are tested in parallel using a matrix strategy.

## Prerequisites

- **Podman** – Build and run the container image (for local testing)
- **gcloud CLI** – Authenticate to GCP for Vertex AI (for Vertex AI testing)

## Running Tests Locally

### Using vLLM (Default)

```bash
# Start the vllm container first
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

# Run tests
./scripts/run-live-tests-local.sh

# Clean up
podman rm -f vllm
```

### Using Vertex AI

```bash
export VERTEX_AI_PROJECT=your-gcp-project-id
export VERTEX_AI_LOCATION=us-central1        # optional, defaults to us-central1
gcloud auth application-default login        # ensures ADC credentials exist

./scripts/run-live-tests-local.sh
```

The script performs the following steps:

1. Builds the Llama Stack container image from the current repo.
2. Starts the container configured for the detected provider (Vertex AI when `VERTEX_AI_PROJECT` is set, vLLM otherwise).
3. Runs the integration test suite in live mode only.
4. Tears down the container on completion.

## CI/CD Workflow

The `.github/workflows/redhat-distro-container.yml` workflow runs integration tests for both providers using a matrix strategy.

### Triggering

- **Pull Requests**: Automatically runs on PRs to `main`, `rhoai-v*`, and `konflux-poc*` branches
- **Push**: Runs on pushes to `main` and `rhoai-v*` branches
- **Scheduled**: Daily at 06:00 UTC
- **Manual**: `gh workflow run redhat-distro-container.yml` or via the GitHub UI

### Required Secrets

For Vertex AI tests to run in CI:

- `VERTEX_AI_PROJECT` – Target GCP project
- `GCP_WORKLOAD_IDENTITY_PROVIDER` – Used for OIDC authentication
- `VERTEX_AI_LOCATION` – Optional, defaults to `us-central1` if not set

If Vertex AI secrets are not configured, the Vertex AI matrix job will skip with a message.

### How it Works

1. **Build Phase**: Builds the container image once (shared across matrix jobs)
2. **Test Phase**: Runs two parallel matrix jobs:
   - **vLLM**: Starts VLLM container, runs smoke tests and integration tests
   - **Vertex AI**: Authenticates to GCP using Workload Identity Federation, starts container with Vertex AI configuration, runs integration tests in live mode
3. **Publish Phase**: Only after all matrix jobs pass, the image is published to Quay.io

The workflow uses `fail-fast: false` so both provider tests run independently, and failures in one don't cancel the other.

## Adding New Providers

This section provides step-by-step instructions for adding support for a new inference provider. Follow these steps in order, using the existing `vllm` and `vertex` implementations as reference examples.

### Step 1: Update `scripts/run-live-tests-local.sh`

#### 1.1 Add Provider Detection Logic

In the `detect_provider()` function (around line 29), add a new condition before the `else` clause that checks for your provider's environment variable:

```bash
detect_provider() {
  if [ -n "${NEW_PROVIDER_API_KEY:-}" ]; then
    PROVIDER="newprovider"
    CONTAINER_NAME="llama-stack-newprovider"
    INFERENCE_MODEL="${NEW_PROVIDER_MODEL:-model-name}"
    PROVIDER_MODEL="newprovider/$INFERENCE_MODEL"
    NEW_PROVIDER_REGION="${NEW_PROVIDER_REGION:-us-east-1}"
    echo "Using New Provider with model: $PROVIDER_MODEL"
  elif [ -n "${VERTEX_AI_PROJECT:-}" ]; then
    # ... existing vertex code ...
  else
    # ... existing vllm code ...
  fi
}
```

**Key points:**
- Check for a unique environment variable that indicates your provider should be used
- Set `PROVIDER` to a lowercase identifier (used in matrix strategy)
- Set `CONTAINER_NAME` to a unique container name
- Set `PROVIDER_MODEL` to the format expected by llama-stack (typically `provider-name/model-name`)
- Define any provider-specific configuration variables

#### 1.2 Add Provider-Specific Verification Function (if needed)

If your provider requires credential verification, add a function similar to `verify_gcp_credentials()`:

```bash
# Verify credentials for New Provider
verify_newprovider_credentials() {
  if [ -z "${NEW_PROVIDER_API_KEY:-}" ]; then
    echo "Error: NEW_PROVIDER_API_KEY environment variable not set"
    echo "Please set: export NEW_PROVIDER_API_KEY=your-api-key"
    exit 1
  fi
}
```

#### 1.3 Add Provider Case to `prepare_container_env()`

In the `prepare_container_env()` function (around line 80), add a new case:

```bash
prepare_container_env() {
  case "$PROVIDER" in
    newprovider)
      verify_newprovider_credentials  # if needed
      ENV_ARGS="-e NEW_PROVIDER_API_KEY=\"$NEW_PROVIDER_API_KEY\" -e NEW_PROVIDER_REGION=\"$NEW_PROVIDER_REGION\" -e INFERENCE_MODEL=\"$INFERENCE_MODEL\""
      SECRET_ARGS=""  # or add secret handling if needed
      ;;
    vertex)
      # ... existing vertex code ...
      ;;
    vllm)
      # ... existing vllm code ...
      ;;
  esac
}
```

**Key points:**
- Add all environment variables your provider needs
- If using podman secrets (like Vertex AI), set up `SECRET_ARGS` accordingly
- If no secrets needed, set `SECRET_ARGS=""`

#### 1.4 Add Provider Case to `export_provider_env()`

In the `export_provider_env()` function (around line 98), add a new case:

```bash
export_provider_env() {
  case "$PROVIDER" in
    newprovider)
      export NEW_PROVIDER_API_KEY NEW_PROVIDER_REGION
      ;;
    vertex)
      # ... existing vertex code ...
      ;;
    vllm)
      # ... existing vllm code ...
      ;;
  esac
}
```

**Key points:**
- Export all environment variables that the test script needs
- These variables will be available to `tests/run_integration_tests.sh`

### Step 2: Update `tests/run_integration_tests.sh`

In the `run_integration_tests()` function (around line 56), add a new condition in the provider/model selection logic:

```bash
# Determine provider and model based on environment variables
if [ -n "${PROVIDER_MODEL:-}" ]; then
    # Use provider model from environment (set by live test scripts)
    TEXT_MODEL="$PROVIDER_MODEL"
    echo "Using provider model: $TEXT_MODEL"
elif [ -n "${NEW_PROVIDER_API_KEY:-}" ]; then
    # Use New Provider
    TEXT_MODEL="${NEW_PROVIDER_MODEL:-newprovider/model-name}"
    echo "Using New Provider with API key"
    echo "Using model: $TEXT_MODEL"
elif [ -n "${VERTEX_AI_PROJECT:-}" ]; then
    # ... existing vertex code ...
else
    # ... existing vllm code ...
fi
```

**Key points:**
- Check for the same environment variable used in `detect_provider()`
- Set `TEXT_MODEL` to the format expected by llama-stack client
- The format is typically `provider-name/model-name` (e.g., `newprovider/claude-3`)

### Step 3: Update `.github/workflows/redhat-distro-container.yml`

#### 3.1 Add Environment Variables

In the `jobs.test.env` section (around line 45), add your provider's environment variables:

```yaml
env:
  INFERENCE_MODEL: Qwen/Qwen3-0.6B
  EMBEDDING_MODEL: granite-embedding-125m
  VLLM_URL: http://localhost:8000
  # ... existing variables ...
  NEW_PROVIDER_API_KEY: ${{ secrets.NEW_PROVIDER_API_KEY }}
  NEW_PROVIDER_REGION: ${{ secrets.NEW_PROVIDER_REGION != '' && secrets.NEW_PROVIDER_REGION || 'us-east-1' }}
```

#### 3.2 Add Matrix Entry

In the `strategy.matrix.include` section (around line 57), add a new entry:

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - provider: vllm
        platform: linux/amd64
      - provider: vertex
        platform: linux/amd64
      - provider: newprovider
        platform: linux/amd64
```

#### 3.3 Add Provider-Specific Test Steps

After the existing provider steps (around line 166), add your provider's test steps. Follow this pattern:

```yaml
# New Provider steps
- name: New Provider secrets not configured
  if: github.event_name != 'workflow_dispatch' && matrix.provider == 'newprovider' && env.NEW_PROVIDER_API_KEY == ''
  run: echo "New Provider secrets not configured; skipping New Provider live tests."

- name: Authenticate to New Provider (if needed)
  if: github.event_name != 'workflow_dispatch' && matrix.provider == 'newprovider' && env.NEW_PROVIDER_API_KEY != ''
  run: |
    # Add authentication steps here
    # Example: configure API credentials, set up access tokens, etc.

- name: Start Llama Stack container (New Provider)
  if: github.event_name != 'workflow_dispatch' && matrix.provider == 'newprovider' && env.NEW_PROVIDER_API_KEY != ''
  shell: bash
  run: |
    docker run -d --net=host -p 8321:8321 \
      -e NEW_PROVIDER_API_KEY="${{ env.NEW_PROVIDER_API_KEY }}" \
      -e NEW_PROVIDER_REGION="${{ env.NEW_PROVIDER_REGION }}" \
      -e INFERENCE_MODEL="${INFERENCE_MODEL}" \
      --name llama-stack-newprovider \
      "${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}"
    echo "Waiting for New Provider-backed Llama Stack..."
    for i in {1..60}; do
      curl -fsS http://127.0.0.1:8321/v1/health 2>/dev/null | grep -q '"status":"OK"' && break
      if [ "$i" -eq 60 ]; then
        docker logs llama-stack-newprovider || true
        docker rm -f llama-stack-newprovider || true
        exit 1
      fi
      sleep 1
    done

- name: Integration tests (New Provider)
  if: github.event_name != 'workflow_dispatch' && matrix.provider == 'newprovider' && env.NEW_PROVIDER_API_KEY != ''
  id: integration-tests-newprovider
  env:
    NEW_PROVIDER_API_KEY: ${{ env.NEW_PROVIDER_API_KEY }}
    NEW_PROVIDER_REGION: ${{ env.NEW_PROVIDER_REGION }}
  shell: bash
  run: ./tests/run_integration_tests.sh
```

**Key points:**
- Always check `github.event_name != 'workflow_dispatch'` to skip tests for manual builds
- Check `matrix.provider == 'newprovider'` to only run for your provider
- Check for required secrets/environment variables
- Use a unique container name (e.g., `llama-stack-newprovider`)
- Pass all required environment variables to the container
- Wait for health check before running tests
- Export environment variables needed by the test script

#### 3.4 Update Cleanup Step

In the `cleanup` step (around line 204), add your container name:

```yaml
- name: cleanup
  if: always()
  shell: bash
  run: |
    docker rm -f vllm llama-stack llama-stack-vertex llama-stack-newprovider >/dev/null 2>&1 || true
```

#### 3.5 Update Log Gathering (if needed)

In the `Gather logs` step (around line 172), add your container logs:

```yaml
docker logs llama-stack-newprovider > "$TARGET_DIR/llama-stack-newprovider.log" 2>&1 || true
```

### Step 4: Update `distribution/run.yaml`

Ensure that your provider is configured in the Llama Stack distribution configuration. Check `distribution/run.yaml` and verify that:

1. The provider is listed in the supported providers section
2. The provider configuration includes all required settings
3. The model format matches what you're using in the test scripts

**Example:**
```yaml
providers:
  newprovider:
    enabled: true
    api_key: ${NEW_PROVIDER_API_KEY}
    region: ${NEW_PROVIDER_REGION}
    # ... other provider-specific settings
```

### Step 5: Update Documentation

1. **Update this file (`docs/live-tests-guide.md`)**:
   - Add your provider to the "Supported Providers" section
   - Add a "Using New Provider" subsection under "Running Tests Locally"
   - Update the CI/CD section if your provider has special requirements

2. **Update `README.md`** (if applicable):
   - Document any provider-specific prerequisites
   - Add examples of how to use your provider

### Step 6: Add Required GitHub Secrets

For CI/CD to work, add the following secrets in your GitHub repository settings:

- `NEW_PROVIDER_API_KEY` – API key or access token for your provider
- `NEW_PROVIDER_REGION` – Optional, region for your provider (if applicable)

**To add secrets:**
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each required secret

### Step 7: Test Your Implementation

1. **Local Testing:**
   ```bash
   export NEW_PROVIDER_API_KEY=your-key
   export NEW_PROVIDER_REGION=us-east-1
   ./scripts/run-live-tests-local.sh
   ```

2. **CI Testing:**
   - Create a PR with your changes
   - Verify the new provider matrix job appears in the workflow run
   - Check that tests run successfully (or skip gracefully if secrets aren't configured)

### Common Patterns

- **No Authentication Required**: Skip authentication steps, only check for configuration variables
- **API Key Authentication**: Store key in GitHub secrets, pass as environment variable
- **OAuth/Workload Identity**: Follow the Vertex AI pattern with authentication actions
- **Container Required**: If your provider needs a separate container (like vLLM), add a setup step similar to the VLLM action
- **Smoke Tests**: If your provider should run smoke tests, add a step similar to the vLLM smoke test step

### Example: Complete Provider Addition

For a complete example, see how `vertex` provider was added:
- Provider detection: `scripts/run-live-tests-local.sh` lines 30-36
- Container setup: `scripts/run-live-tests-local.sh` lines 82-86
- Test script integration: `tests/run_integration_tests.sh` lines 61-65
- Workflow matrix: `.github/workflows/redhat-distro-container.yml` lines 60, 124-170
