require "base64"
require "dotenv/load"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "sinatra/base"
require "uri"

class LineInvestmentBot < Sinatra::Base
  set :bind, "0.0.0.0"
  set :port, ENV.fetch("PORT", 3000)

  ROOT_DIR = File.expand_path(__dir__)
  MEMORY_PATH = File.join(ROOT_DIR, "investment_memory.md")
  INBOX_DIR = File.join(ROOT_DIR, "data", "inbox")

  post "/webhook" do
    raw_body = request.body.read
    halt 401, "Invalid LINE signature" unless valid_line_signature?(raw_body)

    payload = JSON.parse(raw_body)
    payload.fetch("events", []).each { |event| handle_event(event) }

    status 200
    "OK"
  rescue JSON::ParserError
    status 400
    "Invalid JSON"
  rescue StandardError => e
    warn e.full_message
    status 500
    "Internal server error"
  end

  get "/health" do
    "OK"
  end

  helpers do
    def line_channel_access_token
      ENV.fetch("LINE_CHANNEL_ACCESS_TOKEN")
    end

    def line_channel_secret
      ENV.fetch("LINE_CHANNEL_SECRET")
    end

    def owner_user_id
      ENV["LINE_OWNER_USER_ID"]
    end

    def target_group_id
      ENV["LINE_TARGET_GROUP_ID"]
    end

    def openai_api_key
      ENV["OPENAI_API_KEY"]
    end

    def openai_model
      ENV.fetch("OPENAI_MODEL", "gpt-4.1")
    end

    def valid_line_signature?(raw_body)
      signature = request.env["HTTP_X_LINE_SIGNATURE"].to_s
      expected = Base64.strict_encode64(
        OpenSSL::HMAC.digest("sha256", line_channel_secret, raw_body)
      )

      return false unless signature.bytesize == expected.bytesize

      Rack::Utils.secure_compare(signature, expected)
    rescue KeyError
      false
    end

    def handle_event(event)
      return unless event["type"] == "message"

      message = event.fetch("message")
      sender = event.dig("source", "userId") || "unknown"
      group_id = event.dig("source", "groupId")

      if group_id && target_group_id.to_s.empty?
        reply_text(
          event.fetch("replyToken"),
          [
            "設定用 groupId：",
            group_id,
            "",
            "請把這串填到 LINE_TARGET_GROUP_ID。"
          ].join("\n")
        )
        return
      end

      return if target_group_id.to_s != "" && group_id != target_group_id

      if owner_user_id.to_s.empty?
        reply_text(
          event.fetch("replyToken"),
          [
            "設定用 userId：",
            sender,
            "",
            "請把這串填到 LINE_OWNER_USER_ID。"
          ].join("\n")
        )
        return
      end

      case message["type"]
      when "text"
        source_label = group_id ? "LINE group #{group_id} text from #{sender}" : "LINE text from #{sender}"
        result = analyze_investment_text(message.fetch("text"), source_label)
        push_text(result)
      when "file", "image"
        file_name = message["fileName"] || "#{message['type']}-#{message.fetch('id')}"
        saved_path = download_line_content(message.fetch("id"), file_name)
        push_text(
          [
            "已收到投資訊息附件。",
            "檔案已先保存：#{saved_path}",
            "",
            "目前 Ruby 最小版本已可分析 LINE 文字；PDF、圖片 OCR、Excel 解析可在下一版接上。"
          ].join("\n")
        )
      else
        push_text("已收到 #{message['type']} 類型訊息，但目前尚未支援分析。")
      end
    end

    def analyze_investment_text(source_text, source_label)
      raise "Missing OPENAI_API_KEY" if openai_api_key.to_s.empty?

      memory = investment_memory
      prompt = [
        "你是使用者的台股投資研究助理。",
        "請嚴格依照下方 investment_memory.md 的規則分析，使用繁體中文。",
        "必須先整理再評論；資訊不足請寫「不確定／需補資料」，不要自行編造。",
        "若內容涉及個股，請整理推薦觀察個股、核心題材、目標價或估值假設、追蹤條件、風險、停利停損或風險報酬比。",
        "請避免保證式買賣語氣，改用研究觀察與條件式追蹤建議。",
        "",
        "# investment_memory.md",
        memory,
        "",
        "# 來源：#{source_label}",
        source_text
      ].join("\n")

      response = post_json(
        "https://api.openai.com/v1/responses",
        {
          model: openai_model,
          input: prompt
        },
        "Authorization" => "Bearer #{openai_api_key}"
      )

      extract_openai_text(response)
    end

    def investment_memory
      return ENV["INVESTMENT_MEMORY_TEXT"] if ENV["INVESTMENT_MEMORY_TEXT"].to_s.strip != ""
      return File.read(MEMORY_PATH, encoding: "UTF-8") if File.exist?(MEMORY_PATH)

      [
        "使用者需要台股投資研究助理。",
        "請先整理來源內容，再提出分析與追蹤建議。",
        "若資訊不足，請明確標示「不確定／需補資料」，不要自行編造。",
        "若內容涉及個股，請整理核心題材、目標價或估值假設、追蹤條件、風險與停利停損。",
        "請避免保證式買賣語氣，改用研究觀察與條件式追蹤建議。"
      ].join("\n")
    end

    def push_text(text)
      raise "Missing LINE_OWNER_USER_ID" if owner_user_id.to_s.empty?

      split_for_line(text).each do |chunk|
        post_json(
          "https://api.line.me/v2/bot/message/push",
          {
            to: owner_user_id,
            messages: [{ type: "text", text: chunk }]
          },
          "Authorization" => "Bearer #{line_channel_access_token}"
        )
      end
    end

    def reply_text(reply_token, text)
      post_json(
        "https://api.line.me/v2/bot/message/reply",
        {
          replyToken: reply_token,
          messages: split_for_line(text).first(5).map { |chunk| { type: "text", text: chunk } }
        },
        "Authorization" => "Bearer #{line_channel_access_token}"
      )
    end

    def download_line_content(message_id, file_name)
      FileUtils.mkdir_p(INBOX_DIR)

      uri = URI("https://api-data.line.me/v2/bot/message/#{message_id}/content")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{line_channel_access_token}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      raise "LINE content download error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      safe_name = file_name.gsub(/[\\\/:*?"<>|]/, "_")
      saved_path = File.join(INBOX_DIR, "#{Time.now.to_i}-#{safe_name}")
      File.binwrite(saved_path, response.body)
      saved_path
    end

    def post_json(url, payload, headers = {})
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      headers.each { |key, value| request[key] = value }
      request.body = JSON.generate(payload)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      raise "HTTP error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s
      body.empty? ? {} : JSON.parse(body)
    end

    def extract_openai_text(response)
      return response["output_text"] if response["output_text"].to_s.strip != ""

      texts = response.fetch("output", []).flat_map do |item|
        item.fetch("content", []).filter_map { |content| content["text"] }
      end

      texts.join("\n").strip.empty? ? "分析完成，但沒有取得文字結果。" : texts.join("\n").strip
    end

    def split_for_line(text)
      max_length = 4_800
      rest = text.to_s.strip
      parts = []

      while rest.length > max_length
        cut_at = rest.rindex("\n", max_length) || max_length
        cut_at = max_length if cut_at < 1_000
        parts << rest[0...cut_at]
        rest = rest[cut_at..].to_s.strip
      end

      parts << rest unless rest.empty?
      parts
    end
  end
end
