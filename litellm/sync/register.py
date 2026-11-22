"""Phase 2: register discovered models that the gateway does not know yet.

Usage: register.py DISCOVERED_JSON
Env: GATEWAY_URL, GATEWAY_WAIT_TIMEOUT, LITELLM_MASTER_KEY

Never fatal: every failure logs and exits 0, so the gateway keeps running.
"""
import json
import os
import sys
import time

from gateway import call, is_unauthorized, model_ids
from log import error, info, warn

RETRY_DELAY = 5
SUCCESS_MIN = 200
SUCCESS_MAX = 300


def load_discovered(disc_path):
    try:
        with open(disc_path) as f:
            return json.load(f)
    except Exception as e:
        warn(f"cannot read {disc_path} ({e}); skipping API sync")
        return None


def wait_for_api(base_url, master_key, timeout):
    """Return the ids the gateway already serves, or None if it never became usable."""
    deadline = time.time() + timeout
    while True:
        try:
            status, text = call(base_url, master_key, "GET", "/v1/models")
            if status == 200:
                return model_ids(text)
            info(f"gateway /v1/models -> {status}, retrying...")
        except Exception as e:
            if is_unauthorized(e):
                error("gateway rejected the master key (401); check LITELLM_MASTER_KEY")
                return None
            info(f"gateway not ready ({e}), retrying...")
        if time.time() >= deadline:
            error(f"gateway API not ready after {timeout:.0f}s; "
                  f"models not registered this boot")
            return None
        time.sleep(RETRY_DELAY)


def model_body(entry):
    return {
        "model_name": entry["name"],
        "litellm_params": {
            "model": "openai/" + entry["mid"],
            "api_base": entry["base_url"],
            "api_key": entry["api_key"],
            **entry["params"],
        },
        "model_info": entry["info"],
    }


def register_all(entries, existing, base_url, master_key):
    added = 0
    for entry in entries:
        name = entry["name"]
        if name in existing:
            continue
        try:
            status, text = call(base_url, master_key, "POST", "/model/new",
                                model_body(entry))
        except Exception as e:
            if is_unauthorized(e):
                error("gateway rejected the master key (401); stopping registration")
                break
            warn(f"registering {name} failed ({e})")
            continue
        if SUCCESS_MIN <= status < SUCCESS_MAX:
            info(f"registered {name} as DB model")
            existing.add(name)
            added += 1
        else:
            warn(f"registering {name} -> {status}: {text[:200]}")
    info(f"registered {added} new model(s) via API")


def main():
    entries = load_discovered(sys.argv[1])
    if not entries:
        return

    base_url = os.environ.get("GATEWAY_URL", "http://127.0.0.1:4000").rstrip("/")
    wait_timeout = float(os.environ.get("GATEWAY_WAIT_TIMEOUT", "180"))
    master_key = os.environ.get("LITELLM_MASTER_KEY", "")
    if not master_key:
        error("LITELLM_MASTER_KEY not set; cannot register models via API")
        return

    existing = wait_for_api(base_url, master_key, wait_timeout)
    if existing is None:
        return
    register_all(entries, existing, base_url, master_key)


if __name__ == "__main__":
    main()
