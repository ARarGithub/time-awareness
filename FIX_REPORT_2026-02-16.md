# Time Awareness 修正報告（2026-02-16）

## 目標

本次修正聚焦在先前確認的三類問題：

1. `bar name` 作為唯一鍵導致衝突與覆蓋
2. `TimeRule` 進度起算與不合法 duration 驗證
3. 滑鼠事件與 YAML 解析的效能優化

## 變更檔案

- `Sources/TimeAwareness/UI/BarConfigWindow.swift`
- `Sources/TimeAwareness/Config/ConfigManager.swift`
- `Sources/TimeAwareness/Config/TimeRule.swift`
- `Sources/TimeAwareness/UI/DynamicIslandController.swift`

## 變更內容

### 1) Bar 名稱衝突修正

#### 問題

- 既有流程多處以 `bar.name` 當 key，重名時會互相覆蓋。
- 拖曳排序使用名稱定位，重名時會找錯目標。

#### 修正

- `ConfigManager.save(_:)` 新增正規化流程：
  - 去除名稱前後空白
  - 空名稱改為 `bar`
  - 重複名稱自動補後綴 `_1`, `_2`, ...
- 新增 helper：`makeBarNamesUnique(_:)`
- Bar 編輯視窗拖曳由「名稱比對」改為「index 比對」：
  - `draggingBarName` -> `draggingBarIndex`
  - `BarDropDelegate` 改為用 `targetIndex`/`draggingIndex`
- 新增 bar 時先檢查既有名稱，確保預設名稱唯一。

#### 影響

- 防止資料覆蓋與排序錯亂。
- 使用者即使輸入重名，儲存後仍能得到可用且唯一的配置。

### 2) TimeRule 邏輯修正

#### 問題

- 週/月/年（以及 `d` 規則）進度以第 1 天算入，導致一開始不是 0%。
- 規則字串可接受 `0` 或負數 duration，可能造成不正確計算。

#### 修正

- 進度改為「已經過量 / 總量」：
  - `elapsedDays = dayIndex - 1`
  - week/month/year/day-based 皆改為從 0 起算
- 解析階段加入 duration 驗證：
  - 僅接受 `isFinite && > 0`
- `progress(at:)` 內加 defensive guard：`totalDuration > 0` 時才進行除法。

#### 影響

- 進度語意更直覺，避免首日直接顯示非 0% 的問題。
- 規則輸入更安全，不會因非法 duration 導致異常值。

### 3) 效能優化

#### A. 滑鼠事件監聽優化

- `DynamicIslandController` 新增狀態觀察（Combine）：依 `viewModel.state` 動態啟停監聽。
- 在 `.settings` 狀態移除 move monitor（此狀態不需 hover 自動收合）。
- move 事件監聽由 `mouseMoved + leftMouseDragged` 收斂為 `mouseMoved`。
- `idle` 時不保留 local monitor，僅在可互動狀態啟用。

**預期效果**：降低高頻事件處理量與不必要 CPU 消耗。

#### B. YAML 單次解析

- `AppConfig.from(yaml:)` 由雙解析（`Yams.load` + `Yams.compose`）改為單次 `Yams.compose`。
- 透過 `Node.Mapping` 直接解析 bars/animation/top-level 欄位。
- 新增 helper：`nodeValue`、`nodeCGFloat`、`nodeDouble`。

**預期效果**：reload config 時減少重複解析成本，並維持 bars 順序解析能力。

## 驗證

- 已執行：`swift build`
- 結果：**通過**（可成功編譯）

## 相容性與風險說明

- 名稱唯一化會在儲存時改寫重複名稱（預期行為，避免衝突）。
- 週/月/年進度顯示會與舊版本不同（由首日非 0% 改為 0% 起算）。
- 滑鼠監聽策略改動後，若未來互動規則變更，需同步檢查狀態切換時的 monitor 啟停邏輯。

## 備註

- 目前工作區還有與本次修正無關的既有變更（`AppIcon.iconset/*` 刪除狀態）；本次報告與程式碼修正未處理該部分。
