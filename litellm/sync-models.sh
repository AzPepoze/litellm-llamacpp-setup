#!/bin/sh
# Entrypoint for the litellm container (see docker-compose.yaml).
#
# On start:
#   1. Check the providers ini and write the gateway config. Fails on a bad ini.
#   2. Start LiteLLM. It does not wait for llama.cpp servers.
#   3. In the background: find models on every llama.cpp server and register
#      the ones LiteLLM does not know yet. Repeat every SYNC_INTERVAL seconds.
#   4. Forward TERM and INT to LiteLLM and to the sync loop.
#
# Models are added through the API, not the config file, because
# config-file models cannot be edited in the UI. Sync only adds: a model
# already in the database is never changed, so UI edits are kept.
#
# A slow or dead llama.cpp server never delays the gateway. Any sync
# failure only logs, and the gateway keeps running with whatever is already
# in its database.
#
# The Python helpers live in ./sync/. Env overrides (also for dry runs):
#   PROVIDERS_INI          default /app/provider/providers.ini
#   TEMPLATE_YAML          default /app/config.template.yaml
#   CONFIG_OUT             default /app/config.yaml
#   DISCOVERED_JSON        default /tmp/sync-models-discovered.json
#   SYNC_DIR               default /app/sync
#   GATEWAY_URL            default http://127.0.0.1:4000
#   GATEWAY_BIN            default litellm
#   GATEWAY_WAIT_TIMEOUT   seconds to wait for the API, default 180
#   SYNC_WAIT_TIMEOUT      seconds to wait per llama.cpp server, default 120
#   SYNC_INTERVAL          seconds between re-syncs, default 300, 0 = once only
#   SYNC_DRY_RUN=1         find models, print them, exit without starting
#   LITELLM_MASTER_KEY     API auth (already set in the container)
set -eu

PROVIDERS_INI="${PROVIDERS_INI:-/app/provider/providers.ini}"
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

prepare_config() {
    if [ -f "$PROVIDERS_INI" ]; then
        python3 "$SYNC_DIR/check_ini.py" "$PROVIDERS_INI"
    else
        log "WARNING: $PROVIDERS_INI not found, starting with no models"
    fi
    python3 "$SYNC_DIR/write_config.py" "$TEMPLATE_YAML" "$CONFIG_OUT"
}

find_models() {
    python3 "$SYNC_DIR/discover.py" "$PROVIDERS_INI" "$DISCOVERED_JSON" "$SYNC_WAIT_TIMEOUT"
}

register_models() {
    python3 "$SYNC_DIR/register.py" "$DISCOVERED_JSON" \
        || log "WARNING: model registration crashed, gateway keeps running"
}

sync_once() {
    find_models || log "WARNING: model discovery failed"
    register_models
}

sync_forever() {
    sync_once
    if [ "$SYNC_INTERVAL" -eq 0 ]; then
        return 0
    fi
    while sleep "$SYNC_INTERVAL"; do
        sync_once
    done
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

start_sync() {
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
        find_models
        show_dry_run
        exit 0
    fi

    start_gateway "$@"
    trap on_term TERM INT
    start_sync

    status=0
    wait "$gw_pid" || status=$?
    if [ -n "$sync_pid" ]; then
        kill "$sync_pid" 2>/dev/null || true
    fi
    exit "$status"
}

main "$@"
