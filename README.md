# Red Hat Distribution Build Instructions

This directory contains the necessary files to build a Red Hat compatible container image for the llama-stack.

## Prerequisites

- Python >=3.11
- `llama` CLI tool installed: `pip install llama-stack`
- Podman or Docker installed

## Build Modes

The build script supports three modes:

### 1. Full Mode (Default)
Includes all features including TrustyAI providers that require Kubernetes/OpenShift:
```bash
./distribution/build.py
```

### 2. Standalone Mode
Builds a version without Kubernetes dependencies, using Llama Guard for safety:
```bash
./distribution/build.py --standalone
```

### 3. Unified Mode (Recommended)
Builds a single container that supports both modes via environment variables:
```bash
./distribution/build.py --unified
```

## Generating the Containerfile

The Containerfile is auto-generated from a template. To generate it:

1. Make sure you have the `llama` CLI tool installed
2. Run the build script from root of this git repo with your desired mode:
   ```bash
   ./distribution/build.py [--standalone] [--unified]
   ```

This will:
- Check for the `llama` CLI installation
- Generate dependencies using `llama stack build`
- Create a new `Containerfile` with the required dependencies

## Editing the Containerfile

The Containerfile is auto-generated from a template. To edit it, you can modify the template in `distribution/Containerfile.in` and run the build script again.
NEVER edit the generated `Containerfile` manually.

## Building the Container Image

Once the Containerfile is generated, you can build the image using either Podman or Docker:

### Using Podman build image for x86_64

```bash
podman build --platform linux/amd64 -f distribution/Containerfile -t llama-stack-rh .
```

### Using Docker

```bash
docker build -f distribution/Containerfile -t llama-stack-rh .
```

## Running the Container

### Running in Standalone Mode (No Kubernetes)

To run the container in standalone mode without Kubernetes dependencies, set the `STANDALONE` environment variable:

```bash
# Using Docker
docker run -e STANDALONE=true \
  -e VLLM_URL=http://host.docker.internal:8000/v1 \
  -e INFERENCE_MODEL=your-model-name \
  -p 8321:8321 \
  llama-stack-rh

# Using Podman
podman run -e STANDALONE=true \
  -e VLLM_URL=http://host.docker.internal:8000/v1 \
  -e INFERENCE_MODEL=your-model-name \
  -p 8321:8321 \
  llama-stack-rh
```

### Running in Full Mode (With Kubernetes)

To run with all features including TrustyAI providers (requires Kubernetes/OpenShift):

```bash
# Using Docker
docker run -p 8321:8321 llama-stack-rh

# Using Podman
podman run -p 8321:8321 llama-stack-rh
```

## Notes

- The generated Containerfile should not be modified manually as it will be overwritten the next time you run the build script

## Push the image to a registry

```bash
podman push <build-ID> quay.io/opendatahub/llama-stack:rh-distribution
```
