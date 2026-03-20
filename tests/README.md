# Testing

This document describes the testing strategy for the Open Data Hub Llama Stack Distribution.

## Test Scripts

All test scripts live in the `tests/` directory:

| File | Purpose |
|------|---------|
| `smoke.sh` | Smoke tests against a running Llama Stack container |
| `run_integration_tests.sh` | Integration tests using upstream llama-stack's pytest suite |
| `test_utils.sh` | Shared utility functions (e.g., `validate_model_parameter`) |

### Smoke Tests (`smoke.sh`)

Smoke tests verify the container image works end-to-end. The script:

1. **Starts the Llama Stack container** with environment variables for inference models, embedding models, and database configuration, then waits up to 60 seconds for the `/v1/health` endpoint to return `OK`.
2. **Model listing** - Verifies each configured model appears in the `/v1/models` response.
3. **OpenAI-compatible inference** - Sends a chat completion request to `/v1/chat/completions` and validates the response.
4. **PostgreSQL verification** - Checks that expected database tables (`llamastack_kvstore`, `inference_store`) are created and populated with data after inference.

Models tested depend on available credentials:

| Model | Environment Variable | Always Tested |
|-------|---------------------|---------------|
| vLLM inference model (`Qwen/Qwen3-0.6B`) | `VLLM_INFERENCE_MODEL` | Yes |
| Embedding model (`ibm-granite/granite-embedding-125m-english`) | `EMBEDDING_MODEL` | Yes (list only) |
| Vertex AI model (`google/gemini-2.0-flash`) | `VERTEX_AI_PROJECT` | Only if set |
| OpenAI model (`gpt-4o-mini`) | `OPENAI_API_KEY` | Only if set |

#### Running locally

```bash
# Required environment variables
export VLLM_INFERENCE_MODEL="vllm-inference/Qwen/Qwen3-0.6B"
export EMBEDDING_MODEL="sentence-transformers/ibm-granite/granite-embedding-125m-english"
export VLLM_URL="http://localhost:8000/v1"
export IMAGE_NAME="quay.io/opendatahub/llama-stack"
export GITHUB_SHA="<image-tag>"

# Optional (enables additional model tests)
export VERTEX_AI_PROJECT="<project>"
export VERTEX_AI_LOCATION="us-central1"
export OPENAI_API_KEY="<key>"

./tests/smoke.sh
```

### Integration Tests (`run_integration_tests.sh`)

Integration tests run the upstream [llama-stack pytest suite](https://github.com/llamastack/llama-stack) against the distribution's running server. The script:

1. **Extracts the llama-stack version** from the generated `distribution/Containerfile` to ensure tests match the bundled version.
2. **Clones the llama-stack repository** at the matching version tag into `/tmp/llama-stack-integration-tests`.
3. **Runs `pytest`** against `tests/integration/inference/` with `llama-stack-client` and `ollama` installed, pointing at the distribution's `config.yaml`.

Tests are run for each configured inference model (vLLM, and optionally Vertex AI and OpenAI).

Some tests are currently skipped:

- `test_text_chat_completion_tool_calling_tools_not_in_request`
- `test_text_chat_completion_structured_output`
- `test_text_chat_completion_non_streaming`
- `test_openai_chat_completion_non_streaming`
- `test_openai_chat_completion_with_tool_choice_none`
- `test_openai_chat_completion_with_tools`
- `test_openai_format_preserves_complex_schemas`
- `test_multiple_tools_with_different_schemas`
- `test_tool_with_complex_schema`
- `test_tool_without_schema`
- `test_openai_completion_guided_choice` (requires vLLM >= v0.12.0)

#### Running locally

```bash
# Requires a running Llama Stack server and vLLM endpoint
./tests/run_integration_tests.sh
```

## CI/CD Pipelines

Testing is automated via GitHub Actions workflows in `.github/workflows/`.

### Container Build, Test & Publish (`redhat-distro-container.yml`)

The main CI pipeline that builds, tests, and publishes the container image. It runs on:

- **Pull requests** to `main` and `rhoai-v*` branches (when `distribution/`, `tests/`, or workflow files change)
- **Pushes** to `main` and `rhoai-v*` branches
- **Manual dispatch** (`workflow_dispatch`) to build from an arbitrary llama-stack commit
- **Nightly schedule** (6 AM UTC) to test the `main` branch of llama-stack

Pipeline steps:

1. **Build** the container image for AMD64 (loaded for testing) and ARM64 (build verification only)
2. **Start vLLM** via the `setup-vllm` action (CPU-based `Qwen3-0.6B` model with Hermes tool-call parser)
3. **Start PostgreSQL** via the `setup-postgres` action (PostgreSQL 17)
4. **Run smoke tests** (`tests/smoke.sh`)
5. **Run integration tests** (`tests/run_integration_tests.sh`)
6. **Publish** multi-arch image to `quay.io/opendatahub/llama-stack` (on push to `main` when `distribution/` changed, or on manual dispatch)
7. **Notify Slack** on failure or successful publish

Logs from all containers (llama-stack, vLLM, PostgreSQL) and system info are uploaded as artifacts with 7-day retention.

### Pre-commit (`pre-commit.yml`)

Runs on all pull requests and pushes to `main`. Executes the full pre-commit hook suite and verifies no files were changed or created:

- **Ruff** - Python linting and formatting
- **Shellcheck** - Shell script linting
- **Actionlint** - GitHub Actions workflow linting
- **Standard hooks** - merge conflict detection, trailing whitespace, large file checks, YAML/JSON/TOML validation, executable shebangs, private key detection, mixed line endings
- **Distribution Build** (`distribution/build.py`) - Regenerates `distribution/Containerfile`
- **Distribution Documentation** (`scripts/gen_distro_docs.py`) - Regenerates `distribution/README.md`

### Semantic PR Titles (`semantic-pr.yml`)

Validates that pull request titles follow [Conventional Commits](https://www.conventionalcommits.org/) format (e.g., `feat:`, `fix:`, `docs:`).

### Stale Bot (`stale_bot.yml`)

Automatically marks issues and PRs as stale after 60 days of inactivity and closes them after 30 more days. Runs daily at midnight UTC.
