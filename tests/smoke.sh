#!/bin/bash

set -uo pipefail

LLAMA_STACK_BASE_URL="http://127.0.0.1:8321"

function start_and_wait_for_llama_stack_container {
  # Start llama stack
  docker run \
    -d \
    --pull=never \
    --net=host \
    -p 8321:8321 \
    --env INFERENCE_MODEL="$VLLM_INFERENCE_MODEL" \
    --env EMBEDDING_MODEL="$EMBEDDING_MODEL" \
    --env VLLM_URL="$VLLM_URL" \
    --env ENABLE_SENTENCE_TRANSFORMERS=True \
    --env EMBEDDING_PROVIDER=sentence-transformers \
    --env TRUSTYAI_LMEVAL_USE_K8S=False \
    --env VERTEX_AI_PROJECT="$VERTEX_AI_PROJECT" \
    --env VERTEX_AI_LOCATION="$VERTEX_AI_LOCATION" \
    --env GOOGLE_APPLICATION_CREDENTIALS="/run/secrets/gcp-credentials" \
    --volume "$GOOGLE_APPLICATION_CREDENTIALS:/run/secrets/gcp-credentials:ro" \
    --name llama-stack \
    "$IMAGE_NAME:$GITHUB_SHA"
  echo "Started Llama Stack container..."

  # Wait for llama stack to be ready by doing a health check
  echo "Waiting for Llama Stack server..."
  for i in {1..60}; do
    echo "Attempt $i to connect to Llama Stack..."
    resp=$(curl -fsS $LLAMA_STACK_BASE_URL/v1/health)
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
  # Check if model is provided
  if [ -z "$1" ]; then
    echo "Error: No model provided"
    exit 1
  fi
  local model="$1"
  echo "===> Looking for model $model..."
  resp=$(curl -fsS $LLAMA_STACK_BASE_URL/v1/models)
  echo "Response: $resp"
  if echo "$resp" | grep -q "$model"; then
    echo "Model $model was found :)"
  else
    echo "Model $model was not found :("
    echo "Response: $resp"
    echo "Container logs:"
    docker logs llama-stack || true
    return 1
  fi
  return 0
}

function test_model_openai_inference {
  # Check if model is provided
  if [ -z "$1" ]; then
    echo "Error: No model provided"
    exit 1
  fi
  local model="$1"
  echo "===> Attempting to chat with model $model..."
  resp=$(curl -fsS $LLAMA_STACK_BASE_URL/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"$model\",\"messages\": [{\"role\": \"user\", \"content\": \"What color is grass?\"}], \"max_tokens\": 128, \"temperature\": 0.0}")
  if echo "$resp" | grep -q "green"; then
    echo "===> Inference is working :)"
    return 0
  else
    echo "===> Inference is not working :("
    echo "Response: $resp"
    echo "Container logs:"
    docker logs llama-stack || true
    return 1
  fi
}

main() {
  echo "===> Starting smoke test..."
  start_and_wait_for_llama_stack_container
  # test model list for all models
  for model in "$VLLM_INFERENCE_MODEL" "$VERTEX_AI_INFERENCE_MODEL" "$EMBEDDING_MODEL"; do
    if ! test_model_list "$model"; then
      echo "Model list test failed for $model :("
      exit 1
    fi
  done
  # test model inference for all models
  for model in "$VLLM_INFERENCE_MODEL" "$VERTEX_AI_INFERENCE_MODEL"; do
    if ! test_model_openai_inference "$model"; then
      echo "Inference test failed for $model :("
      exit 1
    fi
  done
  echo "===> Smoke test completed successfully!"
}

main "$@"
exit 0
