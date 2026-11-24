#!/bin/sh
set -e

ollama serve &
SERVER_PID=$!

# wait for the API to come up
until ollama list >/dev/null 2>&1; do
  sleep 1
done

for model in $PULL_MODELS; do
  echo "pulling $model ..."
  ollama pull "$model"
done

touch /tmp/models-ready
echo "ollama ready"
wait $SERVER_PID
