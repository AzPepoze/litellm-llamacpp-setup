Back to [README](../README.md)

# Manual setup

Use this if you do not want to run `setup.sh`. `setup.conf` is not needed. Set the ports in the `.env` files instead.

## Steps

1. Copy the example files.

   | Source | Target | Used by |
   |---|---|---|
   | `litellm/.env.example` | `litellm/.env` | LiteLLM |
   | `litellm/provider/providers.ini.example` | `litellm/provider/providers.ini` | LiteLLM |
   | `inference/llama-cpp/.env.example` | `inference/llama-cpp/.env` | llama.cpp |
   | `inference/llama-cpp/presets.ini.example` | `inference/llama-cpp/presets.ini` | llama.cpp |

   ```bash
   cp litellm/.env.example litellm/.env
   cp litellm/provider/providers.ini.example litellm/provider/providers.ini
   cp inference/llama-cpp/.env.example inference/llama-cpp/.env
   cp inference/llama-cpp/presets.ini.example inference/llama-cpp/presets.ini
   ```

2. Set your secrets. Use long random values, for example from `openssl rand -hex 24`.

   | File | Key |
   |---|---|
   | `litellm/.env` | `POSTGRES_PASSWORD` |
   | `litellm/.env` | `LITELLM_ADMIN_PASSWORD` |
   | `inference/llama-cpp/.env` | `LLAMA_CPP_API_KEY` |

3. Set the ports (optional). The defaults are used if you skip this.

   | File | Keys | Defaults |
   |---|---|---|
   | `inference/llama-cpp/.env` | `LISTEN_ADDRESS`, `LLAMA_CPP_PORT` | `0.0.0.0`, `8080` |
   | `litellm/.env` | `LISTEN_ADDRESS`, `LITELLM_PORT` | `0.0.0.0`, `4000` |

4. Add a model to `inference/llama-cpp/presets.ini`. Uncomment one example block and set its `hf-repo`. See [Models](models.md).

5. Set the provider in `litellm/provider/providers.ini`. See [Providers](providers.md).

   | Key | Value |
   |---|---|
   | `base_url` | `http://<machine-name-or-IP>:8080/v1` |
   | `api_key` | The same value as `LLAMA_CPP_API_KEY` |

   > [!IMPORTANT]
   > Use the model machine's name or IP. Do not use `localhost`: the gateway runs in Docker, so `localhost` means the gateway container itself.

6. Start the services.

   ```bash
   docker compose -f inference/llama-cpp/docker-compose.yaml up -d
   docker compose -f litellm/docker-compose.yaml up -d
   ```

7. Open the admin UI at `http://<gateway-machine>:4000/ui/`. Your models should be listed.

## Basalt

Basalt is an optional second model server. It needs an NVIDIA RTX 50 series GPU. See [Basalt](basalt.md).

1. Copy the config and create the API key. The `.env` file sets the port. See [Basalt](basalt.md).

   ```bash
   cp inference/basalt/basalt_config.json.example inference/basalt/basalt_config.json
   cp inference/basalt/.env.example inference/basalt/.env
   openssl rand -hex 24 > inference/basalt/api_key
   chmod 600 inference/basalt/api_key
   ```

2. Add a `[basalt]` section to `litellm/provider/providers.ini`.

   | Key | Value |
   |---|---|
   | `base_url` | `http://<machine-name-or-IP>:8081/v1` |
   | `api_key` | The content of `inference/basalt/api_key` |

3. Start Basalt before the gateway.

   ```bash
   docker compose -f inference/basalt/docker-compose.yaml up -d --build
   ```
