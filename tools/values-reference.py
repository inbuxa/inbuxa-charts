#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Coffey Labs LLC
# SPDX-License-Identifier: Apache-2.0
"""The chart's values reference, charts/inbuxa/VALUES.md, from values.yaml
(each value's comment and default) and values.schema.json (its type and
limits). CI checks the committed copy is current:

  tools/values-reference.py            writes it
  tools/values-reference.py --check    fails when it's out of date

Standard library only: values.yaml is read line by line, which is how its
comments are kept, and the chart's values.yaml keeps to the plain block
style this reads (one key per line; lists and maps inline, or as a block
under their key).
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHART = ROOT / "charts" / "inbuxa"
OUT = CHART / "VALUES.md"
KEY = re.compile(r"^(?P<indent> *)(?P<key>[A-Za-z0-9_.\"-]+):(?: (?P<value>.*))?$")


def read_values(text):
    """[(path, comment lines, default or None for a section, block lines)]"""
    entries, stack, comment, current = [], [], [], None
    for raw in text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if stripped.startswith("#"):
            comment.append(re.sub(r"^# ?", "", stripped))
            continue
        if not stripped:
            # A blank line ends a comment that belongs to nothing below it
            comment = [] if comment and not entries else comment
            continue
        m = KEY.match(line)
        if m and not stripped.startswith("- "):
            indent = len(m["indent"])
            while stack and stack[-1][0] >= indent:
                stack.pop()
            key = m["key"].strip('"')
            stack.append((indent, key))
            path = ".".join(k for _, k in stack)
            value = m["value"]
            if value is not None and " #" in value:
                value = value.split(" #", 1)[0].rstrip()
            current = [path, comment, value, []]
            entries.append(current)
            comment = []
        elif current is not None:
            # A list item or a nested line under the last key
            current[3].append(raw)
            comment = []
    return entries


def resolve(schema, root):
    while isinstance(schema, dict):
        if "$ref" in schema:
            schema = dict(walk_ref(root, schema["$ref"]), **{k: v for k, v in schema.items() if k != "$ref"})
            continue
        if "allOf" in schema:
            merged = {k: v for k, v in schema.items() if k != "allOf"}
            for part in schema["allOf"]:
                part = resolve(part, root)
                for k, v in part.items():
                    if k == "properties":
                        merged.setdefault("properties", {})
                        for name, sub in v.items():
                            merged["properties"][name] = (
                                {"allOf": [merged["properties"][name], sub]}
                                if name in merged["properties"] else sub
                            )
                    else:
                        merged.setdefault(k, v)
            schema = merged
            continue
        return schema
    return schema or {}


def walk_ref(root, ref):
    node = root
    for part in ref.lstrip("#/").split("/"):
        node = node[part]
    return node


def schema_at(root, path):
    node = resolve(root, root)
    for key in path.split("."):
        props = node.get("properties", {})
        if key in props:
            node = resolve(props[key], root)
        elif isinstance(node.get("additionalProperties"), dict):
            node = resolve(node["additionalProperties"], root)
        else:
            return {}
    return node


def describe_type(s):
    if "anyOf" in s or "oneOf" in s:
        kinds = []
        for alt in s.get("anyOf", s.get("oneOf")):
            kinds.append(alt.get("type", "object"))
        kind = " or ".join(dict.fromkeys(str(k) for k in kinds))
    else:
        kind = s.get("type", "")
        if not kind and s.get("enum"):
            # An enum alone: the type its values have
            names = {bool: "boolean", int: "integer", float: "number", str: "string"}
            kind = " or ".join(dict.fromkeys(names.get(type(v), "value") for v in s["enum"]))
        if isinstance(kind, list):
            kind = " or ".join(kind)
    if kind == "array" and isinstance(s.get("items"), dict) and s["items"].get("type"):
        kind = f"list of {s['items']['type']}"
    if kind == "object" and isinstance(s.get("additionalProperties"), dict) and not s.get("properties"):
        kind = f"map of {s['additionalProperties'].get('type', 'object')}"
    limits = []
    if "enum" in s:
        limits.append("one of " + ", ".join(f"`{json.dumps(v)}`" for v in s["enum"]))
    for word, key in (("at least", "minimum"), ("more than", "exclusiveMinimum"),
                      ("at most", "maximum")):
        if key in s:
            limits.append(f"{word} {s[key]}")
    for word, key in (("at least", "minLength"), ("at most", "maxLength")):
        if key in s:
            limits.append(f"{word} {s[key]} character" + ("" if s[key] == 1 else "s"))
    if "pattern" in s:
        limits.append(f"matching `{s['pattern']}`")
    return kind, limits


def prose(comment):
    """The comment's prose, and its indented lines (examples) as a block"""
    text, example = [], []
    for line in comment:
        if line.startswith("  ") or (example and line.startswith("-")):
            example.append(line[2:] if line.startswith("  ") else line)
        else:
            text.append(line)
    paragraph = " ".join(t for t in text if t).strip()
    return paragraph, example


def render(entries, root):
    out = [
        "<!-- Generated by tools/values-reference.py from values.yaml and",
        "     values.schema.json. Don't edit it by hand: change those, then run",
        "     the tool. CI fails when this is out of date. -->",
        "",
        "# inbuxa chart values",
        "",
        "Every value the chart takes, with its default and what the values",
        "schema allows. A value the schema doesn't name is refused, as is one",
        "outside these limits, before anything is applied.",
        "",
    ]
    for path, comment, value, block in entries:
        depth = path.count(".")
        s = schema_at(root, path)
        kind, limits = describe_type(s)
        paragraph, example = prose(comment)
        if not paragraph and s.get("description"):
            paragraph = s["description"]
        is_section = (value is None or value == "") and not block and s.get("properties")
        if is_section or (value is None and not block and kind == "object" and s.get("properties")):
            out.append(f"{'#' * min(depth + 2, 4)} `{path}`")
            out.append("")
            if paragraph:
                out += [paragraph, ""]
            if example:
                out += ["```yaml", *example, "```", ""]
            continue
        default = value if value not in (None, "") else None
        out.append(f"- **`{path}`**" + (f" ({kind})" if kind else ""))
        if default is not None:
            out.append(f"  Default: `{default}`.")
        elif block:
            out.append("  Default:")
            out.append("")
            out.append("  ```yaml")
            indent = min(len(b) - len(b.lstrip()) for b in block if b.strip())
            out += ["  " + b[indent:] for b in block if b.strip()]
            out.append("  ```")
        if limits:
            out.append("  Allowed: " + "; ".join(limits) + ".")
        if paragraph:
            out.append("  " + paragraph)
        if example:
            out += ["", "  ```yaml", *["  " + e for e in example], "  ```"]
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main():
    values = (CHART / "values.yaml").read_text()
    schema = json.loads((CHART / "values.schema.json").read_text())
    text = render(read_values(values), schema)
    if "--check" in sys.argv[1:]:
        if not OUT.exists() or OUT.read_text() != text:
            sys.exit(f"{OUT.relative_to(ROOT)} is out of date: run tools/values-reference.py")
        print(f"{OUT.relative_to(ROOT)} is current")
        return
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
