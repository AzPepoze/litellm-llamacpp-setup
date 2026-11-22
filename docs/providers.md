# Providers and sync

Back to [README](../README.md)

A provider is one [llama.cpp](https://github.com/ggml-org/llama.cpp) server. The [LiteLLM](https://docs.litellm.ai) gateway reads `litellm/provider/llamacpp.ini` and adds the models of each server.

## Configure a server

Each `[section]` is one server. The name is only a label.

```ini
[beast-gpu]
base_url = http://beast-gpu:8080/v1
api_key = sk-your-key-here
# model_prefix = beast-
```

| Key | Required | What it does |
|---|---|---|
| `base_url` | Yes | Server address, as seen from the gateway container |
| `api_key` | Yes | Must match that server's `LLAMA_CPP_API_KEY` |
| `model_prefix` | No | Text added before each model name. Use it with 2 or more servers to avoid name clashes |

The example file lists more optional overrides, such as `max_input_tokens`, `supports_vision` and `timeout`. They are commented out by default.

## When models are added

- The gateway checks every server when it starts.
- It checks again every 5 minutes, so new servers and new models appear without a restart.
- It adds only models it does not know yet.
- Models you edit in the Admin UI are never overwritten.

> [!NOTE]
> To change the check interval, set `SYNC_INTERVAL` in `litellm/.env` (seconds). Use `0` to check only at start.

## Troubleshooting

Look for `sync-models:` lines in the gateway log:

```bash
docker logs litellm 2>&1 | grep sync-models
```

| Message | Fix |
|---|---|
| `unreachable after ...` | Check `base_url`. Use a LAN name or IP, not `localhost` |
| `rejected the master key (401)` | Check `LITELLM_ADMIN_PASSWORD` in `litellm/.env` |
| `discovered 0 model(s)` | Check that the llama.cpp server has models loaded |
