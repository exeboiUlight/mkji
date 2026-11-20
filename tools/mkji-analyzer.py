#!/usr/bin/env python3
"""
MKJI static analyzer / linter.

Usage:
  python tools/mkji-analyzer.py [--format text|json|vscode] [--compiler PATH] <file.mk|dir> [...]

- Scans .mk files (or directories recursively).
- Reports lexical/structural issues with file:line:col locations.
- Optionally runs the MKJI compiler to surface compiler diagnostics.

Exit code: 0 if no errors, 1 if errors were found.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict
from typing import List, Optional, Tuple


@dataclass
class Diag:
    file: str
    line: int
    col: int
    severity: str  # error|warning|info
    message: str
    source: str = "mkji-analyzer"

    def format_text(self) -> str:
        return f"{self.file}:{self.line}:{self.col}: {self.severity}: {self.message}"

    def format_vscode(self) -> str:
        # VS Code problem matcher friendly: file(line,col): severity: message
        return f"{self.file}({self.line},{self.col}): {self.severity}: {self.message}"


KEYWORDS = {
    "fn", "class", "if", "else", "while", "return", "use", "new", "this",
    "true", "false", "null", "print", "panic", "read_file", "write_file",
    "str_from", "arg_count", "get_arg", "var",
}
TYPE_KEYWORDS = {"int", "bool", "byte", "string", "void"}


def read_text(path: str) -> Optional[str]:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def scan_source(path: str, src: str) -> List[Diag]:
    diags: List[Diag] = []
    i = 0
    n = len(src)
    line = 1
    col = 1

    stack: List[Tuple[str, int, int]] = []  # (ch, line, col)

    def add(sev: str, msg: str, ln: int, cl: int):
        diags.append(Diag(path, ln, cl, sev, msg))

    def peek(off: int = 0) -> str:
        j = i + off
        return src[j] if j < n else "\0"

    while i < n:
        ch = src[i]
        ch2 = src[i:i+2]

        if ch == "\n":
            i += 1
            line += 1
            col = 1
            continue

        # whitespace
        if ch in " \t\r\f\v":
            i += 1
            col += 1
            continue

        # line comment
        if ch2 == "//":
            while i < n and src[i] != "\n":
                i += 1
                col += 1
            continue

        # block comment
        if ch2 == "/*":
            start_ln, start_col = line, col
            i += 2
            col += 2
            closed = False
            while i + 1 <= n:
                if src[i:i+2] == "*/":
                    i += 2
                    col += 2
                    closed = True
                    break
                if src[i] == "\n":
                    i += 1
                    line += 1
                    col = 1
                else:
                    i += 1
                    col += 1
            if not closed:
                add("error", "unterminated block comment", start_ln, start_col)
            continue

        # string literal
        if ch == '"':
            start_ln, start_col = line, col
            i += 1
            col += 1
            closed = False
            while i < n:
                c = src[i]
                if c == '"':
                    i += 1
                    col += 1
                    closed = True
                    break
                if c == "\n":
                    break
                if c == "\\":
                    i += 1
                    col += 1
                    if i < n:
                        # consume escaped char (may be newline in odd cases)
                        if src[i] == "\n":
                            i += 1
                            line += 1
                            col = 1
                        else:
                            i += 1
                            col += 1
                    continue
                i += 1
                col += 1
            if not closed:
                add("error", "unterminated string literal", start_ln, start_col)
            continue

        # char-like: not in MKJI, but catch single quotes to warn? ignore

        # identifiers / keywords
        if ch.isalpha() or ch == "_":
            start_ln, start_col = line, col
            j = i + 1
            while j < n and (src[j].isalnum() or src[j] == "_"):
                j += 1
            ident = src[i:j]
            if ident == "var":
                add("warning", "'var' declarations are not supported; use explicit types", start_ln, start_col)
            i = j
            col += (j - i + 0)  # adjusted below
            col = start_col + (j - (j - len(ident)))
            # simpler: recompute col
            col = start_col + len(ident)
            continue

        # numbers (decimal or hex 0x...)
        if ch.isdigit():
            start_col0 = col
            j = i + 1
            if ch == "0" and j < n and src[j] in "xX":
                j += 1
                k = j
                while j < n and src[j] in "0123456789abcdefABCDEF":
                    j += 1
                if j == k:
                    add("error", "invalid hexadecimal literal", line, start_col0)
            else:
                while j < n and src[j].isdigit():
                    j += 1
            col += (j - i)
            i = j
            continue

        # two-char operators/punct
        if ch2 in ("&&", "||", "<<", ">>", "==", "!=", "<=", ">="):
            i += 2
            col += 2
            continue

        # brackets
        if ch in "({[":
            stack.append((ch, line, col))
            i += 1
            col += 1
            continue
        if ch in ")}]":
            match = {"(": ")", "{": "}", "[": "]"}
            if not stack:
                add("error", f"unexpected closing '{ch}'", line, col)
            else:
                open_ch, oln, ocol = stack.pop()
                if match[open_ch] != ch:
                    add("error", f"mismatched closing '{ch}' (opened '{open_ch}' at {oln}:{ocol})", line, col)
                    # try to recover: push back if it might close something else? keep simple
            i += 1
            col += 1
            continue

        # any other single char
        i += 1
        col += 1

    for open_ch, oln, ocol in stack:
        add("error", f"unclosed '{open_ch}'", oln, ocol)

    # simple line-based checks: use paths and semicolons hints are tricky; do lightweight checks
    for idx, raw in enumerate(src.splitlines(), start=1):
        s = raw.strip()
        if s.startswith("use ") and "use \"" in s:
            m = re.search(r'use\s+"([^"]+)"\s*;?', s)
            if m:
                rel = m.group(1)
                base_dir = os.path.dirname(path)
                target = rel if os.path.isabs(rel) else os.path.normpath(os.path.join(base_dir, rel))
                if not os.path.exists(target):
                    # may be resolved differently in some setups, warn
                    add("warning", f"included file not found: {rel}", idx, raw.find('use') + 1 if 'use' in raw else 1)
            elif "use " in s:
                if not re.search(r'use\s+"', s):
                    add("warning", "use directive should be: use \"file.mk\";", idx, 1)

    return diags


def collect_files(inputs: List[str]) -> List[str]:
    out: List[str] = []
    for p in inputs:
        if os.path.isdir(p):
            for root, _, files in os.walk(p):
                for fn in files:
                    if fn.lower().endswith(".mk"):
                        out.append(os.path.join(root, fn))
        else:
            out.append(p)
    # dedupe preserving order
    seen = set()
    res = []
    for p in out:
        ap = os.path.normpath(p)
        if ap not in seen:
            seen.add(ap)
            res.append(p)
    return res


def run_compiler(compiler: str, path: str) -> List[Diag]:
    # Try to compile to a temp-named output to detect errors; compiler may not support --check.
    # Use a throwaway output name in temp dir behavior is complex cross-platform; instead compile to
    # a sibling temp file and remove it if created.
    base = os.path.splitext(os.path.basename(path))[0]
    tmp_out = os.path.join(os.path.dirname(path) or ".", f".__mkji_analyze_{base}.tmp")
    diags: List[Diag] = []
    try:
        cmd = [compiler, path, "-o", tmp_out, "--target", "pe"]
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        out = (proc.stdout or "").strip()
        if proc.returncode != 0:
            msg = out if out else "compilation failed"
            # try to extract file:line:col if ever present
            m = re.search(r"(.+?):(\d+):(\d+):\s*(.*)", msg)
            if m:
                diags.append(Diag(m.group(1), int(m.group(2)), int(m.group(3)), "error", m.group(4) or msg, source="mkji-compiler"))
            else:
                # compiler currently emits plain messages without location
                diags.append(Diag(path, 1, 1, "error", msg, source="mkji-compiler"))
    except OSError as e:
        diags.append(Diag(path, 1, 1, "error", f"failed to run compiler: {e}", source="mkji-compiler"))
    finally:
        try:
            if os.path.exists(tmp_out):
                os.remove(tmp_out)
        except OSError:
            pass
    return diags


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(description="MKJI static analyzer")
    ap.add_argument("paths", nargs="+", help=".mk files or directories")
    ap.add_argument("--format", choices=["text", "json", "vscode"], default="text")
    ap.add_argument("--compiler", help="Path to mkji compiler to also report compile errors")
    args = ap.parse_args(argv)

    files = collect_files(args.paths)
    all_diags: List[Diag] = []

    for f in files:
        src = read_text(f)
        if src is None:
            all_diags.append(Diag(f, 1, 1, "error", "cannot read file"))
            continue
        all_diags.extend(scan_source(f, src))
        if args.compiler:
            all_diags.extend(run_compiler(args.compiler, f))

    # de-duplicate identical diags
    uniq = []
    seen = set()
    for d in all_diags:
        key = (d.file, d.line, d.col, d.severity, d.message, d.source)
        if key not in seen:
            seen.add(key)
            uniq.append(d)
    all_diags = uniq

    if args.format == "json":
        print(json.dumps([asdict(d) for d in all_diags], ensure_ascii=False, indent=2))
    else:
        for d in all_diags:
            if args.format == "vscode":
                print(d.format_vscode())
            else:
                print(d.format_text())

    has_error = any(d.severity == "error" for d in all_diags)
    return 1 if has_error else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
