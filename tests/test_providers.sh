#!/bin/bash
set -uo pipefail

# Test that conditional provider loading respects env vars.
# Each test starts its own container with its own name and port.

function check_provider {
  local port="$1" provider_type="$2" expect="$3" name="$4"
  resp=$(curl -fsS "http://127.0.0.1:${port}/v1/providers" 2>/dev/null) || true
  match=$(echo "$resp" | jq --arg pt "$provider_type" \
    '[.data[] | select(.provider_type == $pt)] | length')
  match=${match:-0}
  if [ "$expect" = "present" ] && [ "$match" -gt 0 ]; then return 0; fi
  if [ "$expect" = "absent" ] && [ "$match" -eq 0 ]; then return 0; fi
  echo "FAIL: $provider_type expected $expect"; docker logs "$name" || true; return 1
}

function run_container {
  local name="$1" port="$2"; shift 2
  docker rm -f "$name" 2>/dev/null || true
  docker run -d --pull=never --net=host --name "$name" "$@" \
    "$IMAGE_NAME:${IMAGE_TAG:-$GITHUB_SHA}" --port "$port"
  for _ in {1..60}; do
    curl -fsS "http://127.0.0.1:${port}/v1/health" 2>/dev/null && return 0
    sleep 1
  done
  echo "Server $name failed to start"; docker logs "$name" || true; return 1
}

failed=()

run_container pt-no-milvus 8421 && \
  check_provider 8421 inline::milvus absent pt-no-milvus || failed+=(milvus-absent)
docker rm -f pt-no-milvus 2>/dev/null || true

run_container pt-with-milvus 8422 --env ENABLE_INLINE_MILVUS=true && \
  check_provider 8422 inline::milvus present pt-with-milvus || failed+=(milvus-present)
docker rm -f pt-with-milvus 2>/dev/null || true

if [ ${#failed[@]} -eq 0 ]; then echo "Provider tests passed"; exit 0; fi
echo "Provider tests failed: ${failed[*]}"; exit 1
