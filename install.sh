#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="colab-notebook"
REPO_RAW_BASE="https://raw.githubusercontent.com/btczoa/colab-notebook-skill/main"
REPO_RAW_URL="${REPO_RAW_BASE}/SKILL.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. SKILL.md および scripts/ の取得元決定（ローカル実行 or curl ワンライナー実行）
TMP_DIR=""
cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

if [[ -f "${SCRIPT_DIR}/SKILL.md" ]]; then
  SRC_SKILL="${SCRIPT_DIR}/SKILL.md"
  SRC_LLAMA_SCRIPT="${SCRIPT_DIR}/scripts/install_llama_cpp.sh"
else
  TMP_DIR="$(mktemp -d)"
  SRC_SKILL="${TMP_DIR}/SKILL.md"
  SRC_LLAMA_SCRIPT="${TMP_DIR}/install_llama_cpp.sh"
  echo "Downloading SKILL.md and scripts from GitHub..."
  curl -fsSL "${REPO_RAW_URL}" -o "${SRC_SKILL}"
  curl -fsSL "${REPO_RAW_BASE}/scripts/install_llama_cpp.sh" -o "${SRC_LLAMA_SCRIPT}" || true
fi

# 2. スキル展開先エージェントの定義
declare -A AGENT_SKILL_DIRS=(
  ["antigravity"]="${HOME}/.gemini/antigravity-cli/skills/${SKILL_NAME}"
  ["gemini"]="${HOME}/.gemini/skills/${SKILL_NAME}"
  ["claude"]="${HOME}/.claude/skills/${SKILL_NAME}"
  ["codex"]="${HOME}/.codex/skills/${SKILL_NAME}"
)

declare -A AGENT_RULE_FILES=(
  ["antigravity"]="${HOME}/.gemini/AGENTS.md"
  ["gemini"]="${HOME}/.gemini/GEMINI.md"
  ["claude"]="${HOME}/.claude/CLAUDE.md"
  ["codex"]="${HOME}/.codex/AGENTS.md"
)

RULE_START="<!-- colab-notebook-skill:start -->"
RULE_END="<!-- colab-notebook-skill:end -->"

read -r -d '' RULE_BLOCK << 'EOF' || true
<!-- colab-notebook-skill:start -->
## Colab Notebook Standard (`colab-notebook`)
When creating, editing, or reviewing Google Colab / Jupyter notebooks (`.ipynb`) for AI inference servers or Studio workflows, you MUST read and strictly follow the `colab-notebook` skill (`SKILL.md`) before writing any code:
- Single-responsibility cells, external `.env` only (no `%%writefile .env`, no default fallbacks), `uv venv` isolation, `%%writefile` declarative generation, pre-launch port/process cleanup, and quiet/warning-suppressed command execution.
<!-- colab-notebook-skill:end -->
EOF

upsert_rule() {
  local rule_file="$1"
  mkdir -p "$(dirname "${rule_file}")"
  if [[ ! -f "${rule_file}" ]]; then
    printf "%s\n" "${RULE_BLOCK}" > "${rule_file}"
    echo "  + Created rule file: ${rule_file}"
    return
  fi

  python3 - "$rule_file" "$RULE_START" "$RULE_END" "$RULE_BLOCK" << 'PYEOF'
import sys
from pathlib import Path

path = Path(sys.argv[1])
start, end, block = sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text(encoding="utf-8")

if start in text and end in text:
    s_idx = text.index(start)
    e_idx = text.index(end, s_idx) + len(end)
    new_text = text[:s_idx] + block + text[e_idx:]
else:
    sep = "\n\n" if text and not text.endswith("\n\n") else ("\n" if text and not text.endswith("\n") else "")
    new_text = text + sep + block + "\n"

path.write_text(new_text, encoding="utf-8")
PYEOF
  echo "  + Updated rule file: ${rule_file}"
}

installed=0
for agent in antigravity gemini claude codex; do
  skill_dir="${AGENT_SKILL_DIRS[$agent]}"
  agent_root="$(dirname "$(dirname "${skill_dir}")")"

  if [[ -d "${agent_root}" ]]; then
    mkdir -p "${skill_dir}"
    cp "${SRC_SKILL}" "${skill_dir}/SKILL.md"
    if [[ -f "${SRC_LLAMA_SCRIPT}" ]]; then
      mkdir -p "${skill_dir}/scripts"
      cp "${SRC_LLAMA_SCRIPT}" "${skill_dir}/scripts/install_llama_cpp.sh"
      chmod +x "${skill_dir}/scripts/install_llama_cpp.sh"
    fi
    echo "[${agent}] Installed skill -> ${skill_dir}/SKILL.md"
    upsert_rule "${AGENT_RULE_FILES[$agent]}"
    installed=$((installed + 1))
  fi
done

if [[ "${installed}" -eq 0 ]]; then
  echo "No supported agent directories found under ${HOME} (.gemini, .claude, .codex)."
  exit 1
fi

echo "Done! Installed colab-notebook skill & rules to ${installed} agent(s)."

if ! command -v colab >/dev/null 2>&1; then
  echo ""
  echo "[Optional] 'colab' CLI was not found."
  echo "  If you want agents to launch/operate Google Colab VMs directly, install the Colab CLI and authenticate."
fi
