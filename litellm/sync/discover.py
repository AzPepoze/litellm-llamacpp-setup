"""Phase 1: find llama.cpp models and write the model-free LiteLLM config.

Usage: discover.py PROVIDERS_INI TEMPLATE_YAML CONFIG_OUT DISCOVERED_JSON TIMEOUT
"""
import configparser
import json
import sys

from ini import read_provider
from llamacpp import fetch_models
from log import fail, info, warn
from model_info import build_entry


def discover_entries(cp, timeout):
    entries = []
    seen = set()
    for section in cp.sections():
        provider = read_provider(cp, section)
        models = fetch_models(provider.base_url, provider.api_key, timeout)
        info(f"[{section}] discovered {len(models)} model(s)")
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


def read_template(template_path):
    with open(template_path) as f:
        template = f.read()
    # Keep the file model-free: config-listed models cannot be edited in the UI.
    if "model_list: []" not in [line.strip() for line in template.splitlines()]:
        fail("no 'model_list: []' line in template, refusing to guess where models go")
    return template


def write_config(template, out_path):
    with open(out_path, "w") as f:
        f.write(template if template.endswith("\n") else template + "\n")


def main():
    ini_path, template_path, out_path, disc_path, timeout = sys.argv[1:6]

    cp = configparser.ConfigParser()
    cp.read(ini_path)

    entries = discover_entries(cp, float(timeout))
    template = read_template(template_path)
    write_config(template, out_path)
    with open(disc_path, "w") as f:
        json.dump(entries, f)
    info(f"discovered {len(entries)} model(s), wrote model-free config")


if __name__ == "__main__":
    main()
