# LiteLLM LLM Server & Gateway with Admin UI

A production-ready, multi-container LLM gateway. This setup exposes **LiteLLM directly on host port 4000** for key-management and routing API requests to local backends (llama.cpp) or external APIs, using a stateful PostgreSQL database container for metadata storage.

Access is routed directly:
*   **Official Admin UI:** Access at **`http://localhost:4000/ui/`** (make sure to include the trailing slash!).
*   **LLM API Gateway:** Route requests to **`http://localhost:4000/v1/*`**.

---

## Table of Contents
1. [Architecture & Flow](#architecture--flow)
2. [Project Structure](#project-structure)
3. [Prerequisites](#prerequisites)
4. [Deployment Guide](#deployment-guide)
5. [Adding new models (vLLM, Ollama, APIs)](#adding-new-models)
6. [Verifying API Requests](#verifying-api-requests)

---

## Architecture & Flow

```mermaid
graph TD
    Client[Client App / Admin Browser] -->|Port 4000| LiteLLM[LiteLLM Proxy<br/>Port 4000 Exposed]
    
    LiteLLM -->|Saves Keys & Spend| Postgres[(PostgreSQL DB<br/>Port 5432 Internal)]
    
    subgraph Model Runtimes
        LiteLLM -->|GGUF Queries| TinyLlama[TinyLlama Container]
        LiteLLM -->|GGUF Queries| Qwen[Qwen Container]
    end
```

### Key Security & Operational Benefits
*   **Direct Access (Port 4000):** LiteLLM maps directly to port `4000` on the host system. Internal database query requests and inference traffic route securely within the docker network.
*   **Stateful Key Persistence:** Virtual API keys, model rate limits (TPM/RPM), and team budgets are stored persistently in PostgreSQL.

---

## Project Structure

```bash
.
├── docker-compose.yaml     # Service orchestrator (Database, LiteLLM)
└── litellm/
    └── config.yaml         # LiteLLM routing rules and model definitions
```

---

## Prerequisites

Ensure you have the following installed on your system:
*   [Docker](https://docs.google.com/get-docker/)
*   [Docker Compose V2](https://docs.google.com/compose/)
*   [Git](https://git-scm.com/)

---

## Deployment Guide

### Step 1: Start the Containers
```bash
docker compose up -d --build
```

### Step 2: Open the Admin UI
Navigate to:
👉 **[http://localhost:4000/ui/](http://localhost:4000/ui/)**

Enter the configured master key **`sk-super-secret-key`** as the token to start using the official LiteLLM UI for managing virtual keys.

---

## Adding New Models

You can customize or add models by mapping them inside `docker-compose.yaml` and registering them in `litellm/config.yaml`.

### 1. Adding a vLLM Container
In [docker-compose.yaml](file:///home/bwrpsp/proj/LLM/docker-compose.yaml), add:
```yaml
  vllm-server:
    image: vllm/vllm-openai:latest
    container_name: vllm-server
    restart: unless-stopped
    volumes:
      - ~/.cache/huggingface:/root/.cache/huggingface
    ipc: host
    command: --model facebook/opt-125m
```

In [litellm/config.yaml](file:///home/bwrpsp/proj/LLM/litellm/config.yaml), add:
```yaml
model_list:
  - model_name: my-vllm-model
    litellm_params:
      model: openai/facebook/opt-125m
      api_base: http://vllm-server:8000/v1
      api_key: dummy
```

### 2. Adding Commercial APIs (OpenAI, Anthropic, Gemini)
Pass your provider API key in the environment block of the `litellm` service inside [docker-compose.yaml](file:///home/bwrpsp/proj/LLM/docker-compose.yaml), then add them to your model list:
```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: gpt-4o
      api_key: "os.environ/OPENAI_API_KEY"
```

---

## Verifying API Requests

Once you generate a virtual key (e.g., `sk-12345...`) from the Admin UI, use it to query models through the gateway.

### 1. List Available Models
```bash
curl --location 'http://localhost:4000/v1/models' \
--header 'Authorization: Bearer sk-your-generated-key'
```

### 2. Chat Completion Request (TinyLlama)
```bash
curl --location 'http://localhost:4000/v1/chat/completions' \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer sk-your-generated-key' \
--data '{
  "model": "tinyllama",
  "messages": [
    {
      "role": "user",
      "content": "Why is the sky blue?"
    }
  ],
  "temperature": 0.2
}'
```
