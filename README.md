# LiteLLM LLM Server & Gateway with Admin Dashboard

A secure, production-ready, multi-container LLM gateway. This setup isolates the internal LLM routers (LiteLLM), inference backends (llama.cpp/vLLM), key database (PostgreSQL), and admin APIs behind a single **Nginx Secure Gateway** that acts as the only entry point exposed to the host machine.

Access is routed using virtual hosting ports:
*   **`http://localhost` (Port 80)** -> For the secure admin key-management dashboard.
*   **`http://localhost:8080` (Port 8080)** -> For client LLM API requests (`/v1/*`).

---

## Table of Contents
1. [Architecture & Flow](#architecture--flow)
2. [Project Structure](#project-structure)
3. [Prerequisites](#prerequisites)
4. [Deployment Guide](#deployment-guide)
5. [Admin Dashboard Guide](#admin-dashboard-guide)
6. [Adding new models (vLLM, Ollama, APIs)](#adding-new-models)
7. [Verifying API Requests](#verifying-api-requests)

---

## Architecture & Flow

```mermaid
graph TD
    Client[Client App / Admin Browser] -->|Port 80 / 8080| Nginx[Nginx Gateway<br/>Only Exposed Container]
    
    Nginx -->|Port 8080| LiteLLM[LiteLLM Proxy<br/>Port 4000 Internal]
    Nginx -->|Port 80| Frontend[Admin Frontend<br/>Port 80 Internal]
    Nginx -->|Port 80 /api/*| Backend[Admin Backend<br/>Port 5000 Internal]
    
    Backend -->|Calls API with Master Key| LiteLLM
    LiteLLM -->|Saves Keys & Spend| Postgres[(PostgreSQL DB<br/>Port 5432 Internal)]
    
    subgraph Model Runtimes
        LiteLLM -->|GGUF Queries| TinyLlama[TinyLlama Container]
        LiteLLM -->|GGUF Queries| Qwen[Qwen Container]
    end
```

### Key Security Benefits
*   **Decoupled Frontend:** The static HTML frontend communicates only with the Admin Backend. LiteLLM master tokens are never sent to or stored in the client web browser.
*   **Stateful Key Persistence:** Virtual API keys, model rate limits (TPM/RPM), and team budgets are stored persistently in PostgreSQL.

---

## Project Structure

```bash
.
├── docker-compose.yaml     # Service orchestrator (Database, LiteLLM, Front, Back, Nginx)
├── litellm/
│   └── config.yaml         # LiteLLM routing rules and model definitions
├── nginx/
│   └── nginx.conf          # Nginx routing config (Port 80 & Port 8080 servers)
├── backend/
│   ├── server.js           # Admin Dashboard Express API Backend
│   ├── package.json
│   └── Dockerfile
└── frontend/
    ├── index.html          # Admin Dashboard HTML5 Layout
    ├── style.css           # Premium Dark Slate Theme
    └── app.js              # State management & fetch logic
```

---

## Prerequisites

Ensure you have the following installed on your system:
*   [Docker](https://docs.docker.com/get-docker/)
*   [Docker Compose V2](https://docs.docker.com/compose/)
*   [Git](https://git-scm.com/)

---

## Deployment Guide

### Step 1: Clone the Repository
```bash
git clone <your-repo-url>
cd LLM
```

### Step 2: Configure Environment Secrets
Ensure the same `LITELLM_MASTER_KEY` is defined in [docker-compose.yaml](file:///home/bwrpsp/proj/LLM/docker-compose.yaml) under the `litellm` and `backend` services.

### Step 3: Start the Containers
```bash
docker compose up -d --build
```
This builds the admin backend image, pulls Nginx, Postgres, and llama.cpp images, configures database tables, and mounts static folders automatically.

---

## Admin Dashboard Guide

Open your web browser and navigate to:
👉 **[http://localhost](http://localhost)**

### Features:
1.  **Overview Telemetry:** Displays total active virtual keys, total gateway spend in USD, and total allocated budget across all generated keys.
2.  **Generate Keys:** 
    *   Enter an alias description (e.g. `Marketing Devs`).
    *   Select which models this key has access to (e.g., `tinyllama`, `qwen-small`).
    *   Set maximum USD budgets and request rate limits (RPM / TPM).
3.  **Secure Modal Display:** When a key is created, the raw token is displayed in a warning popup. **Copy it immediately**, as it will not be displayed again.
4.  **Revocation:** Click **Revoke** on any key to delete it from the Postgres database. The key will immediately stop working.

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

Once you generate a virtual key (e.g., `sk-12345...`) from the Admin Dashboard, use it to query models through the gateway.

### 1. List Available Models
```bash
curl --location 'http://localhost:8080/v1/models' \
--header 'Authorization: Bearer sk-your-generated-key'
```

### 2. Chat Completion Request (TinyLlama)
```bash
curl --location 'http://localhost:8080/v1/chat/completions' \
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
