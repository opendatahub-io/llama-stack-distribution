#!/bin/sh
set -e

if [ -n "$RUN_CONFIG_PATH" ] && [ -f "$RUN_CONFIG_PATH" ]; then
  exec llama stack run "$RUN_CONFIG_PATH" "$@"
fi

if [ -n "$DISTRO_NAME" ]; then
  exec llama stack run "$DISTRO_NAME" "$@"
fi

exec llama stack run /opt/app-root/run.yaml "$@"
