Back to [README](../README.md)

# Setup and roles

`./setup.sh` sets up one machine. A machine can run the model servers, the gateway, or both.

## Roles

| Role | Runs on | What setup does |
|---|---|---|
| Model servers | The GPU machine | Sets up llama.cpp and/or Basalt, applies the ports, and offers to start them |
| Gateway | The machine that serves your apps | Sets up LiteLLM and asks for the model servers' addresses and keys |
| Both | One machine with a GPU | Does both steps on the same machine |

## setup.conf

`setup.sh` creates `setup.conf` from `setup.conf.example`. The file is git-ignored and holds no secrets.

Edit it, then run `./setup.sh` again to apply the change.

| Key | Default | What it does |
|---|---|---|
| `ROLE` | Asked once | `models`, `gateway` or `both` |
| `ENABLE_LLAMA_CPP` | `true` on a model machine | Runs llama.cpp |
| `ENABLE_BASALT` | `false` | Runs Basalt. Needs an RTX 50 series GPU |
| `LISTEN_ADDRESS` | `0.0.0.0` | Address the servers listen on. `0.0.0.0` means all network addresses |
| `LLAMA_CPP_PORT` | `8080` | Host port for llama.cpp |
| `BASALT_PORT` | `8081` | Host port for Basalt |
| `LITELLM_PORT` | `4000` | Host port for the LiteLLM gateway |

## Apply a change

1. Edit `setup.conf`.
2. Run `./setup.sh`.

The ports and flags go into each service's `.env` file. Do not edit those files by hand.

## Connect the gateway

Do these steps in order.

1. On the model machine, run:

   ```bash
   ./setup.sh connect
   ```

   It prints the address, port and key for each model server.

2. On the gateway machine, run:

   ```bash
   ./setup.sh
   ```

   Choose `2`. Enter the address, port and key from step 1.

   To add a second model server later, run `./setup.sh add-server`.

> [!IMPORTANT]
> Do not use `localhost` for the model server address in the gateway. LiteLLM runs in Docker, so `localhost` means the LiteLLM container itself.

Use the machine's name or IP, for example `beast-gpu` or `192.168.1.20`.

## Ports

| Service | Host port variable | Default | Container port |
|---|---|---|---|
| llama.cpp | `LLAMA_CPP_PORT` | `8080` | `8080` |
| Basalt | `BASALT_PORT` | `8081` | `8080` |
| LiteLLM | `LITELLM_PORT` | `4000` | `4000` |
