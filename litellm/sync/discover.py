"""Find the models on every inference server and save them as JSON.

Usage: discover.py PROVIDERS_INI DISCOVERED_JSON TIMEOUT
"""
import configparser
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from itertools import repeat

from ini import read_provider
from llamacpp import fetch_models
from log import info, warn
from model_info import build_entry


def fetch_provider_models(provider, timeout):
    models = fetch_models(provider.base_url, provider.api_key, timeout)
    info(f"[{provider.section}] discovered {len(models)} model(s)")
    return models


def fetch_all_models(providers, timeout):
    """Query all servers at once, so a slow or dead server never delays the others."""
    with ThreadPoolExecutor(max_workers=max(1, len(providers))) as pool:
        return list(pool.map(fetch_provider_models, providers, repeat(timeout)))


def discover_entries(cp, timeout):
    providers = [read_provider(cp, section) for section in cp.sections()]
    model_lists = fetch_all_models(providers, timeout)

    entries = []
    seen = set()
    for provider, models in zip(providers, model_lists):
        for model in models:
            if not isinstance(model, dict):
                continue
            model_id = model.get("id", "")
            if not model_id:
                continue
            name = f"{provider.prefix}{model_id}"
            if name in seen:
                warn(f"duplicate model name {name!r}, keeping first")
                continue
            seen.add(name)
            entries.append(build_entry(provider, name, model_id, model))
    return entries


def main():
    ini_path, disc_path, timeout = sys.argv[1:4]

    cp = configparser.ConfigParser()
    cp.read(ini_path)

    entries = discover_entries(cp, float(timeout))
    with open(disc_path, "w") as f:
        json.dump(entries, f)
    info(f"found {len(entries)} model(s)")


if __name__ == "__main__":
    main()
