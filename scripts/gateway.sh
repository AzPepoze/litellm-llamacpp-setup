#!/usr/bin/env bash
# Gateway steps: LiteLLM and the providers.ini list of model servers.

default_port_for() {
  case "$1" in
    llama-cpp) printf '8080\n' ;;
    basalt) printf '8081\n' ;;
  esac
}

server_kind_for_choice() {
  case "$1" in
    1) printf 'llama-cpp\n' ;;
    2) printf 'basalt\n' ;;
  esac
}

print_server_menu() {
  printf 'Which server is it?\n'
  printf '  1) llama.cpp   default port 8080\n'
  printf '  2) Basalt      default port 8081\n'
}

print_localhost_note() {
  printf 'Not localhost: LiteLLM runs in Docker, so localhost would mean the LiteLLM container itself.\n'
}

ensure_providers_file() {
  if [[ -e "$PROVIDERS_FILE" ]]; then return 0; fi
  mkdir -p "$(dirname "$PROVIDERS_FILE")"
  (umask 077; : > "$PROVIDERS_FILE")
  file_action created "$PROVIDERS_FILE"
}

next_section_name() {
  local kind="$1"
  local name="$kind"
  local count=2
  while grep -Fxq "[$name]" "$PROVIDERS_FILE" 2>/dev/null; do
    name="$kind-$count"
    count=$((count + 1))
  done
  printf '%s\n' "$name"
}

write_server_section() {
  local name="$1"
  local base_url="$2"
  local key="$3"
  ensure_providers_file
  printf '[%s]\nbase_url = %s\napi_key = %s\n\n' "$name" "$base_url" "$key" >> "$PROVIDERS_FILE"
  file_action added "[$name] in $PROVIDERS_FILE"
}

add_one_server() {
  local address choice kind port key
  print_localhost_note
  address="$(ask_text "Name or IP of the machine that runs the model servers (example: beast-gpu or 192.168.1.20)" "")"
  if [[ -z "$address" ]]; then
    warn "No address given. Skipped."
    return 1
  fi
  print_server_menu
  choice="$(ask_choice "Choose 1 or 2" 1 '1|2')"
  kind="$(server_kind_for_choice "$choice")"
  port="$(ask_text "Port of the $kind server" "$(default_port_for "$kind")")"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    warn "Port must be a number. Skipped."
    return 1
  fi
  key="$(read_secret "API key of that server (typed hidden)")"
  if [[ -z "$key" ]]; then
    warn "No API key given. Skipped."
    return 1
  fi
  write_server_section "$(next_section_name "$kind")" "http://$address:$port/v1" "$key"
}

ask_gateway_servers() {
  if [[ -e "$PROVIDERS_FILE" ]]; then
    file_action kept "$PROVIDERS_FILE"
    printf 'To add a model server later, run ./setup.sh add-server.\n'
    return 0
  fi
  add_one_server || true
  while ask_yes_no "Add another model server?" n; do
    add_one_server || true
  done
  if [[ ! -e "$PROVIDERS_FILE" ]]; then
    warn "No model server added. Run ./setup.sh add-server to add one."
  fi
}

prepare_local_providers() {
  local address
  if [[ -e "$PROVIDERS_FILE" ]]; then
    file_action kept "$PROVIDERS_FILE"
    return 0
  fi
  if ! llama_enabled && ! basalt_enabled; then
    warn "No model server is enabled. Run ./setup.sh add-server later."
    return 0
  fi
  print_localhost_note
  address="$(ask_text "Name or IP of this GPU machine, as the gateway sees it" "$(first_lan_ip)")"
  if [[ -z "$address" ]]; then
    warn "No address given. Run ./setup.sh add-server later."
    return 0
  fi
  if llama_enabled; then
    write_server_section llama-cpp "http://$address:$LLAMA_CPP_PORT/v1" "$(llama_api_key)"
  fi
  if basalt_enabled; then
    write_server_section basalt "http://$address:$BASALT_PORT/v1" "$(basalt_api_key)"
  fi
}

prepare_gateway_env() {
  create_secret_env litellm/.env.example litellm/.env POSTGRES_PASSWORD LITELLM_ADMIN_PASSWORD
  set_env_value litellm/.env LISTEN_ADDRESS "$LISTEN_ADDRESS"
  set_env_value litellm/.env LITELLM_PORT "$LITELLM_PORT"
}

offer_start_gateway() {
  if ask_yes_no "Start LiteLLM now?" y; then
    run_compose litellm/docker-compose.yaml up -d
    print_service_row LiteLLM "$LITELLM_PORT" started
  else
    printf 'Start later with:\n  docker compose -f litellm/docker-compose.yaml up -d\n'
  fi
}

setup_gateway() {
  prepare_gateway_env
  ask_gateway_servers
  offer_start_gateway
}

add_server_command() {
  add_one_server
}
