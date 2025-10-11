# Open Data Hub Llama Stack Distribution

![Build](https://github.com/opendatahub-io/llama-stack-distribution/actions/workflows/redhat-distro-container.yml/badge.svg?branch=main)

This directory contains the necessary files to build an Open Data Hub-compatible container image for [Llama Stack](https://github.com/llamastack/llama-stack).

To learn more about the distribution image content, see the [README](distribution/README.md) in the `distribution/` directory.

## Build Instructions

### Prerequisites

- The `pre-commit` tool is [installed](https://pre-commit.com/#install)

### Generating the Containerfile

The Containerfile is auto-generated from a template. To generate it:

```
pre-commit run --all-files
```

This will:
- Install the dependencies (llama-stack etc) in a virtual environment
- Execute the build script `./distribution/build.py`

The build script will:
- Execute the `llama` CLI to generate the dependencies
- Create a new `Containerfile` with the required dependencies

### Editing the Containerfile

The Containerfile is auto-generated from a template. To edit it, you can modify the template in `distribution/Containerfile.in` and run pre-commit again.

> [!WARNING]
> *NEVER* edit the generated `Containerfile` manually.

## Run Instructions

> [!TIP]
> Ensure you include any env vars you might need for providers in the container env - you can read more about that [here](distribution/README.md).

```bash
podman run -p 8321:8321 quay.io/opendatahub/llama-stack:latest
```
