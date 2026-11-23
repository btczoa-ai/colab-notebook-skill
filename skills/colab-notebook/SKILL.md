---
name: colab-notebook
description: >-
  Google Colab 上で AI モデル推論エンジンやマイクロサービス Studio を構築・運用するノートブック作成規約と設計パターン。
  設定の外部化 (.env によるシークレット一元管理)、単一責務コードブロック原則、%%writefile による宣言的ファイル生成、
  API 単位のファイル分離、モデルロード/実行時エラーハンドリング、サーバー & トンネル非同期トレースログ出力などの標準ベストプラクティスを定義。
---

# Colab Studio Notebook Architecture & Design Standards

Google Colab 上で AI モデル（vLLM, llama.cpp, TTS, HyperFrames 等）の推論サーバーやマイクロサービス Studio ノートブックを開発・保守する厳格な標準規約です。

---

## 1. コア原則 (Core Principles)

### 原則 1: 単一責務コードブロック (1セル＝1処理)
- 相互に関係のない処理を同一セルに混在させることを禁止する。
- 設定、ロガー、状態管理、ルーター、メインサーバーはセルを1つずつ完全に分けて記述する。

### 原則 2: 外部 `.env` への完全依存（Colab 内生成・デフォルト値フォールバック厳禁）
- **ペアリング納品**: ノートブック（`.ipynb`）作成時は、同一ディレクトリ内に環境変数を定義した外部 `.env` を必ず同時作成する。
- **内部生成の禁止**: ノートブック内での `%%writefile .env` 等による自前生成を禁止（ユーザーが事前にアップロードした外部 `.env` のみに依存）。
- **デフォルト値フォールバックの禁止**: `os.getenv("KEY", "default")` のハードコードを禁止。すべて `.env` から直接取得する。
- **4大標準環境変数の定義と検証**:
  - `TUNNEL_HOST`, `TUNNEL_PORT`, `TUNNEL_HOSTNAME`, `LLM_API_KEY`（および `MODEL_NAME` 等）の必須項目が未定義・空文字の場合は即座に Halt（エラー停止）。
  - 設定読み込みセルで `LLM_API_KEY` の値を直接コンソールへ出力（マスク禁止）。
- **Colab Secret API の廃止**: `google.colab.userdata` は使用せず、`python-dotenv` で外部 `.env` から注入。

### 原則 3: API エンドポイントごとのファイル分離 (`routers/`)
- 単一 `server.py` への全エンドポイント記述を禁止。
  - `routers/health.py`: `GET /healthz`
  - `routers/status.py`: `GET /api/v1/status`（モデル状態、VRAM情報、例外スタックトレース）
  - `routers/chat.py`: `POST /v1/chat/completions`（OpenAI互換、ストリーミング、`<think>` タグ対応）
  - `routers/models.py`: `GET /v1/models`（OpenAI仕様準拠）
  - `routers/<feature>.py`: 各専用推論ロジック
  - `server.py`: 各ルーターの `include_router` のみを行う薄いエントリーポイント。

### 原則 4: モデルロード & 実行時エラーの完全ハンドリング
- モデル初期化は `try-except` で例外捕捉し、スタックトレースを状態管理（`ServerState`）に保持。サーバーをクラッシュさせない。
- クライアント側は `/api/v1/status` をポーリングし、`model_status == 'ready'`（または `failed`）になるまで待機。

### 原則 5: 隔離された仮想環境 (`uv venv`) への依存インストール
- Colab ホストのシステム Python への `!pip install` を**厳格に禁止**。
- `current_py = sys.executable` を取得し、`!UV_SYSTEM_PYTHON=0 uv venv --allow-existing --python {current_py} {VENV_DIR}` で独立環境を作成。
- 依存関係は `!uv pip install --python {VENV_DIR}/bin/python ...` で導入し、実行も `{VENV_DIR}/bin/python` または `{VENV_DIR}/bin/uvicorn` を明示。

### 原則 6: `%%writefile` による宣言的ファイル生成（Python 変数代入禁止）
- Python 文字列変数へのコード代入や `open().write()` での書き出しを禁止。コードセルの1行目に必ず `%%writefile <出力先パス>` を記述。

### 原則 7: 既存プロセスの事前強制解放（起動の冪等性保証）
- サーバー・トンネル起動セルの冒頭で対象ポート・プロセスを解放（`!fuser -k -n tcp {PORT} 2>/dev/null || true`、`!pkill -9 -f uvicorn || true`、`!pkill -9 -f cloudflared || true`）。

### 原則 8: 一時領域・キャッシュの自動クリーンアップ
- 一時ファイルは `try-finally` 内で確実に削除（`shutil.rmtree` / `os.unlink`）。`!uv cache clean` や古いログの自動破棄を組み込む。

### 原則 9: 推論リクエストの JST 日時・実 IP・入力プレビュー出力規約
- **JST 固定**: `datetime.timezone(datetime.timedelta(hours=9))` で `YYYY-MM-DD HH:MM:SS JST` を出力（UTC 禁止）。
- **実 IP 特定**: `CF-Connecting-IP` → `X-Forwarded-For` → `request.client.host` の順。
- **入力プレビュー**: 最新 `user` 入力を1行（最大120文字）で表示。
  ```text
  [INFERENCE REQUEST] [2026-11-20 21:40:00 JST] IP: 203.0.113.195 | Input: "プロジェクトの概要を教えて" | msgs: 2, stream: True
  [INFERENCE COMPLETED] [2026-11-20 21:40:02 JST] IP: 203.0.113.195 | Tokens: 128 | Duration: 1.85s
  ```

---

## 2. ビルド・ランタイム規約（ソースビルド禁止）

### 2.1. 事前環境ダンプ規約
- ノートブック冒頭で OS (`cat /etc/os-release`)、Python (`python3 --version`)、CUDA/GPU (`nvidia-smi`)、推論エンジンのバージョンを出力。

### 2.2. `llama.cpp` プリビルドバイナリ / wheel の採用（厳守）
Colab 上での CMake ソースビルドは禁止。以下のいずれかを採用すること。
1. **公式ネイティブバイナリ (`llama-server`)**:
   - `ggml-org/llama.cpp` 公式 GitHub Releases から環境適合バイナリを取得し `/opt/llama.cpp` へ展開、`/usr/local/bin/` へリンク（参考: `scripts/install_llama_cpp.sh`）。
2. **プリビルド wheel (`llama-cpp-python[server]`)**:
   - `--extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu124` で導入。`nvidia-cuda-runtime-cu12` / `nvidia-cublas-cu12` を追加し、`LD_LIBRARY_PATH` を設定。

### 2.3. リアルタイムストリーミング & 冗長ログ抑制
- **ストリーミング**: `subprocess.Popen` を用い、1行ずつ `print(line, end="", flush=True)` へ流すヘルパー（`run_stream` 等）を使用。
- **抑制フラグ**: `apt-get -qq`、`pip -q`、`curl -fsSL`、`git -q`、`PYTHONWARNINGS="ignore"` を付与。

---

## 3. 標準ノートブック構造 (24ステップ・テンプレート)

```text
Cell 01 [GPU確認]: !nvidia-smi
Cell 02 [システムリソース確認]: !free -h & !df -h
Cell 03 [外部 .env 検証 & 読み込み]: 外部 .env 存在確認、必須環境変数バリデーション
Cell 04 [OSパッケージ導入]: curl, psmisc 等の apt-get インストール
Cell 05 [cloudflared導入]: Cloudflare Tunnel CLI バイナリ配備
Cell 06 [uv仮想環境初期化]: uv 導入と独立 .venv の初期化
Cell 07 [Pythonライブラリ導入]: uv pip で .venv 配下に必要なライブラリをインストール
Cell 08 [ディレクトリ初期化]: core/, routers/, logs/ 作成
Cell 09 [core/config.py]: %%writefile による外部 .env 読み込み・APIキー検証モジュール
Cell 10 [core/logger.py]: %%writefile による非同期トレースロガーモジュール
Cell 11 [core/state.py]: %%writefile によるサーバー状態・エラー履歴・GPUメトリクス
Cell 12 [core/engine.py]: %%writefile による推論エンジンの安全な非同期初期化
Cell 13 [routers/health.py]: %%writefile による GET /healthz
Cell 14 [routers/status.py]: %%writefile による GET /api/v1/status
Cell 15 [routers/chat.py]: %%writefile による POST /v1/chat/completions
Cell 16 [routers/models.py]: %%writefile による GET /v1/models
Cell 17 [server.py]: %%writefile による FastAPI メインアプリケーション結合
Cell 18 [バックグラウンド起動]: 既存プロセスの事前解放と Uvicorn 起動
Cell 19 [ロード待機ループ]: /api/v1/status をポーリングし準備完了待機
Cell 20 [Cloudflare Tunnel起動]: 既存トンネル解放と公開 URL 発行
Cell 21 [ステータスAPI検証]: ステータス疎通確認
Cell 22 [推論テスト]: OpenAI 互換リクエストの実行とレスポンス確認
Cell 23 [トレースログ監視]: サーバー & トンネルログのリアルタイム統合表示 (tail -f)
```

---

## 4. 同梱ファイル作成要件（厳守）

ノートブック（`.ipynb`）および `.env` と同一ディレクトリに、以下2ファイルを必ず作成すること。

1. **`README.html`**:
   - `readme-html-skill`（Rule.11 / Rule.14 準拠）による完全自己完結型技術仕様書。
   - ハイレベル（論理機能）＆ インフラレベル（物理・ネットワーク）の2種類のインライン SVG 図解を必須収録。
2. **`http.rest`**:
   - VS Code REST Client 用の疎通・推論テストファイル。
   - 全エンドポイント（`/healthz`, `/api/v1/status`, `/v1/models`, `/v1/chat/completions` 等）の Local / Tunnel 経由テストを網羅。
   - **ハードコード厳禁**: すべての変数（URL、キー、ポート）は同一ディレクトリの `.env` から `{{$dotenv <KEY>}}` で動的参照。
     ```http
     @localUrl = http://127.0.0.1:{{$dotenv PORT}}
     @tunnelUrl = {{$dotenv TUNNEL_URL}}
     @apiKey = {{$dotenv API_KEY}}
     ```
