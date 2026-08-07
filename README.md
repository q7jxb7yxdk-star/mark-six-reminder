# Mark Six Reminder

Mark Six Reminder 是一個非官方的香港六合彩資訊 iOS App，顯示下期攪珠資料，並在攪珠當日、估計頭獎基金達到用戶設定門檻時發送通知。

本 App 不提供投注、不收取款項、不協助下注，也不提供博彩建議。資料只供參考，最終資料以香港賽馬會公布為準。

## 目前進度

已完成：

- iOS 首頁顯示期數、攪珠日期、估計頭獎基金、累積多寶及更新時間
- 通知權限、$8,000,000／$13,000,000／$18,000,000／$25,000,000 固定門檻，以及啟用或停用通知
- APNs 裝置註冊及前景通知顯示
- 獨立「運財號碼」頁面，隨機產生六個 1 至 49、不重複並由小至大排列的號碼，使用紅、藍、綠標準球色
- 獨立「自選號碼」頁面，可選擇單式、複式或膽拖，並顯示所代表的六個號碼組合數目
- 使用 SwiftData 把運財或自選號碼綁定下一期攪珠，號碼只保存在用戶裝置
- 首頁按攪珠期數把多組已儲存號碼分組，官方結果標題包含期數並每期只顯示一次，各組號碼逐一標示期數、組別、玩法、命中號碼及頭獎至七獎資格；記錄可向左滑動刪除
- 設定頁可選擇在下一個攪珠日自動刪除早於目前攪珠期數的已儲存號碼；預設關閉，關閉時保留所有期數
- 首頁、運財號碼、自選號碼及設定頁採用一致的卡片、狀態提示與按鈕樣式；命中或選取的號碼球以完整金色外框標示
- App 首次進入首頁時先顯示本機快取；啟動或由背景返回前景時，距上次成功更新未滿 15 分鐘則不重複呼叫 Worker。攪珠日 21:40 及 21:50 的結果更新、跨過該時間後返回前景，以及用戶下拉重新整理仍會強制更新
- 已公布的完整官方攪珠結果會保存在用戶裝置，後續只查詢尚未公布結果的已儲存期數
- Cloudflare Worker 透過香港賽馬會網頁所使用的 GraphQL 端點取得及驗證資料
- Cron 逢星期日、二、四、六香港時間 09:15 更新資料及判斷通知條件，21:39 更新結果，21:49 後備重試
- 每個裝置每期最多通知一次
- D1 持久化攪珠、訂閱及發送紀錄，KV 快取目前攪珠資料
- Worker 單元測試、結構化 logging 及容錯處理；官方金額可包含 `$`、`HK$` 及千位分隔，金額暫時無效時仍會保存有效攪珠結果
- 1024×1024、無 Alpha Channel 的自訂 App Icon；App Store Primary Category 使用 Reference

尚待開發：

- 隨機號碼複製功能
- 「我的投注」頁面
- production Worker、production 儲存資源及 Release API URL

## 技術架構

- iOS 26+
- Swift 6、SwiftUI、Observation、Async/Await、UserNotifications
- Cloudflare Workers、KV、D1、Cron Triggers
- TypeScript、Vitest
- Apple Push Notification service（APNs）Token Authentication

資料流程：

```text
HKJC GraphQL
      │
      ▼
Cloudflare Worker Cron ──► D1 + KV
      │                       │
      │ APNs                  │ HTTPS API
      ▼                       ▼
  iPhone 通知 ◄──────── Mark Six Reminder
```

Worker 與本機 OpenCode 的六合彩 Telegram tracker 是兩套獨立流程。本機 tracker 繼續執行並不會把資料傳送給 Worker；Worker 會自行依 Cron 直接讀取官方 GraphQL 端點。

## Repository 結構

```text
.
├── Configuration/                 # iOS Info.plist
├── Mark Six Reminder/             # SwiftUI App
│   ├── App/
│   ├── Configuration/
│   ├── Features/
│   ├── Models/
│   ├── Networking/
│   └── Notifications/
├── Worker/                        # Cloudflare Worker
│   ├── migrations/
│   ├── src/
│   └── test/
└── TECHNICAL_DOCUMENTATION.md
```

## iOS 設定

1. 使用 Xcode 開啟 `Mark Six Reminder.xcodeproj`。
2. 選擇可使用 Push Notifications 的 Apple Developer Team。
3. 確認 Bundle Identifier 與 Worker 的 `APNS_TOPIC` 相同。
4. Debug build 使用 APNs sandbox；Release build 使用 APNs production。
5. Debug 的 `JACKPOT_API_BASE_URL` 目前指向 staging Worker；Release 必須在上架前填入 production HTTPS URL。
6. 使用實體 iPhone 完成上架前 APNs 測試；開發期間亦可用支援 remote notifications 的 Simulator 驗證註冊流程。
7. 設定頁會在等待 APNs token 時顯示註冊狀態；若系統註冊失敗，會直接顯示錯誤而不會靜默等待。

目前設定：

- Bundle Identifier：`Sunny.Mark-Six-Reminder`
- Staging API：`https://mark-six-reminder-api-staging.sonicman.workers.dev`
- 最低支援版本：iOS 26.0

## Worker 本機開發

需要 Node.js、npm 及可存取 Cloudflare 帳戶的 Wrangler。

```bash
cd Worker
npm install
npm run check
npm run dev
```

本機開發伺服器可使用 Wrangler 的 scheduled 測試功能。請勿把 APNs 私鑰或 `.dev.vars` 提交到 Git。

## Cloudflare 設定

Staging environment 使用：

- Worker：`mark-six-reminder-api-staging`
- KV binding：`DRAW_CACHE`
- D1 binding：`DB`
- 通知 Cron：`15 1 * * SUN,TUE,THU,SAT`（UTC，即香港時間 09:15）
- 結果 Cron：`39 13 * * SUN,TUE,THU,SAT`（UTC，即香港時間 21:39）
- 後備結果 Cron：`49 13 * * SUN,TUE,THU,SAT`（UTC，即香港時間 21:49）

必須設定以下 secrets：

```text
APNS_KEY_ID
APNS_TEAM_ID
APNS_PRIVATE_KEY
```

部署及資料庫 migration：

```bash
cd Worker
npx wrangler d1 migrations apply jackpot-alert-staging --env staging --remote
npx wrangler deploy --env staging
```

部署前先執行：

```bash
npm run check
```

## HTTP API

```text
GET  /health
GET  /v1/draws/current
GET  /v1/draws/{drawID}
POST /v1/notification-subscriptions
```

詳細 request、資料模型、通知判斷、維運及故障排查請參閱 [TECHNICAL_DOCUMENTATION.md](TECHNICAL_DOCUMENTATION.md)。

## 資料來源與風險

Worker 使用 `https://info.cld.hkjc.com/graphql/base/` 的 `marksixDraw` operation。這是香港賽馬會網頁目前使用的資料端點，但並非本專案控制的公開合約；GraphQL schema、欄位或存取規則變更時，可能需要更新 source client 及 parser。

## License

此 repository 目前未指定開源授權。未經授權，不代表可複製、修改或重新發布程式碼。
