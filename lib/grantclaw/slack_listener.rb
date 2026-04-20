# frozen_string_literal: true

require "slack-ruby-client"

module Grantclaw
  class SlackListener
    def initialize(processor:, config:, logger:)
      @processor = processor
      @config = config
      @logger = logger
      @bot_user_id = nil

      setup_clients
    end

    def start
      @logger.info("slack", "Connecting to Slack in Socket Mode...")
      fetch_bot_identity
      register_handlers
      @socket_client.start_async
      @logger.info("slack", "Slack listener started")
    end

    def stop
      @logger.info("slack", "Slack listener stopping")
    end

    def web_client
      @web_client
    end

    private

    def setup_clients
      Slack.configure do |c|
        c.token = ENV.fetch("SLACK_BOT_TOKEN")
      end

      @web_client = Slack::Web::Client.new
      @socket_client = Slack::RealTime::Client.new(
        token: ENV.fetch("SLACK_APP_TOKEN"),
        websocket_ping: 30
      )
    end

    def fetch_bot_identity
      auth = @web_client.auth_test
      @bot_user_id = auth["user_id"]
      @logger.info("slack", "Connected as #{auth['user']} (#{@bot_user_id})")
    rescue => e
      @logger.warn("slack", "Could not fetch bot identity: #{e.message}")
    end

    def register_handlers
      @socket_client.on :message do |data|
        handle_message(data)
      end
    end

    def handle_message(data)
      return if data["user"] == @bot_user_id
      return if data["subtype"] && data["subtype"] != "message_replied"

      channel_id = data["channel"]
      text = data["text"] || ""
      thread_ts = data["thread_ts"] || data["ts"]
      is_dm = data["channel_type"] == "im"

      return unless allowed_channel?(channel_id, is_dm)

      if requires_mention?(channel_id, is_dm) && !mentioned?(text)
        return
      end

      clean_text = text.gsub(/<@#{@bot_user_id}>/, "").strip

      @logger.info("slack", "Message from #{data['user']} in #{channel_id}: #{clean_text[0..80]}")

      history = fetch_thread_history(channel_id, thread_ts, data["ts"])

      begin
        result = @processor.process(
          user_message: clean_text,
          conversation_history: history,
          source: "slack"
        )

        @web_client.chat_postMessage(
          channel: channel_id,
          text: result[:content],
          thread_ts: thread_ts
        )
      rescue => e
        @logger.error("slack", "Error processing message: #{e.class}: #{e.message}")
        @web_client.chat_postMessage(
          channel: channel_id,
          text: "Sorry, I encountered an error processing your message.",
          thread_ts: thread_ts
        )
      end
    end

    def allowed_channel?(channel_id, is_dm)
      return true if is_dm && dm_policy == "open"

      channels = @config.slack.fetch("channels", [])
      channels.any? { |c| c["id"] == channel_id && c.fetch("allow", true) }
    end

    def requires_mention?(channel_id, is_dm)
      return false if is_dm

      channels = @config.slack.fetch("channels", [])
      ch = channels.find { |c| c["id"] == channel_id }
      ch&.fetch("require_mention", true) != false
    end

    def dm_policy
      @config.slack.fetch("dm_policy", "open")
    end

    def mentioned?(text)
      return false unless @bot_user_id

      text.include?("<@#{@bot_user_id}>")
    end

    def fetch_thread_history(channel, thread_ts, current_ts)
      return [] unless thread_ts && thread_ts != current_ts

      begin
        response = @web_client.conversations_replies(channel: channel, ts: thread_ts, limit: 50)
        messages = response["messages"] || []

        messages
          .reject { |m| m["ts"] == current_ts }
          .map { |m|
            role = m["user"] == @bot_user_id ? "assistant" : "user"
            { role: role, content: m["text"] || "" }
          }
      rescue => e
        @logger.warn("slack", "Could not fetch thread history: #{e.message}")
        []
      end
    end
  end
end
