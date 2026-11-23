#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/scripts/lib.sh"
source "$SCRIPT_DIR/scripts/models.sh"
source "$SCRIPT_DIR/scripts/gateway.sh"

role_for_choice() {
  case "$1" in
    1) printf 'models\n' ;;
    2) printf 'gateway\n' ;;
    3) printf 'both\n' ;;
  esac
}

print_role_menu() {
  printf 'What will this machine run?\n'
  printf '  1) Model servers   llama.cpp and/or Basalt on this GPU machine\n'
  printf '  2) Gateway         LiteLLM: one API in front of your model servers\n'
  printf '  3) Both            everything on this machine\n'
}

choose_role() {
  local default=2
  local choice=""
  if has_nvidia_gpu_support; then default=1; fi
  print_role_menu
  choice="$(ask_choice "Choose 1, 2 or 3" "$default" '1|2|3')"
  ROLE="$(role_for_choice "$choice")"
}

ensure_conf() {
  if [[ -e "$CONF_FILE" ]]; then
    file_action kept "$CONF_FILE"
    return 0
  fi
  choose_role
  copy_example "$CONF_EXAMPLE" "$CONF_FILE"
  set_env_value "$CONF_FILE" ROLE "$ROLE"
  file_action created "$CONF_FILE"
}

setup_both() {
  check_nvidia_runtime
  ask_model_servers
  prepare_model_servers
  prepare_gateway_env
  prepare_local_providers
  offer_start_model_servers
  offer_start_gateway
}

run_setup() {
  ensure_conf
  load_conf
  validate_conf
  check_docker
  check_openssl
  case "$ROLE" in
    models) setup_models ;;
    gateway) setup_gateway ;;
    both) setup_both ;;
  esac
}

connect_command() {
  require_file "$CONF_FILE" "Run ./setup.sh first."
  load_conf
  validate_conf
  if [[ "$ROLE" == gateway ]]; then
    fail_exit "This machine runs the gateway only. Run connect on the model machine."
  fi
  print_connect_blocks
}

main() {
  case "${1:-}" in
    "") run_setup ;;
    connect) connect_command ;;
    add-server) add_server_command ;;
    *) fail_exit "Unknown command: $1. Use ./setup.sh, ./setup.sh connect or ./setup.sh add-server." ;;
  esac
}

main "$@"
