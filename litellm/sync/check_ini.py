"""Fail fast on a malformed providers ini, before the gateway starts. No network calls.

Usage: check_ini.py PROVIDERS_INI
"""
import configparser
import sys

from ini import read_provider


def main():
    cp = configparser.ConfigParser()
    cp.read(sys.argv[1])
    for section in cp.sections():
        read_provider(cp, section)


if __name__ == "__main__":
    main()
