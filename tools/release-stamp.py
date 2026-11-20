#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Coffey Labs LLC
# SPDX-License-Identifier: Apache-2.0
"""Stamps a release into the chart (K-C13): the chart's version, and the
server, webmail and console images it runs, by tag and digest.

    tools/release-stamp.py VERSION DIGESTS.json

VERSION is the chart's (27.1.0-rc.1). DIGESTS.json is what the release
workflow resolved from release/suite.yaml, every image's signature checked:

    {"server":  {"tag": "27.1-rc.34", "digest": "sha256:..."},
     "webmail": {"tag": "27.1-rc.11", "digest": "sha256:..."},
     "console": {"tag": "27.1-rc.23", "digest": "sha256:..."}}

Only the lines it changes are touched, so values.yaml keeps its comments
and the values reference stays as it was. It edits the chart in place: run
it on a checkout made for the release, never on a branch.
"""
import json
import re
import sys
from pathlib import Path

CHART = Path(__file__).resolve().parent.parent / "charts" / "inbuxa"
# The values.yaml section each image's block is under
SECTIONS = {"server": "server", "webmail": "webmail", "console": "console"}
VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(-(rc\.[0-9]+|test\.[0-9]+))?$")
TAG = re.compile(r"^[0-9]{2,4}\.[0-9]+(\.[0-9]+){0,2}(-rc\.[0-9]+)?$")
DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


def fail(msg):
    sys.exit(f"release-stamp: {msg}")


def stamp_chart(text, version, app_version):
    out, n = re.subn(r"(?m)^version: .*$", f"version: {version}", text)
    if n != 1:
        fail("Chart.yaml: no single version: line")
    out, n = re.subn(r'(?m)^appVersion: .*$', f'appVersion: "{app_version}"', out)
    if n != 1:
        fail("Chart.yaml: no single appVersion: line")
    return out


def stamp_values(text, images):
    lines = text.split("\n")
    done = set()
    section = None
    in_image = False
    for i, line in enumerate(lines):
        top = re.match(r"^([A-Za-z]\w*):", line)
        if top:
            section, in_image = top.group(1), False
            continue
        if line == "  image:":
            in_image = True
            continue
        if in_image and not line.startswith("    "):
            in_image = False
        if not in_image:
            continue
        name = next((k for k, s in SECTIONS.items() if s == section), None)
        if name is None:
            continue
        for key in ("tag", "digest"):
            m = re.match(rf'^    {key}: ""$', line)
            if m:
                lines[i] = f'    {key}: "{images[name][key]}"'
                done.add((name, key))
    want = {(n, k) for n in SECTIONS for k in ("tag", "digest")}
    if done != want:
        fail(f"values.yaml: didn't find an empty {sorted(want - done)}")
    return "\n".join(lines)


def main():
    if len(sys.argv) != 3:
        fail("usage: release-stamp.py VERSION DIGESTS.json")
    version, digests = sys.argv[1], sys.argv[2]
    if not VERSION.match(version):
        fail(f"not a chart version: {version}")
    images = json.loads(Path(digests).read_text())
    if set(images) != set(SECTIONS):
        fail(f"{digests}: want exactly {sorted(SECTIONS)}")
    for name, img in images.items():
        if not TAG.match(img.get("tag", "")):
            fail(f"{name}: not a release tag: {img.get('tag')!r}")
        if not DIGEST.match(img.get("digest", "")):
            fail(f"{name}: not a digest: {img.get('digest')!r}")
    # A chart runs its own series' server: chart 27.1.x, server 27.1*
    series = ".".join(version.split("-")[0].split(".")[:2])
    if not version.startswith("0.0.0-test.") and not re.match(
        rf"^{re.escape(series)}([.-]|$)", images["server"]["tag"]
    ):
        fail(f"chart {version} with server {images['server']['tag']}: not the same series")

    chart = CHART / "Chart.yaml"
    chart.write_text(stamp_chart(chart.read_text(), version, images["server"]["tag"]))
    values = CHART / "values.yaml"
    values.write_text(stamp_values(values.read_text(), images))
    for name, img in images.items():
        print(f"{name}: {img['tag']} {img['digest']}")
    print(f"chart {version}, appVersion {images['server']['tag']}")


if __name__ == "__main__":
    main()
