"""Print the names of discovered models (dry run).

Usage: list_names.py DISCOVERED_JSON
"""
import json
import sys

with open(sys.argv[1]) as f:
    for entry in json.load(f):
        print(f"  - {entry['name']}")
