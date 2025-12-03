# Live Tests Guide

This guide explains how to run Llama Stack integration tests in live inference mode against both vLLM and Vertex AI providers.

## Supported Providers

- **vllm-inference** – Local VLLM inference server (default)
- **vertexai** – Google Cloud Vertex AI (when GCP secrets are configured)

In CI, both providers are tested in parallel using a matrix strategy in `.github/workflows/run-integration-tests.yml`. A single Llama Stack instance is deployed (by the vllm-inference matrix entry) and both test suites run in parallel.

## Prerequisites

- **Docker/Podman** – Build and run the container image (for local testing)
- **gcloud CLI** – Authenticate to GCP for Vertex AI (for Vertex AI testing)
- **uv** – Python package manager (installed automatically in CI)

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

# Set environment variables and run tests
export INFERENCE_MODEL="vllm-inference/Qwen/Qwen3-0.6B"
export EMBEDDING_MODEL="ibm-granite/granite-embedding-125m-english"
export VLLM_URL="http://localhost:8000/v1"
./tests/run_integration_tests.sh

# Clean up
podman rm -f vllm
```

### Using Vertex AI

```bash
# Authenticate to GCP
export VERTEX_AI_PROJECT=your-gcp-project-id
export VERTEX_AI_LOCATION=us-central1        # optional, defaults to us-central1
gcloud auth application-default login        # ensures ADC credentials exist

# Set environment variables and run tests
export INFERENCE_MODEL="vertexai/google/gemini-2.0-flash"
export EMBEDDING_MODEL="ibm-granite/granite-embedding-125m-english"
export VERTEX_AI_PROJECT="your-gcp-project-id"
export VERTEX_AI_LOCATION="us-central1"
./tests/run_integration_tests.sh
```

**Note:** The test script (`tests/run_integration_tests.sh`) is provider-agnostic and expects the `INFERENCE_MODEL` environment variable to be set with the full provider prefix (e.g., `vllm-inference/Qwen/Qwen3-0.6B` or `vertexai/google/gemini-2.0-flash`).

## CI/CD Workflow

The `.github/workflows/run-integration-tests.yml` workflow runs integration tests for both providers in parallel using a matrix strategy. The `.github/workflows/redhat-distro-container.yml` workflow handles building and publishing images only after tests pass.

### Triggering

- **Pull Requests**: Automatically runs on PRs to `main`, `rhoai-v*`, and `konflux-poc*` branches
- **Push**: Runs on pushes to `main` and `rhoai-v*` branches
- **Scheduled**: Daily at 06:00 UTC
- **Manual**: `gh workflow run run-integration-tests.yml` or via the GitHub UI

### Required Secrets

For Vertex AI tests to run in CI:

- `VERTEX_AI_PROJECT` – Target GCP project
- `GCP_WORKLOAD_IDENTITY_PROVIDER` – Used for OIDC authentication via Workload Identity Federation
- `VERTEX_AI_LOCATION` – Optional, defaults to `us-central1` if not set

If Vertex AI secrets are not configured, the Vertex AI tests will be skipped with a warning message.

### How it Works

1. **Deployment Phase** (vllm-inference matrix entry):
   - Builds the container image once
   - Authenticates to Google Cloud (if Vertex AI secrets are configured)
   - Starts VLLM container (non-blocking, starts early)
   - Starts Llama Stack container with **both vLLM and Vertex AI support** configured
   - Verifies deployment is ready

2. **Testing Phase** (Parallel):
   - **vLLM Tests** (vllm-inference matrix entry): Validates vLLM is ready, runs smoke tests and integration tests
   - **Vertex AI Tests** (vertexai matrix entry): Waits for deployment, authenticates to GCP, runs integration tests
   - Both test suites run in parallel using the matrix strategy

3. **Publish Phase**: The `redhat-distro-container.yml` workflow triggers after tests pass and publishes the image to Quay.io

**Key Architecture:**
- **Single Deployment**: One Llama Stack instance is deployed by the vllm-inference matrix entry with both vLLM and Vertex AI providers configured
- **Parallel Execution**: Tests run in parallel using a matrix strategy (`fail-fast: false` ensures both run independently)
- **Optimized Startup**: vLLM starts early (non-blocking) and is validated before tests run
- **Early Cleanup**: vLLM is stopped immediately after vLLM tests complete

**Important:** Vertex AI is a remote cloud service, so no local container is needed for Vertex AI itself. However, the Llama Stack container is configured to support both vLLM (local) and Vertex AI (remote) providers simultaneously.

**Note:** Matrix jobs run on separate runners by default, so containers aren't shared. The vertexai entry waits for deployment, assuming both jobs run on the same runner (not guaranteed with GitHub-hosted runners).

## Adding New Providers

This section provides step-by-step instructions for adding support for a new inference provider. The test script (`tests/run_integration_tests.sh`) is provider-agnostic and expects `INFERENCE_MODEL` to be set with the full provider prefix (e.g., `provider-name/model-name`). All provider-specific logic is handled in the GitHub Actions workflow.

**For Code Agents (Cursor, Copilot, Claude):** Follow these steps in order. Each step includes exact file locations, code patterns, and examples. Use the existing `vllm-inference` and `vertexai` implementations as reference.

### Step 1: Update `.github/workflows/run-integration-tests.yml`

#### 1.1 Add Environment Variables

**Location:** `.github/workflows/run-integration-tests.yml`, in the `jobs.test.env` section (around line 48)

Add your provider's environment variables to the job-level `env` section:

```yaml
env:
  INFERENCE_MODEL: Qwen/Qwen3-0.6B
  EMBEDDING_MODEL: ibm-granite/granite-embedding-125m-english
  VLLM_URL: http://localhost:8000/v1
  LLAMA_STACK_COMMIT_SHA: ${{ github.event_name == 'workflow_dispatch' && github.event.inputs.llama_stack_commit_sha || 'main' }}
  VERTEX_AI_PROJECT: ${{ secrets.VERTEX_AI_PROJECT }}
  VERTEX_AI_LOCATION: 'us-central1'
  GCP_WORKLOAD_IDENTITY_PROVIDER: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
  # Add your provider's environment variables here:
  NEW_PROVIDER_API_KEY: ${{ secrets.NEW_PROVIDER_API_KEY }}
  NEW_PROVIDER_REGION: ${{ secrets.NEW_PROVIDER_REGION != '' && secrets.NEW_PROVIDER_REGION || 'us-east-1' }}
```

**Key points:**
- Add all environment variables your provider needs
- Use GitHub secrets for sensitive values (API keys, tokens, etc.)
- Provide default values where appropriate

#### 1.2 Add Test Configuration Variables

**Location:** `.github/workflows/run-integration-tests.yml`, in the `jobs.test.env` section (around line 49)

Add your provider's test configuration variables alongside the existing `VLLM_INFERENCE_MODEL` and `VERTEXAI_INFERENCE_MODEL`:

```yaml
env:
  # ... existing variables ...
  # Test configurations
  VLLM_INFERENCE_MODEL: Qwen/Qwen3-0.6B
  VLLM_EMBEDDING_MODEL: ibm-granite/granite-embedding-125m-english
  VERTEXAI_INFERENCE_MODEL: google/gemini-2.0-flash
  VERTEXAI_EMBEDDING_MODEL: ibm-granite/granite-embedding-125m-english
  # Add your provider's test configuration:
  NEWPROVIDER_INFERENCE_MODEL: your-model-name
  NEWPROVIDER_EMBEDDING_MODEL: ibm-granite/granite-embedding-125m-english
```

**Key points:**
- Use the pattern `{PROVIDER}_INFERENCE_MODEL` and `{PROVIDER}_EMBEDDING_MODEL` (uppercase)
- Model name should be the base model name (without provider prefix - the prefix is added automatically in test steps)

#### 1.3 Add Provider-Specific Setup Steps (if needed)

**Location:** `.github/workflows/run-integration-tests.yml`, in the "Deployment Section" (around line 80-149)

**Most providers are remote services and don't need additional setup steps** (like Vertex AI). The deployment section already handles:
- Building the image
- Authenticating to Google Cloud (if needed)
- Starting VLLM (if needed)
- Starting Llama Stack with both vLLM and Vertex AI support

**Only add provider-specific setup if your provider requires:**
- Additional authentication steps beyond what's already in the deployment section
- Special configuration that must happen before deployment

**Standard Pattern: Remote Service (Default - like Vertex AI)**

For most remote service providers, no additional setup is needed. The Llama Stack container is already configured to support multiple providers. You only need to add authentication steps if your provider requires it and it's not already handled in the deployment section.

**Example (if additional authentication is needed):**

```yaml
# Add in the Deployment Section, after "Set up Cloud SDK (Vertex)" step
- name: Authenticate to New Provider
  if: github.event_name != 'workflow_dispatch' && env.NEW_PROVIDER_API_KEY != ''
  uses: your-auth-action@v1  # or use a custom authentication step
  with:
    api_key: ${{ env.NEW_PROVIDER_API_KEY }}
    region: ${{ env.NEW_PROVIDER_REGION }}
```

**Key points:**
- Most providers don't need additional setup - the deployment section handles everything
- Only add steps if your provider requires special authentication or configuration
- Always check `github.event_name != 'workflow_dispatch'` to skip for manual builds
- Always check for required secrets/environment variables
- **No container needed** - tests connect directly to the remote provider API
- **No smoke tests needed** - same logic applies to all providers
- **No cleanup needed** - no containers to clean up

**Exception: Local Sidecar Service (vLLM only)**

If your provider requires a local sidecar service container (like vLLM), you'll need to:
1. Add container startup in the deployment section (before "Start Llama Stack")
2. Add smoke tests in the testing section (like vLLM)
3. Add containers to cleanup step

See the vLLM implementation (`.github/workflows/run-integration-tests.yml` lines 127-129 for VLLM startup, lines 155-162 for smoke tests) as a reference, but **this is the exception, not the rule**.

#### 1.4 Verify Integration Tests Step

**Location:** `.github/workflows/run-integration-tests.yml`, the "Integration tests" step (around line 200)

The integration tests step is already provider-agnostic and uses the matrix to set `INFERENCE_MODEL`:

```yaml
- name: Integration tests
  if: github.event_name != 'workflow_dispatch'
  shell: bash
  env:
    INFERENCE_MODEL: ${{ matrix.provider }}/${{ matrix.inference_model }}
    EMBEDDING_MODEL: ${{ matrix.embedding_model }}
  run: |
    echo "Running integration tests for ${{ matrix.provider }} with model ${{ matrix.inference_model }}"
    ./tests/run_integration_tests.sh
```

**No changes needed** - this step automatically works for all providers in the matrix. The `INFERENCE_MODEL` is constructed as `{provider}/{model}` (e.g., `newprovider/your-model-name`).

**Note:** The cleanup and log gathering steps are already configured for all providers. **Most providers don't need containers**, so no changes are needed to these steps. Only update them if your provider requires a local sidecar service (exception case).

### Step 2: Update `distribution/run.yaml`

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

### Step 3: Update Documentation

1. **Update this file (`docs/live-tests-guide.md`)**:
   - Add your provider to the "Supported Providers" section
   - Add a "Using New Provider" subsection under "Running Tests Locally"
   - Update the CI/CD section if your provider has special requirements

2. **Update `README.md`** (if applicable):
   - Document any provider-specific prerequisites
   - Add examples of how to use your provider

### Step 4: Add Required GitHub Secrets

For CI/CD to work, add the following secrets in your GitHub repository settings:

- `NEW_PROVIDER_API_KEY` – API key or access token for your provider
- `NEW_PROVIDER_REGION` – Optional, region for your provider (if applicable)

**To add secrets:**
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each required secret

### Step 5: Test Your Implementation

1. **Local Testing:**
   ```bash
   # Set provider-specific environment variables
   export NEW_PROVIDER_API_KEY=your-key
   export NEW_PROVIDER_REGION=us-east-1

   # Set INFERENCE_MODEL with full provider prefix
   export INFERENCE_MODEL="newprovider/your-model-name"
   export EMBEDDING_MODEL="ibm-granite/granite-embedding-125m-english"

   # Run tests directly
   ./tests/run_integration_tests.sh
   ```

2. **CI Testing:**
   - Create a PR with your changes
   - Verify the new provider matrix job appears in the workflow run
   - Check that tests run successfully (or skip gracefully if secrets aren't configured)

### Common Patterns

- **Remote Service (Standard Pattern)**: Like Vertex AI - no additional setup needed, just add test section
  - Example: Vertex AI (`.github/workflows/run-integration-tests.yml` lines 179-195)
  - No container startup needed (handled in deployment section)
  - No smoke tests needed (same logic as other providers)
  - No cleanup needed (no containers)
  - Just add a testing section with integration tests
  - **This is the standard pattern for most providers**

- **Local Sidecar Service (Exception - vLLM only)**: Like vLLM - requires a local inference server running as a sidecar
  - Example: vLLM (`.github/workflows/run-integration-tests.yml` lines 127-129 for startup, lines 155-162 for smoke tests)
  - **This is an exception** - vLLM needs a local inference server container
  - Add container startup in deployment section (before "Start Llama Stack")
  - Add smoke tests in testing section (before integration tests)
  - Clean up containers in cleanup step
  - **Only use this pattern if your provider requires a local sidecar service**

- **API Key Authentication**: Store key in GitHub secrets, pass as environment variable
  - Add to `jobs.test.env` section
  - Check in step conditions: `env.NEW_PROVIDER_API_KEY != ''`

- **OAuth/Workload Identity**: Follow the Vertex AI pattern with authentication actions
  - Use `google-github-actions/auth@v3` or similar
  - Set up Cloud SDK or equivalent
  - Use `permissions: id-token: write` in job

- **No Authentication Required**: Skip authentication steps, only check for configuration variables

### Reference Examples

**Vertex AI Provider (Standard Pattern - Remote Service):**
- Matrix entry: `.github/workflows/run-integration-tests.yml` lines 60-63
- Authentication: `.github/workflows/run-integration-tests.yml` lines 130-133 (in deployment section, vllm-inference entry)
- Wait step: `.github/workflows/run-integration-tests.yml` lines 150-161 (vertexai entry)
- Integration tests: `.github/workflows/run-integration-tests.yml` lines 200-207 (shared step)
- No container needed (remote GCP service)
- **Use this as the template for most new providers**

**vLLM Provider (Exception - Local Sidecar):**
- Matrix entry: `.github/workflows/run-integration-tests.yml` lines 57-59
- Service setup: `.github/workflows/run-integration-tests.yml` lines 86-88 (in deployment section, vllm-inference entry)
- Validation: `.github/workflows/run-integration-tests.yml` lines 170-181 (vllm-inference entry)
- Smoke tests: `.github/workflows/run-integration-tests.yml` lines 183-188 (vllm-inference entry)
- Integration tests: `.github/workflows/run-integration-tests.yml` lines 200-207 (shared step)
- **Only reference this if your provider requires a local sidecar service**

### Important Notes for Code Agents

1. **Test Script is Provider-Agnostic**: The `tests/run_integration_tests.sh` script does NOT need any changes. It simply uses the `INFERENCE_MODEL` environment variable which is set by the workflow.

2. **Matrix Strategy**: The workflow uses a matrix strategy for parallel execution. Each provider gets its own matrix entry and runs in parallel.

3. **Deployment**: Deployment happens only for the `vllm-inference` matrix entry. Other entries wait for deployment to be ready.

4. **Matrix Format**: The `inference_model` in the matrix should be the base model name. The workflow automatically constructs `{provider}/{model}` format.

5. **Conditional Steps**: All provider-specific steps must check:
   - `github.event_name != 'workflow_dispatch'` (skip for manual builds)
   - `matrix.provider == 'your-provider'` (only for your provider)
   - Required secrets/environment variables are set

6. **Integration Tests Step**: The integration tests step (line 200) is shared and works for all providers - no changes needed. The `INFERENCE_MODEL` is constructed as `{provider}/{model}` format.

7. **Containers are the Exception**: Most providers are remote services and don't need containers. Only vLLM requires a local sidecar container. **Do not add container setup steps unless your provider specifically requires a local sidecar service.**

8. **File Locations**:
   - Workflow: `.github/workflows/run-integration-tests.yml`
   - Test script: `tests/run_integration_tests.sh` (no changes needed)
   - Distribution config: `distribution/run.yaml` (verify provider is configured)
