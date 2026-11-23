---
name: colab-notebook
description: Build Google Colab Studio inference notebooks with external .env validation, single-responsibility %%writefile cells, uv venv isolation, router separation, and companion README.html / http.rest.
---

# Colab Studio Notebook Standards

Execute standard Colab Studio scaffolding and validation via pre-built scripts in `scripts/`.

## Pre-Built Operations (`scripts/`)

| Operation | Invocation | Purpose |
|:---|:---|:---|
| `scaffold_colab_project` | `python3 scripts/scaffold_colab_project.py --dir <dir> --model-name <model>` | Generates `.env.example` and `http.rest` (`{{$dotenv ...}}` dynamic references). |
| `validate_colab_bundle` | `python3 scripts/validate_colab_bundle.py <dir> <notebook.ipynb>` | Validates Rule.13 (`no %%writefile .env`, no `google.colab.userdata`), JSON syntax, `%%writefile` Python AST, and companion files. |
| `install_llama_cpp` | `bash scripts/install_llama_cpp.sh` | Installs official `ggml-org/llama.cpp` Ubuntu x64 CUDA 13 prebuilt binaries under `/opt/llama.cpp` (no CMake source build). |

## Workflow Calls
1. `scaffold_colab_project(--dir, --model-name)` → create `.env.example` and `http.rest` (raw skeletons in `templates/`), then populate external `.env`.
2. Build `<name>.ipynb` following the 24-step layout (`nvidia-smi` & resource check → external `.env` validation → `apt-get` / `cloudflared` / `uv venv` → `%%writefile` `core/{config,logger,state,engine}.py` & `routers/{health,status,chat,models}.py` & `server.py` → Uvicorn launch → `/api/v1/status` polling → Cloudflare Tunnel → API test → `tail -f` logs).
3. Generate `README.html` (via `readme-html-skill`, Rule.11 / Rule.14 dual inline SVGs) and `http.rest` (all endpoints for local & tunnel).
4. `validate_colab_bundle(<dir>, <notebook.ipynb>)` → must pass before delivery.

## Implementation Constraints
- **External `.env` Only (Rule.13)**: Never use `%%writefile .env`, `google.colab.userdata`, or `os.getenv("KEY", "default")`. Halt if `TUNNEL_HOST`, `TUNNEL_PORT`, `TUNNEL_HOSTNAME`, `LLM_API_KEY`, or `MODEL_NAME` are missing; print `LLM_API_KEY` directly.
- **Isolation & No Source Build**: Use `UV_SYSTEM_PYTHON=0 uv venv --allow-existing --python {sys.executable} {VENV_DIR}` and run `{VENV_DIR}/bin/python` / `uvicorn`. For `llama.cpp`, use prebuilt CUDA wheels (`cu124` + `LD_LIBRARY_PATH`) or `install_llama_cpp()`.
- **Cells & Routers**: One task per cell; use `%%writefile <path>` (no Python string writes). Keep `server.py` thin (`include_router` only) and split `routers/{health,status,chat,models}.py`.
- **Resilience & Logging**: Catch model load exceptions into `ServerState` (`/api/v1/status`). Pre-free ports (`fuser -k -n tcp`, `pkill -9`), clean `/tmp` in `try-finally`, run `uv cache clean`, use quiet flags (`-qq`, `-q`, `-fsSL`, `PYTHONWARNINGS="ignore"`), and log requests with **JST (`UTC+9`)**, real client IP (`CF-Connecting-IP` → `X-Forwarded-For` → `client.host`), and 120-char input preview.

## Trigger & Exit Criteria
- **Trigger**: Creating, updating, or reviewing a Google Colab Studio inference notebook.
- **Exit Criteria**: `validate_colab_bundle(<dir>, <notebook.ipynb>)` exits `0` and `references/CHECKLIST.md` passes.

## Anti-Patterns
- Never use `%%writefile .env`, `google.colab.userdata`, `os.getenv(..., default)`, system `pip install`, or CMake `llama.cpp` source builds.
- Never write Python source files from string variables (`open().write()`); always use `%%writefile`.
