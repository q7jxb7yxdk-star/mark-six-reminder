# Mark Six Reminder 技術文件

## 1. 文件目的

本文件描述 Mark Six Reminder 現有 iOS App 與 Cloudflare Worker 的實作、資料契約、通知規則、環境設定及維運方法。內容以 repository 目前程式碼為準，未完成的 MVP 功能另列於第 12 節。

## 2. 產品邊界

Mark Six Reminder 是非官方六合彩資訊工具，只提供資料顯示及通知。

- 不提供投注
- 不收取任何款項
- 不協助下注
- 不提供博彩建議或勝率預測
- 顯示資料只供參考，最終結果以香港賽馬會為準

## 3. 整體架構

```text
┌────────────────────────────┐
│ HKJC GraphQL marksixDraw   │
└──────────────┬─────────────┘
               │ HTTPS POST
               ▼
┌────────────────────────────┐
│ Cloudflare Worker          │
│ - Scheduled handler        │
│ - Source client + parser   │
│ - Notification rules       │
│ - Public HTTP API          │
└───────┬───────────┬────────┘
        │           │
        ▼           ▼
   ┌────────┐   ┌────────┐
   │ D1     │   │ KV     │
   │ durable│   │ current│
   │ data   │   │ cache  │
   └────────┘   └────────┘
        │
        │ APNs HTTP/2
        ▼
┌────────────────────────────┐
│ iOS App                    │
│ - Home                     │
│ - SwiftData saved numbers  │
│ - Settings                 │
│ - APNs registration        │
└────────────────────────────┘
```

架構刻意保持簡單：Worker 原生 router、明確的 source/service/repository 分工，以及小型 SwiftUI MV 結構，不加入第三方 runtime library 或不必要的抽象層。

### 3.1 OpenCode tracker 的關係

本機 OpenCode tracker 與本專案 Worker 沒有資料傳送關係：

- OpenCode tracker：由 Mac 的 launchd 執行，讀取 GraphQL 後發 Telegram 訊息。
- Cloudflare Worker：由 Cloudflare Cron 執行，獨立讀取 GraphQL、更新 D1/KV 並發 APNs。

因此 Mac 關機或 tracker 停止不會阻止 Worker 的正常 Cron；反過來，本機 tracker 正常執行也不代表 Worker 已收到或更新資料。

## 4. iOS App

### 4.1 平台及語言

- iOS 26.0+
- Swift 6
- SwiftUI
- Observation (`@Observable`)
- Structured concurrency (`async` / `await`)
- SwiftData
- UserNotifications 及 APNs

### 4.2 App 結構

```text
Mark Six Reminder/
├── Components/MarkSixNumberBall.swift
├── App/RootTabView.swift
├── Configuration/AppConfiguration.swift
├── Features/
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── HomeViewModel.swift
│   │   ├── SavedNumbersSection.swift
│   │   └── MarkSixPrizeEvaluator.swift
│   ├── CustomNumbers/
│   │   ├── CustomNumbersView.swift
│   │   └── CustomNumbersViewModel.swift
│   ├── RandomNumbers/
│   │   ├── RandomNumbersView.swift
│   │   └── RandomNumbersViewModel.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── SettingsViewModel.swift
├── Models/
│   ├── DrawInfo.swift
│   └── SavedNumberEntry.swift
├── Networking/
│   ├── JackpotAPIClient.swift
│   └── NotificationAPIClient.swift
├── Notifications/NotificationManager.swift
└── Mark_Six_ReminderApp.swift
```

### 4.3 啟動及依賴

`Mark_Six_ReminderApp` 建立共享的 `NotificationManager` 與 `SettingsViewModel`，再透過 SwiftUI environment 注入頁面。`AppDelegate` 只負責 UIApplication/APNs callbacks，避免把畫面及網絡邏輯放入 application delegate。

### 4.4 首頁

`HomeViewModel` 透過 `JackpotAPIClient` 呼叫 `GET /v1/draws/current`。頁面顯示：

- 估計頭獎基金
- 累積多寶（有值時）
- 期數
- 攪珠日期
- 最近更新時間
- 已儲存號碼及相應期數的官方核對結果

首次進入首頁時自動載入；App 每次由背景返回前景時亦會自動更新目前攪珠及所有已儲存期數的結果。若 App 一直停留在前景，首頁會只針對尚未有完整結果的已儲存攪珠日期建立等待 Task，在香港時間 21:46 自動更新，仍未有結果時於 22:16 後備重試。Task 不會輪詢，進入背景或結果已完整時會自動取消。首頁不設獨立 toolbar 按鈕，但保留 pull-to-refresh 作手動後備。未設定 API URL、沒有資料或 request 失敗時，頁面顯示可重試錯誤狀態，不使用假資料。

### 4.5 設定及本機持久化

通知設定暫時使用 `UserDefaults`：

| Key | 用途 | 預設值 |
|---|---|---:|
| `notification.threshold` | 通知金額門檻 | 13,000,000 |
| `notification.enabled` | 是否啟用通知 | `true` |
| `notification.installationId` | 每次 App 安裝的穩定 UUID | 首次啟動產生 |

App 提供 $8,000,000、$13,000,000 及 $18,000,000 三個固定選項，新安裝預設使用 $13,000,000。設定頁不提供自訂輸入或獨立的「目前門檻」列；勾號直接標示目前選項。已安裝用戶如已有舊自訂門檻，更新後會保留原值，直至用戶選擇新的固定門檻。

### 4.6 APNs 註冊

流程如下：

1. App 讀取 `UNNotificationSettings`。
2. 已授權時呼叫 `registerForRemoteNotifications()`。
3. `AppDelegate` 接收 APNs device token。
4. `NotificationManager` 轉換為小寫 hexadecimal token。實體裝置通常是 64 字元；Simulator 可能回傳較長 token。
5. `SettingsViewModel` 把 installation ID、token、門檻、enabled 及 APNs environment 傳送到 Worker。

Debug build 註冊為 `sandbox`，Release build 註冊為 `production`。Worker 會依每筆訂閱選擇相應 APNs gateway。
設定頁不持續顯示系統權限文字；尚未詢問時顯示「設定通知權限」，已拒絕時顯示「開啟 iPhone 設定」。等待 token 時顯示「正在註冊通知裝置」，`AppDelegate` 亦會把 APNs 註冊失敗傳回畫面。同步成功不額外顯示「通知設定已更新」，但處理中、關閉通知及錯誤提示會保留。

### 4.7 運財號碼

`RandomNumbersViewModel` 使用 Swift 標準隨機產生器，從 1 至 49 洗牌後取首六個數值，再按小至大排列。因為來源範圍本身沒有重複值，所以結果必定是六個不重複號碼。

`RandomNumbersView` 是底部 Tab Bar 的獨立頁面。首次進入時會顯示六個灰色「0」佔位球，但不會自動產生號碼；用戶必須按「產生號碼」才會取得第一組，其後可按「重新產生」取得新一組。佔位球的 `nil` 狀態與有效的 1 至 49 號碼分開處理，避免把 0 誤當成六合彩號碼。

用戶按「儲存號碼」時，App 先讀取目前下一期攪珠，把官方 `drawID`、期數、日期及六個號碼寫入本機 `SavedNumberEntry`。同一期可保存多組號碼，但完全相同的一組不會重複建立。現有六個整數欄位繼續保留，確保舊 SwiftData 記錄可向後兼容；新記錄另以簡單逗號分隔文字保存原始選號及玩法。這些號碼不會上傳到 Worker。

首頁以 SwiftData `@Query` 顯示已儲存號碼，並呼叫 `GET /v1/draws/{drawID}` 讀取該期官方結果。`SavedNumbersSection` 按 `drawID` 把多組號碼分組，每一期只顯示一次六個官方正選號碼及特別號碼，再按儲存先後把選擇標示為「第 1 組」、「第 2 組」等並逐一核對。每組命中的球以黃色邊框標示，結果列顯示獎項資格或「未獲獎」；用戶可向左滑動刪除個別記錄。未公布結果時顯示「等待官方攪珠結果」。

`MarkSixNumberBall` 是可重用的 SwiftUI 元件，按六合彩標準號碼分組顯示紅、藍或綠球。元件以 SwiftUI 漸層、白色中央區域及黑色數字自行繪製，不包含或下載香港賽馬會的 SVG、Logo 或其他圖片資產，並為 VoiceOver 提供球色及號碼標籤。

### 4.8 自選號碼

`CustomNumbersView` 是底部 Tab Bar 的獨立頁面，重用 `MarkSixNumberBall` 顯示 1 至 49。`CustomNumbersViewModel` 依目前玩法管理選取狀態：

- 單式：必須選擇 6 個不同號碼。
- 複式：必須選擇最少 7 個不同號碼。
- 膽拖：必須選擇 1 至 5 個膽，膽與拖合共最少 7 個，且兩組不會重複。

規則依照香港賽馬會六合彩注項說明。App 只保存原始選號，不會為複式或膽拖建立大量六號碼 SwiftData 記錄；組合數使用 `n choose k` 計算。`SavedNumberEntry` 的 `selectionTypeRawValue`、`selectedNumbersStorage` 及 `bankerNumbersStorage` 保存玩法資料，舊記錄在沒有新欄位內容時自動視為單式。

首頁會在同一期內逐項顯示單式、複式或膽拖。膽拖分開顯示膽及拖；官方結果公布後，所有命中球均以黃色邊框標示。`MarkSixPrizeEvaluator` 依每注六個號碼判定：6 個正選為頭獎、5 個正選加特別號碼為二獎、5 個正選為三獎、4 個正選加特別號碼為四獎、4 個正選為五獎、3 個正選加特別號碼為六獎、3 個正選為七獎。

複式及膽拖不會逐注建立陣列；核對器按正選、特別號碼及其他號碼的組合數直接彙總各獎項注數，例如「二獎資格 × 2、七獎資格 × 5」。這避免大量選號時展開所有組合。App 只表示獎項資格，不提交投注，也不計算或顯示投注金額或實際派彩。

## 5. Worker

### 5.1 入口

`Worker/src/index.ts` 提供兩個 handler：

- `fetch`：處理 HTTP API。
- `scheduled`：更新官方資料，再執行通知判斷。

錯誤以 JSON 結構寫入 console，避免記錄 GraphQL response body、APNs 私鑰或完整敏感內容。

### 5.2 官方資料來源

Endpoint：

```text
https://info.cld.hkjc.com/graphql/base/
```

Worker 以 POST 呼叫官方網頁使用的 `marksixDraw` operation，主要讀取：

- `id`
- `year` / `no`
- `closeDate`
- `drawDate`
- `status`
- `lotteryPool.jackpot`
- `lotteryPool.derivedFirstPrizeDiv`
- `drawResult.drawnNo`
- `drawResult.xDrawnNo`

`HKJCSourceClient` 設有 8 秒 timeout 及 256 KiB response 上限。GraphQL query 和 endpoint 集中在 source client，容易在上游 schema 改變時修改。

### 5.3 Parser 規則

`parseHKJCResponse`：

1. 拒絕無效 JSON 或 GraphQL errors。
2. 驗證及正規化 GraphQL 回傳的所有可用攪珠，再按日期排序。
3. 選擇尚未有六個正選號碼且時間未過的最早一期作 current draw；如晚間結果已公布但下一期尚未建立，current 可以暫時為空，已公布結果仍會保存。
4. 把 `year` 及 `no` 格式化為例如 `26/080`。
5. 接受官方金額的 number 或純數字 string，並轉為非負安全整數。
6. 官方 `drawDate` 如只有日期，補成香港時間 21:30。
7. 只有完整六個正選號碼時才接受特別號碼，避免把未攪珠 placeholder 當成結果。
8. 已公布號碼必須為 1 至 49、共七個且不重複。

`salesCloseAt` 使用官方 `closeDate`，不在 App 端自行推算。

### 5.4 穩定資料模型

Worker 對 App 回傳的 `DrawInfo`：

| 欄位 | 類型 | 說明 |
|---|---|---|
| `id` | string | 官方攪珠識別碼 |
| `drawNumber` | string | 顯示期數，例如 `26/080` |
| `drawDate` | string | ISO 8601 攪珠時間 |
| `salesCloseAt` | string | ISO 8601 截止售票時間 |
| `estimatedFirstPrizeFund` | number/null | 估計頭獎基金 |
| `jackpot` | number/null | 累積多寶 |
| `status` | string | 官方狀態 |
| `mainNumbers` | number[] | 六個正選號碼；未攪珠時為空陣列 |
| `specialNumber` | number/null | 特別號碼 |
| `updatedAt` | string | Worker 更新時間 |
| `sourceURL` | string | 官方 Mark Six 網頁 |

## 6. 儲存設計

### 6.1 KV

Binding：`DRAW_CACHE`

| Key | Value |
|---|---|
| `draw:current` | JSON 編碼的目前 `DrawInfo` |

API 先讀 KV；cache miss 時讀取 D1 最新資料並回填 KV。

### 6.2 D1

Binding：`DB`

`draws` 保存每次 GraphQL 回傳的所有經驗證攪珠。相同 `id` 使用 upsert 更新，因此同一期可由未攪珠狀態更新成完整結果。整批 D1 statement 成功後，只有存在下一期 current draw 時才更新 KV；晚間沒有下一期資料亦不會阻止已公布結果寫入 D1。

`notification_subscriptions` 以 `installation_id` 為 primary key，保存：

- APNs device token
- 門檻
- enabled 狀態
- sandbox / production environment
- 更新時間

`notification_deliveries` 使用 `(draw_id, installation_id)` 複合 primary key，保存 pending、sent 或 failed 狀態。這個唯一鍵是每期最多一次通知的主要保護。

目前 failed delivery 仍保留唯一 claim，不會在下一次 Cron 自動重試，以優先避免重複通知。日後如需要 retry，必須加入有上限、可區分暫時／永久錯誤的明確策略。

## 7. 通知規則

Cron：

```text
15 1 * * SUN,TUE,THU,SAT
45 13 * * SUN,TUE,THU,SAT
15 14 * * SUN,TUE,THU,SAT
```

Cloudflare Cron 使用 UTC。以上分別等同香港時間逢星期日、星期二、星期四及星期六 09:15、21:45 及 22:15。09:15 排程更新資料及判斷 APNs 通知；21:45 排程更新攪珠結果；22:15 是官方結果延遲時的後備重試。兩個晚間排程只更新 D1/KV，不會發送頭獎基金通知。

Worker 只會在這四個可能的攪珠星期執行；通知服務仍會比較官方 `drawDate` 與香港當日日期，因此沒有攪珠的星期六或星期日不會發送通知。

通知必須同時符合：

1. `drawDate` 的香港日期等於執行當日香港日期。
2. `estimatedFirstPrizeFund` 已公布。
3. 訂閱為 enabled。
4. 用戶門檻小於或等於估計頭獎基金。
5. 該 `draw_id + installation_id` 尚未有 delivery 紀錄。
6. Worker 已設定完整 APNs secrets。

發送前先原子地插入 `pending` delivery；成功後標示 `sent`，失敗則標示 `failed`。APNs 回覆 `BadDeviceToken`、`DeviceTokenNotForTopic` 或 `Unregistered` 時，Worker 會停用該訂閱。

通知 payload 包含：

- 標題：`今晚六合彩攪珠`
- 內容：期數及估計頭獎基金，金額以 `$` 加千位分隔顯示
- 預設提示聲
- 自訂 `drawId`
- `apns-collapse-id` 使用 draw ID

## 8. HTTP API

### 8.1 Health check

```http
GET /health
```

成功回應：

```json
{
  "status": "ok"
}
```

### 8.2 目前攪珠

```http
GET /v1/draws/current
```

成功回應：

```json
{
  "data": {
    "id": "202680N",
    "drawNumber": "26/080",
    "drawDate": "2026-07-25T21:30:00+08:00",
    "salesCloseAt": "2026-07-25T21:15:00+08:00",
    "estimatedFirstPrizeFund": 13000000,
    "jackpot": 8000000,
    "status": "Defined",
    "mainNumbers": [],
    "specialNumber": null,
    "updatedAt": "2026-07-24T00:00:00.000Z",
    "sourceURL": "https://bet.hkjc.com/ch/marksix"
  }
}
```

範例只說明 schema，並非保證目前一期的即時資料。尚未有任何 cache 或 D1 record 時回應 `503 DRAW_NOT_READY`。

### 8.3 指定攪珠結果

```http
GET /v1/draws/{drawID}
```

`drawID` 是 current draw response 內的官方 `id`，只接受 1 至 80 字元的英文字母、數字、底線或連字號。找到記錄時回傳相同 `DrawInfo` schema；未找到時回傳 `404 DRAW_NOT_FOUND`。未攪珠記錄的 `mainNumbers` 為空陣列及 `specialNumber` 為 `null`。

### 8.4 通知訂閱

```http
POST /v1/notification-subscriptions
Content-Type: application/json
```

Request：

```json
{
  "installationId": "xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx",
  "deviceToken": "hexadecimal-device-token",
  "threshold": 20000000,
  "enabled": true,
  "apnsEnvironment": "sandbox"
}
```

限制：

- body 最多 8 KiB
- installation ID 必須為 UUID
- device token 必須為 64 至 512 個 hexadecimal 字元、長度為雙數（完整 bytes）；這同時支援實體裝置及 Simulator token
- threshold 必須為 0 至 1,000,000,000 的整數
- APNs environment 只接受 `sandbox` 或 `production`

成功回應：

```json
{
  "data": {
    "registered": true
  }
}
```

## 9. 環境及 secrets

### 9.1 iOS build settings

| Setting | Debug | Release |
|---|---|---|
| `JACKPOT_API_BASE_URL` | staging URL | 上架前必須設定 production URL |
| `APS_ENVIRONMENT` | `development` | `production` |

`AppConfiguration` 只接受 HTTPS；HTTP 只允許 `localhost`、`127.0.0.1` 或 `::1`，避免正式 App 誤用明文遠端連線。

### 9.2 Worker non-secret vars

```text
HKJC_GRAPHQL_URL
APNS_TOPIC
```

### 9.3 Worker secrets

```text
APNS_KEY_ID
APNS_TEAM_ID
APNS_PRIVATE_KEY
```

設定方式：

```bash
cd Worker
npx wrangler secret put APNS_KEY_ID --env staging
npx wrangler secret put APNS_TEAM_ID --env staging
npx wrangler secret put APNS_PRIVATE_KEY --env staging
```

`.p8` 私鑰只可在 Apple Developer 下載一次。不要把私鑰、secret 值、`.dev.vars` 或 APNs token 提交到 Git、加入文件或寫入 log。

## 10. 測試及部署

### 10.1 Worker quality gate

```bash
cd Worker
npm install
npm run check
```

`npm run check` 依次產生 binding types、執行 TypeScript type-check 及 Vitest。測試涵蓋：

- HKJC parser 正常及錯誤資料
- source client request/query 行為
- draw update 的 source-to-store 流程
- draw-day、門檻、缺少 APNs 及 once-per-draw 通知行為

### 10.2 D1 migration

```bash
cd Worker
npx wrangler d1 migrations apply jackpot-alert-staging --env staging --remote
```

先 migration，後部署 Worker，避免新程式先使用尚未存在的 table。

### 10.3 Staging 部署

```bash
cd Worker
npx wrangler deploy --env staging
```

部署後檢查：

```bash
curl https://mark-six-reminder-api-staging.nutrition-api.workers.dev/health
curl https://mark-six-reminder-api-staging.nutrition-api.workers.dev/v1/draws/current
npx wrangler tail --env staging
```

不要在無確認通知條件及 delivery 狀態時反覆手動觸發 production scheduled handler。

## 11. 故障排查

### 11.1 `WHITELIST_ERROR`

舊的或不完整 GraphQL operation 可能被 upstream 拒絕。現有 source client 必須使用完整的 `marksixDraw` query，且 `operationName` 必須為 `marksixDraw`。若再次出現錯誤：

1. 先查看 Worker structured logs。
2. 比對香港賽馬會目前 SPA 使用的 operation 及 selection set。
3. 更新 `hkjc-source-client.ts`。
4. 為新 payload 加入或更新 parser fixture/test。
5. `npm run check` 成功後才部署。

### 11.2 App 顯示「尚未設定 Jackpot Alert API 網址」

檢查 target build setting `JACKPOT_API_BASE_URL`。值不可為空或未展開的 `$(...)`，遠端 URL 必須使用 HTTPS。

### 11.3 收不到 APNs

依序檢查：

1. 使用實體裝置或支援 remote notifications 的 Simulator，並已允許通知。
2. App 已取得有效的 hexadecimal device token；實體裝置通常是 64 字元，Simulator 可能較長。
3. D1 訂閱的 `enabled`、`threshold` 及 `apns_environment` 正確。
4. Debug 對 sandbox，Release 對 production。
5. `APNS_TOPIC` 與 App Bundle Identifier 完全相同。
6. APNs Key、Key ID、Team ID secrets 屬於相同 Apple Developer Team。
7. 今日香港日期確實等於官方 `drawDate`。
8. 該期 delivery record 是否已存在。
9. Worker log 及 `notification_deliveries.error_code` 是否有 APNs 錯誤。

### 11.4 Worker 沒有更新資料

檢查 Cron、Worker logs、GraphQL HTTP status、response 大小及 schema。Parser 會刻意拒絕欄位不足、金額無效、日期無效或號碼不完整的資料，避免錯誤內容污染 D1/KV。

## 12. 後續 MVP 工作

以下功能尚未在目前 repository 實作：

1. 完整「我的投注」管理頁面。
2. 隨機號碼複製功能。
3. production Worker、production KV/D1、Release API URL 及 App Store 上架設定。

新增以上功能時應維持目前原則：功能按 feature 分檔、ViewModel 只管理畫面狀態、網絡及 persistence 保持獨立、避免 God Object，也不引入不必要的第三方 library。

## 13. App Store 注意事項

- App 名稱及 metadata 應持續清楚標示為非官方工具。
- App Store Primary Category 使用 `Reference`；如設定 Secondary Category，可使用 `Utilities`。
- App 內保留「不提供投注／款項／博彩建議」聲明。
- 不使用香港賽馬會商標暗示官方認可。
- App Icon 使用自製圖像，標準版本為 1024×1024 PNG、無 Alpha Channel，並由系統套用圓角遮罩。
- 提供可公開存取的 Privacy Policy 及 Support URL。
- Privacy nutrition label 必須與實際收集資料一致；目前 backend 保存 installation ID、APNs device token、門檻及通知狀態。
- 上架前使用 production APNs entitlement、production Worker URL 及 production 資源完成實機測試。
