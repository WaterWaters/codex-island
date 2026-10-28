<p align="center">
  <img src="assets/banner.png" alt="Codex Island — aquatic cat and terminal prompt" width="960">
</p>

<h1 align="center">Codex Island</h1>

<p align="center">Codex と Claude Code の進み具合を、ひと目で。<br>現在の作業と回答待ちを知らせる、macOS ネイティブのステータスアイランド。</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-0B7285?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6%2B-F05138?style=flat-square" alt="Swift 6+">
  <img src="https://img.shields.io/badge/status-preview-64748B?style=flat-square" alt="Preview">
  <a href="https://github.com/WaterWaters/codex-island/actions/workflows/ci.yml"><img src="https://github.com/WaterWaters/codex-island/actions/workflows/ci.yml/badge.svg?branch=main" alt="macOS CI"></a>
  <a href="../LICENSE"><img src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <strong>日本語</strong>
</p>

<p align="center">
  <a href="#previews">プレビュー</a> · <a href="#features">特徴</a> · <a href="#getting-started">はじめる</a> · <a href="#privacy">プライバシー</a> · <a href="#documentation">ドキュメント</a>
</p>

Codex Island は、ローカルの Codex と Claude Code セッションのタイトルと作業状況を画面上部に表示します。対応が必要かを確認し、クリックすると表示中のサービスのデスクトップアプリを開けます。

**OpenAI および Anthropic とは提携していない独立プロジェクトです。** ローカルの Codex と Claude Code に対応する 0.x プレビュー版です。

<a id="previews"></a>
## アイランドの表示を見る

日常の 4 つの状態を、ノッチ付き MacBook と通常の外部ディスプレイで比較できます。上段にセッションのタイトル、下段に現在の作業を表示し、輪郭で状態を区別します。

画像は合成データを使ったネイティブ SwiftUI ビューのレンダリングで、現在の簡体字中国語 UI と素材がない場合の代替猫マークを表示しています。画面背景は説明用の構成であり、実際のデスクトップのスクリーンショットや実機検証の証拠ではありません。[プレビューの生成方法](assets/previews/README.md)。

| MacBook · ノッチ付き | 外部ディスプレイ · 通常画面 |
| :---: | :---: |
| <img src="assets/previews/running-notched.png" alt="ノッチ付き MacBook の作業中アイランド" width="440"><br><strong>作業中</strong><br>コマンドやツールの動作をひと目で確認。 | <img src="assets/previews/running-standard.png" alt="通常の外部ディスプレイの作業中アイランド" width="440"><br><strong>作業中</strong><br>コマンドやツールの動作をひと目で確認。 |
| <img src="assets/previews/needsInput-notched.png" alt="ノッチ付き MacBook の回答待ち表示" width="440"><br><strong>回答待ち</strong><br>あなたの回答が必要なときに、わかりやすく表示。 | <img src="assets/previews/needsInput-standard.png" alt="通常の外部ディスプレイの回答待ち表示" width="440"><br><strong>回答待ち</strong><br>あなたの回答が必要なときに、わかりやすく表示。 |
| <img src="assets/previews/blocked-notched.png" alt="ノッチ付き MacBook のエラー状態" width="440"><br><strong>作業が停止</strong><br>ターンの失敗を、独立したエラー状態で表示。 | <img src="assets/previews/blocked-standard.png" alt="通常の外部ディスプレイのエラー状態" width="440"><br><strong>作業が停止</strong><br>ターンの失敗を、独立したエラー状態で表示。 |
| <img src="assets/previews/idle-notched.png" alt="ノッチ付き MacBook のアイドル状態" width="440"><br><strong>アイドル</strong><br>Codex の起動中は、静かに画面に残ります。 | <img src="assets/previews/idle-standard.png" alt="通常の外部ディスプレイのアイドル状態" width="440"><br><strong>アイドル</strong><br>Codex の起動中は、静かに画面に残ります。 |

### Mini モード

通常の画面では上部中央に 44 × 22 pt の小さなカプセル、ノッチ付き画面ではノッチの外周に沿ったライトを表示します。メニューバーの **Mini モード**、または **設定 → 外観 → 表示モード** で切り替えます。ポインタを置くと状態を確認でき、クリックで表示中のサービスのデスクトップアプリを開きます。Mini では文字とペットを表示せず、フルモードのペットと高さの設定は保持します。タイトル非表示を有効にすると、ホバーと VoiceOver でもタイトルを隠します。

| ノッチ付き画面 | 通常画面 |
| :---: | :---: |
| <img src="assets/previews/mini-running-notched.png" alt="Mini · 作業中 · ノッチ付き画面" width="440"><br><strong>作業中</strong> | <img src="assets/previews/mini-running-standard.png" alt="Mini · 作業中 · 通常画面" width="440"><br><strong>作業中</strong> |
| <img src="assets/previews/mini-needsInput-notched.png" alt="Mini · 回答待ち · ノッチ付き画面" width="440"><br><strong>回答待ち</strong> | <img src="assets/previews/mini-needsInput-standard.png" alt="Mini · 回答待ち · 通常画面" width="440"><br><strong>回答待ち</strong> |
| <img src="assets/previews/mini-blocked-notched.png" alt="Mini · 作業が停止 · ノッチ付き画面" width="440"><br><strong>作業が停止</strong> | <img src="assets/previews/mini-blocked-standard.png" alt="Mini · 作業が停止 · 通常画面" width="440"><br><strong>作業が停止</strong> |
| <img src="assets/previews/mini-idle-notched.png" alt="Mini · アイドル · ノッチ付き画面" width="440"><br><strong>アイドル</strong> | <img src="assets/previews/mini-idle-standard.png" alt="Mini · アイドル · 通常画面" width="440"><br><strong>アイドル</strong> |

<a id="features"></a>
## ウインドウの切り替えを、少し減らす

- **タイトルと作業状況をまとめて表示。** 思考、コマンド、ファイル変更、ツールの動作をコンパクトな 2 行で確認できます。
- **回答が必要なときに通知。** 認識できた未回答の質問は輪郭の点滅で知らせ、エラーは別の表示で区別します。
- **macOS になじむ設計。** SwiftUI と AppKit を使用し、ノッチを避けた配置、メニューバー操作、「視差効果を減らす」に対応します。
- **好みに合わせて調整。** 色、高さ、表示、アニメーションを変更できます。中クリックで 30 秒間クリックを透過します。
- **あなたの Codex ペット。** 内蔵、ローカルのカスタム、ローカルにキャッシュ済みのクラウドペットを選べます。個人画像は同梱しません。素材がない場合は Codex でペットを表示してから再同期してください。[素材の読み取り元と制限](pet-animation.md)。
- **データは基本的にローカルで処理。** ローカル状態への読み取り専用アクセスを使い、アプリにテレメトリーやネットワークサービスはありません。

<a id="getting-started"></a>
## はじめる

**v0.9.0 で Claude Code に対応しました。** メニューバーまたは設定 → 接続で Codex、Claude、自動切り替えを選べます。既存の設定を保持し、標準は Codex のままです。

**プレビュー版：** [GitHub Releases](https://github.com/WaterWaters/codex-island/releases)。リリースの検証が成功すると、Universal DMG と ZIP が公開されます。[リリースガイド](releases.md)。

**ソースからビルド：** macOS 14 以降、Swift 6 以降、Xcode または Command Line Tools が必要です。実際のローカル状態を表示するには Codex または対応する Claude Code の起動方法が必要です。サードパーティーの Swift パッケージには依存しません。

プロジェクトのルートで実行します。

```bash
./Scripts/package_app.sh
open build/CodexIsland.app
```

起動後はメニューバーから操作できます。選択したサービスの接続状態に従って表示し、確認済みのアイドルセッションも表示を続けます。メニューバーで手動表示・非表示も切り替えられます。

v0.8.0 には、スキップできる初回ガイドと、一般・外観・接続・実験機能の設定が追加されています。接続ページには次の手順と、個人情報を除いた診断のコピーがあります。[初回ガイドと接続確認](getting-started.md)。

v0.8.0 には、タイトルの非表示、任意のログイン時起動、手動で有効にする ⌃⌥⌘I 表示切替、固定ディスプレイの再接続復元、標準・静か・高コントラストの外観もあります。設定はすぐに反映され、ログイン許可とショートカットの競合はシステムの結果を表示します。

> [!NOTE]
> 現在のアプリはローカル利用向けの ad-hoc 署名で、公証されていません。ビルド対象は現在の CPU アーキテクチャです。Apple Silicon / Swift 6.4 では検証済みですが、macOS 14 と Intel での実機動作は未検証です。

<a id="usage"></a>
## 使い方

| 操作 | 動作 |
| --- | --- |
| アイランドを左クリック | 表示中のサービスのデスクトップアプリを開く |
| アイランドを中クリック | 半透明になり、30 秒間クリックを透過する |
| メニューバーのメニューを開く | 表示・非表示、ペットの選択、外観の変更、状態とペットを個別に再同期 |
| 「視差効果を減らす」を有効化、またはアニメーションを一時停止 | 動きの少ない表示にする |

作業中は輪郭が動き、認識できた質問の回答待ちには入力待ちの色、エラーには赤色の点滅を使います。アイドル時は控えめな表示になります。ターンの完了を**未読結果がある状態とは扱いません**。

<a id="privacy"></a>
## セッションデータはローカルに

標準のデータソースは、現在のユーザーの `~/.codex/` 内のデータベースと進行中のセッションイベントを読み取ります。Codex のデータ変更、メッセージ送信、リクエストの承認、既読への変更は行いません。イベントはメモリー上で処理し、診断出力にはタイトルや会話内容を含めません。

**タイトルは初期状態で表示されます。** v0.8.0 では、アイランド・ホバー・VoiceOver のタイトルをまとめて隠せます。画面共有時はアイランド自体も非表示にできます。承認ボタンの認識は、初期状態では無効のオプション機能で、アクセシビリティ権限の許可が必要です。OS が与える権限は、このアプリが実行する読み取り専用の確認より広いものです。詳細は [セキュリティとプライバシー](../SECURITY.md) を参照してください。

<a id="compatibility"></a>
## 現在の対応範囲

| 機能 | 現在の範囲 |
| --- | --- |
| ローカルセッションのタイトル、作業状況、認識できた質問の回答待ち | ローカル履歴アダプターが対象とする範囲で利用可能 |
| 承認ボタンの認識 | 実験的機能。アクセシビリティ権限が必要。実際の承認カードでの検証は未完了 |
| 完全な未読状態、リモート・クラウドチャット、Codex ペットとの完全な状態一致 | 未対応 |
| すべてのフルスクリーン・Spaces の組み合わせ、ディスプレイ変更、長時間の性能 | 検証未完了 |

Codex の内部データ形式は変わる可能性があります。互換性がない場合は利用不可と表示し、アイドル状態と見なすことはありません。v0.7.3 以降は、起動時の環境変数 `CODEX_HOME` に指定した絶対パスを使用し、不正な指定は明示的にエラーとします。イベントの読み取りに失敗すると上限付きの間隔で再試行し、データベースで確認できた作業状況を保ちながら同期の制限を表示します。公開済みの v0.7.2 は `~/.codex/` を使用します。詳細は [ローカルデータソースの範囲](local-session-source.md) を参照してください。

### v0.9.0 の Claude Code 対応

メニューバーと接続設定で **Codex**、**Claude**、**自動切り替え**を選択できます。通常は 6 秒ごとに切り替え、回答待ちやエラーを優先し、ポインタを置くと一時停止します。アイランドと VoiceOver は表示中のサービス名を示します。Claude のクリックではデスクトップアプリを開き、ターミナルや特定のセッションは推測しません。

Claude はローカルの `~/.claude` のセッション登録と、上限付きのイベント投影を読み取ります。別のディレクトリは起動環境の `CLAUDE_CONFIG_DIR` に絶対パスで指定し、不正な指定はエラーになります。診断にタイトル、パス、セッション ID、メッセージ本文は含めません。`CodexIslandProbe --source all` で両方を確認できます。

記録済みの互換対象は Claude Code 2.1.309 の `claude-desktop-3p` です。CLI / IDE の登録範囲は未検証です。データの欠落、曖昧さ、読み取り失敗は利用不可または同期制限と表示し、完了を未読とは見なしません。ペットは引き続きローカル Codex の素材を使います。[Claude の範囲と制限](claude-session-source.md)。

<a id="development"></a>
## 開発

テスト用データを使うテストを実行します。

```bash
./Scripts/test.sh
```

実際の会話や個人の画像は不要です。インストール済みアプリの素材チェックと性能ベンチマークは、明示的に有効にして実行します。[貢献ガイド](../CONTRIBUTING.md) と [性能に関する説明](performance.md) を参照してください。

<details>
<summary>デモと診断</summary>

デモと明示される状態を使う、別のアプリをビルドします。

```bash
PREVIEW_STATE=needsInput ./Scripts/package_app.sh
open build/CodexIslandPreview.app
```

デモ状態：`running`、`needsInput`、`blocked`、`ready`、`idle`。

タイトルや会話内容を出力せず、集計した診断情報を確認できます。

```bash
./build/CodexIsland.app/Contents/MacOS/CodexIsland --diagnose
./build/CodexIsland.app/Contents/MacOS/CodexIslandProbe --watch 10
```

独自のデータ生成側を接続する場合は [明示的な状態ファイルの仕様](status-input.md) を参照してください。これは本プロジェクトの開発用インターフェースであり、Codex API ではありません。

</details>

<a id="documentation"></a>
## ドキュメント

アーキテクチャ、データソース、ペットのアニメーション、ベンチマーク、リリース確認は [ドキュメント一覧](README.md) から参照できます。技術ガイドは現在主に中国語で、プロジェクト紹介は上記の 4 言語で提供しています。v0.8.0 では、システム設定に従うほか、英語・簡体字中国語・繁体字中国語・日本語の UI を選択できます。

<a id="contributing"></a>
## 貢献

不具合報告、互換性の修正、ドキュメントの改善を歓迎します。PR を作成する前に [貢献ガイド](../CONTRIBUTING.md) を確認してください。合成テストデータを使い、診断データから機密情報を取り除いてください。README の各翻訳は英語版に合わせて更新します。方針は [翻訳のメンテナンス](README.md#readme-translations) にまとめています。

<a id="license"></a>
## 謝辞とライセンス

作者は **Water** です。水の猫を描いたロゴは、波とターミナルのプロンプトを組み合わせています。視覚的な方向性は [Atoll](https://github.com/Ebullioscopic/Atoll) を参考にしました。

プロジェクトのコード、ドキュメント、新しいブランド素材は [MIT](../LICENSE) で提供します。Codex の名称や実行時に読み込む第三者のペット素材は、それぞれの権利者に帰属します。[素材と商標に関する注意事項](../THIRD_PARTY_NOTICES.md) を参照してください。
