from __future__ import annotations

from ini import Provider


def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def modalities(values):
    return [str(v).lower() for v in (values or [])]


def choose(override, default):
    return override if override is not None else default


def pick_mode(provider: Provider, model_id, output_modes):
    if provider.mode:
        return provider.mode
    if any("embed" in m for m in output_modes) or "embed" in model_id.lower():
        return "embedding"
    return "chat"


def pick_max_input(provider: Provider, n_ctx):
    if provider.max_input_tokens is not None:
        return provider.max_input_tokens
    return n_ctx if is_int(n_ctx) else None


def build_info(provider: Provider, model_id, model):
    arch = model.get("architecture") or {}
    input_modes = modalities(arch.get("input_modalities"))
    output_modes = modalities(arch.get("output_modalities"))
    n_ctx = (model.get("meta") or {}).get("n_ctx")

    info = {"mode": pick_mode(provider, model_id, output_modes)}

    max_input = pick_max_input(provider, n_ctx)
    if max_input:
        info["max_tokens"] = max_input
        info["max_input_tokens"] = max_input
    if provider.max_output_tokens:
        info["max_output_tokens"] = provider.max_output_tokens

    info["supports_vision"] = choose(provider.vision, "image" in input_modes)
    info["supports_audio_input"] = "audio" in input_modes
    info["supports_system_messages"] = choose(provider.system_messages, True)
    info["supports_response_schema"] = choose(provider.response_schema, True)
    if provider.function_calling is not None:
        info["supports_function_calling"] = provider.function_calling
    if provider.parallel_function_calling is not None:
        info["supports_parallel_function_calling"] = provider.parallel_function_calling

    info["input_cost_per_token"] = provider.input_cost
    info["output_cost_per_token"] = provider.output_cost
    return info


def build_entry(provider: Provider, name, model_id, model):
    return {
        "name": name,
        "mid": model_id,
        "base_url": provider.base_url,
        "api_key": provider.api_key,
        "params": provider.params,
        "info": build_info(provider, model_id, model),
    }
