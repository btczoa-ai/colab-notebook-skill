# colab-notebook-skill

`colab-notebook` スキルを別 PC やチーム環境に `npx skills add` で 1 コマンド導入するための配布用 Git リポジトリです。

---

## 概要

Google Colab 上で AI モデル（vLLM, Ollama, TTS, HyperFrames 等）の推論サーバーやマイクロサービス Studio ノートブックを開発・保守する際の厳格な標準規約・設計パターンです。

* **単一責務コードブロック**: 1セル＝1処理、設定・ロガー・APIルーターの生成セルを完全分離。
* **設定の完全外部化 (`.env` 一元管理)**: ベンダーロックインを招く Colab Secrets API を廃止し、4大標準環境変数（`TUNNEL_HOST`, `TUNNEL_PORT`, `TUNNEL_HOSTNAME`, `LLM_API_KEY`）を `.env` で厳格管理。設定読み込みセルでは `LLM_API_KEY` を直接コンソール出力。
* **API エンドポイント分離 & モデル一覧標準化**: `routers/` 配下での疎結合な設計（health, status, chat 等）。OpenAI 仕様を満たす `routers/models.py` (`GET /v1/models`) の実装を標準化。
* **モデルロード & 実行時エラーの完全ハンドリング**: サーバーを落とさず状態を保持・監視可能。
* **サーバー & Cloudflare Tunnel ログの非同期出力**: トンネル接続状態やサーバー I/O を Colab コンソールへリアルタイム出力。
* **隔離仮想環境 (`uv venv`)**: Colab OS グローバル Python の汚染を厳禁とし、独立 `.venv` 環境内にのみ依存パッケージをインストール。
* **`%%writefile` による宣言的ファイル生成**: Python 変数による文字列代入書き込みを禁止し、セル先頭の `%%writefile` で完全なシンタックスハイライト・保守性を担保。
* **既存プロセスの事前強制解放（冪等性）**: サーバー・トンネル起動前の `fuser -k` や `pkill` により、セル再実行時のポート重複エラー (`Address already in use`) を根絶。
* **一時領域 & キャッシュの自動クリーンアップ**: API 処理完了後の一時ファイル削除（`try-finally`）や `uv cache clean` により Colab ディスクの枯渇（Disk Full）を防止。
* **推論リクエスト詳細コンソール出力（JST日時 / 実訪問元IP / 入力プレビュー）**: Colab デフォルトの UTC を禁止し、日本標準時（JST）固定・Cloudflare 実 IP（`CF-Connecting-IP`）・入力テキストのプレビューを推論時にリアルタイム出力。

---

## インストール方法

### 1. GitHub リポジトリから直接インストール
```bash
npx skills add btczoa/colab-notebook-skill
```

または明示的にスキル名を指定する場合：
```bash
npx skills add btczoa/colab-notebook-skill --skill colab-notebook
```

### 2. ローカル環境からの検証・追加
```bash
npx skills add ./path/to/colab-notebook-skill
```

---

## インストール後の確認

```bash
# スキル一覧の確認
npx skills list

# スキルの実行確認
npx skills run colab-notebook
```

---

## ディレクトリ構成

```text
colab-notebook-skill/
├── README.md
├── skill.json                     # スキル定義マニフェスト
├── SKILL.md                       # ルート定義
└── skills/
    └── colab-notebook/            # スキル本体
        └── SKILL.md               # 24ステップ構成・設計規約定義
```
