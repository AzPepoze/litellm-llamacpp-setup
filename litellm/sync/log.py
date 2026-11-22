import sys


def info(message):
    print(f"sync-models: {message}", file=sys.stderr)


def warn(message):
    print(f"sync-models: WARNING: {message}", file=sys.stderr)


def error(message):
    print(f"sync-models: ERROR: {message}", file=sys.stderr)


def fail(message):
    sys.exit(f"sync-models: ERROR: {message}")
