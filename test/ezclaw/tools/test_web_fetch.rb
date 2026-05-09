# frozen_string_literal: true

require_relative "../../test_helper"
require "ezclaw/tools/web_fetch"

class TestWebFetchTool < Minitest::Test
  def setup
    @tool = Ezclaw::Tools::WebFetchTool.new
  end

  def test_rejects_non_http_scheme
    result = @tool.call(url: "ftp://example.com/foo")
    assert_match(/must start with http/, result)
  end

  def test_basic_get
    stub_request(:get, "https://example.com/").to_return(status: 200, body: "hello")
    result = @tool.call(url: "https://example.com/")
    assert_match(/^HTTP 200/, result)
    assert_match(/hello/, result)
  end

  def test_passes_headers_through_unchanged_when_no_vars
    stub_request(:get, "https://example.com/")
      .with(headers: { "X-Custom" => "literal-value" })
      .to_return(status: 200, body: "ok")
    result = @tool.call(url: "https://example.com/", headers: { "X-Custom" => "literal-value" })
    assert_match(/^HTTP 200/, result)
  end

  def test_expands_env_var_in_header_value
    ENV["TEST_API_KEY"] = "secret-abc-123"
    stub_request(:get, "https://example.com/")
      .with(headers: { "Authorization" => "Bearer secret-abc-123" })
      .to_return(status: 200, body: "ok")
    result = @tool.call(
      url: "https://example.com/",
      headers: { "Authorization" => "Bearer $TEST_API_KEY" }
    )
    assert_match(/^HTTP 200/, result)
  ensure
    ENV.delete("TEST_API_KEY")
  end

  def test_expands_multiple_env_vars_in_one_header
    ENV["TEST_USER"] = "alice"
    ENV["TEST_PASS"] = "wonderland"
    stub_request(:get, "https://example.com/")
      .with(headers: { "X-Auth" => "alice:wonderland" })
      .to_return(status: 200, body: "ok")
    result = @tool.call(
      url: "https://example.com/",
      headers: { "X-Auth" => "$TEST_USER:$TEST_PASS" }
    )
    assert_match(/^HTTP 200/, result)
  ensure
    ENV.delete("TEST_USER")
    ENV.delete("TEST_PASS")
  end

  def test_leaves_unknown_var_reference_unchanged
    # If the env var doesn't exist, pass through the literal $NAME so the
    # failure surfaces clearly to the LLM (rather than silently sending empty auth).
    ENV.delete("DEFINITELY_NOT_SET_VAR")
    stub_request(:get, "https://example.com/")
      .with(headers: { "Authorization" => "Bearer $DEFINITELY_NOT_SET_VAR" })
      .to_return(status: 200, body: "ok")
    result = @tool.call(
      url: "https://example.com/",
      headers: { "Authorization" => "Bearer $DEFINITELY_NOT_SET_VAR" }
    )
    assert_match(/^HTTP 200/, result)
  end

  def test_does_not_treat_lowercase_dollar_words_as_vars
    # Bash-style env vars are uppercase. `$foo` or `$Foo` should pass through
    # untouched so we don't accidentally mangle JSON tokens like `$set`, `$pageview`, etc.
    stub_request(:get, "https://example.com/")
      .with(headers: { "X-Body-Hint" => "use $set and $pageview" })
      .to_return(status: 200, body: "ok")
    result = @tool.call(
      url: "https://example.com/",
      headers: { "X-Body-Hint" => "use $set and $pageview" }
    )
    assert_match(/^HTTP 200/, result)
  end

  def test_post_with_body_and_expanded_header
    ENV["TEST_API_KEY"] = "k-xyz"
    stub_request(:post, "https://example.com/api")
      .with(
        headers: { "Authorization" => "Bearer k-xyz", "Content-Type" => "application/json" },
        body: '{"q":1}'
      )
      .to_return(status: 200, body: '{"ok":true}')
    result = @tool.call(
      url: "https://example.com/api",
      method: "post",
      headers: { "Authorization" => "Bearer $TEST_API_KEY", "Content-Type" => "application/json" },
      body: '{"q":1}'
    )
    assert_match(/^HTTP 200/, result)
    assert_match(/"ok":true/, result)
  ensure
    ENV.delete("TEST_API_KEY")
  end

  def test_truncates_long_response_body
    big = "x" * 60_000
    stub_request(:get, "https://example.com/big").to_return(status: 200, body: big)
    result = @tool.call(url: "https://example.com/big")
    assert_match(/Truncated/, result)
  end
end
