# LLM Server

A server for local models with AI gateway and LLM proxy.

Mostly used for non-conversational AI tasks like translation and text composition of GTFS datasets.

## Features

This is Docker Compose repository, set up for routing and reverse proxy with Traefik.

- Local model hosting with Ollama
- AI gateway and LLM proxy with LiteLLM
- MCP endpoint with FastMCP

It offers the following LLM types (configurable):

- Generative model (e.g., Gemma 4)
- Embedding model (e.g., EmbeddingGemma)
- System 1 model (e.g., Laya)

## Services

- `ollama` (`ollama/ollama`): model server, only reachable on the internal network.
- `ollama-pull`: one-shot job that pulls the models in `OLLAMA_MODELS` (`gemma4:e4b` and `embeddinggemma`).
- `postgres` (`postgres`): stores LiteLLM's models, users, teams, virtual keys and spend logs. Internal only.
- `litellm` (`litellm/litellm`): OpenAI-compatible gateway with the admin UI at `/ui` (`/` redirects there) and the API docs (Swagger) at `/docs`. Models are stored in the database; general settings are in `litellm/config.yaml`.
- `mcp` (built from `mcp/` on the official `astral/uv` image; FastMCP has no official Docker Hub image): MCP server at `/mcp`. Add tools in `mcp/server.py` and manage dependencies with uv (`cd mcp && uv add <package>`, which updates `uv.lock`).

## Compose files

- `compose.yml`: the services, without any exposure. Always used together with one of the next two.
- `compose.dev.yml`: local development. No Traefik; services are published on loopback only.
- `compose.prod.yml`: production. Routing by an external Traefik container on the external `traefik_proxy` network (`docker network create traefik_proxy` if it doesn't exist); no host ports.
- `compose.gpu.yml`: optional add-on that gives Ollama an NVIDIA GPU (needs the NVIDIA Container Toolkit).

## Local development

```sh
cp .env.example .env   # fill in all secrets (openssl rand -hex 32)
docker compose -f compose.yml -f compose.dev.yml up -d --build
```

- LiteLLM: http://localhost:4000 (admin UI at http://localhost:4000/ui)
- MCP: http://localhost:8000/mcp
- Ollama (container): http://localhost:11435. It deliberately avoids 11434, which a native Ollama on your machine uses.

To avoid repeating the `-f` flags: `export COMPOSE_FILE=compose.yml:compose.dev.yml`.

Then register the MCP server's key once (see below), using the local URL:

```sh
LITELLM_URL=http://localhost:4000 ./scripts/create-mcp-key.sh
```

Gemma 4 (`gemma4:e4b`, about 6.6 GB) is pulled by `ollama-pull` on first start. It is a thinking model: with small `max_tokens` the budget can be spent on reasoning and `content` comes back empty. For non-conversational tasks such as translation, send `"reasoning_effort": "none"` (LiteLLM maps it to Ollama's `think: false`).

## Production

```sh
cp .env.example .env   # fill in all secrets (openssl rand -hex 32)
docker compose -f compose.yml -f compose.prod.yml up -d --build
./scripts/create-mcp-key.sh
```

- LiteLLM: https://llm.simovi.org (`/` redirects to the admin UI at `/ui`)
- MCP: https://mcp.simovi.org/mcp

`TRAEFIK_ENTRYPOINT` (default `websecure`) and `TRAEFIK_CERTRESOLVER` (default `letsencrypt`) in `.env` must match your Traefik. With an NVIDIA GPU add `-f compose.gpu.yml`.

Keep `LITELLM_SALT_KEY` unchanged once the database has data, otherwise stored credentials become unreadable.

## Models, users and keys

Open the admin UI and sign in with `UI_USERNAME` / `UI_PASSWORD`. There you can add models, invite users, create teams and issue virtual keys with model restrictions, budgets and rate limits. Use the master key only for administration and give clients their own virtual keys. The examples below use the dev URL; in production use https://llm.simovi.org.

Models are stored in LiteLLM's database, so they have to be registered once (the UI keeps them afterwards). The stack has three:

- `gemma4` (`gemma4:e4b`): chat, from the Ollama container.
- `embeddinggemma`: text embeddings (768 dimensions), from the Ollama container.
- `laya`: decision model, see below.

`ollama-pull` fetches the first two on start (`OLLAMA_MODELS` in `.env`). Register them with the idempotent helper script, which uses the master key from `.env`:

```sh
LITELLM_URL=http://localhost:4000 ./scripts/register-models.sh                                  # gemma4 + embeddinggemma
LITELLM_URL=http://localhost:4000 LAYA_API_BASE=http://host.docker.internal:11434 ./scripts/register-models.sh   # + laya (dev)
```

In production omit `LITELLM_URL` (it defaults to `https://$LLM_HOST`). You can also add models in the UI: Models + Endpoints > Add Model, provider Ollama, API base `http://ollama:11434`.

Create a key restricted to some models:

```sh
curl http://localhost:4000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"models": ["gemma4", "embeddinggemma"], "key_alias": "translation"}'
```

Test the gateway:

```sh
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma4", "reasoning_effort": "none", "messages": [{"role": "user", "content": "Hello"}]}'

curl http://localhost:4000/v1/embeddings \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "embeddinggemma", "input": ["Good evening", "Bonsoir"]}'
```

Pull additional models by adding them to `OLLAMA_MODELS` (a space-separated list, keep the quotes in `.env`), register them in LiteLLM, then run `docker compose run --rm ollama-pull`.

### MCP server key

The MCP server calls LiteLLM with its own virtual key (`MCP_LITELLM_API_KEY` in `.env`), not the master key. After the first start, register it once with `./scripts/create-mcp-key.sh` (set `LITELLM_URL` for a local run, see above). Until it is registered, MCP tools that call LiteLLM (for example `list_llm_models`) fail with an authentication error. Restrict the `mcp-server` key's models or budget in the admin UI if needed.

## Laya decision model (`/v1/systemone`)

Laya is a decision model, not a chat model: it answers `POST /v1/systemone` with probabilities for typed questions. LiteLLM serves this route natively, with the same virtual-key authentication as the rest of the API, so Laya is reached through LiteLLM like every other model.

Laya's Ollama builds are MLX models. MLX runs in a native Ollama on Apple Silicon macOS, but not in the Linux `ollama/ollama` container: there `ollama pull laya` fails with "this model requires MLX support, but the MLX runtime is not available". Docker Desktop on a Mac runs Linux containers, so the same applies there.

**Local development (works today).** Run Ollama natively on macOS with `ollama pull laya`, and point LiteLLM at it. `compose.dev.yml` makes the host reachable as `host.docker.internal`. LiteLLM talks to Laya with its `typesafe` provider (same protocol, any `api_base`; the key is ignored by Ollama but required by LiteLLM):

Registration is part of `scripts/register-models.sh` when `LAYA_API_BASE` is set (see above); it creates the equivalent of:

```sh
curl http://localhost:4000/model/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "laya", "litellm_params": {"model": "typesafe/laya", "api_base": "http://host.docker.internal:11434", "api_key": "ollama"}}'
```

Then call it through LiteLLM with a virtual key that may use the `laya` model:

```sh
curl http://localhost:4000/v1/systemone \
  -H "Authorization: Bearer $LITELLM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model": "laya", "state": "Hello World", "questions": {"says_hello": {"type": "noul", "instructions": "Does the state text contain a greeting?"}}}'
```

In production a trailing slash (`/v1/systemone/`) also works; Traefik strips it.

**Production (not deployed yet).** A Linux server cannot run Laya through the Ollama container. Until that is decided, `laya` is simply not registered there. Options for later: a separate Laya server (the official `laya-serve`, which runs on CPU) registered in LiteLLM the same way with its own `api_base`, or an Ollama with an MLX runtime (an Apple Silicon host, or a build from source with CUDA 13).

LiteLLM's dedicated `laya` provider (used by its Auto Router) is not in the pinned LiteLLM version and only accepts the checkpoint names `english`, `multilingual` and `typed-decisions`, so `typesafe` is used instead.
