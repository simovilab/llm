#!/bin/sh
# Registers MCP_LITELLM_API_KEY (from .env) as a virtual key in LiteLLM.
# Run once after `docker compose up -d`. Uses the master key for this call only.
set -eu

cd "$(dirname "$0")/.."

set -a
. ./.env
set +a

: "${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY is not set in .env}"
: "${MCP_LITELLM_API_KEY:?MCP_LITELLM_API_KEY is not set in .env}"

LITELLM_URL="${LITELLM_URL:-https://${LLM_HOST:-llm.simovi.org}}"

curl --fail-with-body -sS "$LITELLM_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"key\": \"$MCP_LITELLM_API_KEY\", \"key_alias\": \"mcp-server\"}" >/dev/null

echo "Registered virtual key 'mcp-server'."
