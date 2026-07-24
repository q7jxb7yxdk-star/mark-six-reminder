# Mark Six Reminder

Mark Six Reminder 是一個非官方的香港六合彩資訊 iOS App，顯示下期攪珠資料，並在攪珠當日、估計頭獎基金達到用戶設定門檻時發送通知。

本 App 不提供投注、不收取款項、不協助下注，也不提供博彩建議。資料只供參考，最終資料以香港賽馬會公布為準。

## 目前進度

已完成：

- iOS 首頁顯示期數、攪珠日期、截止售票時間、估計頭獎基金、累積多寶及更新時間
- 通知權限、HK$8,000,000／HK$13,000,000 預設門檻、自訂門檻，以及啟用或停用通知
- APNs 裝置註冊及前景通知顯示
- Cloudflare Worker 透過香港賽馬會網頁所使用的 GraphQL 端點取得及驗證資料
- Cron 逢星期日、二、四、六香港時間 09:15 更新資料及判斷通知條件
- 每個裝置每期最多通知一次
- D1 持久化攪珠、訂閱及發送紀錄，KV 快取目前攪珠資料
- Worker 單元測試、結構化 logging 及基本錯誤處理

尚待開發：

- 使用 SwiftData 管理多組投注號碼
- 攪珠結果自動核對及獎項顯示
- 產生、複製、儲存及加入投注紀錄的隨機號碼
- 「我的投注」頁面

## 技術架構

- iOS 18+
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
6. 使用實體 iPhone 測試 APNs，並允許通知權限。

目前設定：

- Bundle Identifier：`Sunny.Mark-Six-Reminder`
- Staging API：`https://mark-six-reminder-api-staging.nutrition-api.workers.dev`
- 最低支援版本：iOS 18.0

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
- Cron：`15 1 * * 0,2,4,6`（UTC，即香港時間逢星期日、二、四、六 09:15）

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
POST /v1/notification-subscriptions
```

詳細 request、資料模型、通知判斷、維運及故障排查請參閱 [TECHNICAL_DOCUMENTATION.md](TECHNICAL_DOCUMENTATION.md)。

## 資料來源與風險

Worker 使用 `https://info.cld.hkjc.com/graphql/base/` 的 `marksixDraw` operation。這是香港賽馬會網頁目前使用的資料端點，但並非本專案控制的公開合約；GraphQL schema、欄位或存取規則變更時，可能需要更新 source client 及 parser。

## License

此 repository 目前未指定開源授權。未經授權，不代表可複製、修改或重新發布程式碼。
