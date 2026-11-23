#!/usr/bin/env bash
# Shared helpers for setup.sh, scripts/models.sh and scripts/gateway.sh.
# Loaded once by setup.sh; the other scripts rely on it being loaded first.

CONF_FILE="setup.conf"
CONF_EXAMPLE="setup.conf.example"
PROVIDERS_FILE="litellm/provider/providers.ini"
CONF_KEYS="ROLE ENABLE_LLAMA_CPP ENABLE_BASALT LISTEN_ADDRESS LLAMA_CPP_PORT BASALT_PORT LITELLM_PORT"

# Defaults. setup.conf overrides them.
ROLE=""
ENABLE_LLAMA_CPP=true
ENABLE_BASALT=false
LISTEN_ADDRESS=0.0.0.0
LLAMA_CPP_PORT=8080
BASALT_PORT=8081
LITELLM_PORT=4000

ok() { printf 'OK    %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1" >&2; }
fail_exit() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
file_action() { printf '%-8s %s\n' "$1" "$2"; }

llama_enabled() { [[ "$ENABLE_LLAMA_CPP" == true ]]; }
basalt_enabled() { [[ "$ENABLE_BASALT" == true ]]; }

read_answer() {
  local answer=""
  read -r -p "$1" answer || true
  printf '%s\n' "$answer"
}

ask_text() {
  local question="$1"
  local default="$2"
  local hint=""
  local answer=""
  if [[ -n "$default" ]]; then hint=" [$default]"; fi
  answer="$(read_answer "$question$hint: ")"
  printf '%s\n' "${answer:-$default}"
}

ask_yes_no() {
  local question="$1"
  local default="$2"
  local hint="[y/N]"
  local answer=""
  if [[ "$default" == y ]]; then hint="[Y/n]"; fi
  answer="$(read_answer "$question $hint ")"
  answer="${answer:-$default}"
  [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

ask_choice() {
  local question="$1"
  local default="$2"
  local pattern="$3"
  local answer=""
  while true; do
    answer="$(ask_text "$question" "$default")"
    if [[ "$answer" =~ ^($pattern)$ ]]; then
      printf '%s\n' "$answer"
      return 0
    fi
    warn "Type one of the numbers shown."
  done
}

read_secret() {
  local answer=""
  read -r -s -p "$1: " answer || true
  printf '\n' >&2
  printf '%s\n' "$answer"
}

yes_no_default() {
  if [[ "$1" == true ]]; then printf 'y\n'; else printf 'n\n'; fi
}

ask_server_enabled() {
  if ask_yes_no "$1" "$(yes_no_default "$2")"; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

generate_secret() {
  openssl rand -hex 24
}

first_lan_ip() {
  local addresses
  addresses="$(hostname -I 2>/dev/null || true)"
  awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9.]+$/ && $i !~ /^127\./) { print $i; exit } }' <<< "$addresses"
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
  awk -v key="$key" -v value="$value" '
    index($0, key "=") == 1 { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

require_file() {
  [[ -f "$1" ]] || fail_exit "$2"
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

create_env_file() {
  local example="$1"
  local target="$2"
  if [[ -e "$target" ]]; then
    file_action kept "$target"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  if [[ -f "$example" ]]; then
    cp "$example" "$target"
  else
    : > "$target"
  fi
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

run_compose() {
  local file="$1"
  shift
  docker compose -f "$file" "$@"
}

print_service_row() {
  printf '  %-10s port %-6s %s\n' "$1" "$2" "$3"
}

is_conf_key() {
  [[ " $CONF_KEYS " == *" $1 "* ]]
}

# Reads KEY=value lines. Only known keys are taken; the file is never sourced.
load_conf() {
  local line key value
  [[ -f "$CONF_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      if is_conf_key "$key"; then printf -v "$key" '%s' "$value"; fi
    fi
  done < "$CONF_FILE"
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || fail_exit "Ports in $CONF_FILE must be numbers. Got: $1"
}

validate_conf() {
  case "$ROLE" in
    models|gateway|both) ;;
    *) fail_exit "ROLE in $CONF_FILE must be models, gateway or both." ;;
  esac
  [[ "$ENABLE_LLAMA_CPP" =~ ^(true|false)$ ]] || fail_exit "ENABLE_LLAMA_CPP in $CONF_FILE must be true or false."
  [[ "$ENABLE_BASALT" =~ ^(true|false)$ ]] || fail_exit "ENABLE_BASALT in $CONF_FILE must be true or false."
  validate_port "$LLAMA_CPP_PORT"
  validate_port "$BASALT_PORT"
  validate_port "$LITELLM_PORT"
}
