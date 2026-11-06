#!/usr/bin/env python3
"""Summarize a Catalog Diff JSON report.

    catalog-diff/summary.py REPORT.json          # Markdown, for a pull request comment
    catalog-diff/summary.py --text REPORT.json   # plain text, for a terminal

Nodes that change in the same way are reported together.
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


def changes(data):
    """What changes on a node: added and removed resources, and a diff per changed one."""
    content = data.get("content_differences", {})
    diffs = []
    for resource, lines in data.get("differences_as_diff", {}).items():
        if resource in content:
            body = unified_body(content[resource])
        else:
            body = "\n".join(line.rstrip() for line in lines)
        diffs.append((resource, body))
    return (tuple(data["only_in_new"]), tuple(data["only_in_old"]), tuple(diffs))


def grouped(nodes):
    """Changed nodes grouped by identical changes, in node order."""
    groups = {}
    for name, data in nodes.items():
        if data["node_differences"]:
            groups.setdefault(changes(data), []).append(name)
    return [(names, change) for change, names in groups.items()]


def headline(nodes, failed):
    changed = sum(1 for data in nodes.values() if data["node_differences"])
    lines = [f"{changed} of {len(nodes) + len(failed)} nodes would change."]
    if failed:
        lines.append(f"{len(failed)} failed to compile.")
    return lines


def markdown(nodes, failed):
    out = ["## Catalog diff", ""]
    out += [f"**{line}**" for line in headline(nodes, failed)]
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

    for names, (added, removed, diffs) in grouped(nodes):
        title = ", ".join(f"<code>{name}</code>" for name in names)
        out += [f"<details><summary>{title}</summary>", ""]
        for label, resources in (("Added", added), ("Removed", removed)):
            if resources:
                out += [f"{label}:", ""]
                out += [f"- `{resource}`" for resource in resources]
                out.append("")
        for resource, body in diffs:
            out += [f"Changed: `{resource}`", "", "```diff", body, "```", ""]
        out += ["</details>", ""]

    return out


def text(nodes, failed):
    out = headline(nodes, failed) + [""]

    if nodes:
        width = max(len(name) for name in nodes)
        out.append(f"  {'NODE':<{width}}  CHANGED  ADDED / REMOVED  DIFFERENCES")
        for name, data in nodes.items():
            out.append(
                f"  {name:<{width}}  {data['node_percentage']:>6.1f}%  "
                f"{data['added_and_removed_resources']:<15}  {data['node_differences']}"
            )
        out.append("")

    for name, error in sorted(failed.items()):
        out += [f"{name} failed to compile:", f"  {str(error).strip()}", ""]

    for names, (added, removed, diffs) in grouped(nodes):
        out.append(", ".join(names))
        out += [f"  added    {resource}" for resource in added]
        out += [f"  removed  {resource}" for resource in removed]
        for resource, body in diffs:
            out.append(f"  changed  {resource}")
            out += [f"    {line}" for line in body.expandtabs(2).splitlines()]
        out.append("")

    return out


def main():
    args = sys.argv[1:]
    render = markdown
    if args and args[0] == "--text":
        render = text
        args = args[1:]

    try:
        with open(args[0], encoding="utf-8") as handle:
            report = json.load(handle)
    except (IndexError, OSError, ValueError):
        print("No catalog diff report was produced. See the output above or the job log.")
        return 1

    nodes = node_reports(report)
    failed = report.get("pull_output", {}).get("failed_nodes", {})
    print("\n".join(render(nodes, failed)).rstrip())
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
