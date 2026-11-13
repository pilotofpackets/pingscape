#!/usr/bin/env python3
"""Summarizes a run of scripts/ui-matrix.sh.

Reads every .xcresult in the output folder and writes:
  report.md         failures and audit findings, grouped, with where they occur
  screenshots/      every screenshot, as <screen>/<device>/<variant>.png
  index.html        the screenshots side by side, one row per screen

Usage: scripts/ui-matrix-report.py build/ui-matrix/<time>
"""
import html
import json
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path


def xcresult(*args):
    out = subprocess.run(["xcrun", "xcresulttool", *args], capture_output=True, text=True)
    return json.loads(out.stdout) if out.returncode == 0 and out.stdout.strip() else None


def safe(name):
    return re.sub(r"[^\w.-]+", "_", name).strip("_")


def walk_failures(nodes, test=None, device=None):
    """Yields (test, device, message) for every failure message in the tree."""
    for node in nodes or []:
        kind = node.get("nodeType")
        name = node.get("name", "")
        here_test = name if kind == "Test Case" else test
        here_device = name if kind == "Device" else device
        if kind == "Failure Message":
            yield here_test, here_device, name
        yield from walk_failures(node.get("children"), here_test, here_device)


def main(out: Path):
    bundles = sorted(out.glob("*.xcresult"))
    if not bundles:
        print(f"No results in {out}")
        return 1

    totals = defaultdict(int)
    failures = defaultdict(set)  # (test, message) -> {(device, variant)}
    audits = {"issue": defaultdict(set), "warning": defaultdict(set)}  # (screen, type, element, issue) -> {(device, variant)}
    shots = defaultdict(dict)  # screen -> {(device, variant): path}
    devices_seen, variants_seen = set(), []

    shots_dir = out / "screenshots"
    for bundle in bundles:
        variant = bundle.stem.split("@")[0]
        if variant not in variants_seen:
            variants_seen.append(variant)
        summary = xcresult("get", "test-results", "summary", "--path", str(bundle), "--compact") or {}
        for key in ("passedTests", "failedTests", "skippedTests"):
            totals[key] += summary.get(key, 0)
        for entry in summary.get("devicesAndConfigurations", []):
            devices_seen.add(entry["device"]["deviceName"])

        tests = xcresult("get", "test-results", "tests", "--path", str(bundle), "--compact") or {}
        single_device = (tests.get("devices") or [{}])[0].get("deviceName") if len(tests.get("devices") or []) == 1 else None
        for test, device, message in walk_failures(tests.get("testNodes")):
            # Audit findings are listed below with their element; here only the rest.
            if message.startswith(("Contrast", "Dynamic Type", "Text clipped", "Hit region", "Element", "Trait", "Label", "Sufficient")):
                continue
            failures[(test or "?", message.split("\n")[0][:400])].add((device or single_device or "?", variant))

        export = out / ".attachments" / bundle.stem
        if export.exists():
            shutil.rmtree(export)
        export.mkdir(parents=True)
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle), "--output-path", str(export)],
            capture_output=True,
        )
        manifest = export / "manifest.json"
        if not manifest.exists():
            continue
        for test in json.loads(manifest.read_text()):
            for attachment in test.get("attachments", []):
                name = re.sub(r"_\d+_[0-9A-F-]{36}\.\w+$", "", attachment["suggestedHumanReadableName"])
                device = attachment.get("deviceName", "?").removeprefix("PS ")
                file = export / attachment["exportedFileName"]
                if name.startswith("Audit ") and file.exists():
                    verdict = name.removeprefix("Audit ")
                    if verdict not in audits:
                        continue
                    fields = dict(
                        line.split(": ", 1) for line in file.read_text().splitlines() if ": " in line
                    )
                    screen = fields.get("Screen", "?").split(", page")[0]
                    key = (screen, fields.get("Type", "?"), fields.get("Element", "?"), fields.get("Issue", "?"))
                    audits[verdict][key].add((device, variant))
                elif file.suffix == ".png" and " · " in name:
                    screen = name.split(" · ", 1)[1]
                    target = shots_dir / safe(screen) / safe(device) / f"{safe(variant)}.png"
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy(file, target)
                    shots[screen][(device, variant)] = target.relative_to(out)
                    devices_seen.add("PS " + device)
    shutil.rmtree(out / ".attachments", ignore_errors=True)

    devices = sorted(d.removeprefix("PS ") for d in devices_seen)

    def where(places):
        by_device = defaultdict(list)
        for device, variant in sorted(places):
            by_device[device.removeprefix("PS ")].append(variant)
        if len(places) >= len(devices) * len(variants_seen) and len(places) > 1:
            return "everywhere"
        return "; ".join(f"{d}: {', '.join(v)}" for d, v in by_device.items())

    lines = [
        f"# UI test matrix {out.name}",
        "",
        f"Devices: {', '.join(devices)}  ",
        f"Variants: {', '.join(variants_seen)}  ",
        f"Tests: {totals['passedTests']} passed, {totals['failedTests']} failed, {totals['skippedTests']} skipped",
        "",
        f"## Failures ({len(failures) - len([k for k in failures if 'execution time allowance' in k[1]])})",
        "",
    ]
    hangs = {key: places for key, places in failures.items() if "execution time allowance" in key[1]}
    for (test, message), places in sorted(failures.items(), key=lambda item: (-len(item[1]), item[0])):
        if (test, message) in hangs:
            continue
        lines.append(f"- **{test}**: {message}  \n  _{where(places)}_")
    if hangs:
        lines += ["", f"## Stopped after 5 minutes ({len(hangs)})", "",
                  "Apple's accessibility audit sometimes never returns (seen on iPhone SE and Pro Max, iOS 26 and 27),",
                  "while the app stays responsive (main thread idle). The rest of that screen was not checked.", ""]
        for (test, message), places in sorted(hangs.items()):
            lines.append(f"- **{test}**  \n  _{where(places)}_")
    found = audits["issue"]
    lines += ["", f"## Accessibility issues, fail the test ({len(found)})", ""]
    by_screen = defaultdict(list)
    for (screen, kind, element, issue), places in found.items():
        by_screen[screen].append((kind, element, issue, places))
    for screen in sorted(by_screen):
        lines.append(f"### {screen}")
        for kind, element, issue, places in sorted(by_screen[screen]):
            lines.append(f"- {kind}: {element} — {issue}  \n  _{where(places)}_")

    # Warnings: one line per screen and kind, with a few of the elements.
    warnings = defaultdict(lambda: defaultdict(set))  # screen -> issue -> {element}
    for (screen, kind, element, issue), places in audits["warning"].items():
        warnings[screen][issue].add(element.split("” ")[0].lstrip("“").rstrip("”"))
    lines += ["", f"## Accessibility warnings ({len(audits['warning'])})", "",
              "Not failures: nearly enough contrast (the system's secondary text color), and the audit's",
              "guesses about text sizes the variant does not use. Look at them in the AX variants' screenshots.", ""]
    for screen in sorted(warnings):
        parts = []
        for issue, elements in sorted(warnings[screen].items()):
            short = [e if len(e) <= 40 else e[:39] + "…" for e in sorted(elements)[:6]]
            sample = ", ".join(short) + (" …" if len(elements) > 6 else "")
            parts.append(f"{issue} ({len(elements)}: {sample})")
        lines.append(f"- **{screen}**: " + "; ".join(parts))
    (out / "report.md").write_text("\n".join(lines) + "\n")

    # Screenshot gallery: one section per screen, devices as rows, variants as columns.
    parts = [
        "<!doctype html><meta charset=utf-8><title>Pingscape screenshots</title>",
        "<style>body{font:14px -apple-system,sans-serif;margin:16px;background:#f2f2f7}"
        "h2{margin-top:32px}table{border-collapse:collapse}td,th{padding:4px;vertical-align:top;text-align:left}"
        "img{width:220px;border:1px solid #ccc;border-radius:8px;background:#fff}"
        ".scroll{overflow-x:auto}@media(prefers-color-scheme:dark){body{background:#000;color:#eee}}</style>",
        f"<h1>Pingscape · {html.escape(out.name)}</h1><p><a href=report.md>report.md</a></p>",
    ]
    for screen in sorted(shots):
        parts.append(f"<h2>{html.escape(screen)}</h2><div class=scroll><table><tr><th></th>")
        parts += [f"<th>{html.escape(v)}</th>" for v in variants_seen]
        parts.append("</tr>")
        for device in devices:
            row = [shots[screen].get((device, v)) for v in variants_seen]
            if not any(row):
                continue
            parts.append(f"<tr><th>{html.escape(device)}</th>")
            for path in row:
                parts.append(f"<td><a href='{path}'><img loading=lazy src='{path}'></a></td>" if path else "<td></td>")
            parts.append("</tr>")
        parts.append("</table></div>")
    (out / "index.html").write_text("".join(parts))

    issues = len(audits["issue"])
    print(
        f"{totals['passedTests']} passed, {totals['failedTests']} failed · {len(failures)} distinct failures, "
        f"{issues} accessibility issues, {len(audits['warning'])} warnings"
    )
    print(f"Report:      {out / 'report.md'}")
    print(f"Screenshots: {out / 'index.html'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]).resolve()))
