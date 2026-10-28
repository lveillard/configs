#!/usr/bin/env python3
"""Install the adjacent common Pi config into an explicit portable profile."""

import argparse
import copy
import json
import re
import sys
from pathlib import Path


FILES = ("models.json", "settings.json")
SECRET = re.compile(r'sk-[A-Za-z0-9]{16,}|tp-[A-Za-z0-9]{16,}|gho_[A-Za-z0-9]+|"apiKey"\s*:\s*"[^$]')


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def normalized(value):
    value = copy.deepcopy(value)
    value.pop("lastChangelogVersion", None)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--push", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--omit-local-packages", action="store_true",
                        help="Omit filesystem package sources for a remote profile")
    args = parser.parse_args()
    target = args.target.expanduser().resolve()
    source = Path(__file__).resolve().parent
    if target == source:
        parser.error("target must differ from the common config directory")

    # Prepare both files before writing; credentials and Pi-managed files are excluded.
    prepared = {}
    for name in FILES:
        raw = (source / name).read_text(encoding="utf-8-sig")
        if SECRET.search(raw):
            raise ValueError(f"Config source appears to contain a credential: {name}")
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError(f"Expected a JSON object: {name}")
        if name == "settings.json":
            value["sessionDir"] = str(target / "sessions")
            if args.omit_local_packages:
                packages = []
                for package in value.get("packages", []):
                    package_source = package if isinstance(package, str) else package["source"]
                    if package_source.startswith(("npm:", "git:", "https://", "http://", "git@")):
                        packages.append(package)
                value["packages"] = packages
        live_path = target / name
        live = read_json(live_path) if live_path.exists() else None
        value.pop("lastChangelogVersion", None)
        if live is not None and "lastChangelogVersion" in live:
            value["lastChangelogVersion"] = live["lastChangelogVersion"]
        prepared[name] = (value, live)

    drift = False
    if args.push:
        target.mkdir(parents=True, exist_ok=True)
    for name, (value, live) in prepared.items():
        if args.push:
            (target / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
            print(f"[push] {name}")
        else:
            differs = live is None or normalized(value) != normalized(live)
            drift |= differs
            print(f"[{'drift' if differs else 'ok'}] {name}")
    return int(drift)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(2)
