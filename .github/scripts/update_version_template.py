#!/usr/bin/env python3
"""Replaces the options list under the 'id: version' dropdown in a GitHub
issue form YAML with a fresh list fetched from GitHub Releases."""

from __future__ import annotations
import json
import sys


def main() -> None:
    releases_path, template_path = sys.argv[1], sys.argv[2]

    with open(releases_path) as f:
        tags: list[str] = json.load(f)

    with open(template_path) as f:
        lines = f.readlines()

    new_lines: list[str] = []
    in_version_block = False
    replaced = False
    i = 0

    while i < len(lines):
        line = lines[i]

        if "    id: version" in line:
            in_version_block = True

        if in_version_block and not replaced and "      options:" in line:
            new_lines.append(line)
            i += 1
            # Skip the existing option lines
            while i < len(lines) and lines[i].startswith("        - "):
                i += 1
            # Write fresh options
            new_lines.append("        - Select a version\n")
            for tag in tags:
                new_lines.append(f"        - {tag}\n")
            replaced = True
            in_version_block = False
            continue

        new_lines.append(line)
        i += 1

    if not replaced:
        print("ERROR: could not find 'id: version' options block", file=sys.stderr)
        sys.exit(1)

    with open(template_path, "w") as f:
        f.writelines(new_lines)

    print(f"Updated with {len(tags)} version(s): {', '.join(tags)}")


if __name__ == "__main__":
    main()
