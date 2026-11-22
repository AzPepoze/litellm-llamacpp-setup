from __future__ import annotations

import configparser
from dataclasses import dataclass

from log import fail

TRUE_VALUES = ("1", "true", "yes", "on")
FALSE_VALUES = ("0", "false", "no", "off")
NUMBER_PARAMS = (
    ("timeout", float),
    ("stream_timeout", float),
    ("max_retries", int),
    ("tpm", int),
    ("rpm", int),
)


@dataclass(frozen=True)
class Provider:
    section: str
    base_url: str
    api_key: str
    prefix: str
    mode: str | None
    max_input_tokens: int | None
    max_output_tokens: int | None
    vision: bool | None
    function_calling: bool | None
    parallel_function_calling: bool | None
    response_schema: bool | None
    system_messages: bool | None
    input_cost: float
    output_cost: float
    params: dict


def text(cp, section, key):
    return cp.get(section, key, fallback="").strip()


def required(cp, section, key):
    try:
        return cp.get(section, key).strip()
    except configparser.NoOptionError as e:
        fail(f"[{section}] missing option: {e}")


def bool_opt(cp, section, key):
    value = text(cp, section, key).lower()
    if value in TRUE_VALUES:
        return True
    if value in FALSE_VALUES:
        return False
    if value:
        fail(f"[{section}] {key} must be true/false, got {value!r}")
    return None


def num_opt(cp, section, key, numtype):
    value = text(cp, section, key)
    if not value:
        return None
    try:
        return numtype(value)
    except ValueError:
        fail(f"[{section}] {key} must be a number, got {value!r}")


def read_params(cp, section):
    params = {}
    for key, numtype in NUMBER_PARAMS:
        value = num_opt(cp, section, key, numtype)
        if value is not None:
            params[key] = value
    return params


def read_provider(cp, section):
    base_url = required(cp, section, "base_url")
    api_key = required(cp, section, "api_key")
    if not base_url or not api_key:
        fail(f"[{section}] needs base_url and api_key")

    return Provider(
        section=section,
        base_url=base_url,
        api_key=api_key,
        prefix=text(cp, section, "model_prefix"),
        mode=text(cp, section, "mode") or None,
        max_input_tokens=num_opt(cp, section, "max_input_tokens", int),
        max_output_tokens=num_opt(cp, section, "max_output_tokens", int),
        vision=bool_opt(cp, section, "supports_vision"),
        function_calling=bool_opt(cp, section, "supports_function_calling"),
        parallel_function_calling=bool_opt(
            cp, section, "supports_parallel_function_calling"),
        response_schema=bool_opt(cp, section, "supports_response_schema"),
        system_messages=bool_opt(cp, section, "supports_system_messages"),
        input_cost=num_opt(cp, section, "input_cost_per_token", float) or 0.0,
        output_cost=num_opt(cp, section, "output_cost_per_token", float) or 0.0,
        params=read_params(cp, section),
    )
