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


entries = []  # (model_name, litellm_model, api_base, api_key)
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
    models = fetch_models(base_url, api_key)
    print(f"sync-models: [{section}] discovered {len(models)} model(s)", file=sys.stderr)
    for m in models:
        mid = m.get("id", "") if isinstance(m, dict) else ""
        if not mid:
            continue
        name = f"{prefix}{mid}"
        if name in seen:
            print(f"sync-models: WARNING: duplicate model name {name!r}, "
                  f"keeping first", file=sys.stderr)
            continue
        seen.add(name)
        entries.append((name, mid, base_url, api_key))

with open(template_path) as f:
    template = f.read()

if entries:
    lines = []
    for name, mid, base_url, api_key in entries:
        lines.append(f"  - model_name: {yq(name)}")
        lines.append("    litellm_params:")
        lines.append(f"      model: {yq('openai/' + mid)}")
        lines.append(f"      api_base: {yq(base_url)}")
        lines.append(f"      api_key: {yq(api_key)}")
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
