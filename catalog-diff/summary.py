#!/usr/bin/env python3
"""Turn a Catalog Diff JSON report into a Markdown summary.

    catalog-diff/summary.py REPORT.json > summary.md

Exits 1 when the report is missing or any node failed to compile.
"""

import json
import sys


def node_reports(report):
    """Per-node entries sit beside the totals at the top level of the report."""
    return {
        name: data
        for name, data in sorted(report.items())
        if isinstance(data, dict) and "node_percentage" in data
    }


def unified_body(diff):
    """Drop the temp file names Catalog Diff puts in the unified diff header."""
    lines = diff.splitlines()
    return "\n".join(line for line in lines if not line.startswith(("--- ", "+++ ")))


def node_details(name, data):
    out = [f"<details><summary><code>{name}</code></summary>", ""]

    for title, key in (("Added", "only_in_new"), ("Removed", "only_in_old")):
        if data[key]:
            out.append(f"{title}:")
            out.append("")
            out.extend(f"- `{resource}`" for resource in data[key])
            out.append("")

    content = data.get("content_differences", {})
    for resource, lines in data.get("differences_as_diff", {}).items():
        if resource in content:
            body = unified_body(content[resource])
        else:
            body = "\n".join(line.rstrip() for line in lines)
        out += [f"Changed: `{resource}`", "", "```diff", body, "```", ""]

    out += ["</details>", ""]
    return out


def main():
    try:
        with open(sys.argv[1], encoding="utf-8") as handle:
            report = json.load(handle)
    except (IndexError, OSError, ValueError):
        print("## Catalog diff\n\nNo report was produced. See the job log.")
        return 1

    nodes = node_reports(report)
    changed = {name: data for name, data in nodes.items() if data["node_differences"]}
    failed = report.get("pull_output", {}).get("failed_nodes", {})
    total = len(nodes) + len(failed)

    out = ["## Catalog diff", ""]
    out.append(f"**{len(changed)} of {total} nodes would change.**")
    if failed:
        out.append(f"**{len(failed)} failed to compile.**")
    out.append("")

    if nodes:
        out += ["| Node | Catalog changed | Added / removed | Differences |", "|---|---|---|---|"]
        for name, data in nodes.items():
            out.append(
                f"| `{name}` | {data['node_percentage']:.1f}% "
                f"| {data['added_and_removed_resources']} | {data['node_differences']} |"
            )
        out.append("")

    for name, error in sorted(failed.items()):
        out += [f"`{name}` failed to compile:", "", "```text", str(error).strip(), "```", ""]

    for name, data in changed.items():
        out += node_details(name, data)

    print("\n".join(out).rstrip())
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
