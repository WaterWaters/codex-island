<p align="center">
  <img src="assets/banner.png" alt="Codex Island — aquatic cat and terminal prompt" width="960">
</p>

<h1 align="center">Codex Island</h1>

<p align="center">Codex の進み具合を、ひと目で。<br>現在の作業と回答待ちを知らせる、macOS ネイティブのステータスアイランド。</p>

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
  <a href="#features">特徴</a> · <a href="#getting-started">はじめる</a> · <a href="#privacy">プライバシー</a> · <a href="#documentation">ドキュメント</a>
</p>

Codex Island は、現在のローカルセッションのタイトルと作業状況を画面上部に表示します。Codex が作業中か、あなたの回答を待っているかを確認し、アイランドをクリックして Codex に戻れます。

**OpenAI とは提携していない独立プロジェクトです。** 現在は、ローカルの Codex との互換性を前提とした 0.x プレビュー版です。

<a id="features"></a>
## ウインドウの切り替えを、少し減らす

- **タイトルと作業状況をまとめて表示。** 思考、コマンド、ファイル変更、ツールの動作をコンパクトな 2 行で確認できます。
- **回答が必要なときに通知。** 認識できた未回答の質問は輪郭の点滅で知らせ、エラーは別の表示で区別します。
- **macOS になじむ設計。** SwiftUI と AppKit を使用し、ノッチを避けた配置、メニューバー操作、「視差効果を減らす」に対応します。
- **好みに合わせて調整。** 色、高さ、表示、アニメーションを変更できます。中クリックで 30 秒間クリックを透過します。
- **好みのペットも選択可能。** システムアイコン、またはインストール済み Codex の内蔵ペットを使用できます。個人のペット画像は同梱しません。
- **データは基本的にローカルで処理。** ローカル状態への読み取り専用アクセスを使い、アプリにテレメトリーやネットワークサービスはありません。

<a id="getting-started"></a>
## はじめる

**プレビュー版：** [GitHub Releases](https://github.com/WaterWaters/codex-island/releases)。リリースの検証が成功すると、Universal DMG と ZIP が公開されます。[リリースガイド](releases.md)。

**ソースからビルド：** macOS 14 以降、Swift 6 以降、Xcode または Command Line Tools が必要です。実際のローカル状態を表示するには Codex をインストールしてください。サードパーティーの Swift パッケージには依存しません。

プロジェクトのルートで実行します。

```bash
./Scripts/package_app.sh
open build/CodexIsland.app
```

起動後はメニューバーから操作できます。Codex の起動中はアイドル状態でもアイランドが表示され、Codex を終了すると非表示になります。メニューバーから手動で表示・非表示を切り替えることもできます。

> [!NOTE]
> 現在のアプリはローカル利用向けの ad-hoc 署名で、公証されていません。ビルド対象は現在の CPU アーキテクチャです。Apple Silicon / Swift 6.4 では検証済みですが、macOS 14 と Intel での実機動作は未検証です。

<a id="usage"></a>
## 使い方

| 操作 | 動作 |
| --- | --- |
| アイランドを左クリック | Codex を開く |
| アイランドを中クリック | 半透明になり、30 秒間クリックを透過する |
| メニューバーのメニューを開く | 表示・非表示、ペットの選択、外観の変更、再同期 |
| 「視差効果を減らす」を有効化、またはアニメーションを一時停止 | 動きの少ない表示にする |

作業中は輪郭が動き、認識できた質問の回答待ちには入力待ちの色、エラーには赤色の点滅を使います。アイドル時は控えめな表示になります。ターンの完了を**未読結果がある状態とは扱いません**。

<a id="privacy"></a>
## セッションデータはローカルに

標準のデータソースは、現在のユーザーの `~/.codex/` 内のデータベースと進行中のセッションイベントを読み取ります。Codex のデータ変更、メッセージ送信、リクエストの承認、既読への変更は行いません。イベントはメモリー上で処理し、診断出力にはタイトルや会話内容を含めません。

**タイトルは画面と VoiceOver に表示されます。** 画面共有時は必要に応じてアイランドを非表示にしてください。承認ボタンの認識は、初期状態では無効のオプション機能で、アクセシビリティ権限の許可が必要です。OS が与える権限は、このアプリが実行する読み取り専用の確認より広いものです。詳細は [セキュリティとプライバシー](../SECURITY.md) を参照してください。

<a id="compatibility"></a>
## 現在の対応範囲

| 機能 | 現在の範囲 |
| --- | --- |
| ローカルセッションのタイトル、作業状況、認識できた質問の回答待ち | ローカル履歴アダプターが対象とする範囲で利用可能 |
| 承認ボタンの認識 | 実験的機能。アクセシビリティ権限が必要。実際の承認カードでの検証は未完了 |
| 完全な未読状態、リモート・クラウドチャット、Codex ペットとの完全な状態一致 | 未対応 |
| すべてのフルスクリーン・Spaces の組み合わせ、ディスプレイ変更、長時間の性能 | 検証未完了 |

Codex の内部データ形式は変わる可能性があります。互換性がない場合は利用不可と表示し、アイドル状態と見なすことはありません。現在の実行ファイルは `~/.codex/` を使い、`CODEX_HOME` による上書きには対応していません。詳細は [ローカルデータソースの範囲](local-session-source.md) を参照してください。

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

アーキテクチャ、データソース、ペットのアニメーション、ベンチマーク、リリース確認は [ドキュメント一覧](README.md) から参照できます。技術ガイドは現在主に中国語で、プロジェクト紹介は上記の 4 言語で提供しています。README の翻訳は、アプリ UI の対応言語を追加するものではありません。

<a id="contributing"></a>
## 貢献

不具合報告、互換性の修正、ドキュメントの改善を歓迎します。PR を作成する前に [貢献ガイド](../CONTRIBUTING.md) を確認してください。合成テストデータを使い、診断データから機密情報を取り除いてください。README の各翻訳は英語版に合わせて更新します。方針は [翻訳のメンテナンス](README.md#readme-translations) にまとめています。

<a id="license"></a>
## 謝辞とライセンス

作者は **Water** です。水の猫を描いたロゴは、波とターミナルのプロンプトを組み合わせています。視覚的な方向性は [Atoll](https://github.com/Ebullioscopic/Atoll) を参考にしました。

プロジェクトのコード、ドキュメント、新しいブランド素材は [MIT](../LICENSE) で提供します。Codex の名称や実行時に読み込む第三者のペット素材は、それぞれの権利者に帰属します。[素材と商標に関する注意事項](../THIRD_PARTY_NOTICES.md) を参照してください。
