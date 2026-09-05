# litellm-llamacpp-setup

Run local GGUF models with GPU, and use them through one OpenAI-compatible API.

- `llama-cpp` serves models on `http://localhost:8080`
- `litellm` is the gateway on `http://localhost:4000` (+ Admin UI at `/ui`)

## You need

- Docker + NVIDIA GPU
- A `.gguf` model file

## Setup

1. Create env files, the presets file, and the provider list:

```bash
cp litellm/.env.example litellm/.env
cp llama-cpp/.env.example llama-cpp/.env
cp llama-cpp/presets.ini.example llama-cpp/presets.ini
cp provider/llamacpp.ini.example provider/llamacpp.ini
```

1. Edit them — just change the secrets:

- `litellm/.env`: set `POSTGRES_PASSWORD` and `LITELLM_MASTER_KEY`
- `llama-cpp/.env`: set `LLAMA_CPP_API_KEY`
- `provider/llamacpp.ini`: one section per llama.cpp server with its
  `base_url` (reachable **from inside** the litellm container, so use a LAN
  hostname/IP like `http://beast-gpu:8080/v1`, never `localhost`) and its
  `api_key` (must match that server's `LLAMA_CPP_API_KEY`)

1. Put your model in `llama-cpp/models/`, then declare it in `llama-cpp/presets.ini` by uncommenting and editing one of the template blocks:

```ini
[my-chat-model]
model = /models/my-chat-model/my-model.gguf
ctx-size = 8192
parallel = 2
repeat-penalty = 1.1
load-on-startup = true
# mmproj = /models/my-chat-model/mmproj.gguf  # vision models only
```

(There is also an embedding-model block in the template.)

1. Start both services:

```bash
docker compose -f llama-cpp/docker-compose.yaml up -d
docker compose -f litellm/docker-compose.yaml up -d
```

## How auto-sync works

The `litellm` container starts via `litellm/sync-models.sh`, which queries
`GET <base_url>/models` on every server in `provider/llamacpp.ini` and
writes the discovered ids into its config as `openai/<id>` entries. So every
`docker restart litellm` (or host reboot) re-registers whatever llama.cpp
currently serves — no manual UI step. Static config lives in
`litellm/config.template.yaml`; the generated `litellm/config.yaml` is
git-ignored. UI-added models still persist in Postgres alongside the
auto-synced ones.

## Use it

1. Check `http://localhost:4000/ui/` — your llama.cpp models are already there.
2. Call it like OpenAI:

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"my-model","messages":[{"role":"user","content":"hi"}]}'
```

That's it. Weights (`llama-cpp/models/`), secrets (`*.env`), your
`llama-cpp/presets.ini`, `provider/llamacpp.ini`, and the generated
`litellm/config.yaml` are all ignored by git — only the `*.example` /
`*.template` files are tracked.
