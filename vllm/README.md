# vLLM CPU container images with pre-downloaded models

This directory contains a Containerfile that builds vLLM from source for CPU and includes pre-downloaded HuggingFace models. The image supports both x86_64 and arm64 architectures.

## Building

```bash
DOCKER_BUILDKIT=1 docker build . \
    --build-arg INFERENCE_MODEL="Qwen/Qwen3-0.6B" \
    --build-arg EMBEDDING_MODEL="ibm-granite/granite-embedding-125m-english" \
    --tag opendatahub/vllm-cpu:Qwen3-granite-embedding-125m \
    --file vllm/Containerfile
```

### Gated Models

For models that require authentication (e.g., gated models), provide your HuggingFace token using Docker build secrets:

```bash
export HF_TOKEN="your_huggingface_token_here"
DOCKER_BUILDKIT=1 docker build . \
    --build-arg INFERENCE_MODEL="Qwen/Qwen3-0.6B" \
    --build-arg EMBEDDING_MODEL="ibm-granite/granite-embedding-125m-english" \
    --secret id=hf_token,env=HF_TOKEN \
    --tag opendatahub/vllm-cpu:Qwen3-granite-embedding-125m \
    --file vllm/Containerfile
```

> [!TIP]
> Using Docker build secrets is more secure than build arguments because secrets are not persisted in the image layers or visible in the build history.

## Running

The container can only serve one model at a time - specify this via the `--model` argument

For example, for serving the `Qwen/Qwen3-0.6B` inference model, you would run something like

```bash
docker run -d \
    --name vllm-inference \
    --privileged=true \
    --net=host \
    opendatahub/vllm-cpu:Qwen3-granite-embedding-125m \
    --host 0.0.0.0 \
    --port 8000 \
    --enable-auto-tool-choice \
    --tool-call-parser hermes \
    --model /root/.cache/Qwen/Qwen3-0.6B \
    --served-model-name Qwen/Qwen3-0.6B \
    --max-model-len 8192
```

For serving the `ibm-granite/granite-embedding-125m-english` embedding model, you would run something like

```bash
docker run -d \
    --name vllm-embedding \
    --privileged=true \
    --net=host \
    opendatahub/vllm-cpu:Qwen3-granite-embedding-125m \
    --host 0.0.0.0 \
    --port 8001 \
    --model /root/.cache/ibm-granite/granite-embedding-125m-english \
    --served-model-name ibm-granite/granite-embedding-125m-english
```

> [!TIP]
> Additional vLLM arguments can be passed directly
