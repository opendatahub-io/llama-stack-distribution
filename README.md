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
podman run -p 8321:8321 quay.io/opendatahub/llama-stack:<tag>
```

### What image tag should I use?

Various tags are maintained for this image:

- `latest` will always point to the latest image that has been built off of a merge to the `main` branch
  - You can also pull an older image built off of `main` by using the SHA of the merge commit as the tag
- `rhoai-v*-latest` will always point to the latest image that has been built off of a merge to the corresponding `rhoai-v*` branch

You can see the source code that implements this build strategy [here](.github/workflows/redhat-distro-container.yml)

### Running with a custom run YAML

The distribution image allows you to run a custom run YAML file within it. To do so, run the image in the following way. The "path" mentioned should be the path to your custom run YAML file.

```bash
podman run \
  -p 8321:8321 \
  -v <path_on_host>:<path_in_container> \
  quay.io/opendatahub/llama-stack:<tag> \
  <path_in_container>
```

> [!IMPORTANT]
> The distribution image ships with various dependencies already pre-installed. There is *no* guarantee that your custom run YAML will necessarily work with the included dependencies.
