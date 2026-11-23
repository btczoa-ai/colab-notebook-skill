# Acceptance Checklist (`colab-notebook`)

- [ ] `python3 scripts/validate_colab_bundle.py <dir> <notebook.ipynb>` exits `0`.
- [ ] Rule.13: External `.env` only (no `%%writefile .env`, no `google.colab.userdata`, no default fallbacks).
- [ ] Isolated `uv venv` (`/tmp/.venv`); no system `pip install`.
- [ ] `server.py` thin (`include_router` only); `routers/{health,status,chat,models}.py` separated.
- [ ] `README.html` (Rule.11 / Rule.14) and `http.rest` (`{{$dotenv ...}}`) present.
