#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

readonly NVIDIA_TOOLKIT_URL="https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"

ENABLE_LLAMA_CPP=0
ENABLE_BASALT=0
HOST_ADDRESS=""

ok() { printf 'OK    %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
fail_exit() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
file_action() { printf '%-8s %s\n' "$1" "$2"; }

llama_enabled() { [[ "$ENABLE_LLAMA_CPP" == 1 ]]; }
basalt_enabled() { [[ "$ENABLE_BASALT" == 1 ]]; }

ask_yes_no() {
  local question="$1"
  local default="$2"
  local hint="[y/N]"
  local answer=""
  if [[ "$default" == y ]]; then hint="[Y/n]"; fi
  if [[ -t 0 ]]; then
    read -r -p "$question $hint " answer || true
  fi
  answer="${answer:-$default}"
  [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

generate_secret() {
  openssl rand -hex 24
}

first_lan_ip() {
  local addresses
  addresses="$(hostname -I 2>/dev/null || true)"
  awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9.]+$/ && $i !~ /^127\./) { print $i; exit } }' <<< "$addresses"
}

ask_host() {
  local default_host
  local answer=""
  default_host="$(first_lan_ip)"
  default_host="${default_host:-localhost}"
  printf 'Use the LAN hostname or IP, not localhost: the gateway runs in Docker.\n'
  if [[ -t 0 ]]; then
    read -r -p "Address of this machine [$default_host]: " answer || true
  fi
  HOST_ADDRESS="${answer:-$default_host}"
  if [[ "$HOST_ADDRESS" == localhost ]]; then warn "Host is localhost. The gateway container cannot reach it."; fi
}

read_env_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp="$file.tmp"
  awk -F= -v key="$key" -v value="$value" 'BEGIN { OFS = "=" } $1 == key { $0 = key "=" value } { print }' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

copy_example() {
  local source="$1"
  local target="$2"
  [[ -f "$source" ]] || fail_exit "missing $source"
  mkdir -p "$(dirname "$target")"
  cp "$source" "$target"
}

copy_if_missing() {
  local source="$1"
  local target="$2"
  if [[ -e "$target" ]]; then
    file_action kept "$target"
    return 0
  fi
  copy_example "$source" "$target"
  file_action created "$target"
}

create_secret_env() {
  local source="$1"
  local target="$2"
  local key
  shift 2
  if [[ -e "$target" ]]; then
    file_action kept "$target"
    return 0
  fi
  copy_example "$source" "$target"
  for key in "$@"; do
    set_env_value "$target" "$key" "$(generate_secret)"
  done
  chmod 600 "$target"
  file_action created "$target"
}

create_api_key() {
  local target="$1"
  local secret
  if [[ -e "$target" ]]; then
    file_action kept "$target"
    return 0
  fi
  secret="$(generate_secret)"
  printf '%s\n' "$secret" > "$target"
  chmod 600 "$target"
  file_action created "$target"
}

write_llama_section() {
  local key
  key="$(read_env_value inference/llama-cpp/.env LLAMA_CPP_API_KEY)"
  [[ -n "$key" ]] || fail_exit "LLAMA_CPP_API_KEY is empty in inference/llama-cpp/.env"
  printf '[llama-cpp]\nbase_url = http://%s:8080/v1\napi_key = %s\n\n' "$HOST_ADDRESS" "$key"
}

write_basalt_section() {
  local key
  key="$(head -n 1 inference/basalt/api_key)"
  printf '[basalt]\nbase_url = http://%s:8081/v1\napi_key = %s\n' "$HOST_ADDRESS" "$key"
}

write_providers() {
  if llama_enabled; then write_llama_section; fi
  if basalt_enabled; then write_basalt_section; fi
}

setup_providers() {
  local target="litellm/provider/providers.ini"
  if [[ -e "$target" ]]; then
    file_action kept "$target"
    return 0
  fi
  ask_host
  write_providers > "$target"
  chmod 600 "$target"
  file_action created "$target"
}

setup_gateway() {
  create_secret_env litellm/.env.example litellm/.env POSTGRES_PASSWORD LITELLM_ADMIN_PASSWORD
}

setup_llama_cpp() {
  create_secret_env inference/llama-cpp/.env.example inference/llama-cpp/.env LLAMA_CPP_API_KEY
  copy_if_missing inference/llama-cpp/presets.ini.example inference/llama-cpp/presets.ini
}

setup_basalt() {
  copy_if_missing inference/basalt/data/basalt_config.json.example inference/basalt/data/basalt_config.json
  create_api_key inference/basalt/api_key
}

check_docker() {
  command -v docker >/dev/null 2>&1 || fail_exit "docker is not installed. See https://docs.docker.com/get-docker/"
  docker compose version >/dev/null 2>&1 || fail_exit "docker compose is not available. See https://docs.docker.com/compose/install/"
  ok "$(docker --version)"
}

check_openssl() {
  command -v openssl >/dev/null 2>&1 || fail_exit "openssl is not installed."
  ok "openssl found"
}

has_nvidia_gpu_support() {
  local info
  info="$(docker info 2>/dev/null || true)"
  if grep -qi nvidia <<< "$info"; then return 0; fi
  if command -v nvidia-ctk >/dev/null 2>&1; then return 0; fi
  [[ -f /var/run/cdi/nvidia.yaml ]]
}

check_nvidia_runtime() {
  if has_nvidia_gpu_support; then
    ok "NVIDIA container runtime found"
  else
    warn "NVIDIA container runtime not found. Install the NVIDIA Container Toolkit: $NVIDIA_TOOLKIT_URL"
  fi
}

check_llama_presets() {
  if grep -Eq '^[[:space:]]*\[[^]*]+\]' inference/llama-cpp/presets.ini; then
    ok "Model section found in inference/llama-cpp/presets.ini"
  else
    warn "No model in inference/llama-cpp/presets.ini. Uncomment one example block. See docs/models.md"
  fi
}

check_basalt_models() {
  if compgen -G "inference/basalt/models/*.basalt" >/dev/null; then
    ok "Basalt model found in inference/basalt/models/"
    return 0
  fi
  warn "No .basalt model in inference/basalt/models/. Download one:"
  printf '      cd inference/basalt\n'
  printf '      hf download jesdga/Qwen3.8-27B-Basalt Qwen3.8-27B-QUASAR-NVFP4.basalt --local-dir models\n'
}

choose_backends() {
  if ask_yes_no "Enable llama.cpp?" y; then ENABLE_LLAMA_CPP=1; fi
  printf 'Basalt needs an NVIDIA RTX 50 series GPU (Blackwell).\n'
  if ask_yes_no "Enable Basalt?" n; then ENABLE_BASALT=1; fi
}

run_compose() {
  local file="$1"
  shift
  docker compose -f "$file" "$@"
}

start_services() {
  if llama_enabled; then run_compose inference/llama-cpp/docker-compose.yaml up -d; fi
  if basalt_enabled; then run_compose inference/basalt/docker-compose.yaml up -d --build; fi
  run_compose litellm/docker-compose.yaml up -d
}

print_start_commands() {
  printf 'Start later with:\n'
  if llama_enabled; then printf '  docker compose -f inference/llama-cpp/docker-compose.yaml up -d\n'; fi
  if basalt_enabled; then printf '  docker compose -f inference/basalt/docker-compose.yaml up -d --build\n'; fi
  printf '  docker compose -f litellm/docker-compose.yaml up -d\n'
}

print_summary_row() {
  printf '%-12s %-28s %s\n' "$1" "$2" "$3"
}

print_summary() {
  local status="$1"
  printf '\n'
  print_summary_row Service Address Status
  print_summary_row LiteLLM http://localhost:4000/ui/ "$status"
  if llama_enabled; then print_summary_row llama.cpp http://localhost:8080 "$status"; fi
  if basalt_enabled; then print_summary_row Basalt http://localhost:8081 "$status"; fi
}

main() {
  check_docker
  check_openssl
  check_nvidia_runtime
  choose_backends
  setup_gateway
  if llama_enabled; then setup_llama_cpp; fi
  if basalt_enabled; then setup_basalt; fi
  setup_providers
  if llama_enabled; then check_llama_presets; fi
  if basalt_enabled; then check_basalt_models; fi
  if ask_yes_no "Start the services now?" y; then
    start_services
    print_summary started
  else
    print_start_commands
    print_summary "not started"
  fi
}

main "$@"
