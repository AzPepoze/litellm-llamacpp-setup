# litellm-llamacpp-setup

Run local GGUF models with GPU, and use them through one OpenAI-compatible API.

- `llama-cpp` serves models on `http://localhost:8080`
- `litellm` is the gateway on `http://localhost:4000` (+ Admin UI at `/ui`)

## You need

- Docker + NVIDIA GPU
- A `.gguf` model file

## Setup

1. Create env files:
```bash
cp litellm/.env.example litellm/.env
cp llama-cpp/.env.example llama-cpp/.env
```

2. Edit them — just change the secrets:
- `litellm/.env`: set `POSTGRES_PASSWORD` and `LITELLM_MASTER_KEY`
- `llama-cpp/.env`: set `LLAMA_CPP_API_KEY`

3. Put your model in `llama-cpp/models/`, then declare it in `llama-cpp/presets.ini`:
```ini
[my-model]
model = /models/my-model/my-model.gguf
ctx-size = 8192
load-on-startup = true
```

4. Start both services:
```bash
docker compose -f llama-cpp/docker-compose.yaml up -d
docker compose -f litellm/docker-compose.yaml up -d
```

## Use it

1. Open `http://localhost:4000/ui/` and add `my-model` pointing to `http://host.docker.internal:8080/v1`.
2. Call it like OpenAI:
```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"my-model","messages":[{"role":"user","content":"hi"}]}'
```

That's it. Models are managed in the LiteLLM UI, weights stay in `llama-cpp/models/` (ignored by git).
