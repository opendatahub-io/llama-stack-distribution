#!/bin/bash

set -uo pipefail

# Verify that Llama Stack container is running
function verify_llama_stack_container {
  if ! docker ps --format '{{.Names}}' | grep -q '^llama-stack$'; then
    echo "Error: llama-stack container is not running"
    echo "Expected container 'llama-stack' to be started by setup-llama-stack action"
    exit 1
  fi

  # Verify health endpoint is responding
  resp=$(curl -fsS http://127.0.0.1:8321/v1/health 2>/dev/null)
  if [ "$resp" != '{"status":"OK"}' ]; then
    echo "Error: Llama Stack health check failed"
    echo "Response: $resp"
    echo "Container logs:"
    docker logs llama-stack || true
    exit 1
  fi
  echo "Llama Stack container is running and healthy"
}

function test_model_list {
  for model in "$INFERENCE_MODEL" "$EMBEDDING_MODEL"; do
    echo "===> Looking for model $model..."
    resp=$(curl -fsS http://127.0.0.1:8321/v1/models)
    echo "Response: $resp"
    if echo "$resp" | grep -q "$model"; then
      echo "Model $model was found :)"
      continue
    else
      echo "Model $model was not found :("
      echo "Response: $resp"
      echo "Container logs:"
      docker logs llama-stack || true
      return 1
    fi
  done
  return 0
}

function test_model_openai_inference {
  echo "===> Attempting to chat with model $INFERENCE_MODEL..."
  resp=$(curl -fsS http://127.0.0.1:8321/v1/chat/completions -H "Content-Type: application/json" -d "{\"model\": \"vllm-inference/$INFERENCE_MODEL\",\"messages\": [{\"role\": \"user\", \"content\": \"What color is grass?\"}], \"max_tokens\": 128, \"temperature\": 0.0}")
  if echo "$resp" | grep -q "green"; then
    echo "===> Inference is working :)"
    return
  else
    echo "===> Inference is not working :("
    echo "Response: $resp"
    echo "Container logs:"
    docker logs llama-stack || true
    exit 1
  fi
}

main() {
  echo "===> Starting smoke test..."
  verify_llama_stack_container
  if ! test_model_list; then
    echo "Model list test failed :("
    exit 1
  fi
  test_model_openai_inference
  echo "===> Smoke test completed successfully!"
}

main "$@"
exit 0
