Back to [README](../README.md)

# Manual setup

Use this if you do not want to run `setup.sh`.

## Steps

1. Copy the example files.

   | Source | Target | Used by |
   |---|---|---|
   | `litellm/.env.example` | `litellm/.env` | LiteLLM |
   | `litellm/provider/providers.ini.example` | `litellm/provider/providers.ini` | LiteLLM |
   | `llama-cpp/.env.example` | `llama-cpp/.env` | llama.cpp |
   | `llama-cpp/presets.ini.example` | `llama-cpp/presets.ini` | llama.cpp |

   ```bash
   cp litellm/.env.example litellm/.env
   cp litellm/provider/providers.ini.example litellm/provider/providers.ini
   cp llama-cpp/.env.example llama-cpp/.env
   cp llama-cpp/presets.ini.example llama-cpp/presets.ini
   ```

2. Set your secrets. Use long random values, for example from `openssl rand -hex 24`.

   | File | Key |
   |---|---|
   | `litellm/.env` | `POSTGRES_PASSWORD` |
   | `litellm/.env` | `LITELLM_ADMIN_PASSWORD` |
   | `llama-cpp/.env` | `LLAMA_CPP_API_KEY` |

3. Add a model to `llama-cpp/presets.ini`. Uncomment one example block and set its `hf-repo`. See [Models](models.md).

4. Set the provider in `litellm/provider/providers.ini`. See [Providers](providers.md).

   | Key | Value |
   |---|---|
   | `base_url` | `http://<LAN-host>:8080/v1` |
   | `api_key` | The same value as `LLAMA_CPP_API_KEY` |

   > [!IMPORTANT]
   > Use the server's LAN hostname or IP, not `localhost`. The gateway runs in Docker, so `localhost` means the gateway container itself.

5. Start the services.

   ```bash
   docker compose -f llama-cpp/docker-compose.yaml up -d
   docker compose -f litellm/docker-compose.yaml up -d
   ```

6. Open the admin UI at `http://localhost:4000/ui/`. Your models should be listed.

## Basalt

Basalt is an optional second model server. It needs an NVIDIA RTX 50 series GPU. See [Basalt](basalt.md).

1. Copy the config and create the API key.

   ```bash
   cp basalt/data/basalt_config.json.example basalt/data/basalt_config.json
   openssl rand -hex 24 > basalt/api_key
   chmod 600 basalt/api_key
   ```

2. Add a `[basalt]` section to `litellm/provider/providers.ini`.

   | Key | Value |
   |---|---|
   | `base_url` | `http://<LAN-host>:8081/v1` |
   | `api_key` | The content of `basalt/api_key` |

3. Start Basalt before the gateway.

   ```bash
   docker compose -f basalt/docker-compose.yaml up -d --build
   ```
