import json
import urllib.error
import urllib.request

REQUEST_TIMEOUT = 15
UNAUTHORIZED = 401


def call(base_url, master_key, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        base_url + path, data=data, method=method,
        headers={"Authorization": f"Bearer {master_key}",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as resp:
        return resp.status, resp.read().decode()


def error_code(error):
    return getattr(error, "code", None)


def is_unauthorized(error):
    return error_code(error) == UNAUTHORIZED


def model_ids(models_json):
    items = json.loads(models_json).get("data", [])
    return {item.get("id") for item in items
            if isinstance(item, dict) and item.get("id")}
