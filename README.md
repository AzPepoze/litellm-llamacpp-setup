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
cp litellm/provider/llamacpp.ini.example litellm/provider/llamacpp.ini
```

1. Edit them — just change the secrets:

- `litellm/.env`: set `POSTGRES_PASSWORD` and `LITELLM_ADMIN_PASSWORD`
  (optional: `LITELLM_PORT`, default `4000`, for the host-side port)
- `llama-cpp/.env`: set `LLAMA_CPP_API_KEY`
- `litellm/provider/llamacpp.ini`: one section per llama.cpp server with its
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

## Providers

`litellm/provider/llamacpp.ini` tells the gateway where your llama.cpp
servers live. It has one block per server:

```ini
[beast-gpu]
base_url = http://beast-gpu:8080/v1
api_key = sk-your-key-here
# model_prefix = beast-  (optional)
```

- `base_url` — the server address **as seen from inside the gateway
  container**. `localhost` does not work here; use the machine's LAN
  hostname or IP (like `http://beast-gpu:8080/v1`).
- `api_key` — must match that server's `LLAMA_CPP_API_KEY`.
- `model_prefix` (optional) — only needed with 2+ servers, avoids name
  clashes. More overrides are commented-out in the `.example` file.

The rest fills in by itself.

## Use it

1. Check `http://localhost:4000/ui/` — your llama.cpp models are already there.
2. Call it like OpenAI:

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_ADMIN_PASSWORD" \
  -H "Content-Type: application/json" \
  -d '{"model":"my-model","messages":[{"role":"user","content":"hi"}]}'
```

That's it. The files below hold your private stuff, so they stay on your
machine and are never committed to git:

- `llama-cpp/models/` — your downloaded model weights
- any `.env` file — passwords and secrets
- `llama-cpp/presets.ini` — your model setup
- `litellm/provider/llamacpp.ini` — your server addresses and keys
- `litellm/config.yaml` — auto-generated every time the gateway starts

Only the `*.example` / `*.template` files are tracked in git. Those are
blank templates with no secrets in them.
