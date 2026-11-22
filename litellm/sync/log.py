import sys
import threading

_lock = threading.Lock()


def _write(line):
    with _lock:
        print(line, file=sys.stderr, flush=True)


def info(message):
    _write(f"sync-models: {message}")


def warn(message):
    _write(f"sync-models: WARNING: {message}")


def error(message):
    _write(f"sync-models: ERROR: {message}")


def fail(message):
    sys.exit(f"sync-models: ERROR: {message}")
