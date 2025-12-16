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
    --env ENABLE_SENTENCE_TRANSFORMERS=True \
    --env EMBEDDING_PROVIDER=sentence-transformers \
    --env TRUSTYAI_LMEVAL_USE_K8S=False \
    --env POSTGRES_HOST="${POSTGRES_HOST:-localhost}" \
    --env POSTGRES_PORT="${POSTGRES_PORT:-5432}" \
    --env POSTGRES_DB="${POSTGRES_DB:-llamastack}" \
    --env POSTGRES_USER="${POSTGRES_USER:-llamastack}" \
    --env POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-llamastack}" \
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

function test_postgres_tables_exist {
  echo "===> Verifying PostgreSQL tables have been created..."

  # Expected tables created by llama-stack
  expected_tables=("llamastack_kvstore" "inference_store")

  # Retry for up to 10 seconds for tables to be created
  for i in {1..10}; do
    tables=$(docker exec postgres psql -U llamastack -d llamastack -t -c "SELECT tablename FROM pg_tables WHERE schemaname = 'public';" 2>/dev/null | tr -d ' ' | tr '\n' ' ')
    all_found=true
    for table in "${expected_tables[@]}"; do
      if ! echo "$tables" | grep -q "$table"; then
        all_found=false
        break
      fi
    done
    if [ "$all_found" = true ]; then
      echo "===> All expected tables found: ${expected_tables[*]}"
      echo "===> Available tables: $tables"
      return 0
    fi
    echo "Attempt $i: Waiting for tables to be created..."
    sleep 1
  done

  echo "===> PostgreSQL tables not created after 10s :("
  echo "Expected tables: ${expected_tables[*]}"
  echo "Available tables: $tables"
  docker exec postgres psql -U llamastack -d llamastack -c "\dt" || true
  return 1
}

function test_postgres_populated {
  echo "===> Verifying PostgreSQL database has been populated..."

  # Check that chat_completions table has data (retry for up to 10 seconds)
  echo "Waiting for inference_store table to be populated..."
  for i in {1..10}; do
    inference_count=$(docker exec postgres psql -U llamastack -d llamastack -t -c "SELECT COUNT(*) FROM inference_store;" 2>/dev/null | tr -d ' ')
    if [ -n "$inference_count" ] && [ "$inference_count" -gt 0 ]; then
      echo "===> inference_store table has $inference_count record(s)"
      break
    fi
    echo "Attempt $i: inference_store table not yet populated..."
    sleep 1
  done
  if [ -z "$inference_count" ] || [ "$inference_count" -eq 0 ]; then
    echo "===> PostgreSQL inference_store table is empty or doesn't exist after 10s :("
    echo "Tables in database:"
    docker exec postgres psql -U llamastack -d llamastack -c "\dt" || true
    echo "inference_store table contents:"
    docker exec postgres psql -U llamastack -d llamastack -t -c "SELECT COUNT(*) FROM inference_store;" || true
    return 1
  fi

  echo "===> PostgreSQL database verification passed :)"
  return 0
}

main() {
  echo "===> Starting smoke test..."
  start_and_wait_for_llama_stack_container
  if ! test_model_list; then
    echo "Model list test failed :("
    exit 1
  fi
  test_model_openai_inference
  if ! test_postgres_tables_exist; then
    echo "PostgreSQL tables verification failed :("
    exit 1
  fi
  if ! test_postgres_populated; then
    echo "PostgreSQL data verification failed :("
    exit 1
  fi
  echo "===> Smoke test completed successfully!"
}

main "$@"
exit 0
