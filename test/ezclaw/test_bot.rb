# frozen_string_literal: true

require_relative "../test_helper"

class TestBotShutdown < Minitest::Test
  # Structural regression: trap handlers must not invoke any code that
  # acquires a Mutex (logger, scheduler.stop, slack&.stop). Doing so
  # raises ThreadError ("can't be called from trap context") on a real
  # SIGTERM and crashes the pod.
  def test_run_production_traps_only_signal_a_queue
    src = File.read(File.expand_path("../../lib/ezclaw/bot.rb", __dir__))

    # Pull out everything between "def run_production" and the next "end\n    end"
    rp_match = src.match(/def run_production\b(.*?)^    end\b/m)
    assert rp_match, "run_production method not found in bot.rb"
    body = rp_match[1]

    # Each trap("INT"|"TERM") block must contain ONLY a Queue#<< call.
    trap_blocks = body.scan(/trap\(["'](?:INT|TERM)["']\)\s*\{([^}]+)\}|trap\(["'](?:INT|TERM)["']\)\s*do(.+?)end/m)
    refute_empty trap_blocks, "expected trap('INT'|'TERM') blocks in run_production"

    trap_blocks.flatten.compact.each do |block_body|
      refute_match(/@logger\./, block_body,
        "trap handler must NOT call @logger.* (mutex acquisition is unsafe in trap context)")
      refute_match(/scheduler\./, block_body,
        "trap handler must NOT call scheduler.* (rufus-scheduler.stop uses mutexes)")
      refute_match(/slack[?&]*\./, block_body,
        "trap handler must NOT call slack.* (slack-ruby-client cleanup uses mutexes)")
      refute_match(/exit\(/, block_body,
        "trap handler must NOT call exit; let the main thread do it after cleanup")
    end

    # The fix uses a Queue and pops from it in the main thread.
    assert_match(/Queue\.new/, body, "fix should create a Queue for trap signaling")
    assert_match(/\.pop\b/, body, "main thread should .pop from the shutdown queue")
  end

  # Functional check: a Queue trap handler can be invoked from a real signal
  # without raising ThreadError. We use SIGUSR2 (not INT/TERM) so the test
  # process doesn't actually shut down.
  def test_queue_push_in_trap_handler_is_signal_safe
    q = Queue.new
    previous = trap("USR2") { q << :usr2 }
    begin
      Process.kill("USR2", Process.pid)
      # Trap dispatch is asynchronous; poll briefly for the push.
      deadline = Time.now + 1.0
      sleep(0.01) while q.empty? && Time.now < deadline
      refute_empty q, "trap handler did not push within 1s"
      assert_equal :usr2, q.pop
    ensure
      trap("USR2", previous)
    end
  end
end
