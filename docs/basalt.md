Back to [README](../README.md)

# Basalt

Basalt serves `.basalt` models on NVIDIA GPUs with an OpenAI-compatible API.
Project: [jesdga95/basalt](https://github.com/jesdga95/basalt)

## Requirements

| Item | Need |
|---|---|
| GPU | RTX 50 series (Blackwell) |
| Driver | 580 or newer |
| Software | Docker with the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) |
| Disk | 21 GB for the 27B model |
| RAM | Enough for the part of the model that does not fit on the GPU |

> [!WARNING]
> Basalt does not run on older GPUs.

## Setup

1. Download a model into `basalt/models/`:

   ```bash
   hf download jesdga/Qwen3.8-27B-Basalt Qwen3.8-27B-QUASAR-NVFP4.basalt --local-dir models
   ```

2. Create the config. Copy `basalt/data/basalt_config.json.example` to `basalt/data/basalt_config.json` (`setup.sh` does this). Set the model name. Keep the server port at 8080.

3. Set the API key. It is stored in `basalt/api_key` (`setup.sh` creates it). The server reads this file. The key is not in the config.

4. Build and start:

   ```bash
   docker compose -f basalt/docker-compose.yaml up -d --build
   ```

   > [!NOTE]
   > The first build takes a long time because it compiles the engine.

5. Check the server. Replace `<key>` with your API key:

   ```bash
   curl http://localhost:8081/v1/models -H "Authorization: Bearer <key>"
   ```

## Config keys

| Key | What it does |
|---|---|
| `model` | Model path inside the container, such as `/models/...` |
| `alias` | Name the API reports for the model |
| `kv` | Storage type for the KV cache. For the 27B model: `fp16` or `int8`. `int8` uses about half the memory |
| `max-context` | Longest context in tokens. Default: 8192. The KV cache grows with it |
| `server.port` | Port inside the container. Keep `8080`. To change the host port, edit `docker-compose.yaml` |

## Update

```bash
cd basalt
./update.sh
docker compose up -d
```

## Links

- [Basalt repository](https://github.com/jesdga95/basalt)
- [Basalt configuration docs](https://github.com/jesdga95/basalt/blob/main/docs/configuration/index.md)
