# LiteLLM Gateway & Proxy Server Guide

This guide provides a comprehensive overview of using, configuring, deploying, and integrating **LiteLLM Proxy** in this project. LiteLLM acts as a central API gateway, routing client requests to various local runtimes (such as `llama.cpp`) or external commercial APIs (such as OpenAI, Anthropic, or Gemini) using a unified, OpenAI-compatible API interface.

---

## Table of Contents
1. [Overview](#1-overview)
2. [Key Features](#2-key-features)
3. [Deployment & Infrastructure Guide](#3-deployment--infrastructure-guide)
   - [PostgreSQL Database Requirement](#postgresql-database-requirement)
   - [LiteLLM Configuration (`config.yaml`)](#litellm-configuration-configyaml)
   - [Docker Compose Integration](#docker-compose-integration)
4. [Connecting to the Gateway](#4-connecting-to-the-gateway)
5. [How to Generate Virtual API Keys (Admin UI)](#5-how-to-generate-virtual-api-keys-admin-ui)
6. [Code Integration Examples](#6-code-integration-examples)
   - [1. cURL](#1-curl)
   - [2. LiteLLM Python SDK](#2-litellm-python-sdk)
   - [3. OpenAI Python SDK](#3-openai-python-sdk)
   - [4. Python standard `requests` library](#4-python-standard-requests-library)

---

## 1. Overview

In this deployment architecture, **LiteLLM** sits between client applications and downstream model endpoints. It serves as a unified proxy that accepts standard OpenAI-format REST requests, validates virtual API keys, checks budgets/rate limits, routes requests to the configured target model runner, and streams the responses back to the client.

```mermaid
graph TD
    Client[Client App / Developer] -->|Port 4000<br/>API Requests / UI| LiteLLM[LiteLLM Gateway]
    
    subgraph Storage
        LiteLLM -->|Read/Write state, keys, spend| Postgres[(PostgreSQL DB<br/>Port 5432)]
    end
    
    subgraph Downstream Model Runtimes
        LiteLLM -->|GGUF Routing| TinyLlama[TinyLlama Container<br/>llama.cpp]
        LiteLLM -->|GGUF Routing| Qwen[Qwen Container<br/>llama.cpp]
        LiteLLM -.->|External API Routing| CommercialAPIs[OpenAI / Anthropic / Gemini]
    end
```

---

## 2. Key Features

*   **Unified API Interface:** Access all backend LLMs (whether hosted locally via GGUF format or externally via proprietary clouds) through standard OpenAI-compatible endpoints (`/v1/chat/completions` and `/v1/models`).
*   **Stateful Virtual Key Management:** Generate custom, fine-grained virtual API keys (starting with `sk-`) with specific permissions, expiration dates, and model access lists.
*   **Budgets and Rate Limiting:** Apply constraints to individual virtual keys or users, limiting **Tokens Per Minute (TPM)**, **Requests Per Minute (RPM)**, and maximum currency budget (e.g., $10 max monthly spend).
*   **Admin Dashboard UI:** Easily inspect logs, debug latency, manage keys, track overall spend, and view audit metrics in a visual web interface.
*   **Automatic Fallbacks & Retries:** Configure backup models and retry logic directly within LiteLLM to ensure high availability when inference engines fail or hit rate limits.

---

## 3. Deployment & Infrastructure Guide

### PostgreSQL Database Requirement
LiteLLM requires a database to support **stateful features** such as virtual keys, user access roles, model access groups, and real-time spend tracking. Without a PostgreSQL instance:
1. Virtual keys cannot be persistently stored (they would reset when the container restarts).
2. Advanced key properties, limits, and real-time tracking budgets cannot be computed.
3. The Admin UI will operate in a stateless, read-only mode or fail to load.

In the local setup, PostgreSQL is run in an alpine container (`postgres:15-alpine`) inside the same Docker network. Data is kept persistent via the Docker volume `postgres_data`.

### LiteLLM Configuration (`config.yaml`)
LiteLLM reads routing rules and settings from [litellm/config.yaml](file:///e:/BotNoi/LiteLLM-LLM-Server-and-Gateway/litellm/config.yaml).

A standard configuration registers the models and maps them to their base addresses:
```yaml
model_list:
  # Local GGUF Model hosted via llama.cpp
  - model_name: tinyllama
    litellm_params:
      model: openai/tinyllama
      api_base: http://tinyllama:8080/v1
      api_key: dummy

  # Another local GGUF Model hosted via llama.cpp
  - model_name: qwen-small
    litellm_params:
      model: openai/qwen-small
      api_base: http://qwen-small:8080/v1
      api_key: dummy

general_settings:
  # Master Key to authenticate against Admin UI and Admin APIs
  master_key: os.environ/LITELLM_MASTER_KEY
```

> [!NOTE]
> `os.environ/LITELLM_MASTER_KEY` tells LiteLLM to lookup the environment variable `LITELLM_MASTER_KEY` at runtime.

### Docker Compose Integration
In the orchestrator configuration [docker-compose.yaml](file:///e:/BotNoi/LiteLLM-LLM-Server-and-Gateway/docker-compose.yaml), the database connections and configurations are linked as follows:

```yaml
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=litellm
      - POSTGRES_PASSWORD=litellm-secret-pass
      - POSTGRES_DB=litellm
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -d litellm -U litellm"]
      interval: 5s
      timeout: 5s
      retries: 5

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    ports:
      - "4000:4000"
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - DATABASE_URL=postgresql://litellm:litellm-secret-pass@postgres:5432/litellm
      - LITELLM_MASTER_KEY=sk-super-secret-key
      - STORE_MODEL_IN_DB=True
    volumes:
      - ./litellm/config.yaml:/app/config.yaml
    command:
      - "--config"
      - "/app/config.yaml"
```

---

## 4. Connecting to the Gateway

Once docker services are up, clients and admin browsers connect directly to LiteLLM using port **4000**:

*   **API Base Endpoint:** `http://localhost:4000` (or `http://localhost:4000/v1`)
*   **Admin UI Endpoint:** `http://localhost:4000/ui/`

> [!IMPORTANT]
> When accessing the Admin UI in a web browser, make sure to include the trailing slash: **`/ui/`**. Accessing `http://localhost:4000/ui` (without the slash) may fail to route static assets properly.

---

## 5. How to Generate Virtual API Keys (Admin UI)

Follow these steps to obtain a virtual API key:

1. Open your web browser and navigate to **`http://localhost:4000/ui/`**.
2. You will be prompted for a token. Enter the master key defined in your environment/docker-compose config: **`sk-super-secret-key`**.
3. Under the **Virtual Keys** tab, click the **Generate Key** button.
4. (Optional) In the generation form, configure rules:
   - Restrict the key to specific models (e.g. only `tinyllama`).
   - Define a maximum budget or rate limit (RPM/TPM).
   - Set an expiration window.
5. Click **Generate** / **Save**.
6. Copy the resulting key (starts with `sk-...`). **Warning:** Store it securely, as you will not be able to retrieve or view the full key value again for security reasons.

### Additional Admin UI Capabilities
Beyond basic key generation, the LiteLLM Admin UI provides a full management suite:
*   **Dynamic Model Management:** Add, configure, and manage downstream models directly via the UI (stored persistently when `STORE_MODEL_IN_DB=True` is enabled).
*   **Team and User Management:** Create and provision dedicated teams or users, setting custom budgets and rate limits at the team or individual level.
*   **Usage Dashboards:** Users can log in to view their specific token usage and budget consumption, while administrators have access to full diagnostic logging, cost tracking, and detailed usage analytics.
*   **Advanced Features:** Integrate Model Context Protocol (MCP) servers, configure custom routing agents, and manage fallback configurations directly from the dashboard.

---

## 6. Code Integration Examples

Replace `sk-your-generated-key` below with the virtual key generated from the Admin UI.

### 1. cURL
You can quickly query the gateway's active models list and chat endpoints using simple curl commands:

#### Get Models List
```bash
curl --location 'http://localhost:4000/v1/models' \
     --header 'Authorization: Bearer sk-your-generated-key'
```

#### Chat Completion Request
```bash
curl --location 'http://localhost:4000/v1/chat/completions' \
     --header 'Content-Type: application/json' \
     --header 'Authorization: Bearer sk-your-generated-key' \
     --data '{
       "model": "tinyllama",
       "messages": [
         {
           "role": "user",
           "content": "Explain gravity in one sentence."
         }
       ],
       "temperature": 0.3
     }'
```

---

### 2. LiteLLM Python SDK
If your Python code uses LiteLLM directly, set `api_base` and `api_key` programmatically.

```python
import litellm

# Point to the local LiteLLM proxy
response = litellm.completion(
    model="tinyllama", 
    messages=[{"role": "user", "content": "Hello! How are you?"}],
    api_base="http://localhost:4000",
    api_key="sk-your-generated-key"
)

print(response.choices[0].message.content)
```

---

### 3. OpenAI Python SDK
You can use the standard OpenAI python client library by overriding the `base_url` parameter to point to the LiteLLM Proxy port.

```python
from openai import OpenAI

# Initialize the client pointing to the LiteLLM gateway
client = OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-your-generated-key"
)

response = client.chat.completions.create(
    model="tinyllama",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "What is the capital of France?"}
    ],
    temperature=0.7
)

print(response.choices[0].message.content)
```

---

### 4. Python standard `requests` library
If you want to avoid external SDK dependencies, use standard HTTP request logic:

```python
import requests

url = "http://localhost:4000/v1/chat/completions"

headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer sk-your-generated-key"
}

payload = {
    "model": "tinyllama",
    "messages": [
        {
            "role": "user",
            "content": "Tell me a joke about programming."
        }
    ],
    "temperature": 0.5
}

response = requests.post(url, json=payload, headers=headers)

if response.status_code == 200:
    data = response.json()
    content = data["choices"][0]["message"]["content"]
    print("Response:", content)
else:
    print(f"Error {response.status_code}: {response.text}")
```
