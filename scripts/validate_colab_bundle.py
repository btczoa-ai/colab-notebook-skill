#!/usr/bin/env python3
"""Validate Colab Studio notebook bundle: Rule.13, JSON syntax, %%writefile AST, and companion files."""

from __future__ import annotations

import ast
import json
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print("Usage: validate_colab_bundle.py <project_dir> <notebook.ipynb>", file=sys.stderr)
        return 1

    base = Path(sys.argv[1]).resolve()
    nb_path = base / sys.argv[2]
    nb = json.loads(nb_path.read_text(encoding="utf-8"))
    assert nb.get("nbformat") == 4, "Notebook must be nbformat 4"

    for idx, cell in enumerate(nb.get("cells", [])):
        if cell.get("cell_type") != "code":
            continue
        src = "".join(cell.get("source", []))
        assert not src.lstrip().startswith("%%writefile .env"), f"Cell {idx} violates Rule.13 (%%writefile .env)"
        assert "google.colab.userdata" not in src, f"Cell {idx} uses forbidden google.colab.userdata"
        if src.startswith("%%writefile ") and src.splitlines()[0].strip().endswith(".py"):
            ast.parse("\n".join(src.splitlines()[1:]))

    for req_file in ["README.html", "http.rest", ".env", ".env.example"]:
        assert (base / req_file).is_file(), f"Missing required file: {req_file}"

    print(f"[OK] Validated Colab bundle: {nb_path} ({len(nb['cells'])} cells)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
