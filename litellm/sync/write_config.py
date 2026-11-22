"""Write the gateway config from the template. Run once at container start.

Usage: write_config.py TEMPLATE_YAML CONFIG_OUT
"""
import sys

from log import fail


def read_template(template_path):
    with open(template_path) as f:
        template = f.read()
    # Keep the file model-free: config-listed models cannot be edited in the UI.
    if "model_list: []" not in [line.strip() for line in template.splitlines()]:
        fail("no 'model_list: []' line in template, refusing to guess where models go")
    return template


def main():
    template_path, out_path = sys.argv[1:3]
    template = read_template(template_path)
    with open(out_path, "w") as f:
        f.write(template if template.endswith("\n") else template + "\n")


if __name__ == "__main__":
    main()
