#!/bin/bash

set -uo pipefail

function start_and_wait_for_llama_stack_container {
  # Start llama stack
  docker run \
    -d \
    --pull=never \
    --net=host \
    -p 8321:8321 \
    --env INFERENCE_MODEL="$INFERENCE_MODEL" \
    --env EMBEDDING_MODEL="$EMBEDDING_MODEL" \
    --env VLLM_URL="$VLLM_URL" \
    --env TRUSTYAI_LMEVAL_USE_K8S=False \
    --name llama-stack \
    "$IMAGE_NAME:$GITHUB_SHA"
  echo "Started Llama Stack container..."

  # Wait for llama stack to be ready by doing a health check
  echo "Waiting for Llama Stack server..."
  for i in {1..60}; do
    echo "Attempt $i to connect to Llama Stack..."
    resp=$(curl -fsS http://127.0.0.1:8321/v1/health)
    if [ "$resp" == '{"status":"OK"}' ]; then
      echo "Llama Stack server is up!"
      return
    fi
    sleep 1
  done
  echo "Llama Stack server failed to start :("
  echo "Container logs:"
  docker logs llama-stack || true
  exit 1
}

function test_model_list {
  echo "===> Looking for model $INFERENCE_MODEL..."
  resp=$(curl -fsS http://127.0.0.1:8321/v1/models)
  if echo "$resp" | grep -q "$INFERENCE_MODEL"; then
    echo "Model $INFERENCE_MODEL was found :)"
    return
  else
    echo "Model $INFERENCE_MODEL was not found :("
    echo "Container logs:"
    docker logs llama-stack || true
    exit 1
  fi
}

function test_model_openai_inference {
  echo "===> Attempting to chat with model $INFERENCE_MODEL..."
  resp=$(curl -fsS http://127.0.0.1:8321/v1/openai/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"$INFERENCE_MODEL\",\"messages\": [{\"role\": \"user\", \"content\": \"What color is grass?\"}], \"max_tokens\": 10, \"temperature\": 0.0}")
  if echo "$resp" | grep -q "green"; then
    echo "===> Inference is working :)"
    return
  else
    echo "===> Inference is not working :("
    echo "Container logs:"
    docker logs llama-stack || true
    exit 1
  fi
}

main() {
  echo "===> Starting smoke test..."
  start_and_wait_for_llama_stack_container
  test_model_list
  test_model_openai_inference
  echo "===> Smoke test completed successfully!"
}

main "$@"
exit 0
