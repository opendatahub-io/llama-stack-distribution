# Open Data Hub Llama Stack Distribution

[![Build](https://github.com/opendatahub-io/llama-stack-distribution/actions/workflows/redhat-distro-container.yml/badge.svg?branch=main)](https://github.com/opendatahub-io/llama-stack-distribution/actions/workflows/redhat-distro-container.yml)

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

You can see the source code that implements this build strategy [here](.github/workflows/redhat-distro-container.yml).

### Running with a custom run YAML

The distribution image allows you to run a custom run YAML file within it. To do so, run the image in the following way. The "path" mentioned should be the path to your custom run YAML file.

```bash
podman run \
  -p 8321:8321 \
  -v <path_on_host>:<path_in_container> \
  -e RUN_CONFIG_PATH=<path_in_container> \
  quay.io/opendatahub/llama-stack:<tag>
```

> [!IMPORTANT]
> The distribution image ships with various dependencies already pre-installed. There is *no* guarantee that your custom run YAML will necessarily work with the included dependencies.

## Slack build notifications

Message is sent on successful image push (`push` / `workflow_dispatch`). Script: `scripts/notify_slack_build.sh`.

### One channel

1. Add repo secret: **Settings → Secrets and variables → Actions** → New repository secret
   - Name: `WH_SLACK_TEAM_LLS_CORE`
   - Value: webhook URL (e.g. `https://hooks.slack.com/services/...`)
2. Workflow already uses it; no change.

### More channels (same message to all)

1. Add another secret, e.g. `WH_SLACK_OTHER`, with that channel’s webhook URL.
2. In [.github/workflows/redhat-distro-container.yml](.github/workflows/redhat-distro-container.yml), in the "Notify Slack on successful image push to Quay" step, set:

```yaml
env:
  SLACK_WEBHOOK_URLS: ${{ secrets.WH_SLACK_TEAM_LLS_CORE }},${{ secrets.WH_SLACK_OTHER }}
  # ... rest unchanged
```

### Different channel per registry

Set webhook(s) in the workflow from `env.REGISTRY`, e.g.:

```yaml
env:
  SLACK_WEBHOOK_URL: ${{ env.REGISTRY == 'quay.io' && secrets.WH_SLACK_QUAY || secrets.WH_SLACK_OTHER }}
  # ...
```
