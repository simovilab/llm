#!/bin/sh
# Registers the stack's models in LiteLLM (stored in its database) if they are
# not registered yet. Safe to run repeatedly. Uses the master key from .env.
#
#   LITELLM_URL     default https://$LLM_HOST (dev: http://localhost:4000)
#   OLLAMA_API_BASE default http://ollama:11434 (the Ollama container)
#   LAYA_API_BASE   if set, also registers Laya, served by an Ollama that can run
#                   it (dev: http://host.docker.internal:11434, a native macOS Ollama)
set -eu

cd "$(dirname "$0")/.."

set -a
. ./.env
set +a

: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY is not set in .env}"

LITELLM_URL="${LITELLM_URL:-https://${LLM_HOST:-llm.simovi.org}}"
OLLAMA_API_BASE="${OLLAMA_API_BASE:-http://ollama:11434}"

existing=$(curl --fail-with-body -sS "$LITELLM_URL/v1/models" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY")

# register <public name> <litellm model> <api_base> [api_key]
register() {
  if printf '%s' "$existing" | grep -q "\"id\": *\"$1\""; then
    echo "$1: already registered"
    return
  fi
  key=""
  if [ -n "${4:-}" ]; then key=", \"api_key\": \"$4\""; fi
  curl --fail-with-body -sS "$LITELLM_URL/model/new" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model_name\": \"$1\", \"litellm_params\": {\"model\": \"$2\", \"api_base\": \"$3\"$key}}" >/dev/null
  echo "$1: registered"
}

register gemma4 ollama_chat/gemma4:e4b "$OLLAMA_API_BASE"
register embeddinggemma ollama/embeddinggemma "$OLLAMA_API_BASE"

if [ -n "${LAYA_API_BASE:-}" ]; then
  # typesafe provider: same /v1/systemone protocol; Ollama ignores the key, LiteLLM requires one.
  register laya typesafe/laya "$LAYA_API_BASE" ollama
fi
