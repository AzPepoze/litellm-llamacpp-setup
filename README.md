# litellm-inference-setup

Run models on your NVIDIA GPU with llama.cpp, and optionally Basalt, then call them all through one OpenAI-compatible API.

- **llama.cpp** runs GGUF model files (a compressed model format).
- **Basalt** runs `.basalt` model files on RTX 50 series GPUs.
- **LiteLLM gateway** is one API in front of your servers. Your app talks only to the gateway.

```mermaid
flowchart LR
    App[Your app] --> LiteLLM[LiteLLM gateway<br/>localhost:4000]
    LiteLLM --> LlamaCpp[llama.cpp<br/>localhost:8080]
    LiteLLM --> Basalt[Basalt<br/>localhost:8081, optional]
    LlamaCpp --> GPU[NVIDIA GPU]
    Basalt --> GPU
```

| Service | Address | Role |
|---|---|---|
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | `http://localhost:8080` | Runs the models on the GPU |
| [Basalt](https://github.com/jesdga95/basalt) | `http://localhost:8081` | Runs `.basalt` models on RTX 50 series GPUs, optional |
| [LiteLLM](https://docs.litellm.ai) | `http://localhost:4000` | Gateway and API. Admin UI at `/ui` |

## Requirements

- [Docker](https://docs.docker.com/get-docker/) with [Docker Compose](https://docs.docker.com/compose/)
- NVIDIA GPU with the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- For Basalt only:
  - RTX 50 series (Blackwell) GPU
  - NVIDIA driver 580 or newer

## Quick start

1. Clone the repo.

   ```bash
   git clone https://github.com/AzPepoze/litellm-inference-setup.git
   cd litellm-inference-setup
   ```

2. Run the setup script.

   ```bash
   ./setup.sh
   ```

   It creates the config files, makes the secrets, asks which servers to enable, and can start them.

   Want to do it by hand? See [Manual setup](docs/manual-setup.md).

3. Add a model.

   - **llama.cpp:** add a model to `inference/llama-cpp/presets.ini`. See [Models](docs/models.md).
   - **Basalt:** add a `.basalt` model file to `inference/basalt/models` and set it in `inference/basalt/data/basalt_config.json`. See [Basalt](docs/basalt.md).

   Then point the gateway at your servers in `litellm/provider/providers.ini`. See [Providers](docs/providers.md).

   > [!IMPORTANT]
   > Use the server's LAN hostname or IP, not `localhost`. The gateway runs in Docker, so `localhost` means the gateway container itself.

4. Open `http://localhost:4000/ui/` and check that your models are listed.

The model servers live in `inference/`: `inference/llama-cpp/` and `inference/basalt/`.

## Call the API

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer <LITELLM_ADMIN_PASSWORD>" \
  -H "Content-Type: application/json" \
  -d '{"model":"<model-name>","messages":[{"role":"user","content":"hi"}]}'
```

- Replace `<LITELLM_ADMIN_PASSWORD>` with the value in `litellm/.env`. This password is also the API key for your clients.
- Replace `<model-name>` with the name shown in the Admin UI.

## Update llama.cpp

```bash
cd inference/llama-cpp
./update.sh                      # pulls the newest llama.cpp image
docker compose up -d             # restarts with the new image
```

## Update Basalt

```bash
cd inference/basalt
./update.sh                      # rebuilds the Basalt image with the newest code
docker compose up -d             # restarts with the new image
```

## Private files

These files hold your secrets and settings. Git ignores them.

| Path | Holds |
|---|---|
| `litellm/.env` | Database and admin passwords |
| `inference/llama-cpp/.env` | llama.cpp API key |
| `inference/llama-cpp/presets.ini` | Your model list and settings |
| `litellm/provider/providers.ini` | Your server addresses and keys |
| `inference/llama-cpp/models/` | Downloaded model weights |
| `litellm/config.yaml` | Generated at every gateway start |
| `inference/basalt/data/basalt_config.json` | Basalt settings |
| `inference/basalt/api_key` | Basalt API key |
| `inference/basalt/models/` | Basalt model files |

## More

| Topic | Page |
|---|---|
| Manual setup | [docs/manual-setup.md](docs/manual-setup.md) |
| Models and presets | [docs/models.md](docs/models.md) |
| Providers and sync | [docs/providers.md](docs/providers.md) |
| Basalt | [docs/basalt.md](docs/basalt.md) |
