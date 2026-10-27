#!/usr/bin/env python3
"""config-canvas — a local, endless-canvas explorer for a Nix config tree.

Run:

    ./script/config-canvas/server.py

It scans the repository, serves a small single-page app on localhost, opens
it with xdg-open, and exits by itself when the browser tab goes away.

The scanner is intentionally dependency-free.  It understands the nix
expression structure (attrsets, let/with/if/lambda, lists, calls, imports,
strings …) plus JSON/TOML/Markdown, and falls back to a readable outline for
everything else.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import grp
import json
import mimetypes
import os
import pwd
import re
import secrets
import shutil
import signal
import stat as statmod
import struct
import subprocess
import sys
import threading
import time
import traceback
from collections import OrderedDict
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
DEFAULT_ROOT = APP_DIR.parent.parent

# Generated / vendored directories are noise in a configuration atlas.  They
# are reported in the API as skipped instead of being silently forgotten.
SKIP_DIRS = {
    ".git",
    ".direnv",
    "node_modules",
    "__pycache__",
    "eln-cache",
    "org-typst-inline",
    ".cache",
    ".npm",
    ".local",
    "result",
}
SKIP_DIR_NAMES = frozenset(SKIP_DIRS)

IMAGE_EXTS = {"png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "bmp", "ico", "tiff"}
AUDIO_EXTS = {"mp3", "ogg", "wav", "flac", "m4a", "opus"}
VIDEO_EXTS = {"mp4", "webm", "mov", "mkv", "avi"}
ARCHIVE_EXTS = {"zip", "tar", "gz", "xz", "zst", "bz2", "7z", "rar"}
FONT_EXTS = {"ttf", "otf", "woff", "woff2", "eot"}
DOC_EXTS = {"pdf", "djvu", "epub"}
TEXT_EXTS = {
    "",
    "txt",
    "md",
    "markdown",
    "org",
    "nix",
    "json",
    "jsonc",
    "json5",
    "toml",
    "yaml",
    "yml",
    "ini",
    "conf",
    "cfg",
    "config",
    "sh",
    "bash",
    "zsh",
    "fish",
    "py",
    "lua",
    "js",
    "mjs",
    "cjs",
    "ts",
    "tsx",
    "jsx",
    "css",
    "scss",
    "html",
    "xml",
    "svg",
    "dot",
    "el",
    "vim",
    "rasi",
    "theme",
    "lock",
    "desktop",
    "service",
    "env",
    "gitignore",
    "gitconfig",
    "gitattributes",
    "editorconfig",
    "flake",
}
CODE_EXTS = {
    "sh",
    "bash",
    "zsh",
    "fish",
    "py",
    "lua",
    "js",
    "mjs",
    "cjs",
    "ts",
    "tsx",
    "jsx",
    "css",
    "scss",
    "html",
    "xml",
    "el",
    "vim",
    "rasi",
    "go",
    "rs",
    "c",
    "cc",
    "cpp",
    "h",
    "hs",
    "ml",
    "rb",
}
DATA_EXTS = {"json", "jsonc", "json5", "toml", "yaml", "yml", "ini", "conf", "lock"}

MAX_TEXT_BYTES = 1024 * 1024
MAX_PARSE_NODES = 7000
MAX_RAW_BYTES = 32 * 1024 * 1024


# ---------------------------------------------------------------------------
# generic helpers


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr, flush=True)


def iso_time(ts: float) -> str:
    return _dt.datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds")


def human_size(n: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(n)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{n} B"


def clamp_text(value: str, width: int) -> str:
    value = " ".join(value.split())
    return value if len(value) <= width else value[: width - 1] + "…"


def mime_for(path: Path) -> str:
    mime, _ = mimetypes.guess_type(path.name)
    ext = path.suffix.lower().lstrip(".")
    if ext == "nix":
        return "text/plain"
    if ext in {"md", "markdown"}:
        return "text/markdown"
    if ext in {"toml", "ini", "conf"}:
        return "text/plain"
    return mime or "application/octet-stream"


_USER_CACHE: dict[int, str] = {}
_GROUP_CACHE: dict[int, str] = {}


def owner_name(uid: int) -> str:
    if uid not in _USER_CACHE:
        try:
            _USER_CACHE[uid] = pwd.getpwuid(uid).pw_name
        except (KeyError, OSError):
            _USER_CACHE[uid] = str(uid)
    return _USER_CACHE[uid]


def group_name(gid: int) -> str:
    if gid not in _GROUP_CACHE:
        try:
            _GROUP_CACHE[gid] = grp.getgrgid(gid).gr_name
        except (KeyError, OSError):
            _GROUP_CACHE[gid] = str(gid)
    return _GROUP_CACHE[gid]


def stat_details(st: os.stat_result) -> dict:
    return {
        "mode": statmod.filemode(st.st_mode),
        "modeOctal": oct(statmod.S_IMODE(st.st_mode))[2:].zfill(4),
        "owner": owner_name(st.st_uid),
        "group": group_name(st.st_gid),
        "nlink": st.st_nlink,
        "mtime": int(st.st_mtime),
        "modified": iso_time(st.st_mtime),
        "size": st.st_size,
        "sizeLabel": human_size(st.st_size),
    }


def image_size(path: Path) -> tuple[int, int] | None:
    """Best-effort pixel dimensions for the common local image formats."""
    try:
        with path.open("rb") as fh:
            head = fh.read(256 * 1024)
    except OSError:
        return None
    ext = path.suffix.lower()
    try:
        if ext == ".png" and head.startswith(b"\x89PNG\r\n\x1a\n") and len(head) >= 24:
            return struct.unpack(">II", head[16:24])
        if ext in {".gif"} and head[:6] in {b"GIF87a", b"GIF89a"} and len(head) >= 10:
            return struct.unpack("<HH", head[6:10])
        if ext in {".jpg", ".jpeg"} and head.startswith(b"\xff\xd8"):
            i = 2
            while i + 9 < len(head):
                if head[i] != 0xFF:
                    i += 1
                    continue
                marker = head[i + 1]
                if marker in {0xD8, 0xD9}:
                    i += 2
                    continue
                seg_len = struct.unpack(">H", head[i + 2 : i + 4])[0]
                if marker in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}:
                    height, width = struct.unpack(">HH", head[i + 5 : i + 9])
                    return width, height
                i += 2 + seg_len
        if ext == ".svg":
            text = head.decode("utf-8", "replace")[:20000]
            m = re.search(r'viewBox\s*=\s*["\']\s*[-\d.]+\s+[-\d.]+\s+([\d.]+)\s+([\d.]+)', text)
            if m:
                return int(float(m.group(1))), int(float(m.group(2)))
            w = re.search(r'\bwidth\s*=\s*["\']([\d.]+)', text)
            h = re.search(r'\bheight\s*=\s*["\']([\d.]+)', text)
            if w and h:
                return int(float(w.group(1))), int(float(h.group(1)))
    except (OSError, struct.error, ValueError):
        return None
    return None


def read_text(path: Path, limit: int = MAX_TEXT_BYTES) -> str | None:
    try:
        if path.stat().st_size > limit:
            return None
        raw = path.read_bytes()
    except OSError:
        return None
    if b"\x00" in raw[:4096]:
        return None
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        try:
            return raw.decode("utf-8", "replace")
        except Exception:
            return None


def looks_text(path: Path) -> bool:
    ext = path.suffix.lower().lstrip(".")
    if ext in TEXT_EXTS:
        return True
    if ext in IMAGE_EXTS | AUDIO_EXTS | VIDEO_EXTS | ARCHIVE_EXTS | FONT_EXTS | DOC_EXTS:
        return False
    try:
        with path.open("rb") as fh:
            sample = fh.read(4096)
    except OSError:
        return False
    if not sample or b"\x00" in sample:
        return False
    try:
        sample.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def file_kind(path: Path, text: bool) -> str:
    ext = path.suffix.lower().lstrip(".")
    if ext in IMAGE_EXTS:
        return "image"
    if ext in AUDIO_EXTS:
        return "audio"
    if ext in VIDEO_EXTS:
        return "video"
    if ext in ARCHIVE_EXTS:
        return "archive"
    if ext in FONT_EXTS:
        return "font"
    if ext in DOC_EXTS:
        return "document"
    if ext == "nix" or path.name == "flake.lock":
        return "nix"
    if ext in CODE_EXTS:
        return "code"
    if ext in DATA_EXTS or path.name in {
        ".gitignore",
        ".gitconfig",
        ".editorconfig",
        ".envrc",
    }:
        return "config"
    if text:
        return "text"
    return "binary"


def safe_rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


# ---------------------------------------------------------------------------
# filesystem scan


class ScanError(Exception):
    pass


def resolve_inside(root: Path, rel: str) -> Path:
    """Resolve a user supplied relative path while staying inside root."""
    if "\x00" in rel:
        raise ScanError("invalid path")
    candidate = (root / rel).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ScanError("path escapes the scanned root") from exc
    return candidate


def scan_filesystem(root: Path) -> dict:
    started = time.perf_counter()
    root = root.resolve()
    nodes: list[dict] = []
    edges: list[dict] = []
    files: list[dict] = []
    skipped: list[dict] = []
    dir_count = 0
    file_count = 0
    total_bytes = 0
    text_count = 0
    image_count = 0
    binary_count = 0
    link_count = 0
    seq = 0

    def new_id(prefix: str) -> str:
        nonlocal seq
        seq += 1
        return f"{prefix}{seq}"

    def add_node(
        path: Path,
        parent: str | None,
        node_type: str,
        depth: int,
    ) -> str:
        nonlocal dir_count, file_count, total_bytes, text_count, image_count, binary_count, link_count
        rel = safe_rel(path, root) if path != root else "."
        nid = new_id("fs")
        node: dict = {
            "id": nid,
            "parent": parent,
            "path": rel,
            "name": path.name if path != root else path.name or str(path),
            "type": node_type,
            "depth": depth,
        }
        try:
            st = path.lstat()
        except OSError:
            st = None
        if st is not None:
            node.update(stat_details(st))
        if node_type == "dir":
            dir_count += 1
            node["kind"] = "dir"
            node["childCount"] = 0
            node["fileCount"] = 0
            node["descFiles"] = 0
            node["descDirs"] = 0
            node["descBytes"] = 0
        else:
            file_count += 1
            size = st.st_size if st else 0
            total_bytes += size
            ext = path.suffix.lower().lstrip(".")
            text = looks_text(path)
            kind = file_kind(path, text)
            node.update(
                {
                    "kind": kind,
                    "ext": ext,
                    "size": size,
                    "sizeLabel": human_size(size),
                    "mtime": int(st.st_mtime) if st else 0,
                    "modified": iso_time(st.st_mtime) if st else "",
                    "text": text,
                    "mime": mime_for(path),
                    "image": ext in IMAGE_EXTS,
                }
            )
            if st is not None:
                node["mtime"] = int(st.st_mtime)
                node["modified"] = iso_time(st.st_mtime)
            node["structured"] = ext in {"nix", "json", "jsonc", "toml", "md", "markdown"}
            if text and ext not in IMAGE_EXTS:
                text_count += 1
                if size <= MAX_TEXT_BYTES:
                    body = read_text(path)
                    if body is not None:
                        node["lines"] = body.count("\n") + (0 if body.endswith("\n") else 1) if body else 0
                        node["chars"] = len(body)
                        node["words"] = len(body.split())
            if ext in IMAGE_EXTS:
                image_count += 1
                dims = image_size(path)
                if dims:
                    node["width"], node["height"] = dims
            elif not text and kind not in {"audio", "video", "font", "document"}:
                binary_count += 1
            if node_type == "symlink":
                link_count += 1
                try:
                    node["target"] = os.readlink(path)
                    node["text"] = False
                    node["structured"] = False
                    node["kind"] = "symlink"
                    try:
                        real = path.stat()
                        node["targetSize"] = real.st_size
                        node["targetSizeLabel"] = human_size(real.st_size)
                    except OSError:
                        pass
                except OSError:
                    node["target"] = ""
            files.append(node)
        nodes.append(node)
        if parent:
            edges.append({"id": f"e{len(edges) + 1}", "source": parent, "target": nid, "kind": "tree"})
        return nid

    def walk(directory: Path, parent: str | None, depth: int) -> None:
        try:
            entries = list(directory.iterdir())
        except OSError as exc:
            skipped.append({"path": safe_rel(directory, root), "reason": str(exc)})
            return
        entries.sort(key=lambda p: (p.is_symlink(), not p.is_dir(), p.name.lower()))
        for entry in entries:
            try:
                is_link = entry.is_symlink()
            except OSError:
                is_link = False
            if is_link:
                nid = add_node(entry, parent, "symlink", depth)
                # A symlink is shown as a leaf; following it would duplicate
                # whole trees (this repo has `config -> .config`).
                if parent:
                    parent_node = next((n for n in nodes if n["id"] == parent), None)
                    if parent_node and parent_node["type"] == "dir":
                        parent_node["childCount"] += 1
                continue
            try:
                is_dir = entry.is_dir()
            except OSError:
                is_dir = False
            if is_dir:
                if entry.name in SKIP_DIR_NAMES or entry.name.endswith(".egg-info"):
                    try:
                        n_files = sum(1 for p in entry.rglob("*") if p.is_file())
                    except OSError:
                        n_files = -1
                    skipped.append(
                        {
                            "path": safe_rel(entry, root),
                            "reason": "generated / vendored directory",
                            "files": n_files,
                        }
                    )
                    continue
                nid = add_node(entry, parent, "dir", depth)
                if parent:
                    # childCount is incremented below via the directory's walk
                    pass
                walk(entry, nid, depth + 1)
                node = next(n for n in nodes if n["id"] == nid)
                node["childCount"] = sum(1 for n in nodes if n.get("parent") == nid)
                node["fileCount"] = sum(
                    1
                    for n in nodes
                    if n.get("parent") == nid and n["type"] != "dir"
                )
                node["descFiles"] = 0
                if parent:
                    parent_node = next((n for n in nodes if n["id"] == parent), None)
                    if parent_node and parent_node["type"] == "dir":
                        parent_node["childCount"] += 1
                continue
            nid = add_node(entry, parent, "file", depth)
            if parent:
                parent_node = next((n for n in nodes if n["id"] == parent), None)
                if parent_node and parent_node["type"] == "dir":
                    parent_node["childCount"] += 1

    # Root itself is a node so the graph has an anchor.
    root_id = new_id("fs")
    root_node = {
        "id": root_id,
        "parent": None,
        "path": ".",
        "name": root.name or str(root),
        "type": "dir",
        "depth": 0,
        "kind": "dir",
        "childCount": 0,
        "fileCount": 0,
        "descFiles": 0,
        "descDirs": 0,
        "descBytes": 0,
    }
    try:
        root_node.update(stat_details(root.stat()))
    except OSError:
        pass
    nodes.append(root_node)
    dir_count += 1
    walk(root, root_id, 1)

    root_node = nodes[0]
    root_node["childCount"] = sum(1 for n in nodes if n.get("parent") == root_id)
    root_node["fileCount"] = sum(1 for n in nodes if n.get("parent") == root_id and n["type"] != "dir")

    # descendant file counts, computed bottom-up
    children_by_parent: dict[str, list[dict]] = {}
    for node in nodes:
        if node.get("parent"):
            children_by_parent.setdefault(node["parent"], []).append(node)
    order = sorted(nodes, key=lambda n: n["depth"], reverse=True)
    for node in order:
        if node["type"] == "dir":
            total_files = 0
            total_dirs = 0
            total_size = 0
            for child in children_by_parent.get(node["id"], []):
                if child["type"] == "dir":
                    total_files += child.get("descFiles", 0)
                    total_dirs += 1 + child.get("descDirs", 0)
                    total_size += child.get("descBytes", 0)
                else:
                    total_files += 1
                    total_size += child.get("size", 0)
            node["descFiles"] = total_files
            node["descDirs"] = total_dirs
            node["descBytes"] = total_size
            node["descBytesLabel"] = human_size(total_size)

    # The two importable, structured languages are surfaced in the UI.
    content_files = [
        {
            "id": n["id"],
            "path": n["path"],
            "name": n["name"],
            "kind": n["kind"],
            "ext": n.get("ext", ""),
            "size": n.get("size", 0),
            "sizeLabel": n.get("sizeLabel", ""),
            "lines": n.get("lines"),
            "structured": n.get("structured", False),
        }
        for n in files
        if n.get("text") and n.get("size", 0) <= MAX_TEXT_BYTES
    ]
    content_files.sort(key=lambda f: (not f["structured"], f["path"].lower()))

    flow = build_flow(root, files)

    elapsed = (time.perf_counter() - started) * 1000
    return {
        "root": str(root),
        "rootName": root.name or str(root),
        "generatedAt": iso_time(time.time()),
        "scanMs": round(elapsed, 1),
        "nodes": nodes,
        "edges": edges,
        "files": content_files,
        "flow": flow,
        "stats": {
            "dirs": dir_count,
            "files": file_count,
            "nodes": len(nodes),
            "edges": len(edges),
            "bytes": total_bytes,
            "bytesLabel": human_size(total_bytes),
            "textFiles": text_count,
            "imageFiles": image_count,
            "binaryFiles": binary_count,
            "symlinks": link_count,
            "skipped": skipped,
            "skippedFiles": sum(s.get("files", 0) for s in skipped),
        },
    }


# ---------------------------------------------------------------------------
# tiny nix structural parser
#
# This is not an evaluator.  It tokenizes enough of the language to recover a
# useful shape: bindings, nested attrsets, lists, lambdas, let/with/if, calls,
# imports.  Anything it cannot parse degrades into a line outline.


class NixError(Exception):
    pass


@dataclass
class Tok:
    kind: str
    value: str
    line: int


IDENT_START = re.compile(r"[A-Za-z_]")
IDENT_CHAR = re.compile(r"[A-Za-z0-9_'\-]")
MULTI_OPS = ("...", "==", "!=", "<=", ">=", "&&", "||", "->", "//", "++", "${")
KEYWORDS = {
    "let",
    "in",
    "with",
    "if",
    "then",
    "else",
    "assert",
    "rec",
    "inherit",
    "or",
    "true",
    "false",
    "null",
}
PATH_CHARS = re.compile(r"[A-Za-z0-9._+\-/~]")


def tokenize_nix(src: str) -> list[Tok]:
    tokens: list[Tok] = []
    i = 0
    line = 1
    n = len(src)
    while i < n:
        c = src[i]
        if c in " \t\r":
            i += 1
            continue
        if c == "\n":
            line += 1
            i += 1
            continue
        if c == "#":
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            if j < 0:
                break
            line += src.count("\n", i, j + 2)
            i = j + 2
            continue
        if src.startswith("''", i):
            start_line = line
            j = i + 2
            while j < n:
                if src.startswith("'''", j) or src.startswith("''$", j) or src.startswith("''\\", j):
                    j += 3
                    continue
                if src.startswith("''", j):
                    j += 2
                    break
                if src[j] == "\n":
                    line += 1
                j += 1
            tokens.append(Tok("istr", src[i:j], start_line))
            i = j
            continue
        if c == '"':
            start_line = line
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == '"':
                    j += 1
                    break
                if src[j] == "\n":
                    line += 1
                j += 1
            tokens.append(Tok("str", src[i:j], start_line))
            i = j
            continue
        if src.startswith("...", i):
            tokens.append(Tok("op", "...", line))
            i += 3
            continue
        if c == "$" and i + 1 < n and src[i + 1] == "{":
            tokens.append(Tok("op", "${", line))
            i += 2
            continue
        if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()):
            j = i
            while j < n and (src[j].isalnum() or src[j] in "._"):
                j += 1
            tokens.append(Tok("num", src[i:j], line))
            i = j
            continue
        if IDENT_START.match(c):
            j = i + 1
            while j < n and IDENT_CHAR.match(src[j]):
                j += 1
            word = src[i:j]
            if src.startswith("://", j):
                k = j + 3
                while k < n and src[k] not in " \t\r\n;,)]}":
                    k += 1
                tokens.append(Tok("uri", src[i:k], line))
                i = k
                continue
            tokens.append(Tok("id", word, line))
            i = j
            continue
        if (
            src.startswith("./", i)
            or src.startswith("../", i)
            or (c == "/" and i + 1 < n and src[i + 1] not in " \t\r\n*/")
            or (c == "~" and src.startswith("~/", i))
        ):
            j = i
            while j < n and PATH_CHARS.match(src[j]):
                j += 1
            if j > i:
                tokens.append(Tok("path", src[i:j], line))
                i = j
                continue
        if c == "<":
            j = src.find(">", i + 1)
            if j > i and "\n" not in src[i:j]:
                tokens.append(Tok("path", src[i : j + 1], line))
                i = j + 1
                continue
        matched = False
        for op in MULTI_OPS:
            if src.startswith(op, i):
                tokens.append(Tok("op", op, line))
                i += len(op)
                matched = True
                break
        if matched:
            continue
        if c in "{}[]();,:.@?=+-*/!<>|&$":
            tokens.append(Tok("op", c, line))
            i += 1
            continue
        # An unknown character is kept as an operator so the parser can
        # recover without losing its place.
        tokens.append(Tok("op", c, line))
        i += 1
    tokens.append(Tok("eof", "", line))
    return tokens


class NixParser:
    PRECEDENCE = {
        "->": (1, "right"),
        "||": (2, "left"),
        "&&": (3, "left"),
        "==": (4, "left"),
        "!=": (4, "left"),
        "<": (5, "left"),
        ">": (5, "left"),
        "<=": (5, "left"),
        ">=": (5, "left"),
        "//": (6, "right"),
        "++": (7, "right"),
        "+": (8, "left"),
        "-": (8, "left"),
        "*": (9, "left"),
        "/": (9, "left"),
    }

    def __init__(self, src: str, path: str):
        self.src = src
        self.path = path
        self.tokens = tokenize_nix(src)
        self.i = 0
        self.count = 0
        self.limit_hit = False

    # -- token helpers ------------------------------------------------------
    def peek(self, offset: int = 0) -> Tok:
        return self.tokens[min(self.i + offset, len(self.tokens) - 1)]

    def at(self, value: str) -> bool:
        tok = self.peek()
        return tok.value == value and tok.kind in {"op", "id"}

    def at_kind(self, kind: str) -> bool:
        return self.peek().kind == kind

    def eat(self, value: str) -> bool:
        if self.at(value):
            self.i += 1
            return True
        return False

    def take(self) -> Tok:
        tok = self.peek()
        if tok.kind != "eof":
            self.i += 1
        return tok

    def expect(self, value: str) -> Tok:
        if not self.at(value):
            tok = self.peek()
            raise NixError(f"expected {value!r} at line {tok.line}, got {tok.value!r}")
        return self.take()

    def node(
        self,
        kind: str,
        label: str,
        line: int,
        *,
        detail: str = "",
        children: list[dict] | None = None,
        **extra: object,
    ) -> dict:
        self.count += 1
        if self.count > MAX_PARSE_NODES:
            self.limit_hit = True
            return {
                "kind": "truncated",
                "label": "… output truncated",
                "line": line,
                "detail": "node limit reached",
                "children": [],
            }
        node = {
            "kind": kind,
            "label": label,
            "line": line,
            "detail": detail,
            "children": children or [],
        }
        node.update(extra)
        return node

    # -- grammar ------------------------------------------------------------
    def parse(self) -> dict:
        root = self.expr()
        return root

    def expr(self) -> dict:
        if self.at("let"):
            return self.let_expr()
        if self.at("with"):
            return self.with_expr()
        if self.at("if"):
            return self.if_expr()
        if self.at("assert"):
            return self.assert_expr()
        if self.at("rec") and self.peek(1).value == "{":
            line = self.take().line
            return self.attrset(line, rec=True)
        if self.is_lambda():
            return self.lambda_expr()
        return self.binary(0, allow_app=True)

    def is_lambda(self) -> bool:
        tok = self.peek()
        if tok.kind == "id" and self.peek(1).value == ":":
            return True
        if tok.kind == "id" and self.peek(1).value == "@":
            return True
        if tok.value == "{":
            close = self.match_brace(self.i)
            if close is not None:
                nxt = self.tokens[min(close + 1, len(self.tokens) - 1)]
                return nxt.value in {":", "@"}
        return False

    def match_brace(self, start: int) -> int | None:
        depth = 0
        for idx in range(start, len(self.tokens)):
            value = self.tokens[idx].value
            if value == "{":
                depth += 1
            elif value == "}":
                depth -= 1
                if depth == 0:
                    return idx
        return None

    def lambda_expr(self) -> dict:
        line = self.peek().line
        params: list[str] = []
        if self.peek().kind == "id" and self.peek(1).value == "@":
            params.append(self.take().value)
            self.expect("@")
            if self.at("{"):
                params.extend(self.parse_formals())
            if self.at(":"):
                self.take()
        elif self.peek().kind == "id":
            params.append(self.take().value)
            self.expect(":")
        elif self.at("{"):
            params.extend(self.parse_formals())
            if self.at("@"):
                self.take()
                if self.peek().kind == "id":
                    params.append(self.take().value)
            self.expect(":")
        else:
            raise NixError(f"bad lambda at line {line}")
        body = self.expr()
        label = "λ " + (", ".join(params[:6]) if params else "arguments")
        if len(params) > 6:
            label += ", …"
        return self.node("lambda", clamp_text(label, 80), line, detail="function", children=[body])

    def parse_formals(self) -> list[str]:
        self.expect("{")
        params: list[str] = []
        depth = 1
        while self.peek().kind != "eof" and depth:
            tok = self.take()
            if tok.value == "{":
                depth += 1
            elif tok.value == "}":
                depth -= 1
                if depth == 0:
                    break
            elif depth == 1:
                if tok.kind == "id" and tok.value not in {"true", "false", "null"}:
                    # `name ? default` — keep names, ignore defaults.
                    if self.peek().value != "?":
                        params.append(tok.value)
                elif tok.value == "...":
                    params.append("...")
        return params

    def let_expr(self) -> dict:
        line = self.take().line
        children: list[dict] = []
        while not self.at("in") and self.peek().kind != "eof":
            if self.eat(";"):
                continue
            children.append(self.binding())
        self.expect("in")
        body = self.expr()
        if body["kind"] != "root":
            body["role"] = "body"
        children.append(body)
        return self.node(
            "let",
            f"let … in  ({len(children) - 1} bindings)",
            line,
            detail="scoped bindings",
            children=children,
        )

    def with_expr(self) -> dict:
        line = self.take().line
        scope = self.expr()
        self.expect(";")
        body = self.expr()
        return self.node("with", "with … ;", line, detail="scope", children=[scope, body])

    def if_expr(self) -> dict:
        line = self.take().line
        cond = self.expr()
        self.expect("then")
        yes = self.expr()
        self.expect("else")
        no = self.expr()
        return self.node("if", "if … then … else …", line, children=[cond, yes, no])

    def assert_expr(self) -> dict:
        line = self.take().line
        cond = self.expr()
        self.expect(";")
        body = self.expr()
        return self.node("assert", "assert … ;", line, children=[cond, body])

    def binary(self, min_prec: int, allow_app: bool) -> dict:
        left = self.unary(allow_app)
        while True:
            op = self.peek().value
            if op not in self.PRECEDENCE:
                break
            prec, assoc = self.PRECEDENCE[op]
            if prec < min_prec:
                break
            tok = self.take()
            next_min = prec if assoc == "right" else prec + 1
            right = self.binary(next_min, allow_app)
            label = f"{op} expression"
            children = [left, right]
            if not any(c.get("children") for c in children) and len(left["label"]) + len(right["label"]) < 54:
                label = f"{left['label']} {op} {right['label']}"
                children = []
            else:
                label = f"{op}  ·  {clamp_text(left['label'], 28)} → {clamp_text(right['label'], 28)}"
            left = self.node("op", label, tok.line, detail=f"operator {op}", children=children)
        return left

    def unary(self, allow_app: bool) -> dict:
        if self.at("!") or self.at("-"):
            tok = self.take()
            operand = self.unary(allow_app)
            return self.node(
                "op",
                f"{tok.value} {clamp_text(operand['label'], 44)}",
                tok.line,
                detail="unary",
                children=[operand],
            )
        if allow_app:
            return self.application()
        return self.select()

    def application(self) -> dict:
        head = self.select()
        args: list[dict] = []
        while self.starts_simple():
            args.append(self.select())
        if not args:
            return head
        # `import ./file.nix` is worth marking explicitly.
        if head.get("label") == "import" and len(args) >= 1:
            target = args[0].get("ref") or args[0].get("label", "")
            return self.node(
                "import",
                f"import {clamp_text(target, 54)}",
                head["line"],
                detail="import",
                ref=target,
                children=args[1:],
            )
        children = [head, *args]
        if not any(c.get("children") for c in children) and len(children) <= 5:
            joined = ", ".join(clamp_text(c["label"], 24) for c in children[1:])
            label = f"{clamp_text(head['label'], 34)}({joined})"
            return self.node("call", clamp_text(label, 88), head["line"], detail="call", children=[])
        return self.node(
            "call",
            f"call {clamp_text(head['label'], 46)}",
            head["line"],
            detail=f"{len(args)} argument{'s' if len(args) != 1 else ''}",
            children=children,
        )

    def starts_simple(self) -> bool:
        tok = self.peek()
        if tok.kind in {"str", "istr", "path", "uri", "num"}:
            return True
        if tok.kind == "id":
            return tok.value not in {"in", "then", "else", "or", "inherit"}
        if tok.value in {"(", "{", "["}:
            return True
        if tok.value == "rec" and self.peek(1).value == "{":
            return True
        return False

    def select(self) -> dict:
        base = self.simple()
        parts: list[str] = []
        while self.at("."):
            self.take()
            segment = self.attr_segment()
            parts.append(segment)
            if self.at("or"):
                self.take()
                default = self.expr()
                base = self.node(
                    "select",
                    f"{clamp_text(base['label'], 40)}.{'.'.join(parts)} or …",
                    base["line"],
                    detail="selection with default",
                    children=[base, default],
                )
                return base
        if not parts:
            return base
        label = f"{clamp_text(base['label'], 34)}.{'.'.join(parts)}"
        if base.get("children"):
            return self.node("select", clamp_text(label, 90), base["line"], detail="attribute path", children=[base])
        return self.node("select", clamp_text(label, 90), base["line"], detail="attribute path")

    def attr_segment(self) -> str:
        tok = self.peek()
        if tok.kind in {"id", "num", "str", "istr"}:
            self.take()
            return tok.value
        if tok.value == "${":
            out = ["${"]
            self.take()
            depth = 1
            while self.peek().kind != "eof" and depth:
                t = self.take()
                out.append(t.value)
                if t.value == "{":
                    depth += 1
                elif t.value == "}":
                    depth -= 1
            return "".join(out)
        self.take()
        return tok.value

    def simple(self) -> dict:
        tok = self.peek()
        if tok.value == "(":
            line = self.take().line
            inner = self.expr()
            self.expect(")")
            inner.setdefault("line", line)
            return inner
        if tok.value == "{":
            return self.attrset(tok.line, rec=False)
        if tok.value == "[":
            return self.list_expr()
        if tok.value == "rec" and self.peek(1).value == "{":
            line = self.take().line
            return self.attrset(line, rec=True)
        if tok.kind == "path":
            self.take()
            return self.node("path", clamp_text(tok.value, 90), tok.line, detail="path", ref=tok.value)
        if tok.kind == "uri":
            self.take()
            return self.node("uri", clamp_text(tok.value, 90), tok.line, detail="url", ref=tok.value)
        if tok.kind == "str":
            self.take()
            text = tok.value
            interpolations = text.count("${")
            inner = text[1:-1] if text.startswith('"') and text.endswith('"') else text
            return self.node(
                "string",
                clamp_text(text, 88),
                tok.line,
                detail=f"string · {len(inner)} chars" + (f" · {interpolations} interpolation(s)" if interpolations else ""),
                value=clamp_text(inner, 240),
            )
        if tok.kind == "istr":
            self.take()
            text = tok.value
            inner = text[2:-2] if text.startswith("''") else text
            return self.node(
                "string",
                "'' " + clamp_text(inner.replace("\n", " ⏎ "), 74) + " ''",
                tok.line,
                detail=f"indented string · {len(inner)} chars",
                value=clamp_text(inner, 240),
            )
        if tok.kind == "num":
            self.take()
            return self.node("literal", tok.value, tok.line, detail="number")
        if tok.kind == "id":
            self.take()
            kind = "literal" if tok.value in {"true", "false", "null"} else "ident"
            return self.node(kind, tok.value, tok.line, detail="keyword" if kind == "literal" else "identifier")
        raise NixError(f"unexpected token {tok.value!r} at line {tok.line}")

    def list_expr(self) -> dict:
        line = self.take().line
        items: list[dict] = []
        while not self.at("]") and self.peek().kind != "eof":
            items.append(self.binary(0, allow_app=False))
            # tolerate a stray separator
            self.eat(",")
        self.expect("]")
        return self.node(
            "list",
            f"[ {len(items)} item{'s' if len(items) != 1 else ''} ]",
            line,
            detail="list",
            children=items,
        )

    def attrset(self, line: int, rec: bool) -> dict:
        self.expect("{")
        children: list[dict] = []
        while not self.at("}") and self.peek().kind != "eof":
            if self.eat(";"):
                continue
            if self.at("inherit"):
                children.append(self.inherit_binding())
                continue
            children.append(self.binding())
            self.eat(";")
        self.expect("}")
        label = ("rec { " if rec else "{ ") + f"{len(children)} entr{'y' if len(children) == 1 else 'ies'}" + " }"
        return self.node("attrset", label, line, detail="attribute set", children=children)

    def binding(self) -> dict:
        line = self.peek().line
        parts: list[str] = []
        # Attribute path: stop at the first top-level '='.
        depth = 0
        while self.peek().kind != "eof":
            tok = self.peek()
            if tok.value in {"{", "[", "(", "${"}:
                depth += 1
            elif tok.value in {"}", "]", ")"}:
                if depth == 0:
                    break
                depth -= 1
            if tok.value == "=" and depth == 0:
                break
            if tok.value == ";" and depth == 0:
                break
            parts.append(self.take().value)
            if len(parts) > 80:
                break
        if not parts:
            raise NixError(f"empty binding at line {line}")
        attr = "".join(parts)
        self.expect("=")
        value = self.expr()
        self.eat(";")
        detail = value.get("kind", "value")
        if value.get("detail"):
            detail = value["detail"]
        return self.node(
            "binding",
            clamp_text(attr, 82),
            line,
            detail=detail,
            children=[value],
        )

    def inherit_binding(self) -> dict:
        line = self.take().line
        source = None
        if self.at("("):
            self.take()
            source = self.expr()
            self.expect(")")
        names: list[str] = []
        while not self.at(";") and self.peek().kind != "eof":
            names.append(self.take().value)
        self.eat(";")
        prefix = "inherit "
        if source is not None:
            prefix += f"({clamp_text(source['label'], 26)}) "
        label = prefix + " ".join(names[:8])
        if len(names) > 8:
            label += " …"
        return self.node("inherit", clamp_text(label, 86), line, detail=f"{len(names)} name(s)", children=[])


def fallback_outline(src: str, reason: str = "structural fallback") -> dict:
    children: list[dict] = []
    depth = 0
    lines = src.splitlines()
    for number, raw in enumerate(lines, 1):
        text = raw.strip()
        if not text or text.startswith("#"):
            continue
        if len(children) >= 420:
            children.append(
                {
                    "kind": "truncated",
                    "label": f"… {len(lines) - number + 1} more lines",
                    "line": number,
                    "detail": "line limit",
                    "children": [],
                }
            )
            break
        opens = text.count("{") + text.count("[") + text.count("(")
        closes = text.count("}") + text.count("]") + text.count(")")
        children.append(
            {
                "kind": "line",
                "label": clamp_text(text, 92),
                "line": number,
                "detail": f"line {number}",
                "children": [],
                "indent": max(0, min(depth, 8)),
            }
        )
        depth = max(0, depth + opens - closes)
    return {
        "kind": "root",
        "label": "file outline",
        "line": 1,
        "detail": reason,
        "children": children,
    }


def parse_nix(src: str, path: str) -> dict:
    parser = NixParser(src, path)
    try:
        tree = parser.parse()
    except (NixError, RecursionError, IndexError) as exc:
        return fallback_outline(src, f"fallback: {exc}")
    if parser.limit_hit:
        tree.setdefault("detail", "")
        tree["detail"] = (tree.get("detail", "") + " · truncated").strip(" ·")
    return tree


# ---------------------------------------------------------------------------
# JSON / TOML / Markdown / generic text structure


def _json_tree(value: object, label: str, line: int = 0, depth: int = 0, budget: list[int] | None = None) -> dict:
    if budget is None:
        budget = [MAX_PARSE_NODES]
    budget[0] -= 1
    if budget[0] < 0:
        return {"kind": "truncated", "label": "… truncated", "line": line, "detail": "node limit", "children": []}
    if isinstance(value, dict):
        children = [
            _json_tree(v, str(k), 0, depth + 1, budget)
            for k, v in list(value.items())[:900]
        ]
        return {
            "kind": "attrset",
            "label": label + "  { " + str(len(value)) + " }",
            "line": line,
            "detail": "object",
            "children": children,
        }
    if isinstance(value, list):
        children = [_json_tree(v, f"[{i}]", 0, depth + 1, budget) for i, v in enumerate(value[:900])]
        return {
            "kind": "list",
            "label": label + "  [ " + str(len(value)) + " ]",
            "line": line,
            "detail": "array",
            "children": children,
        }
    if isinstance(value, str):
        return {
            "kind": "string",
            "label": f"{label} = {json.dumps(value[:120], ensure_ascii=False)}",
            "line": line,
            "detail": f"string · {len(value)} chars",
            "children": [],
        }
    if isinstance(value, bool):
        return {"kind": "literal", "label": f"{label} = {'true' if value else 'false'}", "line": line, "detail": "boolean", "children": []}
    if value is None:
        return {"kind": "literal", "label": f"{label} = null", "line": line, "detail": "null", "children": []}
    return {"kind": "literal", "label": f"{label} = {value}", "line": line, "detail": "number", "children": []}


def strip_json_comments(src: str) -> str:
    out: list[str] = []
    i = 0
    n = len(src)
    in_str = False
    while i < n:
        c = src[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(src[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_json(src: str, path: str) -> dict:
    try:
        value = json.loads(strip_json_comments(src))
    except Exception as exc:
        return fallback_outline(src, f"invalid json: {exc}")
    tree = _json_tree(value, Path(path).name)
    tree["kind"] = "root"
    return tree


def parse_toml(src: str, path: str) -> dict:
    root: dict = {"kind": "root", "label": Path(path).name, "line": 1, "detail": "toml", "children": []}
    sections: dict[tuple[str, ...], dict] = {(): root}
    current: dict = root
    for number, raw in enumerate(src.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^\[\[?([^\]]+)\]\]?$", line)
        if m:
            parts = [p.strip().strip('"') for p in m.group(1).split(".")]
            parent = root
            key_parts: list[str] = []
            for part in parts:
                key_parts.append(part)
                key = tuple(key_parts)
                if key not in sections:
                    node = {
                        "kind": "table",
                        "label": "[" + ".".join(key_parts) + "]",
                        "line": number,
                        "detail": "table",
                        "children": [],
                    }
                    parent["children"].append(node)
                    sections[key] = node
                parent = sections[key]
            current = parent
            continue
        m = re.match(r"^([A-Za-z0-9_.\"'\-]+)\s*=\s*(.*)$", line)
        if m:
            key, value = m.group(1), m.group(2)
            value_clean = value.rstrip(",")
            if len(value_clean) > 90:
                value_clean = value_clean[:89] + "…"
            current["children"].append(
                {
                    "kind": "binding",
                    "label": key,
                    "line": number,
                    "detail": value_clean,
                    "children": [],
                }
            )
            continue
        current["children"].append(
            {
                "kind": "line",
                "label": clamp_text(line, 96),
                "line": number,
                "detail": "line",
                "children": [],
            }
        )
    return root


def parse_markdown(src: str, path: str) -> dict:
    root: dict = {"kind": "root", "label": Path(path).name, "line": 1, "detail": "markdown", "children": []}
    stack: list[tuple[int, dict]] = [(0, root)]
    in_fence = False
    for number, raw in enumerate(src.splitlines(), 1):
        line = raw.rstrip()
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or not stripped:
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            level = len(m.group(1))
            node = {
                "kind": "heading",
                "label": clamp_text(m.group(2), 94),
                "line": number,
                "detail": f"h{level}",
                "children": [],
            }
            while stack and stack[-1][0] >= level:
                stack.pop()
            (stack[-1][1] if stack else root)["children"].append(node)
            stack.append((level, node))
            continue
        if re.match(r"^[-*+]\s+", stripped) or re.match(r"^\d+\.\s+", stripped):
            (stack[-1][1] if stack else root)["children"].append(
                {
                    "kind": "item",
                    "label": clamp_text(re.sub(r"^([-*+]|\d+\.)\s+", "", stripped), 94),
                    "line": number,
                    "detail": "list item",
                    "children": [],
                }
            )
    return root


def parse_text_outline(src: str, path: str) -> dict:
    root: dict = {"kind": "root", "label": Path(path).name, "line": 1, "detail": "text outline", "children": []}
    chunk: list[tuple[int, str]] = []
    start = 1

    def flush() -> None:
        nonlocal start
        if not chunk:
            return
        first = chunk[0][1].strip()
        label = clamp_text(first, 96) or "(blank line)"
        detail = f"line {start}" if len(chunk) == 1 else f"lines {start}–{chunk[-1][0]}"
        root["children"].append(
            {
                "kind": "chunk",
                "label": label,
                "line": start,
                "detail": detail,
                "children": [],
            }
        )
        start = chunk[-1][0] + 1
        chunk.clear()

    for number, raw in enumerate(src.splitlines(), 1):
        stripped = raw.strip()
        if not stripped:
            flush()
            start = number + 1
            continue
        if len(chunk) < 14:
            chunk.append((number, stripped))
        if len(root["children"]) >= 600:
            break
    flush()
    return root


def parse_content(src: str, rel: str) -> dict:
    ext = Path(rel).suffix.lower().lstrip(".")
    if ext == "nix" or Path(rel).name == "flake.lock":
        tree = parse_nix(src, rel)
    elif ext in {"json", "jsonc", "json5"}:
        tree = parse_json(src, rel)
    elif ext == "toml":
        tree = parse_toml(src, rel)
    elif ext in {"md", "markdown"}:
        tree = parse_markdown(src, rel)
    else:
        tree = parse_text_outline(src, rel)
    tree["path"] = rel
    tree["kind"] = "root"
    if Path(rel).name and not tree.get("label"):
        tree["label"] = Path(rel).name
    # Assign stable ids and collect stats.
    stats = {"nodes": 0, "maxDepth": 0}

    def assign(node: dict, depth: int) -> None:
        stats["nodes"] += 1
        stats["maxDepth"] = max(stats["maxDepth"], depth)
        node["id"] = f"c{stats['nodes']}"
        node["depth"] = depth
        for child in node.get("children", []):
            assign(child, depth + 1)

    assign(tree, 0)
    tree["stats"] = stats
    return tree


# ---------------------------------------------------------------------------
# rebuild flow: flake inputs -> outputs -> imports -> evaluation -> rebuild

FLOW_STAGES = [
    "INPUTS",
    "FLAKE",
    "OUTPUTS",
    "ENTRYPOINTS",
    "MODULES",
    "EVAL",
    "REBUILD",
    "SYSTEM",
]


def _flow_string(node: dict) -> str:
    raw = node.get("value")
    if raw is not None:
        return str(raw)
    label = str(node.get("label", ""))
    if label.startswith('"') and label.endswith('"'):
        return label[1:-1]
    if label.startswith("''") and label.endswith("''"):
        return label[2:-2]
    return label


def _flow_resolve(value: str, constants: dict[str, str]) -> str:
    def repl(match: re.Match[str]) -> str:
        key = match.group(1).strip()
        return constants.get(key, match.group(0))

    resolved = re.sub(r"\$\{([^}]+)\}", repl, value)
    if resolved.startswith('"') and resolved.endswith('"'):
        resolved = resolved[1:-1]
    return resolved


def _collect_flow_constants(node: dict, prefix: str, out: dict[str, str]) -> None:
    for child in node.get("children", []):
        if child.get("kind") == "binding":
            label = str(child.get("label", ""))
            full = f"{prefix}.{label}" if prefix else label
            value = (child.get("children") or [{}])[0]
            if value.get("kind") in {"string", "literal", "ident"}:
                out[full] = _flow_string(value)
            if value.get("kind") == "attrset":
                _collect_flow_constants(value, full, out)
            else:
                _collect_flow_constants(value, prefix, out)
        else:
            _collect_flow_constants(child, prefix, out)


def _find_flow_binding(node: dict, path: str, prefix: str = "") -> dict | None:
    for child in node.get("children", []):
        if child.get("kind") == "binding":
            label = str(child.get("label", ""))
            full = f"{prefix}.{label}" if prefix else label
            if full == path:
                return child
            value = (child.get("children") or [{}])[0]
            if value.get("kind") == "attrset":
                found = _find_flow_binding(value, path, full)
                if found is not None:
                    return found
        else:
            found = _find_flow_binding(child, path, prefix)
            if found is not None:
                return found
    return None


def _lock_inputs(root: Path) -> dict[str, dict]:
    lock_path = root / "flake.lock"
    if not lock_path.is_file():
        return {}
    try:
        lock = json.loads(read_text(lock_path) or "{}")
    except Exception:
        return {}
    nodes = lock.get("nodes") or {}
    root_inputs = (nodes.get("root") or {}).get("inputs") or {}
    result: dict[str, dict] = {}
    for name, key in root_inputs.items():
        node = nodes.get(key) or {}
        locked = node.get("locked") or {}
        original = node.get("original") or {}
        url = locked.get("url") or original.get("url") or ""
        if not url and locked.get("type") == "github":
            url = f"github:{locked.get('owner')}/{locked.get('repo')}"
        if not url and locked.get("type") == "path":
            url = locked.get("path") or original.get("path") or ""
        rev = str(locked.get("rev") or original.get("rev") or "")
        last_modified = locked.get("lastModified")
        date = ""
        if isinstance(last_modified, (int, float)):
            date = _dt.datetime.fromtimestamp(last_modified).date().isoformat()
        detail = " · ".join(part for part in [url, rev[:7], date] if part)
        result[name] = {
            "url": url,
            "rev": rev,
            "date": date,
            "detail": detail or "locked flake input",
            "type": locked.get("type") or original.get("type") or "",
        }
    return result


def _extract_flow_inputs(tree: dict, constants: dict[str, str], root: Path) -> list[dict]:
    binding = _find_flow_binding(tree, "inputs")
    names: list[str] = []
    if binding is not None:
        value = (binding.get("children") or [{}])[0]
        if value.get("kind") == "attrset":
            for child in value.get("children", []):
                if child.get("kind") != "binding":
                    continue
                name = str(child.get("label", "")).split(".", 1)[0]
                if name and name not in names:
                    names.append(name)
    locked = _lock_inputs(root)
    for name in locked:
        if name not in names:
            names.append(name)

    inputs: list[dict] = []
    for name in names:
        info = locked.get(name) or {}
        ast_url = constants.get(f"inputs.{name}.url") or constants.get(f"inputs.{name}") or ""
        url = info.get("url") or ast_url
        rev = info.get("rev") or ""
        date = info.get("date") or ""
        detail = info.get("detail") or " · ".join(part for part in [url, rev[:7], date] if part) or "flake input"
        inputs.append(
            {
                "name": name,
                "url": url,
                "rev": rev,
                "date": date,
                "detail": detail,
                "type": info.get("type") or "",
            }
        )
    return inputs


def _extract_flow_outputs(tree: dict, constants: dict[str, str], root: Path) -> list[dict]:
    outputs: list[dict] = []
    seen: set[tuple[str, str]] = set()

    def walk(node: dict, prefix: str) -> None:
        for child in node.get("children", []):
            if child.get("kind") == "binding":
                label = str(child.get("label", ""))
                full = f"{prefix}.{label}" if prefix else label
                match = re.match(r"^(nixosConfigurations|homeConfigurations)\.(.+)$", full)
                if match:
                    namespace = match.group(1)
                    raw_name = match.group(2)
                    name = _flow_resolve(raw_name, constants)
                    key = (namespace, name)
                    if key not in seen and "${" not in name:
                        seen.add(key)
                        kind = "nixos" if namespace == "nixosConfigurations" else "home"
                        entry = ""
                        if kind == "nixos":
                            candidate = root / "hosts" / name / "configuration.nix"
                            if candidate.is_file():
                                entry = candidate.relative_to(root).as_posix()
                        else:
                            base = name.split("@", 1)[0]
                            for candidate in (root / "home" / f"{base}.nix", root / "home" / "rei.nix"):
                                if candidate.is_file():
                                    entry = candidate.relative_to(root).as_posix()
                                    break
                        command = (
                            f"sudo nixos-rebuild switch --flake .#{name}"
                            if kind == "nixos"
                            else f"home-manager switch --flake {('.#' + name) if '@' not in name else repr('.#' + name)}"
                        )
                        outputs.append(
                            {
                                "namespace": namespace,
                                "name": name,
                                "kind": kind,
                                "entry": entry,
                                "command": command,
                            }
                        )
                value = (child.get("children") or [{}])[0]
                if value.get("kind") == "attrset":
                    walk(value, full)
                else:
                    walk(value, prefix)
            else:
                walk(child, prefix)

    walk(tree, "")
    outputs.sort(key=lambda item: (0 if item["kind"] == "nixos" else 1, item["name"]))
    return outputs


def _flow_imports(root: Path, files: list[dict]) -> dict[str, set[str]]:
    nix_files = {
        item["path"]: item
        for item in files
        if item["path"].endswith(".nix") and item.get("text")
    }
    graph: dict[str, set[str]] = {path: set() for path in nix_files}
    for rel in nix_files:
        path = root / rel
        source = read_text(path)
        if source is None:
            continue
        for token in tokenize_nix(source):
            if token.kind != "path":
                continue
            value = token.value
            if not (value.startswith("./") or value.startswith("../")):
                continue
            try:
                target = (path.parent / value).resolve()
                target.relative_to(root)
            except (OSError, ValueError):
                continue
            if target.suffix != ".nix" or not target.is_file():
                continue
            target_rel = target.relative_to(root).as_posix()
            if target_rel in nix_files:
                graph[rel].add(target_rel)
    return graph


def _flow_closure(start: str, graph: dict[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    stack = list(graph.get(start, ()))
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        stack.extend(graph.get(current, ()))
    return seen


def _empty_flow() -> dict:
    return {
        "stages": FLOW_STAGES,
        "nodes": [],
        "edges": [],
        "stats": {
            "inputs": 0,
            "outputs": 0,
            "entries": 0,
            "modules": 0,
            "evals": 0,
            "rebuilds": 0,
            "targets": 0,
            "nodes": 0,
            "edges": 0,
        },
    }


def build_flow(root: Path, files: list[dict]) -> dict:
    flake_path = root / "flake.nix"
    source = read_text(flake_path)
    if source is None:
        return _empty_flow()
    try:
        tree = NixParser(source, "flake.nix").parse()
    except Exception:
        return _empty_flow()

    constants: dict[str, str] = {}
    _collect_flow_constants(tree, "", constants)
    inputs = _extract_flow_inputs(tree, constants, root)
    outputs = _extract_flow_outputs(tree, constants, root)
    graph = _flow_imports(root, files)
    file_meta = {item["path"]: item for item in files}

    nodes: list[dict] = []
    edges: list[dict] = []

    def add_node(node: dict) -> None:
        nodes.append(node)

    def add_edge(source_id: str, target_id: str, kind: str) -> None:
        edges.append(
            {
                "id": f"fle{len(edges) + 1}",
                "source": source_id,
                "target": target_id,
                "kind": kind,
            }
        )

    input_ids: list[str] = []
    for index, item in enumerate(inputs):
        node_id = f"fl-input-{index}"
        input_ids.append(node_id)
        add_node(
            {
                "id": node_id,
                "stage": 0,
                "order": index,
                "kind": "input",
                "tag": "INPUT",
                "icon": "config",
                "label": item["name"],
                "detail": item["detail"],
                "url": item["url"],
                "rev": item["rev"],
                "date": item["date"],
            }
        )

    flake_id = "fl-flake"
    add_node(
        {
            "id": flake_id,
            "stage": 1,
            "order": 0,
            "kind": "flake",
            "tag": "FLAKE",
            "icon": "nix",
            "label": "flake.nix",
            "detail": f"{len(inputs)} inputs · {len(outputs)} outputs",
            "path": "flake.nix",
        }
    )
    for input_id in input_ids:
        add_edge(input_id, flake_id, "flow-input")

    entry_ids: dict[str, str] = {}
    module_ids: dict[str, str] = {}
    entry_paths: list[str] = []
    for output in outputs:
        entry = output["entry"]
        if entry and entry not in entry_ids:
            entry_ids[entry] = f"fl-entry-{len(entry_ids)}"
            entry_paths.append(entry)

    for path in entry_paths:
        meta = file_meta.get(path, {})
        imports = graph.get(path, set())
        add_node(
            {
                "id": entry_ids[path],
                "stage": 3,
                "order": entry_paths.index(path),
                "kind": "entry",
                "tag": "ENTRY",
                "icon": "code",
                "label": (path[6:] if path.startswith("hosts/") else path),
                "detail": f"{path} · {meta.get('lines', '—')} L · {meta.get('sizeLabel', '')}",
                "path": path,
                "imports": sorted(imports),
            }
        )

    # Union of all modules reachable from the selected entrypoints.
    closure_by_entry: dict[str, set[str]] = {}
    all_modules: set[str] = set()
    for entry in entry_paths:
        closure = _flow_closure(entry, graph)
        closure_by_entry[entry] = closure
        all_modules.update(path for path in closure if path not in entry_ids)

    for index, path in enumerate(sorted(all_modules)):
        module_ids[path] = f"fl-module-{index}"
        meta = file_meta.get(path, {})
        imports = sorted(graph.get(path, set()))
        add_node(
            {
                "id": module_ids[path],
                "stage": 4,
                "order": index,
                "kind": "module",
                "tag": "MODULE",
                "icon": "code",
                "label": (path[6:] if path.startswith("hosts/") else path),
                "detail": f"{meta.get('lines', '—')} L · {meta.get('sizeLabel', '')} · {len(imports)} import{'s' if len(imports) != 1 else ''}",
                "path": path,
                "imports": imports,
            }
        )

    output_ids: list[str] = []
    rebuild_ids: list[str] = []
    target_ids: list[str] = []
    for index, output in enumerate(outputs):
        output_id = f"fl-output-{index}"
        output_ids.append(output_id)
        add_node(
            {
                "id": output_id,
                "stage": 2,
                "order": index,
                "kind": "output",
                "tag": "NIXOS" if output["kind"] == "nixos" else "HOME",
                "icon": "nix",
                "label": output["name"],
                "detail": f"{output['namespace']}.{output['name']}",
                "outputType": output["kind"],
                "modulePaths": sorted(
                    closure_by_entry.get(output["entry"], set())
                ),
            }
        )
        add_edge(flake_id, output_id, "flow-output")
        entry = output["entry"]
        if entry and entry in entry_ids:
            add_edge(output_id, entry_ids[entry], "flow-entry")

        eval_id = f"fl-eval-{index}"
        rebuild_id = f"fl-rebuild-{index}"
        target_id = f"fl-target-{index}"
        rebuild_ids.append(rebuild_id)
        target_ids.append(target_id)
        add_node(
            {
                "id": eval_id,
                "stage": 5,
                "order": index,
                "kind": "eval",
                "tag": "EVAL",
                "icon": "code",
                "label": f"eval .#{output['name']}",
                "detail": "flake output closure",
                "outputType": output["kind"],
            }
        )
        command = output["command"]
        add_node(
            {
                "id": rebuild_id,
                "stage": 6,
                "order": index,
                "kind": "rebuild",
                "tag": "REBUILD",
                "icon": "code",
                "label": "nixos-rebuild switch" if output["kind"] == "nixos" else "home-manager switch",
                "detail": command,
                "command": command,
                "outputType": output["kind"],
            }
        )
        add_node(
            {
                "id": target_id,
                "stage": 7,
                "order": index,
                "kind": "target",
                "tag": "SYSTEM",
                "icon": "config",
                "label": f"{'NixOS' if output['kind'] == 'nixos' else 'Home Manager'} · {output['name']}",
                "detail": "system generation" if output["kind"] == "nixos" else "user profile generation",
                "outputType": output["kind"],
            }
        )

        reachable = closure_by_entry.get(entry, set())
        linked = [
            module_ids[path]
            for path in sorted(reachable)
            if path in module_ids
        ]
        if linked:
            for module_id in linked:
                add_edge(module_id, eval_id, "flow-eval")
        elif entry and entry in entry_ids:
            add_edge(entry_ids[entry], eval_id, "flow-eval")
        else:
            add_edge(output_id, eval_id, "flow-eval")
        add_edge(eval_id, rebuild_id, "flow-eval")
        add_edge(rebuild_id, target_id, "flow-rebuild")

    # Import edges within the reachable module set.
    selected = set(entry_ids) | set(module_ids)
    seen_imports: set[tuple[str, str]] = set()
    for source_path in sorted(selected):
        source_id = entry_ids.get(source_path) or module_ids.get(source_path)
        if not source_id:
            continue
        for target_path in sorted(graph.get(source_path, ())):
            target_id = entry_ids.get(target_path) or module_ids.get(target_path)
            if not target_id or (source_id, target_id) in seen_imports:
                continue
            seen_imports.add((source_id, target_id))
            add_edge(source_id, target_id, "flow-import")

    return {
        "stages": FLOW_STAGES,
        "nodes": nodes,
        "edges": edges,
        "stats": {
            "inputs": len(inputs),
            "outputs": len(outputs),
            "entries": len(entry_ids),
            "modules": len(module_ids),
            "evals": len(outputs),
            "rebuilds": len(rebuild_ids),
            "targets": len(target_ids),
            "nodes": len(nodes),
            "edges": len(edges),
        },
    }


# ---------------------------------------------------------------------------
# HTTP server + heartbeat lifecycle


class CanvasState:
    def __init__(self, root: Path, heartbeat_timeout: float = 14.0, startup_timeout: float = 180.0):
        self.root = root
        self.heartbeat_timeout = heartbeat_timeout
        self.startup_timeout = startup_timeout
        self.started = time.monotonic()
        self.lock = threading.RLock()
        self.clients: dict[str, float] = {}
        self.sse: set[str] = set()
        self.ever_connected = False
        self.empty_since: float | None = None
        self.shutdown_event = threading.Event()
        self.browser_exit = True
        self.httpd: ThreadingHTTPServer | None = None
        self.scan_cache: dict | None = None
        self.scan_at = 0.0
        self.scan_lock = threading.Lock()
        self.pending: list[dict] = []  # structured client events for the log

    def refresh_scan(self, max_age: float = 0.0) -> dict:
        with self.scan_lock:
            now = time.monotonic()
            if self.scan_cache is not None and now - self.scan_at <= max_age:
                return self.scan_cache
            data = scan_filesystem(self.root)
            self.scan_cache = data
            self.scan_at = now
            return data

    def event(self, kind: str, sid: str) -> None:
        with self.lock:
            self.pending.append({"kind": kind, "sid": sid[:8], "at": round(time.monotonic(), 2)})

    def beat(self, sid: str) -> None:
        with self.lock:
            self.clients[sid] = time.monotonic()
            self.ever_connected = True
            self.empty_since = None

    def join_sse(self, sid: str) -> None:
        with self.lock:
            self.sse.add(sid)
            self.clients[sid] = time.monotonic()
            self.ever_connected = True
            self.empty_since = None

    def leave_sse(self, sid: str) -> None:
        with self.lock:
            self.sse.discard(sid)
            # If the stream dropped and the heartbeat is gone too, do not make
            # the command wait out the whole heartbeat window. A live page
            # refreshes its heartbeat long before this short grace expires.
            if sid in self.clients:
                self.clients[sid] = min(
                    self.clients[sid],
                    time.monotonic() - self.heartbeat_timeout + 6.0,
                )

    def leave(self, sid: str) -> None:
        with self.lock:
            self.clients.pop(sid, None)
            self.sse.discard(sid)
            if not self.clients and self.ever_connected and self.empty_since is None:
                self.empty_since = time.monotonic()

    def shutdown(self, reason: str) -> None:
        if self.shutdown_event.is_set():
            return
        self.shutdown_event.set()
        eprint(f"\n[canvas] {reason}")
        if self.httpd is not None:
            threading.Thread(target=self.httpd.shutdown, daemon=True).start()

    def monitor(self) -> None:
        while not self.shutdown_event.is_set():
            time.sleep(0.25)
            now = time.monotonic()
            with self.lock:
                stale = [sid for sid, seen in self.clients.items() if now - seen > self.heartbeat_timeout and sid not in self.sse]
                for sid in stale:
                    self.clients.pop(sid, None)
                if self.clients:
                    self.empty_since = None
                else:
                    if not self.browser_exit:
                        continue
                    if self.ever_connected:
                        if self.empty_since is None:
                            self.empty_since = now
                        elif now - self.empty_since >= 2.5:
                            self.shutdown("tab closed — shutting down")
                            return
                    elif self.startup_timeout > 0 and now - self.started > self.startup_timeout:
                        self.shutdown("no browser connected — shutting down")
                        return


class Handler(BaseHTTPRequestHandler):
    server_version = "config-canvas/1.0"
    protocol_version = "HTTP/1.1"
    state: CanvasState

    def log_message(self, fmt: str, *args: object) -> None:
        # Keep the terminal quiet; the interesting summaries are printed by
        # the main command instead of every asset request.
        return

    # -- utility -----------------------------------------------------------
    def send_bytes(
        self,
        data: bytes,
        content_type: str,
        *,
        status: int = 200,
        headers: dict[str, str] | None = None,
        head_only: bool = False,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        if headers:
            for key, value in headers.items():
                self.send_header(key, value)
        self.end_headers()
        if not head_only:
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def send_json(self, value: object, *, status: int = 200) -> None:
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_bytes(
            payload,
            "application/json; charset=utf-8",
            status=status,
            headers={"Access-Control-Allow-Origin": "null"},
        )

    def send_error_json(self, message: str, status: int = 400) -> None:
        self.send_json({"error": message}, status=status)

    def body(self) -> bytes:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        length = min(max(length, 0), 2 * 1024 * 1024)
        return self.rfile.read(length) if length else b""

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Allow", "GET, POST, HEAD, OPTIONS")
        self.send_header("Content-Length", "0")
        self.end_headers()

    # -- routing -----------------------------------------------------------
    def do_HEAD(self) -> None:
        self.do_GET(head_only=True)

    def do_GET(self, head_only: bool = False) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        try:
            if path == "/":
                return self.serve_static("index.html", head_only=head_only)
            if path == "/favicon.svg":
                return self.serve_static("favicon.svg", head_only=head_only)
            if path.startswith("/static/"):
                return self.serve_static(path[len("/static/") :], head_only=head_only)
            if path == "/api/graph":
                data = self.state.refresh_scan(max_age=0.0)
                if "refresh" in query:
                    data = self.state.refresh_scan(max_age=0.0)
                return self.send_json(data)
            if path == "/api/content":
                rel = (query.get("path") or [""])[0]
                return self.api_content(rel)
            if path == "/api/preview":
                rel = (query.get("path") or [""])[0]
                return self.api_preview(rel, query)
            if path == "/api/fragment":
                rel = (query.get("path") or [""])[0]
                line = int((query.get("line") or ["1"])[0] or 1)
                return self.api_fragment(rel, line)
            if path == "/api/raw":
                rel = (query.get("path") or [""])[0]
                return self.api_raw(rel, head_only=head_only)
            if path == "/api/events":
                sid = (query.get("sid") or [""])[0]
                return self.api_events(sid)
            if path == "/api/ping":
                return self.send_json({"ok": True, "ts": time.time()})
            if path == "/api/leave":
                sid = (query.get("sid") or [""])[0]
                if sid:
                    self.state.leave(sid)
                return self.send_json({"ok": True})
            if path == "/api/hooks":
                return self.send_json({"clients": len(self.state.clients), "sse": len(self.state.sse), "ever": self.state.ever_connected})
            return self.send_error_json("not found", 404)
        except ScanError as exc:
            return self.send_error_json(str(exc), 400)
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as exc:  # keep the local app alive
            traceback.print_exc()
            return self.send_error_json(f"internal error: {exc}", 500)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        try:
            if path == "/api/heartbeat":
                raw = self.body()
                sid = ""
                try:
                    payload = json.loads(raw.decode("utf-8") or "{}")
                    sid = str(payload.get("sid", ""))
                except Exception:
                    sid = (query.get("sid") or [""])[0]
                if not sid:
                    sid = self.client_address[0]
                self.state.beat(sid)
                return self.send_json({"ok": True, "ts": time.time()})
            if path == "/api/leave":
                raw = self.body()
                sid = ""
                try:
                    sid = str(json.loads(raw.decode("utf-8") or "{}").get("sid", ""))
                except Exception:
                    sid = (query.get("sid") or [""])[0]
                if sid:
                    self.state.leave(sid)
                return self.send_json({"ok": True})
            return self.send_error_json("not found", 404)
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as exc:
            traceback.print_exc()
            return self.send_error_json(f"internal error: {exc}", 500)

    # -- implementations ---------------------------------------------------
    def serve_static(self, rel: str, *, head_only: bool = False) -> None:
        if not rel or rel.endswith("/"):
            rel += "index.html"
        candidate = (STATIC_DIR / rel).resolve()
        try:
            candidate.relative_to(STATIC_DIR.resolve())
        except ValueError:
            return self.send_error_json("not found", 404)
        if not candidate.is_file():
            return self.send_error_json("not found", 404)
        mime = mimetypes.guess_type(candidate.name)[0] or "application/octet-stream"
        if candidate.suffix == ".js":
            mime = "text/javascript; charset=utf-8"
        elif candidate.suffix == ".css":
            mime = "text/css; charset=utf-8"
        elif candidate.suffix == ".svg":
            mime = "image/svg+xml"
        headers = {
            "Content-Security-Policy": (
                "default-src 'self'; img-src 'self' data: blob:; "
                "style-src 'self' 'unsafe-inline'; script-src 'self'; "
                "connect-src 'self'; object-src 'none'; base-uri 'none'; "
                "frame-ancestors 'none'"
            )
        }
        try:
            data = candidate.read_bytes()
        except OSError:
            return self.send_error_json("cannot read file", 500)
        self.send_bytes(data, mime, headers=headers, head_only=head_only)

    def api_content(self, rel: str) -> None:
        if not rel:
            return self.send_error_json("missing path", 400)
        path = resolve_inside(self.state.root, rel)
        if not path.is_file():
            return self.send_error_json("not a file", 404)
        if path.stat().st_size > MAX_TEXT_BYTES:
            return self.send_error_json("file is too large to structure", 413)
        src = read_text(path)
        if src is None:
            return self.send_error_json("file is not text", 415)
        started = time.perf_counter()
        tree = parse_content(src, safe_rel(path, self.state.root))
        parse_ms = (time.perf_counter() - started) * 1000
        self.send_json(
            {
                "path": safe_rel(path, self.state.root),
                "size": path.stat().st_size,
                "sizeLabel": human_size(path.stat().st_size),
                "mtime": int(path.stat().st_mtime),
                "modified": iso_time(path.stat().st_mtime),
                "parseMs": round(parse_ms, 1),
                "tree": tree,
            }
        )

    def api_preview(self, rel: str, query: dict) -> None:
        if not rel:
            return self.send_error_json("missing path", 400)
        path = resolve_inside(self.state.root, rel)
        if not path.is_file():
            return self.send_error_json("not a file", 404)
        size = path.stat().st_size
        ext = path.suffix.lower().lstrip(".")
        st = path.stat()
        result: dict = {
            "path": rel,
            "name": path.name,
            **stat_details(st),
            "mime": mime_for(path),
            "kind": file_kind(path, looks_text(path)),
            "ext": ext,
            "image": ext in IMAGE_EXTS,
            "text": looks_text(path),
        }
        dims = image_size(path) if ext in IMAGE_EXTS else None
        if dims:
            result["width"], result["height"] = dims
        if ext in IMAGE_EXTS:
            result["url"] = "/api/raw?path=" + quote(rel)
            return self.send_json(result)
        if ext in AUDIO_EXTS | VIDEO_EXTS:
            result["url"] = "/api/raw?path=" + quote(rel)
            return self.send_json(result)
        if ext in DOC_EXTS:
            result["url"] = "/api/raw?path=" + quote(rel)
            return self.send_json(result)
        text = read_text(path, limit=256 * 1024)
        if text is not None:
            result["text"] = text[:100000]
            result["truncated"] = len(text) > 100000
            result["lines"] = text.count("\n") + (0 if text.endswith("\n") else 1) if text else 0
            result["chars"] = len(text)
            result["words"] = len(text.split())
            return self.send_json(result)
        # binary: a small, honest hex view
        try:
            with path.open("rb") as fh:
                raw = fh.read(2048)
        except OSError:
            raw = b""
        lines = []
        for offset in range(0, len(raw), 16):
            chunk = raw[offset : offset + 16]
            hex_part = " ".join(f"{b:02x}" for b in chunk)
            ascii_part = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
            lines.append(f"{offset:08x}  {hex_part:<47}  |{ascii_part}|")
        result["hex"] = "\n".join(lines)
        return self.send_json(result)

    def api_fragment(self, rel: str, line: int) -> None:
        if not rel:
            return self.send_error_json("missing path", 400)
        path = resolve_inside(self.state.root, rel)
        if not path.is_file():
            return self.send_error_json("not a file", 404)
        text = read_text(path, limit=MAX_TEXT_BYTES)
        if text is None:
            return self.send_json({"path": rel, "start": 1, "lines": []})
        lines = text.splitlines()
        start = max(1, line - 3)
        end = min(len(lines), line + 5)
        self.send_json(
            {
                "path": rel,
                "start": start,
                "line": line,
                "lines": [
                    {"n": n, "text": lines[n - 1][:300]} for n in range(start, end + 1)
                ],
            }
        )

    def api_raw(self, rel: str, *, head_only: bool = False) -> None:
        if not rel:
            return self.send_error_json("missing path", 400)
        path = resolve_inside(self.state.root, rel)
        if not path.is_file():
            return self.send_error_json("not a file", 404)
        size = path.stat().st_size
        if size > MAX_RAW_BYTES:
            return self.send_error_json("file is too large", 413)
        mime = mime_for(path)
        range_header = self.headers.get("Range", "")
        start, end = 0, size - 1
        status = 200
        if range_header.startswith("bytes="):
            spec = range_header[6:].split(",")[0].strip()
            try:
                a, _, b = spec.partition("-")
                if a:
                    start = int(a)
                    end = int(b) if b else size - 1
                elif b:
                    start = max(0, size - int(b))
                end = min(end, size - 1)
                if start > end:
                    raise ValueError
                status = 206
            except ValueError:
                return self.send_error_json("bad range", 416)
        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(length))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "sandbox; default-src 'none'; style-src 'unsafe-inline'")
        self.end_headers()
        if head_only:
            return
        try:
            with path.open("rb") as fh:
                fh.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = fh.read(min(65536, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            return

    def api_events(self, sid: str) -> None:
        if not sid:
            return self.send_error_json("missing session", 400)
        self.close_connection = True
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache, no-transform")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        self.state.join_sse(sid)
        try:
            self.wfile.write(b"retry: 1500\nevent: hello\ndata: {}\n\n")
            self.wfile.flush()
            while not self.state.shutdown_event.is_set():
                time.sleep(3.0)
                self.wfile.write(b": canvas alive\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            self.state.leave_sse(sid)
            # If the heartbeat is also gone, this disconnect can end the app.
            with self.state.lock:
                seen = self.state.clients.get(sid)
                if seen is None or time.monotonic() - seen > self.state.heartbeat_timeout:
                    self.state.clients.pop(sid, None)
                    if not self.state.clients and self.state.ever_connected and self.state.empty_since is None:
                        self.state.empty_since = time.monotonic()


# ---------------------------------------------------------------------------
# entry point


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="config-canvas",
        description="Open an endless-canvas explorer of a Nix config tree.",
    )
    parser.add_argument("root", nargs="?", default=str(DEFAULT_ROOT), help="folder to scan (default: repository root)")
    parser.add_argument("-p", "--port", type=int, default=0, help="port (default: choose a free one)")
    parser.add_argument("--host", default="127.0.0.1", help="bind address (default: 127.0.0.1)")
    parser.add_argument("--no-open", action="store_true", help="do not call xdg-open")
    parser.add_argument("--open-cmd", default="xdg-open", help="browser opener command")
    parser.add_argument(
        "--heartbeat-timeout",
        type=float,
        default=14.0,
        help="seconds without a heartbeat before considering the tab gone (default: 14)",
    )
    parser.add_argument(
        "--startup-timeout",
        type=float,
        default=180.0,
        help="seconds to wait for the first browser connection, 0 disables (default: 180)",
    )
    parser.add_argument("--check", action="store_true", help="scan and parse everything, print a report, then exit")
    parser.add_argument("--quiet", action="store_true", help="less terminal output")
    parser.add_argument("--no-browser-exit", action="store_true", help="ignore browser lifecycle (Ctrl-C to stop)")
    return parser


def print_scan_summary(data: dict, *, quiet: bool) -> None:
    stats = data["stats"]
    skipped = stats["skipped"]
    print("  scan   " + f"{stats['nodes']} nodes · {stats['dirs']} dirs · {stats['files']} files · {stats['bytesLabel']} · {data['scanMs']:.0f} ms")
    flow = data.get("flow") or {}
    fstats = flow.get("stats") or {}
    if fstats.get("nodes"):
        print(
            "  flow   "
            + f"{fstats.get('inputs', 0)} inputs → {fstats.get('outputs', 0)} outputs · "
            + f"{fstats.get('entries', 0)} entrypoints · {fstats.get('modules', 0)} modules · "
            + f"{fstats.get('rebuilds', 0)} rebuild commands"
        )
    if skipped:
        names = ", ".join(s["path"] for s in skipped[:6])
        extra = f" (+{len(skipped) - 6})" if len(skipped) > 6 else ""
        print("  skipped " + names + extra)


def run_check(root: Path) -> int:
    data = scan_filesystem(root)
    print(f"root   {data['root']}")
    print_scan_summary(data, quiet=False)
    counts: list[tuple[int, str, str]] = []
    for item in data["files"]:
        if not item.get("structured"):
            continue
        path = root / item["path"]
        src = read_text(path)
        if src is None:
            continue
        started = time.perf_counter()
        tree = parse_content(src, item["path"])
        ms = (time.perf_counter() - started) * 1000
        counts.append((tree["stats"]["nodes"], item["path"], f"{ms:.1f}ms d{tree['stats']['maxDepth']} {tree['kind']}"))
    counts.sort(reverse=True)
    print(f"parsed {len(counts)} structured files")
    for n, path, info in counts[:30]:
        print(f"  {n:5d}  {path:<52} {info}")
    return 0


def pick_port(host: str, wanted: int) -> int:
    if wanted:
        return wanted
    import socket

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((host, 0))
        return sock.getsockname()[1]


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    root = Path(args.root).expanduser().resolve()
    if not root.is_dir():
        eprint(f"error: not a directory: {root}")
        return 2
    if args.check:
        return run_check(root)

    state = CanvasState(
        root,
        heartbeat_timeout=max(2.0, args.heartbeat_timeout),
        startup_timeout=max(0.0, args.startup_timeout),
    )
    if args.no_browser_exit:
        state.browser_exit = False
        state.startup_timeout = 0

    # Prime the scan so the startup message is useful and the first paint is
    # instant.  /api/graph still rescans on each call for live edits.
    started = time.perf_counter()
    try:
        data = state.refresh_scan()
    except Exception as exc:
        eprint(f"error: scan failed: {exc}")
        return 1
    total_scan_ms = (time.perf_counter() - started) * 1000

    port = pick_port(args.host, args.port)
    handler = type("CanvasHandler", (Handler,), {"state": state})
    try:
        httpd = ThreadingHTTPServer((args.host, port), handler)
        httpd.daemon_threads = True
    except OSError as exc:
        eprint(f"error: cannot bind {args.host}:{port}: {exc}")
        return 1
    state.httpd = httpd
    url = f"http://{args.host}:{port}/"

    if not args.quiet:
        print("")
        print("  CONFIG CANVAS")
        print(f"  root   {root}")
        print_scan_summary(data, quiet=args.quiet)
        print(f"  ready  {url}   ({total_scan_ms:.0f} ms)")
        print("  exit   close the browser tab · Ctrl-C to stop")
        print("")

    monitor = threading.Thread(target=state.monitor, daemon=True)
    monitor.start()

    if not args.no_open:
        opener = args.open_cmd
        if shutil.which(opener) is None:
            eprint(f"[canvas] {opener!r} not found; open {url} manually")
        else:
            try:
                subprocess.Popen(
                    [opener, url],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    stdin=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError as exc:
                eprint(f"[canvas] could not open browser: {exc}; open {url} manually")

    def on_signal(signum: int, frame: object) -> None:
        state.shutdown("signal received — shutting down")

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    try:
        httpd.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        state.shutdown("interrupted")
    finally:
        try:
            httpd.server_close()
        except Exception:
            pass
        monitor.join(timeout=1.0)
    if not args.quiet:
        print("[canvas] stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
