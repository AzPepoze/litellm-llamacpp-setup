#!/usr/bin/env bash
# Model-server steps: llama.cpp and Basalt on the GPU machine.

NVIDIA_TOOLKIT_URL="https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"

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

ask_model_servers() {
  printf 'Which model servers should run on this machine? Answer y or n.\n'
  printf '  llama.cpp   GGUF models, port %s\n' "$LLAMA_CPP_PORT"
  printf '  Basalt      .basalt models, port %s. Needs an NVIDIA RTX 50 series GPU (Blackwell).\n' "$BASALT_PORT"
  ENABLE_LLAMA_CPP="$(ask_server_enabled "Run llama.cpp?" "$ENABLE_LLAMA_CPP")"
  ENABLE_BASALT="$(ask_server_enabled "Run Basalt?" "$ENABLE_BASALT")"
  set_env_value "$CONF_FILE" ENABLE_LLAMA_CPP "$ENABLE_LLAMA_CPP"
  set_env_value "$CONF_FILE" ENABLE_BASALT "$ENABLE_BASALT"
}

prepare_llama_cpp() {
  local env_file=inference/llama-cpp/.env
  create_secret_env inference/llama-cpp/.env.example "$env_file" LLAMA_CPP_API_KEY
  copy_if_missing inference/llama-cpp/presets.ini.example inference/llama-cpp/presets.ini
  set_env_value "$env_file" LISTEN_ADDRESS "$LISTEN_ADDRESS"
  set_env_value "$env_file" LLAMA_CPP_PORT "$LLAMA_CPP_PORT"
  check_llama_presets
}

prepare_basalt() {
  local env_file=inference/basalt/.env
  copy_if_missing inference/basalt/basalt_config.json.example inference/basalt/basalt_config.json
  create_api_key inference/basalt/api_key
  create_env_file inference/basalt/.env.example "$env_file"
  set_env_value "$env_file" LISTEN_ADDRESS "$LISTEN_ADDRESS"
  set_env_value "$env_file" BASALT_PORT "$BASALT_PORT"
  check_basalt_models
}

prepare_model_servers() {
  if llama_enabled; then prepare_llama_cpp; fi
  if basalt_enabled; then prepare_basalt; fi
}

llama_api_key() {
  read_env_value inference/llama-cpp/.env LLAMA_CPP_API_KEY
}

basalt_api_key() {
  head -n 1 inference/basalt/api_key
}

start_model_servers() {
  if llama_enabled; then run_compose inference/llama-cpp/docker-compose.yaml up -d; fi
  if basalt_enabled; then run_compose inference/basalt/docker-compose.yaml up -d --build; fi
}

print_model_start_commands() {
  printf 'Start later with:\n'
  if llama_enabled; then printf '  docker compose -f inference/llama-cpp/docker-compose.yaml up -d\n'; fi
  if basalt_enabled; then printf '  docker compose -f inference/basalt/docker-compose.yaml up -d --build\n'; fi
}

print_model_summary() {
  local status="$1"
  if llama_enabled; then print_service_row llama.cpp "$LLAMA_CPP_PORT" "$status"; fi
  if basalt_enabled; then print_service_row Basalt "$BASALT_PORT" "$status"; fi
}

offer_start_model_servers() {
  if ! llama_enabled && ! basalt_enabled; then return 0; fi
  if ask_yes_no "Start the model servers now?" y; then
    start_model_servers
    print_model_summary started
  else
    print_model_start_commands
  fi
}

print_model_next() {
  printf 'Next: on the gateway machine run ./setup.sh and choose 2. Then run ./setup.sh connect here to get the lines to paste.\n'
}

print_connect_block() {
  local name="$1"
  local address="$2"
  local port="$3"
  local key="$4"
  printf '[%s]\nbase_url = http://%s:%s/v1\napi_key = %s\n\n' "$name" "$address" "$port" "$key"
}

print_connect_blocks() {
  local address
  if ! llama_enabled && ! basalt_enabled; then
    warn "No model server is enabled in $CONF_FILE."
    return 0
  fi
  address="$(first_lan_ip)"
  address="${address:-YOUR-MACHINE-ADDRESS}"
  printf 'Paste into litellm/provider/providers.ini on the gateway machine.\n'
  printf 'Replace the address if the gateway reaches this machine by another name.\n\n'
  if llama_enabled; then
    require_file inference/llama-cpp/.env "Run ./setup.sh on this machine first."
    print_connect_block llama-cpp "$address" "$LLAMA_CPP_PORT" "$(llama_api_key)"
  fi
  if basalt_enabled; then
    require_file inference/basalt/api_key "Run ./setup.sh on this machine first."
    print_connect_block basalt "$address" "$BASALT_PORT" "$(basalt_api_key)"
  fi
}

setup_models() {
  check_nvidia_runtime
  ask_model_servers
  prepare_model_servers
  offer_start_model_servers
  print_model_next
}
