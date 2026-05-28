# LINE Investment Assistant

這個服務會接收 LINE 官方帳號的 webhook，依照 `investment_memory.md` 的規則分析投資訊息，並把分析結果推送到你的個人 LINE。

## 目前功能

- 接收 LINE 文字訊息
- 驗證 LINE webhook 簽章
- 讀取 `investment_memory.md` 作為投資分析規則
- 呼叫 OpenAI 分析
- 將結果推送到指定個人 LINE userId
- 接收並保存 LINE 傳來的圖片或檔案
- 可用 GitHub 連到 Render / Railway / Fly.io 這類平台部署

## 尚待加強

- PDF 文字抽取
- 圖片 OCR
- Excel / CSV 表格解析
- 法人報告多檔案整合
- 個股追蹤表資料庫

## 設定

1. 複製 `.env.example` 成 `.env`
2. 到 LINE Developers 後台重新產生金鑰，填入：
   - `LINE_CHANNEL_ACCESS_TOKEN`
   - `LINE_CHANNEL_SECRET`
3. 讓你的個人 LINE 加官方帳號好友並傳一則訊息，從 webhook 取得你的 `userId`，填入：
   - `LINE_OWNER_USER_ID`
4. 若要監控 LINE 群組，先把官方帳號加入群組並在群組傳一則訊息，取得 `groupId`，填入：
   - `LINE_TARGET_GROUP_ID`
5. 填入 OpenAI API key：
   - `OPENAI_API_KEY`
6. 啟動服務：

```bash
bundle install
bundle exec rackup config.ru -p 3000
```

如果你還不知道自己的 `LINE_OWNER_USER_ID`，可以先留空並啟動服務。你用個人 LINE 傳一則訊息給官方帳號後，官方帳號會直接回覆你的 userId。

如果你還不知道群組的 `LINE_TARGET_GROUP_ID`，可以先留空並把官方帳號加入群組。群組內有人傳訊息後，官方帳號會回覆 groupId。取得後再填入部署平台的環境變數。

## LINE webhook URL

本機測試時可用 ngrok 或 Cloudflare Tunnel 對外公開：

```text
https://your-public-domain.example/webhook
```

LINE Developers 後台的 Webhook URL 要填上上面這個網址。

## GitHub 部署流程

Repository:

```text
https://github.com/erickai1024-sys/codex.git
```

1. 把本資料夾內容推上 GitHub
2. 到 Render / Railway 建立 Web Service，連接該 repository
3. Build command:

```bash
bundle install
```

4. Start command:

```bash
bundle exec rackup config.ru -p $PORT -o 0.0.0.0
```

5. 在部署平台設定環境變數：
   - `LINE_CHANNEL_ACCESS_TOKEN`
   - `LINE_CHANNEL_SECRET`
   - `LINE_OWNER_USER_ID`
   - `LINE_TARGET_GROUP_ID`
   - `OPENAI_API_KEY`
   - `OPENAI_MODEL`
   - `INVESTMENT_MEMORY_TEXT`

6. 部署完成後，把平台提供的網址加上 `/webhook`，填入 LINE Developers 的 Webhook URL。

## Railway 部署

Railway 會讀取 `railway.json`，並使用以下啟動指令：

```bash
bundle exec rackup config.ru -p $PORT -o 0.0.0.0
```

在 Railway 專案的 Variables 設定：

- `LINE_CHANNEL_ACCESS_TOKEN`
- `LINE_CHANNEL_SECRET`
- `LINE_OWNER_USER_ID`
- `LINE_TARGET_GROUP_ID`
- `OPENAI_API_KEY`
- `OPENAI_MODEL`
- `INVESTMENT_MEMORY_TEXT`

部署完成後，到 Networking 產生 Public Domain，將網址加上 `/webhook` 填入 LINE Developers。

`INVESTMENT_MEMORY_TEXT` 可用來把私人投資分析規則放在 Railway Variables，不需要提交到 GitHub。

## 推送到 GitHub

如果你的電腦已安裝 Git，可在本資料夾執行：

```bash
git init
git add .
git commit -m "Create Ruby LINE investment bot"
git branch -M main
git remote add origin https://github.com/erickai1024-sys/codex.git
git push -u origin main
```
