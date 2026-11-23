# Models and presets

Back to [README](../README.md)

Models are declared in `inference/llama-cpp/presets.ini`. Each `[section]` is one model.

## Add a model

1. Find a [GGUF](https://huggingface.co/docs/hub/gguf) model on [Hugging Face](https://huggingface.co/models?library=gguf).
2. Copy one example block from `inference/llama-cpp/presets.ini.example` into `inference/llama-cpp/presets.ini` and remove the leading `;`.
3. Set `hf-repo` to `user/repo:quant`.

```ini
[my-chat-model]
hf-repo = unsloth/Qwen3-8B-GGUF:Q4_K_M
ctx-size = 8192
parallel = 2
repeat-penalty = 1.1
load-on-startup = true
```

llama.cpp downloads the model for you.

## Keys

| Key | What it does |
|---|---|
| `hf-repo` | Model to download, as `user/repo:quant` |
| `hf-repo-draft` | Small model that speeds up the main model |
| `mmproj-url` | Image projector file, for vision models |
| `ctx-size` | Context length in tokens |
| `parallel` | Number of requests the server handles at once |
| `repeat-penalty` | Penalty for repeated text. `1.1` is a common start |
| `embeddings` | Set to `true` for embedding models |
| `load-on-startup` | Load the model when the server starts |

## Example types

The example file has blocks for:

- Chat models
- Vision models, with or without a custom `mmproj-url`
- Chat models with a draft model
- Embedding models

> [!TIP]
> Restart the llama.cpp container after you change `presets.ini`:
> `docker compose -f inference/llama-cpp/docker-compose.yaml restart`
