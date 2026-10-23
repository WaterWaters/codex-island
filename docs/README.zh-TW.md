<p align="center">
  <img src="assets/banner.png" alt="Codex Island — aquatic cat and terminal prompt" width="960">
</p>

<h1 align="center">Codex Island</h1>

<p align="center">Codex 進度，一眼掌握。<br>原生 macOS 狀態島，讓目前活動、待回答的問題與小小陪伴留在螢幕一角。</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-0B7285?style=flat-square" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6%2B-F05138?style=flat-square" alt="Swift 6+">
  <img src="https://img.shields.io/badge/status-preview-64748B?style=flat-square" alt="Preview">
  <a href="https://github.com/WaterWaters/codex-island/actions/workflows/ci.yml"><img src="https://github.com/WaterWaters/codex-island/actions/workflows/ci.yml/badge.svg?branch=main" alt="macOS CI"></a>
  <a href="../LICENSE"><img src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="../README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <strong>繁體中文</strong> · <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <a href="#previews">介面預覽</a> · <a href="#features">功能特色</a> · <a href="#getting-started">快速開始</a> · <a href="#privacy">隱私</a> · <a href="#documentation">文件</a>
</p>

Codex Island 將目前本機工作階段的標題與活動放在螢幕頂端。工作進行到哪一步、什麼時候需要你回答，一眼就能看到；點擊狀態島即可回到 Codex。

**獨立專案，與 OpenAI 無關聯。** 目前為以本機 Codex 相容性為基礎的 0.x 預覽版。

<a id="previews"></a>
## 看看狀態島的樣子

四種日常狀態，分別展示在 MacBook 瀏海螢幕與一般外接螢幕上。工作階段標題在上、目前活動在下，不同狀態使用清楚可辨的輪廓提示。

下圖以合成內容與原生 SwiftUI 視圖繪製，展示目前的簡體中文介面與缺少素材時的備用貓圖形；螢幕背景為示意構圖，並非桌面截圖或硬體驗收證據。[預覽產生方式](assets/previews/README.md)。

| MacBook · 瀏海螢幕 | 外接顯示器 · 一般螢幕 |
| :---: | :---: |
| <img src="assets/previews/running-notched.png" alt="瀏海螢幕上的工作中狀態島" width="440"><br><strong>工作中</strong><br>一眼查看指令與工具活動。 | <img src="assets/previews/running-standard.png" alt="一般外接螢幕上的工作中狀態島" width="440"><br><strong>工作中</strong><br>一眼查看指令與工具活動。 |
| <img src="assets/previews/needsInput-notched.png" alt="瀏海螢幕上的待回答提示" width="440"><br><strong>需要你</strong><br>需要回答時，給你清楚的提示。 | <img src="assets/previews/needsInput-standard.png" alt="一般外接螢幕上的待回答提示" width="440"><br><strong>需要你</strong><br>需要回答時，給你清楚的提示。 |
| <img src="assets/previews/blocked-notched.png" alt="瀏海螢幕上的工作受阻狀態" width="440"><br><strong>工作受阻</strong><br>回合失敗時，使用獨立的錯誤狀態。 | <img src="assets/previews/blocked-standard.png" alt="一般外接螢幕上的工作受阻狀態" width="440"><br><strong>工作受阻</strong><br>回合失敗時，使用獨立的錯誤狀態。 |
| <img src="assets/previews/idle-notched.png" alt="瀏海螢幕上的閒置狀態島" width="440"><br><strong>閒置</strong><br>Codex 開著時，安靜留在視線裡。 | <img src="assets/previews/idle-standard.png" alt="一般外接螢幕上的閒置狀態島" width="440"><br><strong>閒置</strong><br>Codex 開著時，安靜留在視線裡。 |

<a id="features"></a>
## 少切換幾次視窗

- **標題與活動，一起呈現。** 兩行資訊顯示思考、指令、檔案變更與工具活動。
- **需要你時，給個提示。** 已辨識的待回答問題觸發脈動，錯誤使用獨立的視覺狀態。
- **融入 macOS。** SwiftUI 與 AppKit 原生介面，避開瀏海，支援選單列控制與減少動態效果。
- **依你的習慣調整。** 自訂顏色、高度、顯示與動畫；按滑鼠中鍵即可暫時穿透 30 秒。
- **你的 Codex 小夥伴。** 支援內建、本機自訂與本機已快取的雲端寵物，不隨套件附帶個人圖片。雲端素材缺少時，請在 Codex 查看該寵物後重新同步。[素材來源與限制](pet-animation.md)。
- **預設只在本機運作。** 唯讀存取本機狀態，應用程式沒有遙測或網路服務。

<a id="getting-started"></a>
## 快速開始

**預覽版安裝套件：** [GitHub Releases](https://github.com/WaterWaters/codex-island/releases)。發布流程檢查通過後，會提供 universal DMG 與 ZIP。[發布指南](releases.md)。

**從原始碼建置：** 需要 macOS 14+、Swift 6+，以及 Xcode 或 Command Line Tools。即時本機狀態需要安裝 Codex。專案沒有第三方 Swift 套件相依性。

在專案根目錄執行：

```bash
./Scripts/package_app.sh
open build/CodexIsland.app
```

啟動後可在選單列找到應用程式。Codex 執行期間，狀態島在閒置時仍會保留；Codex 結束後隱藏。也可以從選單列手動顯示或隱藏。

v0.7.3 之後的原始碼新增可略過的首次引導，以及一般 / 外觀 / 連線 / 實驗功能四組設定。連線頁提供下一步與去識別化診斷複製；這些新增功能尚未包含於 v0.7.3 下載套件。[首次使用與連線檢查](getting-started.md)。

> [!NOTE]
> 目前應用程式套件僅使用本機 ad-hoc 簽章，尚未公證，預設建置目前 CPU 架構。已驗證 Apple Silicon / Swift 6.4；macOS 14 與 Intel 的實機執行仍待驗收。

<a id="usage"></a>
## 日常使用

| 操作 | 效果 |
| --- | --- |
| 按左鍵點擊狀態島 | 開啟 Codex |
| 按中鍵點擊狀態島 | 半透明，並讓滑鼠穿透 30 秒 |
| 開啟選單列選單 | 顯示或隱藏、切換寵物、調整外觀，分別重新同步狀態與寵物 |
| 開啟減少動態效果，或暫停動畫 | 保持安靜的顯示效果 |

工作時輪廓流動，已辨識的問題等待使用介入色脈動，錯誤使用紅色脈動，閒置時進入低亮度狀態。回合完成**不等於**存在未讀結果。

<a id="privacy"></a>
## 工作階段資料留在本機

預設來源唯讀存取目前使用者的 `~/.codex/` 資料庫與活動工作階段事件，不修改 Codex 資料，不傳送聊天、核准請求或標記已讀。事件解析在記憶體中處理，診斷輸出不包含工作階段標題或聊天內容。

**標題會出現在螢幕與 VoiceOver 中。** 分享螢幕前可依需要隱藏狀態島。核准按鈕辨識是預設關閉的選用輔助使用功能，需要使用者自行授權；系統權限比應用程式實際執行的唯讀檢查範圍更廣。詳見 [安全與隱私](../SECURITY.md)。

<a id="compatibility"></a>
## 目前能力與限制

| 能力 | 目前範圍 |
| --- | --- |
| 本機工作階段標題、活動、已辨識的問答等待 | 在本機歷史適配器涵蓋範圍內可用 |
| 核准按鈕辨識 | 實驗功能；需主動授權輔助使用；真實核准卡片驗收尚未完成 |
| 完整未讀、遠端 / 雲端聊天、與 Codex 寵物完全同源 | 不支援 |
| 所有全螢幕 / Space 組合、顯示器變更、長時間效能 | 尚未完整驗收 |

Codex 的內部資料格式可能改變。來源不相容時會顯示無法使用，不會假裝閒置。v0.7.3 起支援啟動環境中絕對目錄的 `CODEX_HOME`，無效覆寫會明確報錯；事件失敗會採用有上限的退避重試，保留資料庫已確認的活動並顯示同步受限。已發布的 v0.7.2 讀取 `~/.codex/`。詳見 [本機來源限制](local-session-source.md)。

<a id="development"></a>
## 開發

執行以測試資料為基礎的測試：

```bash
./Scripts/test.sh
```

測試不需要真實聊天或個人圖片。本機安裝版素材檢查與效能基準需明確開啟，方式見 [貢獻指南](../CONTRIBUTING.md) 與 [效能說明](performance.md)。

<details>
<summary>示範與診斷</summary>

建置獨立應用程式，使用明確標示為示範的狀態：

```bash
PREVIEW_STATE=needsInput ./Scripts/package_app.sh
open build/CodexIslandPreview.app
```

支援的示範狀態：`running`、`needsInput`、`blocked`、`ready`、`idle`。

只輸出彙總診斷，不列印標題或聊天內容：

```bash
./build/CodexIsland.app/Contents/MacOS/CodexIsland --diagnose
./build/CodexIsland.app/Contents/MacOS/CodexIslandProbe --watch 10
```

自備產生器的串接方式見 [明確指定的狀態檔案契約](status-input.md)。這是本專案的開發介面，不是 Codex API。

</details>

<a id="documentation"></a>
## 文件

透過 [文件索引](README.md) 查看架構、狀態來源、寵物動畫、效能基準與發布檢查。技術文件目前主要以簡體中文撰寫，專案介紹提供上方四種語言；README 翻譯不會增加應用程式介面的語言選項。

<a id="contributing"></a>
## 參與貢獻

歡迎回報問題、修正相容性與改善文件。提交 PR 前請閱讀 [貢獻指南](../CONTRIBUTING.md)，使用合成測試資料並移除診斷資料中的敏感資訊。各語言 README 以英文主版本為基準同步，規則見 [翻譯維護說明](README.md#readme-translations)。

<a id="license"></a>
## 致謝與授權

由 **Water** 建立。水貓標識結合水波與程式碼提示符號；視覺方向參考了 [Atoll](https://github.com/Ebullioscopic/Atoll)。

專案程式碼、文件與新品牌素材採用 [MIT](../LICENSE)。Codex 名稱與執行時載入的第三方寵物素材保留各自權屬，詳見 [素材與商標說明](../THIRD_PARTY_NOTICES.md)。
