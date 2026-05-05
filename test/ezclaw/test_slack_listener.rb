# frozen_string_literal: true

require_relative "../test_helper"
require "ezclaw/slack_listener"
require "tmpdir"

class TestSlackListener < Minitest::Test
  def setup
    @prev_bot_token = ENV["SLACK_BOT_TOKEN"]
    @prev_app_token = ENV["SLACK_APP_TOKEN"]
    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    ENV["SLACK_APP_TOKEN"] = "xapp-test"

    @output = StringIO.new
    @logger = Ezclaw::Log.new(output: @output, level: :debug)
    @config = Object.new
    def @config.slack
      { "channels" => [], "dm_policy" => "open" }
    end
  end

  def teardown
    ENV["SLACK_BOT_TOKEN"] = @prev_bot_token
    ENV["SLACK_APP_TOKEN"] = @prev_app_token
  end

  def build_listener(heartbeat_path: nil, watchdog_seconds: 90)
    Ezclaw::SlackListener.new(
      processor: Object.new,
      config: @config,
      logger: @logger,
      heartbeat_path: heartbeat_path,
      watchdog_seconds: watchdog_seconds
    )
  end

  def test_touch_heartbeat_creates_file_when_path_configured
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".slack_alive")
      listener = build_listener(heartbeat_path: path)
      listener.send(:touch_heartbeat)
      assert File.exist?(path), "expected heartbeat file to be created at #{path}"
    end
  end

  def test_touch_heartbeat_updates_mtime_on_subsequent_calls
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".slack_alive")
      listener = build_listener(heartbeat_path: path)
      listener.send(:touch_heartbeat)
      old_mtime = File.mtime(path)
      sleep 1.1
      listener.send(:touch_heartbeat)
      new_mtime = File.mtime(path)
      assert new_mtime > old_mtime, "expected mtime to advance on second touch"
    end
  end

  def test_touch_heartbeat_is_noop_when_path_nil
    listener = build_listener(heartbeat_path: nil)
    # Should not raise
    listener.send(:touch_heartbeat)
  end

  def test_touch_heartbeat_swallows_filesystem_errors
    listener = build_listener(heartbeat_path: "/proc/cannot-write-here/.slack_alive")
    # Must not raise — heartbeat failure should never crash the listener
    listener.send(:touch_heartbeat)
    assert_match(/heartbeat/i, @output.string)
  end

  def test_record_event_updates_last_event_timestamp
    listener = build_listener
    before = Time.now
    listener.send(:record_event)
    after = Time.now
    last = listener.instance_variable_get(:@last_event_at)
    refute_nil last
    assert last >= before
    assert last <= after
  end

  def test_traffic_stale_returns_true_when_no_traffic_for_too_long
    listener = build_listener(watchdog_seconds: 60)
    listener.instance_variable_set(:@last_event_at, Time.now - 120)
    assert listener.send(:traffic_stale?), "expected traffic to be considered stale"
  end

  def test_traffic_stale_returns_false_when_recent_traffic
    listener = build_listener(watchdog_seconds: 60)
    listener.instance_variable_set(:@last_event_at, Time.now - 5)
    refute listener.send(:traffic_stale?), "expected traffic not to be stale"
  end

  def test_traffic_stale_returns_false_before_first_event
    listener = build_listener(watchdog_seconds: 60)
    refute listener.send(:traffic_stale?), "expected not stale before any event"
  end

  def test_schedule_reconnect_is_debounced
    listener = build_listener
    # First call should mark reconnect pending and yield "scheduled"
    assert_equal :scheduled, listener.send(:schedule_reconnect, :test) { :ran }
    # Second call while reconnect is pending should be skipped
    assert_equal :skipped, listener.send(:schedule_reconnect, :test) { :ran }
  end

  def test_schedule_reconnect_can_be_called_again_after_clear
    listener = build_listener
    assert_equal :scheduled, listener.send(:schedule_reconnect, :test) { :ran }
    listener.send(:clear_reconnect_pending)
    assert_equal :scheduled, listener.send(:schedule_reconnect, :test) { :ran }
  end
end
