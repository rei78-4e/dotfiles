#!/usr/bin/env python3
"""Render NixOS / flake dependency graphs as SVG (or DOT/PNG).

Examples:
    ./script/nix-deps-graph.py combined
    ./script/nix-deps-graph.py flake
    ./script/nix-deps-graph.py system --depth 1
    ./script/nix-deps-graph.py system --root helix --depth 2
    ./script/nix-deps-graph.py all -o graph

The system graph is the runtime closure of /run/current-system (or any
store path given with --root).  Arrows point from a component to the
things it depends on, so the root is at the top/left.

"combined" puts the flake input graph, the NixOS build output and the
runtime closure into a single SVG.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
import typing as t
from collections import defaultdict, deque
from pathlib import Path

NIX_STORE = "/nix/store"
STORE_BASENAME_RE = re.compile(r"^[a-z0-9]{32}-(.+)$")
GRAPH_EDGE_RE = re.compile(r'^"([^"]+)"\s*->\s*"([^"]+)"')
GRAPH_NODE_RE = re.compile(r'^"([^"]+)"\s*\[(.*)\]\s*;?$')
GRAPH_LABEL_RE = re.compile(r'label\s*=\s*"((?:[^"\\]|\\.)*)"')


# ---------------------------------------------------------------------------
# small helpers


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def fail(message: str, code: int = 1) -> "t.NoReturn":
    eprint(f"error: {message}")
    raise SystemExit(code)


def package_name(store_basename: str) -> str:
    """'hash-name-version' -> 'name-version' (best effort)."""
    m = STORE_BASENAME_RE.match(store_basename)
    return m.group(1) if m else store_basename


def html_escape(value: str) -> str:
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def dot_escape(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "")
        .replace("\n", "\\n")
    )


def wrap_label(label: str, width: int = 32) -> str:
    """Wrap long store-path names so node boxes stay reasonably narrow."""
    if len(label) <= width:
        return label
    lines: list[str] = []
    for original in label.splitlines():
        if len(original) <= width:
            lines.append(original)
            continue
        lines.extend(
            textwrap.wrap(
                original,
                width=width,
                break_long_words=True,
                break_on_hyphens=True,
                subsequent_indent="  ",
            )
        )
    return "\n".join(lines) or label


def run(cmd: list[str], *, capture: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            cmd,
            check=False,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
        )
    except FileNotFoundError:
        fail(f"command not found: {cmd[0]}")


# ---------------------------------------------------------------------------
# graphviz discovery


def find_dot() -> str | None:
    """Locate graphviz's dot: $DOT, $PATH, the nix store, then nixpkgs."""
    override = os.environ.get("DOT")
    if override:
        if os.access(override, os.X_OK):
            return override
        fail(f"$DOT is not executable: {override}")

    found = shutil.which("dot")
    if found:
        return found

    # Graphviz is frequently already in the store even when it is not on PATH.
    for candidate in sorted(
        glob.glob(os.path.join(NIX_STORE, "*-graphviz-*", "bin", "dot")),
        reverse=True,
    ):
        if os.access(candidate, os.X_OK):
            return candidate

    return None


def build_graphviz() -> str | None:
    eprint("graphviz not found; building it with nix (one time)...")
    proc = run(["nix", "build", "--no-link", "--print-out-paths", "nixpkgs#graphviz"])
    if proc.returncode != 0:
        eprint(proc.stderr.strip())
        return None
    for line in proc.stdout.splitlines():
        dot = os.path.join(line.strip(), "bin", "dot")
        if os.access(dot, os.X_OK):
            return dot
    return None


def render(base: Path, dot_text: str, fmt: str, keep_dot: bool) -> Path:
    if fmt == "dot":
        target = base.with_suffix(".dot")
        target.write_text(dot_text, encoding="utf-8")
        return target

    source = base.with_suffix(".dot")
    if keep_dot:
        source.write_text(dot_text, encoding="utf-8")
    else:
        import tempfile

        tmp = tempfile.NamedTemporaryFile(
            "w", suffix=".dot", prefix="nix-deps-", delete=False, encoding="utf-8"
        )
        tmp.write(dot_text)
        tmp.close()
        source = Path(tmp.name)

    dot = find_dot() or build_graphviz()
    if not dot:
        fallback = base.with_suffix(".dot")
        fallback.write_text(dot_text, encoding="utf-8")
        fail(
            "could not find graphviz.\n"
            f"  DOT was written to {fallback}\n"
            "  render it with: nix run nixpkgs#graphviz -- -Tsvg input.dot -o output.svg"
        )

    target = base.with_suffix(f".{fmt}")
    proc = run([dot, f"-T{fmt}", str(source), "-o", str(target)], capture=True)
    if not keep_dot:
        source.unlink(missing_ok=True)
    if proc.returncode != 0 or not target.exists():
        eprint(proc.stderr.strip())
        fail(f"graphviz failed to render {target}")
    return target


# ---------------------------------------------------------------------------
# flake input graph


def load_flake_lock(flake: str) -> tuple[dict[str, t.Any], str]:
    """Return (lock data, description/name)."""
    path = Path(flake).expanduser()
    if path.is_dir():
        lock_file = path / "flake.lock"
        if not lock_file.exists():
            fail(f"{lock_file} does not exist (is this a flake?)")
        data = json.loads(lock_file.read_text(encoding="utf-8"))
        name = path.resolve().name or "flake"
        flake_nix = path / "flake.nix"
        if flake_nix.exists():
            m = re.search(
                r'description\s*=\s*"((?:[^"\\]|\\.)*)"',
                flake_nix.read_text(encoding="utf-8", errors="replace"),
            )
            if m:
                name = m.group(1)
        return data, name

    proc = run(["nix", "flake", "metadata", "--json", flake])
    if proc.returncode != 0:
        eprint(proc.stderr.strip())
        fail(f"cannot read flake metadata for {flake}")
    data = json.loads(proc.stdout)
    description = data.get("description") or flake.rstrip("/").split("/")[-1]
    return {"nodes": data["locks"]["nodes"], "root": data["locks"]["root"]}, description


def flake_source_label(node: dict[str, t.Any]) -> str:
    locked = node.get("locked") or node.get("original") or {}
    kind = locked.get("type", "")
    if kind == "github":
        base = f"{locked.get('owner', '?')}/{locked.get('repo', '?')}"
    elif kind == "gitlab":
        base = f"gitlab:{locked.get('owner', '?')}/{locked.get('repo', '?')}"
    elif kind == "git":
        url = locked.get("url", "git")
        base = re.sub(r"^(https?|git\+https?)://", "", url).rstrip("/")
        base = re.sub(r"\.git$", "", base)
    elif kind == "path":
        base = locked.get("path", "path").rstrip("/").split("/")[-1] or "path"
    elif kind == "tarball":
        base = locked.get("url", "tarball").rsplit("/", 1)[-1]
    else:
        base = (
            locked.get("url")
            or locked.get("path")
            or locked.get("name")
            or kind
            or "input"
        )
    rev = locked.get("rev") or locked.get("dirtyRev") or ""
    if rev:
        rev = rev[:8]
        return f"{base}\n{rev}"
    return str(base)


def resolve_follows(
    ref: t.Any, nodes: dict[str, t.Any], root: str
) -> str | None:
    """Resolve a flake.lock input value (name or follows path) to a node key."""
    if isinstance(ref, str):
        return ref
    if not isinstance(ref, list):
        return None
    current = root
    for segment in ref:
        node = nodes.get(current, {})
        nxt = (node.get("inputs") or {}).get(segment)
        if nxt is None:
            return None
        if isinstance(nxt, str):
            current = nxt
        else:
            resolved = resolve_follows(nxt, nodes, root)
            if resolved is None:
                return None
            current = resolved
    return current


def flake_is_nixpkgs(node: dict[str, t.Any]) -> bool:
    locked = node.get("locked") or node.get("original") or {}
    return (
        locked.get("type") == "github"
        and str(locked.get("owner", "")).lower() == "nixos"
        and str(locked.get("repo", "")).lower() == "nixpkgs"
    )


def build_flake_model(
    data: dict[str, t.Any], description: str, collapse: bool
) -> dict[str, t.Any]:
    """Build a renderer-independent flake input graph."""
    nodes: dict[str, dict[str, t.Any]] = data.get("nodes", {})
    root = data.get("root", "root")
    if root not in nodes:
        fail(f"flake.lock root node {root!r} is missing")

    # Optionally merge identical locked sources (e.g. four systems/default nodes).
    canonical: dict[str, str] = {root: root}
    members: dict[str, list[str]] = {root: [root]}
    if collapse:
        by_source: dict[str, str] = {}
        for name, node in nodes.items():
            if name == root:
                continue
            source = json.dumps(node.get("locked") or {}, sort_keys=True)
            if not source or source == "{}":
                canonical[name] = name
                members[name] = [name]
                continue
            rep = by_source.get(source)
            if rep is None:
                by_source[source] = name
                canonical[name] = name
                members[name] = [name]
            else:
                canonical[name] = rep
                members[rep].append(name)
    else:
        for name in nodes:
            canonical[name] = name
            members[name] = [name]

    def display(name: str) -> str:
        group = members.get(name, [name])
        label = flake_source_label(nodes[name])
        if len(group) > 1:
            label = f"{label}\n×{len(group)}"
        return label

    adjacency: dict[str, set[str]] = defaultdict(set)
    edge_set: set[tuple[str, str, str, bool]] = set()
    for name, node in nodes.items():
        src = canonical.get(name, name)
        for input_name, ref in (node.get("inputs") or {}).items():
            target = resolve_follows(ref, nodes, root)
            if not target or target not in nodes:
                eprint(f"warning: cannot resolve input {name}.{input_name}")
                continue
            dst = canonical.get(target, target)
            follows = isinstance(ref, list)
            adjacency[src].add(dst)
            label = input_name + ("*" if follows else "")
            edge_set.add((src, dst, label, follows))

    depth: dict[str, int] = {root: 0}
    queue = deque([root])
    while queue:
        cur = queue.popleft()
        for nxt in sorted(adjacency.get(cur, ())):
            if nxt not in depth:
                depth[nxt] = depth[cur] + 1
                queue.append(nxt)
    for name in canonical.values():
        depth.setdefault(name, 99)

    used = {src for src, _, _, _ in edge_set} | {dst for _, dst, _, _ in edge_set} | {root}
    ordered = sorted(used, key=lambda n: (depth[n], display(n).lower()))

    node_info: dict[str, dict[str, t.Any]] = {}
    for name in ordered:
        label = display(name)
        kind = "input"
        if name == root:
            label = f"{description}\n(root)"
            kind = "root"
        elif flake_is_nixpkgs(nodes[name]):
            kind = "nixpkgs"
        node_info[name] = {
            "label": label,
            "depth": depth[name],
            "kind": kind,
            "tooltip": ", ".join(members.get(name, [name])),
        }

    stats = {
        "nodes": len(ordered),
        "edges": len(edge_set),
        "collapsed": sum(len(m) - 1 for m in members.values()),
    }
    return {
        "root": root,
        "description": description,
        "nodes": node_info,
        "edges": sorted(edge_set),
        "stats": stats,
        "canonical": canonical,
        "raw_nodes": nodes,
    }


def flake_dot(data: dict[str, t.Any], description: str, collapse: bool) -> tuple[str, dict]:
    model = build_flake_model(data, description, collapse)
    stats = model["stats"]

    def color(kind: str, depth: int) -> str:
        if kind == "root":
            return "#fecaca"
        if kind == "nixpkgs":
            return "#fef08a"
        return {1: "#bfdbfe", 2: "#c7d2fe"}.get(depth, "#e5e7eb")

    def border(kind: str, depth: int) -> str:
        if kind == "root":
            return "#dc2626"
        if kind == "nixpkgs":
            return "#ca8a04"
        return {1: "#2563eb", 2: "#4f46e5"}.get(depth, "#9ca3af")

    lines = [
        "digraph flake_inputs {",
        '  graph [rankdir=LR, bgcolor="white", pad="0.4", nodesep="0.28",',
        '         ranksep="0.9", splines="spline", overlap="false",',
        '         fontname="Helvetica", fontsize=16, labelloc="t",',
        f'         label="{dot_escape(description)}\\nflake inputs · {stats["nodes"]} nodes · {stats["edges"]} edges (solid = input, dashed* = follows)"];',
        '  node [shape="box", style="rounded,filled", fontname="Helvetica",',
        '        fontsize=10, margin="0.10,0.06", penwidth=1.0];',
        '  edge [color="#64748b", arrowsize=0.65, penwidth=0.8,',
        '        fontname="Helvetica", fontsize=8, fontcolor="#334155"];',
    ]

    ordered = sorted(
        model["nodes"].items(),
        key=lambda kv: (kv[1]["depth"], kv[1]["label"].lower()),
    )
    for name, info in ordered:
        lines.append(
            f'  "{dot_escape(name)}" [label="{dot_escape(info["label"])}", '
            f'fillcolor="{color(info["kind"], info["depth"])}", '
            f'color="{border(info["kind"], info["depth"])}", '
            f'tooltip="{dot_escape(info["tooltip"])}"];'
        )

    for src, dst, label, follows in model["edges"]:
        extra = (
            'style="dashed", color="#94a3b8", constraint="false"'
            if follows
            else 'style="solid"'
        )
        lines.append(
            f'  "{dot_escape(src)}" -> "{dot_escape(dst)}" '
            f'[label="{dot_escape(label)}", {extra}];'
        )

    lines.append("}")
    return "\n".join(lines), stats


# ---------------------------------------------------------------------------
# NixOS / store closure graph


def load_store_graph(root: str) -> tuple[dict[str, str], dict[str, set[str]]]:
    proc = run(["nix-store", "-q", "--graph", root])
    if proc.returncode != 0:
        eprint(proc.stderr.strip())
        fail(f"cannot read the store graph for {root}")

    labels: dict[str, str] = {}
    deps: dict[str, set[str]] = defaultdict(set)
    for raw in proc.stdout.splitlines():
        line = raw.strip()
        edge = GRAPH_EDGE_RE.match(line)
        if edge:
            dependency, dependent = edge.groups()
            deps[dependent].add(dependency)
            labels.setdefault(dependency, package_name(dependency))
            labels.setdefault(dependent, package_name(dependent))
            continue
        node = GRAPH_NODE_RE.match(line)
        if node:
            name, attrs = node.groups()
            label_match = GRAPH_LABEL_RE.search(attrs)
            label = label_match.group(1) if label_match else package_name(name)
            labels[name] = label.replace('\\"', '"').replace("\\\\", "\\")
    return labels, deps


def resolve_root(
    root: str, labels: dict[str, str], deps: dict[str, set[str]] | None = None
) -> str:
    expanded = os.path.expanduser(root)
    if os.path.exists(expanded):
        name = os.path.basename(os.path.realpath(expanded))
        if name in labels:
            return name
        fail(f"{expanded} resolves to {name}, which is not in the store graph")

    # Treat it as a package name/regex and pick the best match.
    try:
        pattern = re.compile(root, re.IGNORECASE)
    except re.error as exc:
        fail(f"invalid --root pattern: {exc}")

    # Prefer the package that is used by the most other paths (glibc -> the
    # glibc the system actually uses, not an old one from some vendored tool).
    refcount: dict[str, int] = defaultdict(int)
    for dependency_set in (deps or {}).values():
        for dependency in dependency_set:
            refcount[dependency] += 1

    def best(candidates: list[str]) -> list[str]:
        return sorted(
            candidates,
            key=lambda n: (-refcount.get(n, 0), len(package_name(n)), n),
        )

    exact = [name for name in labels if package_name(name) == root]
    if exact:
        return best(exact)[0]

    # Prefer packages whose name starts with the query (helix -> helix-term),
    # then fall back to a regex over the whole label.
    prefix = root.lower() + "-"
    matches = [
        name for name in labels if package_name(name).lower().startswith(prefix)
    ]
    if not matches:
        matches = [
            name for name, label in labels.items() if pattern.search(label)
        ]
    matches = best(matches)
    if not matches:
        fail(f"no store path matches {root!r}")
    if len(matches) > 1:
        eprint(
            f"note: {len(matches)} matches for {root!r}; "
            f"using {package_name(matches[0])}"
        )
    return matches[0]


def select_subgraph(
    labels: dict[str, str],
    deps: dict[str, set[str]],
    root: str,
    depth: int,
    include: re.Pattern[str] | None,
    exclude: re.Pattern[str] | None,
    max_nodes: int,
) -> tuple[list[str], dict[str, int], int]:
    level: dict[str, int] = {root: 0}
    queue: deque[str] = deque([root])
    while queue:
        cur = queue.popleft()
        if depth >= 0 and level[cur] >= depth:
            continue
        for dep in sorted(deps.get(cur, ())):
            if dep not in level:
                level[dep] = level[cur] + 1
                queue.append(dep)

    def keep(name: str) -> bool:
        if name == root:
            return True
        label = labels.get(name, package_name(name))
        if include and not include.search(label):
            return False
        if exclude and exclude.search(label):
            return False
        return True

    kept = [name for name in level if keep(name)]
    kept.sort(key=lambda n: (level[n], labels.get(n, package_name(n)).lower()))

    truncated = 0
    if max_nodes > 0 and len(kept) > max_nodes:
        truncated = len(kept) - max_nodes
        kept = kept[:max_nodes]
        eprint(
            f"warning: graph truncated to {max_nodes} nodes "
            f"({truncated} omitted; use --max-nodes or --depth to adjust)"
        )

    return kept, level, truncated


def store_dot(
    labels: dict[str, str],
    deps: dict[str, set[str]],
    kept: list[str],
    level: dict[str, int],
    root: str,
    depth: int,
    rankdir: str,
) -> tuple[str, dict]:
    visible = set(kept)
    root_label = labels.get(root, package_name(root))

    def color(level_: int) -> str:
        return {0: "#fecaca", 1: "#bfdbfe", 2: "#bbf7d0"}.get(level_, "#e5e7eb")

    def border(level_: int) -> str:
        return {0: "#dc2626", 1: "#2563eb", 2: "#16a34a"}.get(level_, "#9ca3af")

    title = f"NixOS runtime dependencies — {root_label}"
    subtitle = (
        f"{len(kept)} paths · depth {depth if depth >= 0 else '∞'} · "
        f"arrows point to dependencies"
    )
    lines = [
        "digraph nixos_system {",
        f'  graph [rankdir={rankdir}, bgcolor="white", pad="0.4", nodesep="0.14",',
        '         ranksep="0.55", splines="spline", overlap="false",',
        '         fontname="Helvetica", fontsize=16, labelloc="t",',
        '         label=<<FONT POINT-SIZE="18"><B>'
        + html_escape(title)
        + '</B></FONT><BR/><FONT POINT-SIZE="10">'
        + html_escape(subtitle)
        + '</FONT><BR/><FONT POINT-SIZE="9">'
        + "blue/indigo = flake inputs · yellow = nixpkgs pin · purple = NixOS output · "
        + "teal/green = runtime paths · dashed = flake follows"
        + "</FONT>>];",
        '  node [shape="box", style="rounded,filled", fontname="Helvetica",',
        '        fontsize=9, margin="0.08,0.04", penwidth=0.8];',
        '  edge [color="#94a3b8", arrowsize=0.55, penwidth=0.65];',
    ]

    for name in kept:
        display = labels.get(name, package_name(name))
        if name == root:
            display = f"{display}\n(root)"
        lines.append(
            f'  "{dot_escape(name)}" [label="{dot_escape(wrap_label(display))}", '
            f'fillcolor="{color(level[name])}", color="{border(level[name])}", '
            f'tooltip="{dot_escape(os.path.join(NIX_STORE, name))}"];'
        )

    edge_count = 0
    for dependent in kept:
        for dependency in sorted(deps.get(dependent, ())):
            if dependency in visible:
                lines.append(
                    f'  "{dot_escape(dependent)}" -> "{dot_escape(dependency)}";'
                )
                edge_count += 1

    lines.append("}")
    return "\n".join(lines), {"nodes": len(kept), "edges": edge_count}


def combined_dot(
    flake_data: dict[str, t.Any],
    description: str,
    hostname: str,
    labels: dict[str, str],
    deps: dict[str, set[str]],
    system_root: str,
    system_depth: int,
    include: re.Pattern[str] | None,
    exclude: re.Pattern[str] | None,
    max_nodes: int,
    collapse: bool,
    rankdir: str,
) -> tuple[str, dict]:
    """One graph: flake inputs -> NixOS output -> runtime closure."""
    fg = build_flake_model(flake_data, description, collapse)
    kept, level, truncated = select_subgraph(
        labels, deps, system_root, system_depth, include, exclude, max_nodes
    )
    visible = set(kept)
    store_id = lambda name: "store:" + name
    output_id = "__nixos_output__"

    def flake_color(kind: str, depth: int) -> tuple[str, str]:
        if kind == "root":
            return "#fecaca", "#dc2626"
        if kind == "nixpkgs":
            return "#fef08a", "#ca8a04"
        return {
            1: ("#bfdbfe", "#2563eb"),
            2: ("#c7d2fe", "#4f46e5"),
        }.get(depth, ("#e5e7eb", "#9ca3af"))

    def runtime_color(name: str, depth: int) -> tuple[str, str]:
        if name == system_root:
            return "#fed7aa", "#ea580c"
        return {
            1: ("#99f6e4", "#0d9488"),
            2: ("#bbf7d0", "#16a34a"),
        }.get(depth, ("#e5e7eb", "#9ca3af"))

    edges: list[tuple[str, str, str, str]] = []
    for src, dst, label, follows in fg["edges"]:
        edges.append((src, dst, label, "follows" if follows else "flake"))

    edges.append((fg["root"], output_id, "flake output", "link"))
    root_inputs = fg["raw_nodes"][fg["root"]].get("inputs") or {}
    for input_name in ("nixpkgs", "home-manager"):
        ref = root_inputs.get(input_name)
        if ref is None:
            continue
        target = resolve_follows(ref, fg["raw_nodes"], fg["root"])
        if not target:
            continue
        dst = fg["canonical"].get(target, target)
        if dst in fg["nodes"]:
            edges.append((dst, output_id, input_name, "link"))
    edges.append(
        (output_id, store_id(system_root), "system.build.toplevel", "link")
    )
    for dependent in kept:
        for dependency in sorted(deps.get(dependent, ())):
            if dependency in visible:
                edges.append(
                    (store_id(dependent), store_id(dependency), "", "runtime")
                )

    title = f"NixOS dependency overview — {hostname}"
    subtitle = (
        f"flake inputs → NixOS output → runtime closure · "
        f"{fg['stats']['nodes']} flake nodes · {len(kept)} runtime paths · "
        f"{len(edges)} edges · {_dt.date.today().isoformat()}"
    )

    lines = [
        "digraph nixos_overview {",
        f"  graph [rankdir={rankdir}, newrank=true, compound=true,",
        '         bgcolor="white", pad="0.5", nodesep="0.18", ranksep="0.8",',
        '         splines="spline", overlap="false", fontname="Helvetica",',
        '         fontsize=16, labelloc="t",',
        '         label=<<FONT POINT-SIZE="18"><B>'
        + html_escape(title)
        + '</B></FONT><BR/><FONT POINT-SIZE="10">'
        + html_escape(subtitle)
        + '</FONT><BR/><FONT POINT-SIZE="9">'
        + "blue/indigo = flake inputs · yellow = nixpkgs pin · purple = NixOS output · "
        + "teal/green = runtime paths · dashed = flake follows"
        + "</FONT>>];",
        '  node [shape="box", style="rounded,filled", fontname="Helvetica",',
        '        fontsize=9, margin="0.08,0.04", penwidth=0.9];',
        '  edge [color="#94a3b8", arrowsize=0.6, penwidth=0.7,',
        '        fontname="Helvetica", fontsize=8, fontcolor="#475569"];',
        "",
        "  subgraph cluster_flake {",
        '    label="flake inputs (flake.lock)";',
        '    labeljust="l"; style="rounded,dashed"; color="#cbd5e1";',
        '    fontsize=12; fontcolor="#475569"; margin=18;',
    ]

    ordered_flake = sorted(
        fg["nodes"].items(),
        key=lambda kv: (kv[1]["depth"], kv[1]["label"].lower()),
    )
    for name, info in ordered_flake:
        fill, stroke = flake_color(info["kind"], info["depth"])
        lines.append(
            f'    "{dot_escape(name)}" [label="{dot_escape(info["label"])}", '
            f'fillcolor="{fill}", color="{stroke}", '
            f'tooltip="{dot_escape(info["tooltip"])}"];'
        )
    lines.append("  }")

    lines.append(
        f'  "{output_id}" [label="NixOS configuration\\n({hostname})", '
        'fillcolor="#e9d5ff", color="#9333ea", fontsize=10, penwidth=1.2];'
    )

    lines.append("")
    lines.append("  subgraph cluster_runtime {")
    lines.append('    label="runtime closure (arrows = references)";')
    lines.append(
        '    labeljust="l"; style="rounded"; color="#cbd5e1";'
    )
    lines.append('    fontsize=12; fontcolor="#475569"; margin=18;')

    for name in kept:
        fill, stroke = runtime_color(name, level[name])
        label = labels.get(name, package_name(name))
        if name == system_root:
            label = f"{label}\\n(running system)"
        lines.append(
            f'    "{dot_escape(store_id(name))}" '
            f'[label="{dot_escape(wrap_label(label))}", '
            f'fillcolor="{fill}", color="{stroke}", '
            f'tooltip="{dot_escape(os.path.join(NIX_STORE, name))}"];'
        )
    lines.append("  }")

    for src, dst, label, kind in edges:
        if kind == "follows":
            style = 'style="dashed", color="#94a3b8", constraint="false"'
        elif kind == "link":
            style = 'style="solid", color="#7c3aed", penwidth=1.2, fontcolor="#6d28d9"'
        elif kind == "flake":
            style = 'style="solid", color="#64748b"'
        else:
            style = 'style="solid", color="#94a3b8", penwidth=0.6'
        label_part = f'label="{dot_escape(label)}", ' if label else ""
        lines.append(
            f'  "{dot_escape(src)}" -> "{dot_escape(dst)}" '
            f"[{label_part}{style}];"
        )

    lines.append("}")
    stats = {
        "nodes": fg["stats"]["nodes"] + 1 + len(kept),
        "edges": len(edges),
        "flakes": fg["stats"]["nodes"],
        "paths": len(kept),
        "truncated": truncated,
    }
    return "\n".join(lines), stats


# ---------------------------------------------------------------------------
# commands


def output_base(target: str | None, default: str) -> Path:
    if not target:
        return Path(default)
    path = Path(target).expanduser()
    if path.suffix.lower() in {".svg", ".png", ".dot"}:
        return path.with_suffix("")
    return path


def cmd_flake(args: argparse.Namespace) -> None:
    data, description = load_flake_lock(args.flake)
    dot_text, stats = flake_dot(data, description, collapse=not args.no_collapse)
    base = output_base(args.output, "flake-inputs")
    base.parent.mkdir(parents=True, exist_ok=True)
    target = render(base, dot_text, args.format, keep_dot=not args.no_dot)
    print(
        f"flake: {stats['nodes']} nodes, {stats['edges']} edges"
        + (f" ({stats['collapsed']} duplicate inputs merged)" if stats["collapsed"] else "")
    )
    print(target)


def load_system_data(root_arg: str) -> tuple[dict[str, str], dict[str, set[str]], str]:
    """Return (labels, dependencies, root node name) for a store path or package."""
    expanded = os.path.expanduser(root_arg)
    if os.path.exists(expanded):
        labels, deps = load_store_graph(expanded)
        return labels, deps, resolve_root(expanded, labels, deps)

    # A package name: search the running system's closure.
    current = "/run/current-system"
    if not os.path.exists(current):
        fail(
            f"{root_arg} is not an existing path and {current} is unavailable.\n"
            "Pass a store path or run this on a NixOS system."
        )
    labels, deps = load_store_graph(current)
    return labels, deps, resolve_root(root_arg, labels, deps)


def compile_filters(
    include: str | None, exclude: str | None
) -> tuple[re.Pattern[str] | None, re.Pattern[str] | None]:
    try:
        return (
            re.compile(include, re.IGNORECASE) if include else None,
            re.compile(exclude, re.IGNORECASE) if exclude else None,
        )
    except re.error as exc:
        fail(f"invalid filter regex: {exc}")


def cmd_system(args: argparse.Namespace) -> None:
    labels, deps, root_name = load_system_data(args.root)
    include, exclude = compile_filters(args.include, args.exclude)

    kept, level, truncated = select_subgraph(
        labels, deps, root_name, args.depth, include, exclude, args.max_nodes
    )
    if not kept:
        fail("nothing matched the filters")

    dot_text, stats = store_dot(
        labels, deps, kept, level, root_name, args.depth, args.rankdir
    )
    base = output_base(args.output, "nixos-system-deps")
    base.parent.mkdir(parents=True, exist_ok=True)
    target = render(base, dot_text, args.format, keep_dot=not args.no_dot)
    print(
        f"system: {stats['nodes']} nodes, {stats['edges']} edges"
        + (f", {truncated} truncated" if truncated else "")
    )
    print(target)


def cmd_combined(args: argparse.Namespace) -> None:
    data, description = load_flake_lock(args.flake)
    labels, deps, root_name = load_system_data(args.root)
    include, exclude = compile_filters(args.include, args.exclude)
    hostname = os.uname().nodename

    dot_text, stats = combined_dot(
        data,
        description,
        hostname,
        labels,
        deps,
        root_name,
        args.depth,
        include,
        exclude,
        args.max_nodes,
        collapse=not args.no_collapse,
        rankdir=args.rankdir,
    )
    if not stats["paths"]:
        fail("nothing matched the filters")

    base = output_base(args.output, "nixos-overview")
    base.parent.mkdir(parents=True, exist_ok=True)
    target = render(base, dot_text, args.format, keep_dot=not args.no_dot)
    print(
        f"overview: {stats['flakes']} flake nodes + {stats['paths']} runtime paths, "
        f"{stats['edges']} edges"
        + (f", {stats['truncated']} truncated" if stats["truncated"] else "")
    )
    print(target)


def cmd_all(args: argparse.Namespace) -> None:
    out_dir = Path(args.output).expanduser() if args.output else Path("graph")
    if out_dir.suffix.lower() in {".svg", ".png", ".dot"}:
        fail("--output for 'all' must be a directory, not a file")
    out_dir.mkdir(parents=True, exist_ok=True)

    flake_args = argparse.Namespace(**vars(args))
    flake_args.output = str(out_dir / "flake-inputs")
    cmd_flake(flake_args)

    system_args = argparse.Namespace(**vars(args))
    system_args.output = str(out_dir / "nixos-system-deps")
    cmd_system(system_args)

    combined_args = argparse.Namespace(**vars(args))
    combined_args.output = str(out_dir / "nixos-overview")
    cmd_combined(combined_args)


def positive_or_unlimited(value: str) -> int:
    try:
        depth = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("depth must be an integer")
    if depth < -1:
        raise argparse.ArgumentTypeError("depth must be >= -1 (-1 = unlimited)")
    return depth


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Render NixOS/flake dependency graphs as SVG (or DOT/PNG).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("-o", "--output", help="output file or directory")
        p.add_argument(
            "--format", choices=("svg", "png", "dot"), default="svg", help="output format"
        )
        p.add_argument("--no-dot", action="store_true", help="do not keep the .dot file")

    def system_options(p: argparse.ArgumentParser) -> None:
        p.add_argument(
            "--root",
            default="/run/current-system",
            help="store path or package name to start from (default: /run/current-system)",
        )
        p.add_argument(
            "-d",
            "--depth",
            type=positive_or_unlimited,
            default=1,
            help="dependency levels below the root (default: 1, -1 = unlimited)",
        )
        p.add_argument("--include", help="only keep packages matching this regex")
        p.add_argument("--exclude", help="drop packages matching this regex")
        p.add_argument(
            "--max-nodes", type=int, default=1000, help="safety limit (default: 1000)"
        )
        p.add_argument(
            "--rankdir",
            choices=("TB", "LR", "BT", "RL"),
            default="LR",
            help="graphviz layout direction (default: LR)",
        )

    def flake_options(p: argparse.ArgumentParser) -> None:
        p.add_argument("--flake", default=".", help="flake directory or URL (default: .)")
        p.add_argument(
            "--no-collapse",
            action="store_true",
            help="keep duplicate locked inputs instead of merging identical sources",
        )

    flake = sub.add_parser("flake", help="graph the flake input lock graph")
    flake_options(flake)
    common(flake)
    flake.set_defaults(func=cmd_flake)

    system = sub.add_parser("system", help="graph the runtime closure of a NixOS system")
    system_options(system)
    common(system)
    system.set_defaults(func=cmd_system)

    combined = sub.add_parser(
        "combined",
        help="one graph: flake inputs + NixOS output + runtime closure",
    )
    flake_options(combined)
    system_options(combined)
    common(combined)
    combined.set_defaults(func=cmd_combined)

    all_cmd = sub.add_parser("all", help="write flake, system and combined graphs")
    flake_options(all_cmd)
    system_options(all_cmd)
    common(all_cmd)
    all_cmd.set_defaults(func=cmd_all)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
