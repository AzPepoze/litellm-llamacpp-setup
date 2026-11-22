import json
import time
import urllib.request

from log import error, info

RETRY_DELAY = 5
REQUEST_TIMEOUT = 10


def fetch_models(base_url, api_key, timeout):
    """Return the model list from a llama.cpp server, or [] if it stays unreachable."""
    url = base_url.rstrip("/") + "/models"
    request = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {api_key}"})
    deadline = time.time() + timeout
    attempt = 0
    while True:
        attempt += 1
        try:
            return read_models(request)
        except Exception as e:  # server still booting or host rebooting
            if time.time() >= deadline:
                error(f"{url} unreachable after {timeout:.0f}s ({e}); skipping server")
                return []
            info(f"{url} not ready (attempt {attempt}: {e}), retrying...")
            time.sleep(max(0, min(RETRY_DELAY, deadline - time.time())))


def read_models(request):
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as resp:
        data = json.load(resp)
    if not isinstance(data, dict) or not isinstance(data.get("data"), list):
        raise ValueError("unexpected /v1/models shape")
    return data["data"]
