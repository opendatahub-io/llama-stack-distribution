# vLLM CPU Container Images

This directory contains a multi-stage Containerfile that builds [vLLM](https://github.com/vllm-project/vllm) from source for CPU (AVX2, no AVX-512 requirement) and includes pre-downloaded HuggingFace models.

## Build Arguments

| Argument | Default | Description |
|---|---|---|
| `INFERENCE_MODEL` | *(required)* | HuggingFace model ID for inference |
| `EMBEDDING_MODEL` | *(required)* | HuggingFace model ID for embeddings |
| `VLLM_VERSION` | `v0.17.0` | vLLM git tag to build from source |
| `PYTHON_VERSION` | `3.12` | Python version for the venv |
| `MAX_JOBS` | `4` | Parallel compilation jobs for the build stage |

## Building

```bash
docker build . \
    --build-arg INFERENCE_MODEL="Qwen/Qwen3-0.6B" \
    --build-arg EMBEDDING_MODEL="ibm-granite/granite-embedding-125m-english" \
    --tag vllm-cpu:Qwen3-granite-embedding-125m \
    --file vllm/Containerfile
```

### Gated Models

For models that require authentication (e.g., gated models), provide your HuggingFace token using Docker build secrets:

```bash
export HF_TOKEN="your_huggingface_token_here"
docker build . \
    --build-arg INFERENCE_MODEL="Qwen/Qwen3-0.6B" \
    --build-arg EMBEDDING_MODEL="ibm-granite/granite-embedding-125m-english" \
    --secret id=hf_token,env=HF_TOKEN \
    --tag vllm-cpu:Qwen3-granite-embedding-125m \
    --file vllm/Containerfile
```

> [!TIP]
> Using Docker build secrets is more secure than build arguments because secrets are not persisted in the image layers or visible in the build history.

## Running

The entrypoint is `vllm serve`, so pass model and serving arguments directly. The container can only serve one model at a time.

### Inference model

```bash
docker run -d \
    --name vllm-inference \
    --privileged=true \
    --net=host \
    vllm-cpu:Qwen3-granite-embedding-125m \
    --host 0.0.0.0 \
    --port 8000 \
    --enable-auto-tool-choice \
    --tool-call-parser hermes \
    --model /root/.cache/Qwen/Qwen3-0.6B \
    --served-model-name Qwen/Qwen3-0.6B \
    --max-model-len 8192
```

### Embedding model

```bash
docker run -d \
    --name vllm-embedding \
    --privileged=true \
    --net=host \
    vllm-cpu:Qwen3-granite-embedding-125m \
    --host 0.0.0.0 \
    --port 8001 \
    --model /root/.cache/ibm-granite/granite-embedding-125m-english \
    --served-model-name ibm-granite/granite-embedding-125m-english
```

> [!TIP]
> Additional vLLM arguments can be passed directly. Models are stored under `/root/.cache/<model_id>`.

## How it Works

The Containerfile uses a two-stage build:

1. **Build stage** -- Clones vLLM at the specified version and compiles a CPU-only wheel with `VLLM_CPU_DISABLE_AVX512=1` and `VLLM_CPU_AVX2=1`. This ensures the resulting binary runs on any x86-64 CPU with AVX2 support (including AMD EPYC Zen 1-3 and all GitHub Actions runners).

2. **Release stage** -- Installs the wheel and runtime dependencies on a clean Ubuntu 22.04 base, then downloads the specified models from HuggingFace at build time.
