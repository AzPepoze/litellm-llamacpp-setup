#!/bin/sh
# Entrypoint wrapper for the litellm container (see litellm/docker-compose.yaml).
#
# On every (re)start it queries GET <base_url>/models on each llama.cpp
# server listed in the providers ini and regenerates /app/config.yaml from
# /app/config.template.yaml + the discovered models. Then it execs the real
# LiteLLM process, passing through any CMD args (e.g. --config /app/config.yaml).
#
# Fetching is done with embedded python3 (stdlib only): the litellm image
# has no curl/jq. A malformed ini fails fast; an unreachable server is
# skipped after SYNC_WAIT_TIMEOUT so one dead box can't stop the gateway.
#
# Beyond model/api_base/api_key, every model entry also gets a `model_info`
# block mapped from the llama.cpp /v1/models payload, so the LiteLLM UI
# shows data instead of "Not Set":
#   auto-detected : mode (chat, or embedding when output_modalities or the
#                   id suggests it), max_tokens + max_input_tokens from
#                   meta.n_ctx, supports_vision from input_modalities,
#                   supports_audio_input ditto, supports_system_messages
#                   and supports_response_schema (both always true —
#                   llama.cpp serves system roles and grammar-constrained
#                   JSON schema), zero input/output costs (local inference).
#   ini overrides : mode, max_input_tokens, max_output_tokens,
#                   input_cost_per_token, output_cost_per_token,
#                   supports_vision, supports_function_calling,
#                   supports_parallel_function_calling,
#                   supports_response_schema, supports_system_messages,
#                   timeout, stream_timeout, max_retries, tpm, rpm.
#
# Env overrides (also used for offline dry-runs):
#   PROVIDERS_INI       default /app/provider/llamacpp.ini
#   TEMPLATE_YAML       default /app/config.template.yaml
#   CONFIG_OUT          default /app/config.yaml
#   SYNC_WAIT_TIMEOUT   seconds to wait per server, default 120
#   SYNC_DRY_RUN=1      write the config and exit (do not exec litellm)
set -eu

PROVIDERS_INI="${PROVIDERS_INI:-/app/provider/llamacpp.ini}"
TEMPLATE_YAML="${TEMPLATE_YAML:-/app/config.template.yaml}"
CONFIG_OUT="${CONFIG_OUT:-/app/config.yaml}"
SYNC_WAIT_TIMEOUT="${SYNC_WAIT_TIMEOUT:-120}"

if [ ! -f "$PROVIDERS_INI" ]; then
    echo "sync-models: WARNING: $PROVIDERS_INI not found, starting with template config" >&2
    cp "$TEMPLATE_YAML" "$CONFIG_OUT"
else
    python3 - "$PROVIDERS_INI" "$TEMPLATE_YAML" "$CONFIG_OUT" "$SYNC_WAIT_TIMEOUT" <<'PYEOF'
import configparser
import json
import sys
import time
import urllib.error
import urllib.request

ini_path, template_path, out_path, timeout = (
    sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]))

cp = configparser.ConfigParser()
cp.read(ini_path)


def fetch_models(base_url, api_key):
    url = base_url.rstrip("/") + "/models"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {api_key}"})
    deadline = time.time() + timeout
    attempt = 0
    while True:
        attempt += 1
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.load(resp)
                if not isinstance(data, dict) or not isinstance(data.get("data"), list):
                    raise ValueError("unexpected /v1/models shape")
                return data["data"]
        except Exception as e:  # server still booting / host rebooting
            if time.time() >= deadline:
                print(f"sync-models: ERROR: {url} unreachable after "
                      f"{timeout:.0f}s ({e}); skipping server", file=sys.stderr)
                return []
            print(f"sync-models: {url} not ready (attempt {attempt}: {e}), "
                  f"retrying...", file=sys.stderr)
            time.sleep(5)


def yq(s):  # minimal double-quoted YAML scalar
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def ybool(b):
    return "true" if b else "false"


def bool_opt(section, key):
    v = cp.get(section, key, fallback="").strip().lower()
    if v in ("1", "true", "yes", "on"):
        return True
    if v in ("0", "false", "no", "off"):
        return False
    if v:
        sys.exit(f"sync-models: ERROR: [{section}] {key} must be "
                 f"true/false, got {v!r}")
    return None


def num_opt(section, key, numtype):
    v = cp.get(section, key, fallback="").strip()
    if not v:
        return None
    try:
        return numtype(v)
    except ValueError:
        sys.exit(f"sync-models: ERROR: [{section}] {key} must be a "
                 f"number, got {v!r}")


def is_int(x):
    return isinstance(x, int) and not isinstance(x, bool)


entries = []  # dicts: name, mid, base_url, api_key, params, info
seen = set()
for section in cp.sections():
    try:
        base_url = cp.get(section, "base_url").strip()
        api_key = cp.get(section, "api_key").strip()
    except configparser.NoOptionError as e:
        sys.exit(f"sync-models: ERROR: [{section}] missing option: {e}")
    if not base_url or not api_key:
        sys.exit(f"sync-models: ERROR: [{section}] needs base_url and api_key")
    prefix = cp.get(section, "model_prefix", fallback="").strip()
    ini_mode = cp.get(section, "mode", fallback="").strip() or None
    ov_max_in = num_opt(section, "max_input_tokens", int)
    ov_max_out = num_opt(section, "max_output_tokens", int)
    ov_vision = bool_opt(section, "supports_vision")
    ov_func = bool_opt(section, "supports_function_calling")
    ov_parallel = bool_opt(section, "supports_parallel_function_calling")
    ov_schema = bool_opt(section, "supports_response_schema")
    ov_system = bool_opt(section, "supports_system_messages")
    v = num_opt(section, "input_cost_per_token", float)
    in_cost = 0.0 if v is None else v
    v = num_opt(section, "output_cost_per_token", float)
    out_cost = 0.0 if v is None else v
    params = {}
    for key, numtype in (("timeout", float), ("stream_timeout", float),
                         ("max_retries", int), ("tpm", int), ("rpm", int)):
        v = num_opt(section, key, numtype)
        if v is not None:
            params[key] = v
    models = fetch_models(base_url, api_key)
    print(f"sync-models: [{section}] discovered {len(models)} model(s)", file=sys.stderr)
    for m in models:
        if not isinstance(m, dict):
            continue
        mid = m.get("id", "")
        if not mid:
            continue
        name = f"{prefix}{mid}"
        if name in seen:
            print(f"sync-models: WARNING: duplicate model name {name!r}, "
                  f"keeping first", file=sys.stderr)
            continue
        seen.add(name)
        arch = m.get("architecture") or {}
        in_mod = [str(x).lower() for x in (arch.get("input_modalities") or [])]
        out_mod = [str(x).lower() for x in (arch.get("output_modalities") or [])]
        meta = m.get("meta") or {}
        n_ctx = meta.get("n_ctx")
        if ini_mode:
            mode = ini_mode
        elif any("embed" in x for x in out_mod) or "embed" in mid.lower():
            mode = "embedding"
        else:
            mode = "chat"
        max_in = (ov_max_in if ov_max_in is not None
                  else (n_ctx if is_int(n_ctx) else None))
        info = {"mode": mode}
        if max_in:
            info["max_tokens"] = max_in
            info["max_input_tokens"] = max_in
        if ov_max_out:
            info["max_output_tokens"] = ov_max_out
        info["supports_vision"] = (ov_vision if ov_vision is not None
                                    else ("image" in in_mod))
        info["supports_audio_input"] = "audio" in in_mod
        info["supports_system_messages"] = (ov_system if ov_system is not None
                                             else True)
        info["supports_response_schema"] = (ov_schema if ov_schema is not None
                                             else True)
        if ov_func is not None:
            info["supports_function_calling"] = ov_func
        if ov_parallel is not None:
            info["supports_parallel_function_calling"] = ov_parallel
        info["input_cost_per_token"] = in_cost
        info["output_cost_per_token"] = out_cost
        entries.append({"name": name, "mid": mid, "base_url": base_url,
                        "api_key": api_key, "params": params, "info": info})

with open(template_path) as f:
    template = f.read()

def ynum(v):  # ints plain, floats with repr so 0.0 stays 0.0
    return repr(v) if isinstance(v, float) else str(v)


if entries:
    lines = []
    for e in entries:
        lines.append(f"  - model_name: {yq(e['name'])}")
        lines.append("    litellm_params:")
        lines.append(f"      model: {yq('openai/' + e['mid'])}")
        lines.append(f"      api_base: {yq(e['base_url'])}")
        lines.append(f"      api_key: {yq(e['api_key'])}")
        for key, val in e["params"].items():
            lines.append(f"      {key}: {ynum(val)}")
        lines.append("    model_info:")
        for key, val in e["info"].items():
            if isinstance(val, bool):
                lines.append(f"      {key}: {ybool(val)}")
            elif isinstance(val, (int, float)):
                lines.append(f"      {key}: {ynum(val)}")
            else:
                lines.append(f"      {key}: {yq(str(val))}")
    block = "model_list:\n" + "\n".join(lines)
else:
    block = "model_list: []"

out_lines = []
replaced = False
for line in template.splitlines():
    if not replaced and line.strip() == "model_list: []":
        out_lines.append(block)
        replaced = True
    else:
        out_lines.append(line)
if not replaced:
    sys.exit("sync-models: ERROR: no 'model_list: []' line in template, "
             "refusing to guess where models go")

with open(out_path, "w") as f:
    f.write("\n".join(out_lines) + "\n")

print(f"sync-models: wrote {len(entries)} model(s) to {out_path}", file=sys.stderr)
PYEOF
fi

if [ "${SYNC_DRY_RUN:-0}" = "1" ]; then
    echo "sync-models: dry run, not starting litellm" >&2
    exit 0
fi

exec litellm "$@"
