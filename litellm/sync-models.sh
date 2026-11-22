#!/bin/sh
# Entrypoint for the litellm container (see docker-compose.yaml).
#
# On start:
#   1. Find models on every llama.cpp server and write the gateway config.
#   2. Start LiteLLM and register the found models it does not know yet.
#   3. Repeat the find and register steps every SYNC_INTERVAL seconds.
#   4. Forward TERM and INT to LiteLLM and to the sync loop.
#
# Models are added through the API, not the config file, because
# config-file models cannot be edited in the UI. Sync only adds: a model
# already in the database is never changed, so UI edits are kept.
#
# A malformed ini stops the start. Any other failure only logs, and the
# gateway keeps running with whatever is already in its database.
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
#   SYNC_INTERVAL          seconds between re-syncs, default 300, 0 = off
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
SYNC_INTERVAL="${SYNC_INTERVAL:-300}"

sync_pid=""

log() {
    echo "sync-models: $*" >&2
}

find_models() {
    python3 "$SYNC_DIR/discover.py" "$PROVIDERS_INI" "$DISCOVERED_JSON" "$SYNC_WAIT_TIMEOUT"
}

prepare_config() {
    if [ ! -f "$PROVIDERS_INI" ]; then
        log "WARNING: $PROVIDERS_INI not found, starting with no models"
        printf '[]' >"$DISCOVERED_JSON"
    else
        find_models
    fi
    python3 "$SYNC_DIR/write_config.py" "$TEMPLATE_YAML" "$CONFIG_OUT"
}

register_models() {
    python3 "$SYNC_DIR/register.py" "$DISCOVERED_JSON" \
        || log "WARNING: model registration crashed, gateway keeps running"
}

show_dry_run() {
    log "dry run, these would be registered if unknown:"
    python3 "$SYNC_DIR/list_names.py" "$DISCOVERED_JSON"
    log "dry run, not starting litellm"
}

start_gateway() {
    "$GATEWAY_BIN" "$@" &
    gw_pid=$!
}

sync_forever() {
    while sleep "$SYNC_INTERVAL"; do
        find_models || log "WARNING: model discovery failed, retrying in ${SYNC_INTERVAL}s"
        register_models
    done
}

start_sync() {
    if [ "$SYNC_INTERVAL" -eq 0 ]; then
        return 0
    fi
    sync_forever &
    sync_pid=$!
}

on_term() {
    kill -TERM "$gw_pid" 2>/dev/null || true
    if [ -n "$sync_pid" ]; then
        kill -TERM "$sync_pid" 2>/dev/null || true
    fi
}

main() {
    prepare_config

    if [ "${SYNC_DRY_RUN:-0}" = "1" ]; then
        show_dry_run
        exit 0
    fi

    start_gateway "$@"
    trap on_term TERM INT
    register_models
    start_sync

    status=0
    wait "$gw_pid" || status=$?
    if [ -n "$sync_pid" ]; then
        kill "$sync_pid" 2>/dev/null || true
    fi
    exit "$status"
}

main "$@"
