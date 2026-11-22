#!/bin/sh
# Entrypoint for the litellm container (see docker-compose.yaml).
#
# Each start:
#   1. Find models on every llama.cpp server in the providers ini and
#      write a model-free config from the template.
#   2. Start LiteLLM and wait for its API.
#   3. Register the found models that the API does not know yet.
#   4. Wait on LiteLLM, forwarding TERM and INT to it.
#
# Models are added through the API, not the config file, because
# config-file models cannot be edited in the UI. The add is one-way, so
# UI edits are never overwritten.
#
# A malformed ini stops the start. Any other failure only logs, and the
# gateway runs with whatever is already in its database.
#
# The Python helpers live in ./sync/. Env overrides (also for dry runs):
#   PROVIDERS_INI          default /app/provider/llamacpp.ini
#   TEMPLATE_YAML          default /app/config.template.yaml
#   CONFIG_OUT             default /app/config.yaml
#   DISCOVERED_JSON        default /tmp/sync-models-discovered.json
#   SYNC_DIR               default /app/sync
#   GATEWAY_URL            default http://127.0.0.1:4000
#   GATEWAY_BIN            default litellm
#   GATEWAY_WAIT_TIMEOUT   seconds to wait for the API, default 180
#   SYNC_WAIT_TIMEOUT      seconds to wait per llama.cpp server, default 120
#   SYNC_DRY_RUN=1         find models, print them, exit without starting
#   LITELLM_MASTER_KEY     API auth (already set in the container)
set -eu

PROVIDERS_INI="${PROVIDERS_INI:-/app/provider/llamacpp.ini}"
TEMPLATE_YAML="${TEMPLATE_YAML:-/app/config.template.yaml}"
CONFIG_OUT="${CONFIG_OUT:-/app/config.yaml}"
DISCOVERED_JSON="${DISCOVERED_JSON:-/tmp/sync-models-discovered.json}"
SYNC_DIR="${SYNC_DIR:-/app/sync}"
GATEWAY_BIN="${GATEWAY_BIN:-litellm}"
SYNC_WAIT_TIMEOUT="${SYNC_WAIT_TIMEOUT:-120}"

log() {
    echo "sync-models: $*" >&2
}

discover_models() {
    if [ ! -f "$PROVIDERS_INI" ]; then
        log "WARNING: $PROVIDERS_INI not found, starting with template config"
        cp "$TEMPLATE_YAML" "$CONFIG_OUT"
        printf '[]' >"$DISCOVERED_JSON"
        return 0
    fi
    python3 "$SYNC_DIR/discover.py" "$PROVIDERS_INI" "$TEMPLATE_YAML" \
        "$CONFIG_OUT" "$DISCOVERED_JSON" "$SYNC_WAIT_TIMEOUT"
}

show_dry_run() {
    log "dry run, these would be registered if unknown:"
    python3 "$SYNC_DIR/list_names.py" "$DISCOVERED_JSON"
    log "dry run, not starting litellm"
}

start_gateway() {
    "$GATEWAY_BIN" "$@" &
    gw_pid=$!
    trap 'kill -TERM "$gw_pid" 2>/dev/null || true' TERM INT
}

register_models() {
    python3 "$SYNC_DIR/register.py" "$DISCOVERED_JSON" \
        || log "WARNING: model registration crashed, gateway keeps running"
}

main() {
    discover_models

    if [ "${SYNC_DRY_RUN:-0}" = "1" ]; then
        show_dry_run
        exit 0
    fi

    start_gateway "$@"
    register_models
    wait "$gw_pid"
}

main "$@"
