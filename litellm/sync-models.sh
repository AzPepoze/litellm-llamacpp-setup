#!/bin/sh
# Entrypoint wrapper for the litellm container (see litellm/docker-compose.yaml).
#
# On every (re)start it queries GET <base_url>/models on each llama.cpp
# server listed in the providers ini, writes a model-free /app/config.yaml
# from /app/config.template.yaml, starts the real LiteLLM process, waits for
# its API, then registers any discovered-but-unknown models via POST
# /model/new. Then it waits on LiteLLM, passing through signals.
#
# Why the API and not the config file? LiteLLM marks config-file models as
# "owned by the file": they can never be edited in the UI (db_model=false).
# Models created via /model/new are real DB rows — editable, restart-safe.
# The sync is ADD-ONLY: names already serving are skipped, so UI edits are
# never overwritten. The database itself is the "already exists" check, so
# there is no local state file to lose or reset.
#
# Fetching uses embedded python3 (stdlib only): the litellm image has no
# curl/jq. A malformed ini fails fast (gateway never starts half-configured);
# anything else — llama.cpp down, gateway API not ready, a rejected POST —
# only logs an error and the gateway still runs with whatever is in the DB.
#
# Env overrides (also used for offline dry-runs):
#   PROVIDERS_INI       default /app/provider/llamacpp.ini
#   TEMPLATE_YAML       default /app/config.template.yaml
#   CONFIG_OUT          default /app/config.yaml
#   DISCOVERED_JSON     discovered-model handoff, default /tmp/sync-models-discovered.json
#   GATEWAY_URL         LiteLLM API base, default http://127.0.0.1:4000
#   GATEWAY_BIN         gateway binary, default litellm (tests stub it)
#   GATEWAY_WAIT_TIMEOUT seconds to wait for the API, default 180
#   SYNC_WAIT_TIMEOUT   seconds to wait per llama.cpp server, default 120
#   SYNC_DRY_RUN=1      discover + write config, print what would be
#                       registered, and exit (do not start the gateway)
#   LITELLM_MASTER_KEY  required for API auth (already in container env)
set -eu

PROVIDERS_INI="${PROVIDERS_INI:-/app/provider/llamacpp.ini}"
TEMPLATE_YAML="${TEMPLATE_YAML:-/app/config.template.yaml}"
CONFIG_OUT="${CONFIG_OUT:-/app/config.yaml}"
DISCOVERED_JSON="${DISCOVERED_JSON:-/tmp/sync-models-discovered.json}"
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:4000}"
GATEWAY_BIN="${GATEWAY_BIN:-litellm}"
SYNC_WAIT_TIMEOUT="${SYNC_WAIT_TIMEOUT:-120}"
GATEWAY_WAIT_TIMEOUT="${GATEWAY_WAIT_TIMEOUT:-180}"

if [ ! -f "$PROVIDERS_INI" ]; then
    echo "sync-models: WARNING: $PROVIDERS_INI not found, starting with template config" >&2
    cp "$TEMPLATE_YAML" "$CONFIG_OUT"
    printf '[]' >"$DISCOVERED_JSON"
else
    python3 - "$PROVIDERS_INI" "$TEMPLATE_YAML" "$CONFIG_OUT" "$DISCOVERED_JSON" \
        "$SYNC_WAIT_TIMEOUT" <<'PYEOF'
import configparser
import json
import sys
import time
import urllib.error
import urllib.request

ini_path, template_path, out_path, disc_path, timeout = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], float(sys.argv[5]))

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

# The file stays model-free on purpose: anything listed here becomes an
# uneditable config-owned model. The DB owns all models (see API phase).
if "model_list: []" not in [line.strip() for line in template.splitlines()]:
    sys.exit("sync-models: ERROR: no 'model_list: []' line in template, "
             "refusing to guess where models go")
with open(out_path, "w") as f:
    f.write(template if template.endswith("\n") else template + "\n")

with open(disc_path, "w") as f:
    json.dump(entries, f)

print(f"sync-models: discovered {len(entries)} model(s), wrote model-free config",
      file=sys.stderr)
PYEOF
fi

if [ "${SYNC_DRY_RUN:-0}" = "1" ]; then
    echo "sync-models: dry run, these would be registered if unknown:" >&2
    python3 -c "import json,sys; [print('  -', e['name']) for e in json.load(open('$DISCOVERED_JSON'))]"
    echo "sync-models: dry run, not starting litellm" >&2
    exit 0
fi

"$GATEWAY_BIN" "$@" &
gw_pid=$!
_term() { kill -TERM "$gw_pid" 2>/dev/null || true; }
trap _term TERM INT

# Register unknown models as real DB rows. Never fatal: any failure just
# logs and the gateway keeps serving whatever is already in the DB.
python3 - "$DISCOVERED_JSON" <<'PYEOF'
import json
import os
import sys
import time
import urllib.request

disc_path = sys.argv[1]
gw = os.environ.get("GATEWAY_URL", "http://127.0.0.1:4000").rstrip("/")
wait_timeout = float(os.environ.get("GATEWAY_WAIT_TIMEOUT", "180"))
master = os.environ.get("LITELLM_MASTER_KEY", "")

try:
    with open(disc_path) as f:
        discovered = json.load(f)
except Exception as e:
    print(f"sync-models: WARNING: cannot read {disc_path} ({e}); "
          f"skipping API sync", file=sys.stderr)
    sys.exit(0)
if not discovered:
    sys.exit(0)
if not master:
    print("sync-models: ERROR: LITELLM_MASTER_KEY not set; cannot register "
          "models via API", file=sys.stderr)
    sys.exit(0)


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        gw + path, data=data, method=method,
        headers={"Authorization": f"Bearer {master}",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.status, resp.read().decode()


def code_of(e):
    return getattr(e, "code", None)


# Wait for the API; /v1/models doubles as the existing-set fetch.
deadline = time.time() + wait_timeout
existing = None
while True:
    try:
        st, txt = call("GET", "/v1/models")
        if st == 200:
            items = json.loads(txt).get("data", [])
            existing = {i.get("id") for i in items
                        if isinstance(i, dict) and i.get("id")}
            break
        print(f"sync-models: gateway /v1/models -> {st}, retrying...",
              file=sys.stderr)
    except Exception as e:
        if code_of(e) == 401:
            print("sync-models: ERROR: gateway rejected the master key (401); "
                  "check LITELLM_MASTER_KEY", file=sys.stderr)
            sys.exit(0)
        print(f"sync-models: gateway not ready ({e}), retrying...",
              file=sys.stderr)
    if time.time() >= deadline:
        print(f"sync-models: ERROR: gateway API not ready after "
              f"{wait_timeout:.0f}s; models not registered this boot",
              file=sys.stderr)
        sys.exit(0)
    time.sleep(5)

added = 0
for e in discovered:
    if e["name"] in existing:
        continue
    body = {"model_name": e["name"],
            "litellm_params": {"model": "openai/" + e["mid"],
                               "api_base": e["base_url"],
                               "api_key": e["api_key"],
                               **e["params"]},
            "model_info": e["info"]}
    try:
        st, txt = call("POST", "/model/new", body)
    except Exception as ex:
        if code_of(ex) == 401:
            print("sync-models: ERROR: gateway rejected the master key (401); "
                  "stopping registration", file=sys.stderr)
            break
        print(f"sync-models: WARNING: registering {e['name']} failed ({ex})",
              file=sys.stderr)
        continue
    if 200 <= st < 300:
        print(f"sync-models: registered {e['name']} as DB model",
              file=sys.stderr)
        added += 1
        existing.add(e["name"])
    else:
        print(f"sync-models: WARNING: registering {e['name']} -> {st}: "
              f"{txt[:200]}", file=sys.stderr)

print(f"sync-models: registered {added} new model(s) via API", file=sys.stderr)
PYEOF

wait "$gw_pid"
