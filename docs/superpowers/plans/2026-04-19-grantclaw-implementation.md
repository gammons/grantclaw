# Grantclaw Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a simple Ruby bot framework that connects to Slack, runs scheduled tasks via internal cron, and uses LLM tool calling to execute actions.

**Architecture:** Long-running Ruby process with three threads (Slack socket mode listener, rufus-scheduler cron, optional readline REPL) feeding into a shared message processor that builds prompts from file-based context, calls LLMs via pluggable adapters, and executes tool calls defined as Ruby classes.

**Tech Stack:** Ruby 3.3, minitest, faraday, slack-ruby-client, rufus-scheduler, Docker, Helm

---

## File Structure

```
grantclaw/
  grantclaw.rb                    # Entry point: CLI parsing, thread orchestration
  Gemfile                         # Gem dependencies
  Dockerfile                      # Container image
  lib/
    grantclaw.rb                  # Module root, version constant, requires
    grantclaw/
      config.rb                   # Loads and validates config.yaml
      logger.rb                   # Structured logger with component tags
      llm/
        base.rb                   # LLM adapter interface
        openrouter.rb             # OpenRouter (OpenAI-compatible) adapter
        anthropic.rb              # Anthropic native API adapter
        custom.rb                 # Custom provider adapter
      tool.rb                     # Tool base class with DSL (desc, param)
      tool_registry.rb            # Loads tool files, registers classes
      tools/
        update_memory.rb          # Built-in: update memory.md
        slack_post.rb             # Built-in: post to Slack channel
      memory.rb                   # Read/write memory file
      message_processor.rb        # Core: prompt building, LLM loop, tool dispatch
      slack_listener.rb           # Slack socket mode event handler
      scheduler.rb                # Cron scheduler wrapper
      repl.rb                     # Debug REPL
      bot.rb                      # Bot loader: reads config dir, wires components
  test/
    test_helper.rb                # Minitest setup, shared fixtures
    grantclaw/
      test_config.rb
      test_logger.rb
      test_tool.rb
      test_tool_registry.rb
      test_memory.rb
      test_message_processor.rb
      llm/
        test_openrouter.rb
        test_anthropic.rb
        test_custom.rb
  helm/
    grantclaw/
      Chart.yaml
      values.yaml
      templates/
        deployment.yaml
        configmap.yaml
        pvc.yaml
        _helpers.tpl
  bots/
    pulse/
      config.yaml
      role.md
      memory.md
      heartbeat.md
      tools/
        example_tool.rb
```

---

### Task 1: Project Setup

**Files:**
- Create: `Gemfile`
- Create: `lib/grantclaw.rb`
- Create: `test/test_helper.rb`
- Create: `grantclaw.rb`
- Create: `.ruby-version`

- [ ] **Step 1: Create Gemfile**

```ruby
# Gemfile
source "https://rubygems.org"

gem "faraday", "~> 2.9"
gem "slack-ruby-client", "~> 2.3"
gem "rufus-scheduler", "~> 3.9"

group :test do
  gem "minitest", "~> 5.22"
  gem "webmock", "~> 3.23"
end
```

- [ ] **Step 2: Create .ruby-version**

```
3.3
```

- [ ] **Step 3: Create module root**

Create `lib/grantclaw.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  VERSION = "0.1.0"
end

require_relative "grantclaw/config"
require_relative "grantclaw/logger"
require_relative "grantclaw/llm/base"
require_relative "grantclaw/llm/openrouter"
require_relative "grantclaw/llm/anthropic"
require_relative "grantclaw/llm/custom"
require_relative "grantclaw/tool"
require_relative "grantclaw/tool_registry"
require_relative "grantclaw/memory"
require_relative "grantclaw/message_processor"
require_relative "grantclaw/slack_listener"
require_relative "grantclaw/scheduler"
require_relative "grantclaw/repl"
require_relative "grantclaw/bot"
```

- [ ] **Step 4: Create test helper**

Create `test/test_helper.rb`:

```ruby
# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"
require_relative "../lib/grantclaw"

# Fixtures directory
FIXTURES_DIR = File.join(__dir__, "fixtures")

# Create a minimal bot config for tests
def minimal_config(overrides = {})
  {
    "name" => "test-bot",
    "llm" => {
      "provider" => "openrouter",
      "model" => "anthropic/claude-sonnet-4-20250514",
      "max_tokens" => 1024
    },
    "context" => {
      "system_files" => ["role.md"],
      "memory_file" => "memory.md"
    }
  }.merge(overrides)
end
```

- [ ] **Step 5: Create entry point skeleton**

Create `grantclaw.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/grantclaw"

puts "Grantclaw v#{Grantclaw::VERSION}"
```

- [ ] **Step 6: Bundle install**

Run: `bundle install`
Expected: Gems install successfully, `Gemfile.lock` is created.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: project setup with Gemfile, module root, test helper"
```

---

### Task 2: Logger

**Files:**
- Create: `lib/grantclaw/logger.rb`
- Create: `test/grantclaw/test_logger.rb`

- [ ] **Step 1: Write the failing test**

Create `test/grantclaw/test_logger.rb`:

```ruby
# frozen_string_literal: true

require_relative "../test_helper"

class TestLogger < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = Grantclaw::Log.new(output: @output, level: :info)
  end

  def test_info_message_with_component
    @logger.info("cron", "Triggered: weekly_report")
    line = @output.string
    assert_match(/INFO/, line)
    assert_match(/\[cron\]/, line)
    assert_match(/Triggered: weekly_report/, line)
  end

  def test_debug_suppressed_at_info_level
    @logger.debug("llm", "verbose stuff")
    assert_empty @output.string
  end

  def test_debug_shown_at_debug_level
    logger = Grantclaw::Log.new(output: @output, level: :debug)
    logger.debug("llm", "verbose stuff")
    assert_match(/DEBUG/, @output.string)
  end

  def test_error_message
    @logger.error("slack", "Connection failed")
    assert_match(/ERROR/, @output.string)
    assert_match(/\[slack\]/, @output.string)
  end

  def test_level_from_string
    logger = Grantclaw::Log.new(output: @output, level: "warn")
    logger.info("test", "should not appear")
    assert_empty @output.string
    logger.warn("test", "should appear")
    assert_match(/WARN/, @output.string)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/test_logger.rb`
Expected: FAIL — `Grantclaw::Log` not defined.

- [ ] **Step 3: Implement the logger**

Create `lib/grantclaw/logger.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  class Log
    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    def initialize(output: $stdout, level: :info)
      @output = output
      @level = resolve_level(level)
      @mutex = Mutex.new
    end

    def debug(component, message) = log(:debug, component, message)
    def info(component, message)  = log(:info, component, message)
    def warn(component, message)  = log(:warn, component, message)
    def error(component, message) = log(:error, component, message)

    private

    def log(level, component, message)
      return if LEVELS[level] < @level

      timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      label = level.to_s.upcase.ljust(5)
      line = "[#{timestamp}] #{label} [#{component}] #{message}\n"

      @mutex.synchronize { @output.write(line) }
    end

    def resolve_level(level)
      level = level.to_sym if level.is_a?(String)
      LEVELS.fetch(level) { raise ArgumentError, "Unknown log level: #{level}" }
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/test_logger.rb`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add structured logger with component tags and level filtering"
```

---

### Task 3: Config Loader

**Files:**
- Create: `lib/grantclaw/config.rb`
- Create: `test/grantclaw/test_config.rb`
- Create: `test/fixtures/bot/config.yaml`
- Create: `test/fixtures/bot/role.md`
- Create: `test/fixtures/bot/memory.md`

- [ ] **Step 1: Create test fixtures**

Create `test/fixtures/bot/config.yaml`:

```yaml
name: test-bot

slack:
  channels:
    - id: C12345
      name: general
      require_mention: true
  dm_policy: open

llm:
  provider: openrouter
  model: anthropic/claude-sonnet-4-20250514
  max_tokens: 1024

schedule:
  heartbeat: "*/10 * * * *"

context:
  system_files:
    - role.md
  memory_file: memory.md

logging:
  level: debug
```

Create `test/fixtures/bot/role.md`:

```markdown
# Test Bot
You are a test bot.
```

Create `test/fixtures/bot/memory.md`:

```markdown
# Memory
No memories yet.
```

- [ ] **Step 2: Write the failing test**

Create `test/grantclaw/test_config.rb`:

```ruby
# frozen_string_literal: true

require_relative "../test_helper"

class TestConfig < Minitest::Test
  def setup
    @config = Grantclaw::Config.load(File.join(FIXTURES_DIR, "bot"))
  end

  def test_loads_name
    assert_equal "test-bot", @config.name
  end

  def test_loads_llm_config
    assert_equal "openrouter", @config.llm["provider"]
    assert_equal "anthropic/claude-sonnet-4-20250514", @config.llm["model"]
    assert_equal 1024, @config.llm["max_tokens"]
  end

  def test_loads_slack_channels
    channels = @config.slack["channels"]
    assert_equal 1, channels.length
    assert_equal "C12345", channels.first["id"]
  end

  def test_loads_schedule
    assert_equal "*/10 * * * *", @config.schedule["heartbeat"]
  end

  def test_loads_system_files_content
    system_prompt = @config.system_prompt
    assert_includes system_prompt, "# Test Bot"
    assert_includes system_prompt, "You are a test bot."
  end

  def test_loads_memory_content
    assert_includes @config.memory_content, "No memories yet."
  end

  def test_bot_dir
    assert_equal File.join(FIXTURES_DIR, "bot"), @config.bot_dir
  end

  def test_log_level
    assert_equal "debug", @config.log_level
  end

  def test_log_level_defaults_to_info
    # Create a config without logging section
    config = Grantclaw::Config.new(
      {"name" => "x", "llm" => {}, "context" => {"system_files" => [], "memory_file" => "memory.md"}},
      FIXTURES_DIR
    )
    assert_equal "info", config.log_level
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/test_config.rb`
Expected: FAIL — `Grantclaw::Config` not defined.

- [ ] **Step 4: Implement Config**

Create `lib/grantclaw/config.rb`:

```ruby
# frozen_string_literal: true

require "yaml"

module Grantclaw
  class Config
    attr_reader :bot_dir

    def self.load(bot_dir)
      yaml = YAML.safe_load_file(File.join(bot_dir, "config.yaml"))
      new(yaml, bot_dir)
    end

    def initialize(yaml, bot_dir)
      @yaml = yaml
      @bot_dir = bot_dir
    end

    def name
      @yaml["name"]
    end

    def llm
      @yaml.fetch("llm", {})
    end

    def slack
      @yaml.fetch("slack", {})
    end

    def schedule
      @yaml.fetch("schedule", {})
    end

    def context
      @yaml.fetch("context", {})
    end

    def log_level
      @yaml.dig("logging", "level") || "info"
    end

    def system_prompt
      files = context.fetch("system_files", [])
      files.map { |f| read_bot_file(f) }.join("\n---\n")
    end

    def memory_content
      file = context["memory_file"]
      return "" unless file

      read_bot_file(file)
    end

    private

    def read_bot_file(filename)
      path = File.join(@bot_dir, filename)
      return "" unless File.exist?(path)

      File.read(path)
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/test_config.rb`
Expected: All 9 tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add config loader for bot directory"
```

---

### Task 4: Tool Base Class & Registry

**Files:**
- Create: `lib/grantclaw/tool.rb`
- Create: `lib/grantclaw/tool_registry.rb`
- Create: `test/grantclaw/test_tool.rb`
- Create: `test/grantclaw/test_tool_registry.rb`
- Create: `test/fixtures/bot/tools/greet.rb`

- [ ] **Step 1: Write the failing test for Tool base class**

Create `test/grantclaw/test_tool.rb`:

```ruby
# frozen_string_literal: true

require_relative "../test_helper"

# Define a test tool inline
class GreetTool < Grantclaw::Tool
  desc "Greet a person by name"
  param :name, type: :string, desc: "Person's name", required: true
  param :style, type: :string, enum: %w[formal casual], default: "casual"

  def call(name:, style: "casual")
    if style == "formal"
      "Good day, #{name}."
    else
      "Hey #{name}!"
    end
  end
end

class TestTool < Minitest::Test
  def test_tool_description
    assert_equal "Greet a person by name", GreetTool.tool_description
  end

  def test_tool_params
    params = GreetTool.tool_params
    assert_equal 2, params.length
    assert_equal :name, params[0][:name]
    assert_equal true, params[0][:required]
    assert_equal :style, params[1][:name]
    assert_equal %w[formal casual], params[1][:enum]
  end

  def test_json_schema
    schema = GreetTool.json_schema
    assert_equal "greet", schema[:name]
    assert_equal "Greet a person by name", schema[:description]
    props = schema[:parameters][:properties]
    assert_includes props.keys, "name"
    assert_includes props.keys, "style"
    assert_equal %w[name], schema[:parameters][:required]
  end

  def test_call
    tool = GreetTool.new
    assert_equal "Hey Grant!", tool.call(name: "Grant")
    assert_equal "Good day, Grant.", tool.call(name: "Grant", style: "formal")
  end

  def test_tool_name_derived_from_class
    assert_equal "greet", GreetTool.tool_name
  end

  def test_execute_catches_errors
    bad_tool_class = Class.new(Grantclaw::Tool) do
      desc "broken"
      def call
        raise "boom"
      end
    end
    result = bad_tool_class.new.execute({})
    assert_includes result, "Error"
    assert_includes result, "boom"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/test_tool.rb`
Expected: FAIL — `Grantclaw::Tool` not defined.

- [ ] **Step 3: Implement Tool base class**

Create `lib/grantclaw/tool.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  class Tool
    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@params, [])
        subclass.instance_variable_set(:@description, "")
      end

      def desc(text)
        @description = text
      end

      def param(name, type: :string, desc: nil, enum: nil, required: false, default: nil)
        @params << { name: name, type: type, desc: desc, enum: enum, required: required, default: default }
      end

      def tool_description
        @description
      end

      def tool_params
        @params
      end

      def tool_name
        name_str = self.name || self.to_s
        # "GreetTool" -> "greet", "SlackPostTool" -> "slack_post"
        name_str.split("::").last
          .gsub(/Tool$/, "")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      def json_schema
        properties = {}
        required = []

        tool_params.each do |p|
          prop = { type: p[:type].to_s }
          prop[:description] = p[:desc] if p[:desc]
          prop[:enum] = p[:enum] if p[:enum]
          properties[p[:name].to_s] = prop
          required << p[:name].to_s if p[:required]
        end

        {
          name: tool_name,
          description: tool_description,
          parameters: {
            type: "object",
            properties: properties,
            required: required
          }
        }
      end
    end

    def execute(arguments)
      kwargs = {}
      self.class.tool_params.each do |p|
        key = p[:name]
        str_key = key.to_s
        if arguments.key?(str_key)
          kwargs[key] = arguments[str_key]
        elsif arguments.key?(key)
          kwargs[key] = arguments[key]
        elsif p[:default]
          kwargs[key] = p[:default]
        end
      end
      result = call(**kwargs)
      result.is_a?(String) ? result : JSON.generate(result)
    rescue => e
      "Error executing #{self.class.tool_name}: #{e.message}"
    end

    def call(**kwargs)
      raise NotImplementedError, "#{self.class}#call not implemented"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/test_tool.rb`
Expected: All 6 tests pass.

- [ ] **Step 5: Write the failing test for ToolRegistry**

Create `test/fixtures/bot/tools/greet.rb`:

```ruby
# frozen_string_literal: true

class FixtureGreetTool < Grantclaw::Tool
  desc "Greet someone"
  param :name, type: :string, required: true

  def call(name:)
    "Hello, #{name}!"
  end
end
```

Create `test/grantclaw/test_tool_registry.rb`:

```ruby
# frozen_string_literal: true

require_relative "../test_helper"

class TestToolRegistry < Minitest::Test
  def setup
    @registry = Grantclaw::ToolRegistry.new
  end

  def test_register_and_find
    klass = Class.new(Grantclaw::Tool) do
      desc "test tool"
      def call; "ok"; end
    end
    @registry.register("test", klass)
    assert_equal klass, @registry.find("test")
  end

  def test_find_returns_nil_for_unknown
    assert_nil @registry.find("nope")
  end

  def test_load_from_directory
    tools_dir = File.join(FIXTURES_DIR, "bot", "tools")
    @registry.load_directory(tools_dir)
    assert @registry.find("fixture_greet"), "Expected fixture_greet tool to be registered"
  end

  def test_schemas_returns_all_tool_schemas
    klass = Class.new(Grantclaw::Tool) do
      desc "a tool"
      param :x, type: :string, required: true
      def call(x:); x; end
    end
    # Give it a name for tool_name derivation
    Object.const_set(:SchemaDemoTool, klass)
    @registry.register("schema_demo", klass)
    schemas = @registry.schemas
    assert schemas.any? { |s| s[:name] == "schema_demo" }
  ensure
    Object.send(:remove_const, :SchemaDemoTool) if defined?(SchemaDemoTool)
  end

  def test_execute_tool
    klass = Class.new(Grantclaw::Tool) do
      desc "adder"
      param :a, type: :integer, required: true
      def call(a:); { result: a.to_i + 1 }; end
    end
    @registry.register("adder", klass)
    result = @registry.execute("adder", { "a" => 5 })
    assert_includes result, "6"
  end
end
```

- [ ] **Step 6: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/test_tool_registry.rb`
Expected: FAIL — `Grantclaw::ToolRegistry` not defined.

- [ ] **Step 7: Implement ToolRegistry**

Create `lib/grantclaw/tool_registry.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  class ToolRegistry
    def initialize
      @tools = {}
    end

    def register(name, klass)
      @tools[name] = klass
    end

    def find(name)
      @tools[name]
    end

    def load_directory(dir)
      return unless dir && Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.rb")).each do |file|
        # Track existing Tool subclasses before loading
        before = ObjectSpace.each_object(Class).select { |c| c < Grantclaw::Tool }.to_set
        Kernel.load(file)
        after = ObjectSpace.each_object(Class).select { |c| c < Grantclaw::Tool }.to_set

        (after - before).each do |klass|
          register(klass.tool_name, klass)
        end
      end
    end

    def schemas
      @tools.map { |name, klass| klass.json_schema.merge(name: name) }
    end

    def execute(name, arguments)
      klass = find(name)
      return "Error: unknown tool '#{name}'" unless klass

      klass.new.execute(arguments)
    end
  end
end
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/test_tool_registry.rb`
Expected: All 5 tests pass.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add tool base class with DSL and tool registry"
```

---

### Task 5: LLM Adapters — OpenRouter

**Files:**
- Create: `lib/grantclaw/llm/base.rb`
- Create: `lib/grantclaw/llm/openrouter.rb`
- Create: `test/grantclaw/llm/test_openrouter.rb`

- [ ] **Step 1: Write the failing test**

Create `test/grantclaw/llm/test_openrouter.rb`:

```ruby
# frozen_string_literal: true

require_relative "../../test_helper"

class TestOpenRouter < Minitest::Test
  def setup
    ENV["OPENROUTER_API_KEY"] = "test-key"
    @adapter = Grantclaw::LLM::OpenRouter.new(model: "anthropic/claude-sonnet-4-20250514", max_tokens: 1024)
  end

  def teardown
    ENV.delete("OPENROUTER_API_KEY")
  end

  def test_chat_text_response
    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .with(
        headers: { "Authorization" => "Bearer test-key", "Content-Type" => "application/json" }
      )
      .to_return(
        status: 200,
        body: JSON.generate({
          choices: [{ message: { role: "assistant", content: "Hello!" } }],
          usage: { prompt_tokens: 10, completion_tokens: 5 }
        }),
        headers: { "Content-Type" => "application/json" }
      )

    result = @adapter.chat(messages: [{ role: "user", content: "Hi" }])
    assert_equal "assistant", result[:role]
    assert_equal "Hello!", result[:content]
    assert_nil result[:tool_calls]
  end

  def test_chat_with_tool_calls
    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .to_return(
        status: 200,
        body: JSON.generate({
          choices: [{ message: {
            role: "assistant",
            content: nil,
            tool_calls: [{
              id: "call_123",
              type: "function",
              function: { name: "greet", arguments: '{"name":"Grant"}' }
            }]
          } }],
          usage: { prompt_tokens: 10, completion_tokens: 20 }
        }),
        headers: { "Content-Type" => "application/json" }
      )

    result = @adapter.chat(
      messages: [{ role: "user", content: "Greet Grant" }],
      tools: [{ name: "greet", description: "Greet", parameters: { type: "object", properties: { "name" => { type: "string" } }, required: ["name"] } }]
    )

    assert_equal 1, result[:tool_calls].length
    assert_equal "greet", result[:tool_calls][0][:name]
    assert_equal({ "name" => "Grant" }, result[:tool_calls][0][:arguments])
  end

  def test_sends_tools_in_openai_format
    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .to_return(
        status: 200,
        body: JSON.generate({ choices: [{ message: { role: "assistant", content: "ok" } }], usage: { prompt_tokens: 1, completion_tokens: 1 } }),
        headers: { "Content-Type" => "application/json" }
      )

    @adapter.chat(
      messages: [{ role: "user", content: "test" }],
      tools: [{ name: "foo", description: "bar", parameters: { type: "object", properties: {} } }]
    )

    request = WebMock::API.a_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .with { |req| body = JSON.parse(req.body); body["tools"]&.first&.dig("function", "name") == "foo" }
    assert_requested(request)
  end

  def test_retries_on_server_error
    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .to_return(status: 500, body: "Internal Server Error")
      .then
      .to_return(
        status: 200,
        body: JSON.generate({ choices: [{ message: { role: "assistant", content: "ok" } }], usage: { prompt_tokens: 1, completion_tokens: 1 } }),
        headers: { "Content-Type" => "application/json" }
      )

    result = @adapter.chat(messages: [{ role: "user", content: "test" }])
    assert_equal "ok", result[:content]
  end

  def test_raises_after_max_retries
    stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .to_return(status: 500, body: "fail").times(3)

    assert_raises(Grantclaw::LLM::APIError) do
      @adapter.chat(messages: [{ role: "user", content: "test" }])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/llm/test_openrouter.rb`
Expected: FAIL — `Grantclaw::LLM::Base` not defined.

- [ ] **Step 3: Implement LLM::Base**

Create `lib/grantclaw/llm/base.rb`:

```ruby
# frozen_string_literal: true

require "faraday"
require "json"

module Grantclaw
  module LLM
    class APIError < StandardError; end

    class Base
      MAX_RETRIES = 3

      def initialize(model:, max_tokens: 4096)
        @model = model
        @max_tokens = max_tokens
      end

      # Returns: { role: "assistant", content: String|nil, tool_calls: Array|nil, usage: Hash }
      def chat(messages:, tools: [], model: nil)
        raise NotImplementedError
      end

      private

      def with_retries
        attempts = 0
        begin
          attempts += 1
          yield
        rescue APIError => e
          raise if attempts >= MAX_RETRIES

          sleep(0.1 * (2**attempts))
          retry
        end
      end
    end
  end
end
```

- [ ] **Step 4: Implement LLM::OpenRouter**

Create `lib/grantclaw/llm/openrouter.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  module LLM
    class OpenRouter < Base
      BASE_URL = "https://openrouter.ai/api/v1/chat/completions"

      def initialize(model:, max_tokens: 4096, api_key_env: "OPENROUTER_API_KEY")
        super(model: model, max_tokens: max_tokens)
        @api_key = ENV.fetch(api_key_env)
        @conn = Faraday.new(url: BASE_URL) do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
        end
      end

      def chat(messages:, tools: [], model: nil)
        with_retries do
          body = build_request(messages, tools, model)
          response = @conn.post { |req|
            req.headers["Authorization"] = "Bearer #{@api_key}"
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.generate(body)
          }

          raise APIError, "HTTP #{response.status}: #{response.body}" unless response.status == 200

          parse_response(response.body)
        end
      end

      private

      def build_request(messages, tools, model)
        body = {
          model: model || @model,
          messages: messages.map { |m| normalize_message(m) },
          max_tokens: @max_tokens
        }

        if tools.any?
          body[:tools] = tools.map { |t| openai_tool(t) }
        end

        body
      end

      def normalize_message(msg)
        # Accept both string keys and symbol keys
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]
        tool_call_id = msg[:tool_call_id] || msg["tool_call_id"]

        result = { role: role, content: content }
        result[:tool_call_id] = tool_call_id if tool_call_id
        result
      end

      def openai_tool(tool)
        {
          type: "function",
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:parameters]
          }
        }
      end

      def parse_response(body)
        msg = body.is_a?(String) ? JSON.parse(body) : body
        choice = msg["choices"]&.first&.fetch("message", {})
        usage = msg["usage"] || {}

        tool_calls = nil
        if choice["tool_calls"]&.any?
          tool_calls = choice["tool_calls"].map do |tc|
            {
              id: tc["id"],
              name: tc.dig("function", "name"),
              arguments: JSON.parse(tc.dig("function", "arguments") || "{}")
            }
          end
        end

        {
          role: "assistant",
          content: choice["content"],
          tool_calls: tool_calls,
          usage: { input: usage["prompt_tokens"], output: usage["completion_tokens"] }
        }
      end
    end
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/llm/test_openrouter.rb`
Expected: All 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add LLM base class and OpenRouter adapter"
```

---

### Task 6: LLM Adapters — Anthropic

**Files:**
- Create: `lib/grantclaw/llm/anthropic.rb`
- Create: `test/grantclaw/llm/test_anthropic.rb`

- [ ] **Step 1: Write the failing test**

Create `test/grantclaw/llm/test_anthropic.rb`:

```ruby
# frozen_string_literal: true

require_relative "../../test_helper"

class TestAnthropic < Minitest::Test
  def setup
    ENV["ANTHROPIC_API_KEY"] = "test-key"
    @adapter = Grantclaw::LLM::Anthropic.new(model: "claude-sonnet-4-20250514", max_tokens: 1024)
  end

  def teardown
    ENV.delete("ANTHROPIC_API_KEY")
  end

  def test_chat_text_response
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: JSON.generate({
          content: [{ type: "text", text: "Hello!" }],
          usage: { input_tokens: 10, output_tokens: 5 }
        }),
        headers: { "Content-Type" => "application/json" }
      )

    result = @adapter.chat(messages: [
      { role: "system", content: "You are helpful." },
      { role: "user", content: "Hi" }
    ])
    assert_equal "assistant", result[:role]
    assert_equal "Hello!", result[:content]
  end

  def test_extracts_system_from_messages
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: JSON.generate({ content: [{ type: "text", text: "ok" }], usage: { input_tokens: 1, output_tokens: 1 } }),
        headers: { "Content-Type" => "application/json" }
      )

    @adapter.chat(messages: [
      { role: "system", content: "Be concise." },
      { role: "user", content: "Hi" }
    ])

    request = WebMock::API.a_request(:post, "https://api.anthropic.com/v1/messages")
      .with { |req|
        body = JSON.parse(req.body)
        body["system"] == "Be concise." &&
          body["messages"].none? { |m| m["role"] == "system" }
      }
    assert_requested(request)
  end

  def test_chat_with_tool_calls
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: JSON.generate({
          content: [
            { type: "tool_use", id: "tu_123", name: "greet", input: { "name" => "Grant" } }
          ],
          usage: { input_tokens: 10, output_tokens: 20 }
        }),
        headers: { "Content-Type" => "application/json" }
      )

    result = @adapter.chat(
      messages: [{ role: "user", content: "Greet Grant" }],
      tools: [{ name: "greet", description: "Greet", parameters: { type: "object", properties: { "name" => { type: "string" } }, required: ["name"] } }]
    )

    assert_equal 1, result[:tool_calls].length
    assert_equal "greet", result[:tool_calls][0][:name]
    assert_equal({ "name" => "Grant" }, result[:tool_calls][0][:arguments])
  end

  def test_tool_result_message_format
    # Test that tool results are formatted for Anthropic's API
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 200,
        body: JSON.generate({ content: [{ type: "text", text: "Got it." }], usage: { input_tokens: 1, output_tokens: 1 } }),
        headers: { "Content-Type" => "application/json" }
      )

    @adapter.chat(messages: [
      { role: "user", content: "do it" },
      { role: "assistant", content: nil, tool_calls: [{ id: "tu_1", name: "greet", arguments: { "name" => "X" } }] },
      { role: "tool", tool_call_id: "tu_1", content: "Hello X!" }
    ])

    request = WebMock::API.a_request(:post, "https://api.anthropic.com/v1/messages")
      .with { |req|
        body = JSON.parse(req.body)
        msgs = body["messages"]
        # Anthropic format: assistant has tool_use content, then user has tool_result content
        msgs.any? { |m| m["role"] == "user" && m["content"].is_a?(Array) && m["content"].any? { |c| c["type"] == "tool_result" } }
      }
    assert_requested(request)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/llm/test_anthropic.rb`
Expected: FAIL — `Grantclaw::LLM::Anthropic` not defined.

- [ ] **Step 3: Implement LLM::Anthropic**

Create `lib/grantclaw/llm/anthropic.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  module LLM
    class Anthropic < Base
      BASE_URL = "https://api.anthropic.com/v1/messages"

      def initialize(model:, max_tokens: 4096, api_key_env: "ANTHROPIC_API_KEY")
        super(model: model, max_tokens: max_tokens)
        @api_key = ENV.fetch(api_key_env)
        @conn = Faraday.new(url: BASE_URL) do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
        end
      end

      def chat(messages:, tools: [], model: nil)
        with_retries do
          body = build_request(messages, tools, model)
          response = @conn.post { |req|
            req.headers["x-api-key"] = @api_key
            req.headers["anthropic-version"] = "2023-06-01"
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.generate(body)
          }

          raise APIError, "HTTP #{response.status}: #{response.body}" unless response.status == 200

          parse_response(response.body)
        end
      end

      private

      def build_request(messages, tools, model)
        system_text, converted = convert_messages(messages)

        body = {
          model: model || @model,
          messages: converted,
          max_tokens: @max_tokens
        }
        body[:system] = system_text if system_text
        body[:tools] = tools.map { |t| anthropic_tool(t) } if tools.any?

        body
      end

      def convert_messages(messages)
        system_text = nil
        converted = []

        messages.each do |msg|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]

          case role
          when "system"
            system_text = content
          when "assistant"
            tool_calls = msg[:tool_calls] || msg["tool_calls"]
            if tool_calls&.any?
              converted << {
                role: "assistant",
                content: tool_calls.map { |tc|
                  { type: "tool_use", id: tc[:id], name: tc[:name], input: tc[:arguments] }
                }
              }
            else
              converted << { role: "assistant", content: content }
            end
          when "tool"
            tool_call_id = msg[:tool_call_id] || msg["tool_call_id"]
            # Anthropic expects tool results as user messages with tool_result content
            converted << {
              role: "user",
              content: [{ type: "tool_result", tool_use_id: tool_call_id, content: content }]
            }
          else
            converted << { role: role, content: content }
          end
        end

        [system_text, converted]
      end

      def anthropic_tool(tool)
        {
          name: tool[:name],
          description: tool[:description],
          input_schema: tool[:parameters]
        }
      end

      def parse_response(body)
        data = body.is_a?(String) ? JSON.parse(body) : body
        usage = data["usage"] || {}

        content_text = nil
        tool_calls = nil

        (data["content"] || []).each do |block|
          case block["type"]
          when "text"
            content_text = block["text"]
          when "tool_use"
            tool_calls ||= []
            tool_calls << {
              id: block["id"],
              name: block["name"],
              arguments: block["input"]
            }
          end
        end

        {
          role: "assistant",
          content: content_text,
          tool_calls: tool_calls,
          usage: { input: usage["input_tokens"], output: usage["output_tokens"] }
        }
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/llm/test_anthropic.rb`
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Anthropic LLM adapter"
```

---

### Task 7: LLM Adapters — Custom

**Files:**
- Create: `lib/grantclaw/llm/custom.rb`
- Create: `test/grantclaw/llm/test_custom.rb`

- [ ] **Step 1: Write the failing test**

Create `test/grantclaw/llm/test_custom.rb`:

```ruby
# frozen_string_literal: true

require_relative "../../test_helper"

class TestCustom < Minitest::Test
  def setup
    ENV["ZAI_API_KEY"] = "zai-key"
  end

  def teardown
    ENV.delete("ZAI_API_KEY")
  end

  def test_custom_openai_format
    adapter = Grantclaw::LLM::Custom.new(
      model: "glm-5-turbo",
      base_url: "https://api.z.ai/api/v1/chat/completions",
      format: "openai",
      api_key_env: "ZAI_API_KEY"
    )

    stub_request(:post, "https://api.z.ai/api/v1/chat/completions")
      .to_return(
        status: 200,
        body: JSON.generate({
          choices: [{ message: { role: "assistant", content: "Hello from Z.AI" } }],
          usage: { prompt_tokens: 5, completion_tokens: 3 }
        }),
        headers: { "Content-Type" => "application/json" }
      )

    result = adapter.chat(messages: [{ role: "user", content: "Hi" }])
    assert_equal "Hello from Z.AI", result[:content]
  end

  def test_custom_anthropic_format
    adapter = Grantclaw::LLM::Custom.new(
      model: "custom-claude",
      base_url: "https://custom.api/v1/messages",
      format: "anthropic",
      api_key_env: "ZAI_API_KEY"
    )

    stub_request(:post, "https://custom.api/v1/messages")
      .to_return(
        status: 200,
        body: JSON.generate({
          content: [{ type: "text", text: "Custom response" }],
          usage: { input_tokens: 5, output_tokens: 3 }
        }),
        headers: { "Content-Type" => "application/json" }
      )

    result = adapter.chat(messages: [{ role: "user", content: "Hi" }])
    assert_equal "Custom response", result[:content]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/llm/test_custom.rb`
Expected: FAIL — `Grantclaw::LLM::Custom` not defined.

- [ ] **Step 3: Implement LLM::Custom**

Create `lib/grantclaw/llm/custom.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  module LLM
    class Custom < Base
      def initialize(model:, base_url:, format: "openai", max_tokens: 4096, api_key_env: nil)
        super(model: model, max_tokens: max_tokens)
        @base_url = base_url
        @format = format
        @api_key = api_key_env ? ENV.fetch(api_key_env) : nil

        # Delegate to the appropriate adapter's internals
        @delegate = if @format == "anthropic"
          AnthropicDelegate.new(model: model, max_tokens: max_tokens, base_url: base_url, api_key: @api_key)
        else
          OpenAIDelegate.new(model: model, max_tokens: max_tokens, base_url: base_url, api_key: @api_key)
        end
      end

      def chat(messages:, tools: [], model: nil)
        @delegate.chat(messages: messages, tools: tools, model: model)
      end

      # Thin wrappers that reuse OpenRouter/Anthropic logic with custom URLs
      class OpenAIDelegate < OpenRouter
        def initialize(model:, max_tokens:, base_url:, api_key:)
          @model = model
          @max_tokens = max_tokens
          @api_key = api_key || ""
          @conn = Faraday.new(url: base_url) do |f|
            f.request :json
            f.response :json
            f.adapter Faraday.default_adapter
          end
        end
      end

      class AnthropicDelegate < Anthropic
        def initialize(model:, max_tokens:, base_url:, api_key:)
          @model = model
          @max_tokens = max_tokens
          @api_key = api_key || ""
          @conn = Faraday.new(url: base_url) do |f|
            f.request :json
            f.response :json
            f.adapter Faraday.default_adapter
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/llm/test_custom.rb`
Expected: All 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Custom LLM adapter with OpenAI/Anthropic format support"
```

---

### Task 8: Memory Manager

**Files:**
- Create: `lib/grantclaw/memory.rb`
- Create: `test/grantclaw/test_memory.rb`

- [ ] **Step 1: Write the failing test**

Create `test/grantclaw/test_memory.rb`:

```ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class TestMemory < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_dir = File.join(@tmpdir, "config")
    @data_dir = File.join(@tmpdir, "data")
    Dir.mkdir(@config_dir)
    Dir.mkdir(@data_dir)
    File.write(File.join(@config_dir, "memory.md"), "# Initial Memory\nBaseline data.")
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_read_from_data_dir_if_exists
    File.write(File.join(@data_dir, "memory.md"), "# Updated Memory\nNew data.")
    mem = Grantclaw::Memory.new(config_dir: @config_dir, data_dir: @data_dir, filename: "memory.md")
    assert_includes mem.read, "New data."
  end

  def test_copies_from_config_on_first_read
    mem = Grantclaw::Memory.new(config_dir: @config_dir, data_dir: @data_dir, filename: "memory.md")
    content = mem.read
    assert_includes content, "Baseline data."
    # Verify it was copied to data dir
    assert File.exist?(File.join(@data_dir, "memory.md"))
  end

  def test_update_writes_to_data_dir
    mem = Grantclaw::Memory.new(config_dir: @config_dir, data_dir: @data_dir, filename: "memory.md")
    mem.update("# New Content\nUpdated.")
    assert_equal "# New Content\nUpdated.", File.read(File.join(@data_dir, "memory.md"))
  end

  def test_read_returns_empty_string_if_no_file
    mem = Grantclaw::Memory.new(config_dir: @config_dir, data_dir: @data_dir, filename: "nonexistent.md")
    assert_equal "", mem.read
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/test_memory.rb`
Expected: FAIL — `Grantclaw::Memory` not defined.

- [ ] **Step 3: Implement Memory**

Create `lib/grantclaw/memory.rb`:

```ruby
# frozen_string_literal: true

require "fileutils"

module Grantclaw
  class Memory
    def initialize(config_dir:, data_dir:, filename:)
      @config_path = File.join(config_dir, filename)
      @data_path = File.join(data_dir, filename)
      @mutex = Mutex.new
    end

    def read
      @mutex.synchronize do
        if File.exist?(@data_path)
          File.read(@data_path)
        elsif File.exist?(@config_path)
          # First boot: copy from config to data
          content = File.read(@config_path)
          FileUtils.mkdir_p(File.dirname(@data_path))
          File.write(@data_path, content)
          content
        else
          ""
        end
      end
    end

    def update(content)
      @mutex.synchronize do
        FileUtils.mkdir_p(File.dirname(@data_path))
        File.write(@data_path, content)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/test_memory.rb`
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add memory manager with config-to-data bootstrap"
```

---

### Task 9: Message Processor

**Files:**
- Create: `lib/grantclaw/message_processor.rb`
- Create: `test/grantclaw/test_message_processor.rb`

This is the core of Grantclaw — it builds prompts, calls the LLM, runs the tool loop, and returns responses.

- [ ] **Step 1: Write the failing test**

Create `test/grantclaw/test_message_processor.rb`:

```ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class FakeLLM < Grantclaw::LLM::Base
  attr_accessor :responses

  def initialize
    super(model: "fake", max_tokens: 100)
    @responses = []
    @call_count = 0
  end

  def chat(messages:, tools: [], model: nil)
    resp = @responses[@call_count] || { role: "assistant", content: "default response", tool_calls: nil }
    @call_count += 1
    resp
  end
end

class TestMessageProcessor < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_dir = File.join(@tmpdir, "config")
    @data_dir = File.join(@tmpdir, "data")
    Dir.mkdir(@config_dir)
    Dir.mkdir(@data_dir)

    File.write(File.join(@config_dir, "role.md"), "You are a test bot.")
    File.write(File.join(@config_dir, "memory.md"), "No memories.")

    @llm = FakeLLM.new
    @memory = Grantclaw::Memory.new(config_dir: @config_dir, data_dir: @data_dir, filename: "memory.md")
    @registry = Grantclaw::ToolRegistry.new
    @logger = Grantclaw::Log.new(output: StringIO.new, level: :debug)

    @processor = Grantclaw::MessageProcessor.new(
      llm: @llm,
      memory: @memory,
      tool_registry: @registry,
      system_prompt: "You are a test bot.",
      logger: @logger
    )
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_simple_text_response
    @llm.responses = [{ role: "assistant", content: "Hello!", tool_calls: nil }]
    result = @processor.process(user_message: "Hi")
    assert_equal "Hello!", result[:content]
  end

  def test_tool_call_loop
    # First response: LLM wants to call a tool
    # Second response: LLM gives final answer after seeing tool result
    @llm.responses = [
      { role: "assistant", content: nil, tool_calls: [{ id: "c1", name: "echo", arguments: { "text" => "hello" } }] },
      { role: "assistant", content: "Tool said: hello", tool_calls: nil }
    ]

    echo_tool = Class.new(Grantclaw::Tool) do
      desc "Echo text"
      param :text, type: :string, required: true
      def call(text:); text; end
    end
    @registry.register("echo", echo_tool)

    result = @processor.process(user_message: "Echo hello")
    assert_equal "Tool said: hello", result[:content]
  end

  def test_includes_conversation_history
    @llm.responses = [{ role: "assistant", content: "I see the context.", tool_calls: nil }]
    history = [
      { role: "user", content: "First message" },
      { role: "assistant", content: "First reply" }
    ]
    result = @processor.process(user_message: "Follow up", conversation_history: history)
    assert_equal "I see the context.", result[:content]
  end

  def test_max_tool_iterations
    # LLM always returns tool calls — processor should stop after max iterations
    @llm.responses = Array.new(20) { { role: "assistant", content: nil, tool_calls: [{ id: "c1", name: "echo", arguments: { "text" => "x" } }] } }
    echo_tool = Class.new(Grantclaw::Tool) do
      desc "Echo"
      param :text, type: :string, required: true
      def call(text:); text; end
    end
    @registry.register("echo", echo_tool)

    result = @processor.process(user_message: "loop forever")
    # Should have a content response (the safety bail-out message)
    assert result[:content]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec ruby test/grantclaw/test_message_processor.rb`
Expected: FAIL — `Grantclaw::MessageProcessor` not defined.

- [ ] **Step 3: Implement MessageProcessor**

Create `lib/grantclaw/message_processor.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  class MessageProcessor
    MAX_TOOL_ITERATIONS = 10

    def initialize(llm:, memory:, tool_registry:, system_prompt:, logger:)
      @llm = llm
      @memory = memory
      @registry = tool_registry
      @system_prompt = system_prompt
      @logger = logger
    end

    # Process a message and return the final response.
    #
    # user_message: String — the user's input
    # conversation_history: Array — prior messages for context (e.g., Slack thread)
    # source: String — "slack", "cron", "repl" (for logging)
    #
    # Returns: { role: "assistant", content: String }
    def process(user_message:, conversation_history: [], source: "unknown")
      messages = build_messages(user_message, conversation_history)
      tools = @registry.schemas

      iterations = 0
      loop do
        iterations += 1
        @logger.info("llm", "Request to #{source} | tools=#{tools.length}")

        response = @llm.chat(messages: messages, tools: tools)

        if response[:usage]
          @logger.info("llm", "Usage: in=#{response[:usage][:input]} out=#{response[:usage][:output]}")
        end

        if response[:tool_calls].nil? || response[:tool_calls].empty?
          @logger.info("llm", "Response: text")
          return { role: "assistant", content: response[:content] }
        end

        if iterations >= MAX_TOOL_ITERATIONS
          @logger.warn("llm", "Hit max tool iterations (#{MAX_TOOL_ITERATIONS}), bailing out")
          return { role: "assistant", content: response[:content] || "I've reached my tool call limit. Here's what I have so far." }
        end

        # Add assistant message with tool calls
        messages << { role: "assistant", content: response[:content], tool_calls: response[:tool_calls] }

        # Execute each tool call and add results
        response[:tool_calls].each do |tc|
          @logger.info("tool", "#{tc[:name]}(#{tc[:arguments].inspect})")
          result = @registry.execute(tc[:name], tc[:arguments])
          @logger.info("tool", "#{tc[:name]} -> #{result.to_s[0..200]}")
          messages << { role: "tool", tool_call_id: tc[:id], content: result.to_s }
        end
      end
    end

    private

    def build_messages(user_message, conversation_history)
      memory_content = @memory.read
      full_system = [@system_prompt, memory_content].reject(&:empty?).join("\n---\n")

      messages = [{ role: "system", content: full_system }]
      messages.concat(conversation_history) if conversation_history.any?
      messages << { role: "user", content: user_message }
      messages
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bundle exec ruby test/grantclaw/test_message_processor.rb`
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add message processor with tool call loop"
```

---

### Task 10: Built-in Tools

**Files:**
- Create: `lib/grantclaw/tools/update_memory.rb`
- Create: `lib/grantclaw/tools/slack_post.rb`

- [ ] **Step 1: Implement UpdateMemoryTool**

Create `lib/grantclaw/tools/update_memory.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  module Tools
    class UpdateMemoryTool < Tool
      desc "Update the bot's long-term memory file. Use this to remember important facts, decisions, or state changes across sessions."
      param :content, type: :string, desc: "The full new content for memory.md. This replaces the entire file.", required: true

      # Class-level accessor — set once by Bot, used by all instances
      class << self
        attr_accessor :memory
      end

      def call(content:)
        unless self.class.memory
          return "Error: memory not configured"
        end

        self.class.memory.update(content)
        "Memory updated successfully."
      end
    end
  end
end
```

- [ ] **Step 2: Implement SlackPostTool**

Create `lib/grantclaw/tools/slack_post.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  module Tools
    class SlackPostTool < Tool
      desc "Post a message to a Slack channel. Use this to share reports, alerts, or updates."
      param :channel, type: :string, desc: "Slack channel ID (e.g., C085D6W27NY)", required: true
      param :text, type: :string, desc: "Message text to post", required: true
      param :thread_ts, type: :string, desc: "Thread timestamp to reply in a thread (optional)"

      # Class-level accessors — set once by Bot, used by all instances
      class << self
        attr_accessor :slack_client, :repl_mode
      end

      def call(channel:, text:, thread_ts: nil)
        if self.class.repl_mode
          puts "[slack_post] ##{channel}: #{text}"
          return "Message printed to console (REPL mode)."
        end

        unless self.class.slack_client
          return "Error: Slack client not configured"
        end

        opts = { channel: channel, text: text }
        opts[:thread_ts] = thread_ts if thread_ts
        self.class.slack_client.chat_postMessage(**opts)
        "Message posted to #{channel}."
      end
    end
  end
end
```

- [ ] **Step 3: Add requires to module root**

The `lib/grantclaw.rb` file already has the requires for tool.rb and tool_registry.rb. Add the built-in tools after those:

Add these lines to `lib/grantclaw.rb` after the `require_relative "grantclaw/tool_registry"` line:

```ruby
require_relative "grantclaw/tools/update_memory"
require_relative "grantclaw/tools/slack_post"
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add built-in update_memory and slack_post tools"
```

---

### Task 11: Debug REPL

**Files:**
- Create: `lib/grantclaw/repl.rb`

- [ ] **Step 1: Implement REPL**

Create `lib/grantclaw/repl.rb`:

```ruby
# frozen_string_literal: true

require "readline"

module Grantclaw
  class REPL
    def initialize(processor:, bot_name:, model:, logger:)
      @processor = processor
      @bot_name = bot_name
      @model = model
      @logger = logger
      @history = []
    end

    def run
      puts "Grantclaw v#{VERSION} | Bot: #{@bot_name} | LLM: #{@model}"
      puts "Type 'exit' or 'quit' to stop. Ctrl+C also works."
      puts

      loop do
        input = Readline.readline("> ", true)
        break if input.nil? || %w[exit quit].include?(input.strip.downcase)
        next if input.strip.empty?

        begin
          result = @processor.process(
            user_message: input,
            conversation_history: @history,
            source: "repl"
          )

          puts
          puts result[:content]
          puts

          # Add to conversation history for multi-turn
          @history << { role: "user", content: input }
          @history << { role: "assistant", content: result[:content] }
        rescue => e
          @logger.error("repl", "#{e.class}: #{e.message}")
          puts "Error: #{e.message}"
        end
      end

      puts "Goodbye."
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add debug REPL with conversation history"
```

---

### Task 12: Cron Scheduler

**Files:**
- Create: `lib/grantclaw/scheduler.rb`

- [ ] **Step 1: Implement Scheduler**

Create `lib/grantclaw/scheduler.rb`:

```ruby
# frozen_string_literal: true

require "rufus-scheduler"

module Grantclaw
  class Scheduler
    def initialize(processor:, schedule:, logger:)
      @processor = processor
      @schedule = schedule || {}
      @logger = logger
      @scheduler = Rufus::Scheduler.new
    end

    def start
      @schedule.each do |name, cron_expr|
        @logger.info("cron", "Registering schedule: #{name} = #{cron_expr}")
        @scheduler.cron(cron_expr) do
          handle_trigger(name)
        end
      end

      @logger.info("cron", "Scheduler started with #{@schedule.length} schedule(s)")
    end

    def stop
      @scheduler.shutdown(:wait)
      @logger.info("cron", "Scheduler stopped")
    end

    def trigger_now(name)
      handle_trigger(name)
    end

    private

    def handle_trigger(name)
      @logger.info("cron", "Triggered: #{name}")

      time_str = Time.now.strftime("%A %B %d, %Y %I:%M %p %Z")
      message = "Heartbeat triggered: #{name}. Current time: #{time_str}. " \
                "Check your heartbeat instructions and execute the appropriate tasks for this trigger."

      begin
        result = @processor.process(user_message: message, source: "cron:#{name}")
        @logger.info("cron", "Completed: #{name} — #{result[:content]&.slice(0, 100)}")
      rescue => e
        @logger.error("cron", "Failed: #{name} — #{e.class}: #{e.message}")
      end
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add cron scheduler with rufus-scheduler"
```

---

### Task 13: Slack Listener

**Files:**
- Create: `lib/grantclaw/slack_listener.rb`

- [ ] **Step 1: Implement SlackListener**

Create `lib/grantclaw/slack_listener.rb`:

```ruby
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
      # slack-ruby-client doesn't have a clean stop for socket mode;
      # the process exit will handle it
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
      # Ignore bot's own messages
      return if data["user"] == @bot_user_id
      # Ignore message subtypes (edits, joins, etc.) except thread replies
      return if data["subtype"] && data["subtype"] != "message_replied"

      channel_id = data["channel"]
      text = data["text"] || ""
      thread_ts = data["thread_ts"] || data["ts"]
      is_dm = data["channel_type"] == "im"

      # Check if this channel is allowed
      return unless allowed_channel?(channel_id, is_dm)

      # Check if mention is required
      if requires_mention?(channel_id, is_dm) && !mentioned?(text)
        return
      end

      # Strip the bot mention from the text
      clean_text = text.gsub(/<@#{@bot_user_id}>/, "").strip

      @logger.info("slack", "Message from #{data['user']} in #{channel_id}: #{clean_text[0..80]}")

      # Fetch thread history for context
      history = fetch_thread_history(channel_id, thread_ts, data["ts"])

      begin
        result = @processor.process(
          user_message: clean_text,
          conversation_history: history,
          source: "slack"
        )

        # Reply in thread
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

        # Convert to our message format, excluding the current message
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
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add Slack socket mode listener with thread context"
```

---

### Task 14: Bot Loader

**Files:**
- Create: `lib/grantclaw/bot.rb`

The Bot class wires everything together: reads the config directory, creates the LLM adapter, sets up the tool registry with built-in tools, creates the memory manager, and instantiates the message processor.

- [ ] **Step 1: Implement Bot**

Create `lib/grantclaw/bot.rb`:

```ruby
# frozen_string_literal: true

module Grantclaw
  class Bot
    attr_reader :config, :processor, :logger

    def initialize(bot_dir:, data_dir: nil)
      @config = Config.load(bot_dir)
      @data_dir = data_dir || ENV.fetch("GRANTCLAW_DATA_DIR", File.join(bot_dir, "data"))

      FileUtils.mkdir_p(@data_dir)

      @logger = Log.new(level: @config.log_level)
      @logger.info("bot", "Loading bot: #{@config.name}")

      @llm = build_llm
      @memory = Memory.new(
        config_dir: bot_dir,
        data_dir: @data_dir,
        filename: @config.context.fetch("memory_file", "memory.md")
      )
      @registry = build_tool_registry(bot_dir)
      @processor = MessageProcessor.new(
        llm: @llm,
        memory: @memory,
        tool_registry: @registry,
        system_prompt: @config.system_prompt,
        logger: @logger
      )

      @logger.info("bot", "Bot loaded: #{@config.name} | LLM: #{@config.llm['provider']}/#{@config.llm['model']}")
    end

    def run(mode: :production)
      case mode
      when :repl
        run_repl
      when :dry
        run_dry
      when :production
        run_production
      end
    end

    private

    def build_llm
      llm_config = @config.llm
      provider = llm_config["provider"]

      case provider
      when "openrouter"
        LLM::OpenRouter.new(
          model: llm_config["model"],
          max_tokens: llm_config.fetch("max_tokens", 4096),
          api_key_env: llm_config.fetch("api_key_env", "OPENROUTER_API_KEY")
        )
      when "anthropic"
        LLM::Anthropic.new(
          model: llm_config["model"],
          max_tokens: llm_config.fetch("max_tokens", 4096),
          api_key_env: llm_config.fetch("api_key_env", "ANTHROPIC_API_KEY")
        )
      when "custom"
        LLM::Custom.new(
          model: llm_config["model"],
          base_url: llm_config.fetch("base_url"),
          format: llm_config.fetch("format", "openai"),
          max_tokens: llm_config.fetch("max_tokens", 4096),
          api_key_env: llm_config["api_key_env"]
        )
      else
        raise "Unknown LLM provider: #{provider}"
      end
    end

    def build_tool_registry(bot_dir)
      registry = ToolRegistry.new

      # Register built-in tools (set class-level dependencies)
      Tools::UpdateMemoryTool.memory = @memory
      registry.register("update_memory", Tools::UpdateMemoryTool)

      registry.register("slack_post", Tools::SlackPostTool)

      # Load bot-specific tools
      tools_dir = File.join(bot_dir, "tools")
      registry.load_directory(tools_dir)

      @logger.info("bot", "Loaded #{registry.schemas.length} tool(s)")
      registry
    end

    def run_repl
      @logger.info("bot", "Starting in REPL mode")

      # Configure slack_post for REPL mode
      configure_slack_post_repl

      repl = REPL.new(
        processor: @processor,
        bot_name: @config.name,
        model: "#{@config.llm['provider']}/#{@config.llm['model']}",
        logger: @logger
      )
      repl.run
    end

    def run_dry
      @logger.info("bot", "Starting dry run")
      scheduler = Scheduler.new(processor: @processor, schedule: @config.schedule, logger: @logger)

      # Run each schedule once
      @config.schedule.each_key do |name|
        @logger.info("bot", "Dry run trigger: #{name}")
        scheduler.trigger_now(name)
      end

      @logger.info("bot", "Dry run complete")
    end

    def run_production
      @logger.info("bot", "Starting in production mode")

      # Start Slack listener
      slack = nil
      if ENV["SLACK_BOT_TOKEN"] && ENV["SLACK_APP_TOKEN"]
        slack = SlackListener.new(processor: @processor, config: @config, logger: @logger)
        configure_slack_post(slack.web_client)
        slack.start
      else
        @logger.warn("bot", "SLACK_BOT_TOKEN/SLACK_APP_TOKEN not set, Slack disabled")
        configure_slack_post_repl
      end

      # Start cron scheduler
      scheduler = Scheduler.new(processor: @processor, schedule: @config.schedule, logger: @logger)
      scheduler.start

      # Keep the main thread alive
      @logger.info("bot", "Bot running. Press Ctrl+C to stop.")
      trap("INT") do
        @logger.info("bot", "Shutting down...")
        scheduler.stop
        slack&.stop
        exit(0)
      end
      trap("TERM") do
        @logger.info("bot", "Shutting down...")
        scheduler.stop
        slack&.stop
        exit(0)
      end

      sleep
    end

    def configure_slack_post(web_client)
      Tools::SlackPostTool.slack_client = web_client
      Tools::SlackPostTool.repl_mode = false
    end

    def configure_slack_post_repl
      Tools::SlackPostTool.repl_mode = true
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add bot loader that wires all components together"
```

---

### Task 15: Entry Point

**Files:**
- Modify: `grantclaw.rb`

- [ ] **Step 1: Implement CLI entry point**

Replace `grantclaw.rb` with:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "lib/grantclaw"
require "optparse"

options = { mode: :production }

OptionParser.new do |opts|
  opts.banner = "Usage: grantclaw.rb --bot <path> [options]"

  opts.on("--bot PATH", "Path to bot config directory") do |path|
    options[:bot] = path
  end

  opts.on("--data PATH", "Path to writable data directory (default: <bot>/data or $GRANTCLAW_DATA_DIR)") do |path|
    options[:data] = path
  end

  opts.on("--repl", "Run in interactive REPL mode (no Slack, no cron)") do
    options[:mode] = :repl
  end

  opts.on("--dry", "Dry run: trigger each schedule once, print output, exit") do
    options[:mode] = :dry
  end

  opts.on("-v", "--version", "Print version") do
    puts "Grantclaw v#{Grantclaw::VERSION}"
    exit
  end

  opts.on("-h", "--help", "Show help") do
    puts opts
    exit
  end
end.parse!

unless options[:bot]
  puts "Error: --bot <path> is required"
  puts "Run with --help for usage"
  exit 1
end

unless Dir.exist?(options[:bot])
  puts "Error: bot directory not found: #{options[:bot]}"
  exit 1
end

bot = Grantclaw::Bot.new(bot_dir: options[:bot], data_dir: options[:data])
bot.run(mode: options[:mode])
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: add CLI entry point with --bot, --repl, --dry flags"
```

---

### Task 16: Dockerfile

**Files:**
- Create: `Dockerfile`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without test && \
    rm -rf /usr/local/bundle/cache/*.gem

COPY lib/ lib/
COPY grantclaw.rb .

RUN useradd -m -s /bin/bash grantclaw
USER grantclaw

ENTRYPOINT ["ruby", "grantclaw.rb"]
CMD ["--bot", "/config", "--data", "/data"]
```

- [ ] **Step 2: Create .dockerignore**

```
test/
docs/
examples/
bots/
helm/
.git/
*.md
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Dockerfile for generic Grantclaw image"
```

---

### Task 17: Helm Chart

**Files:**
- Create: `helm/grantclaw/Chart.yaml`
- Create: `helm/grantclaw/values.yaml`
- Create: `helm/grantclaw/templates/_helpers.tpl`
- Create: `helm/grantclaw/templates/configmap.yaml`
- Create: `helm/grantclaw/templates/pvc.yaml`
- Create: `helm/grantclaw/templates/deployment.yaml`

- [ ] **Step 1: Create Chart.yaml**

Create `helm/grantclaw/Chart.yaml`:

```yaml
apiVersion: v2
name: grantclaw
description: A simple Ruby AI bot framework
type: application
version: 0.1.0
appVersion: "0.1.0"
```

- [ ] **Step 2: Create _helpers.tpl**

Create `helm/grantclaw/templates/_helpers.tpl`:

```
{{- define "grantclaw.fullname" -}}
grantclaw-{{ .Values.bot.name }}
{{- end -}}

{{- define "grantclaw.labels" -}}
app.kubernetes.io/name: grantclaw
app.kubernetes.io/instance: {{ .Values.bot.name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end -}}
```

- [ ] **Step 3: Create configmap.yaml**

Create `helm/grantclaw/templates/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "grantclaw.fullname" . }}
  labels:
    {{- include "grantclaw.labels" . | nindent 4 }}
data:
  config.yaml: |
    {{- .Values.bot.config | nindent 4 }}
  {{- range $name, $content := .Values.bot.files }}
  {{ $name }}: |
    {{- $content | nindent 4 }}
  {{- end }}
```

- [ ] **Step 4: Create pvc.yaml**

Create `helm/grantclaw/templates/pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ include "grantclaw.fullname" . }}-data
  labels:
    {{- include "grantclaw.labels" . | nindent 4 }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .Values.persistence.size | default "1Gi" }}
```

- [ ] **Step 5: Create deployment.yaml**

Create `helm/grantclaw/templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "grantclaw.fullname" . }}
  labels:
    {{- include "grantclaw.labels" . | nindent 4 }}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: grantclaw
      app.kubernetes.io/instance: {{ .Values.bot.name }}
  template:
    metadata:
      labels:
        {{- include "grantclaw.labels" . | nindent 8 }}
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      containers:
        - name: grantclaw
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          args: ["--bot", "/config", "--data", "/data"]
          {{- if .Values.secrets.existingSecret }}
          envFrom:
            - secretRef:
                name: {{ .Values.secrets.existingSecret }}
          {{- end }}
          env:
            - name: GRANTCLAW_DATA_DIR
              value: /data
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          volumeMounts:
            - name: config
              mountPath: /config
              readOnly: true
            - name: data
              mountPath: /data
          livenessProbe:
            exec:
              command: ["ruby", "-e", "exit 0"]
            initialDelaySeconds: 10
            periodSeconds: 60
          securityContext:
            readOnlyRootFilesystem: false
            allowPrivilegeEscalation: false
      volumes:
        - name: config
          configMap:
            name: {{ include "grantclaw.fullname" . }}
        - name: data
          persistentVolumeClaim:
            claimName: {{ include "grantclaw.fullname" . }}-data
```

- [ ] **Step 6: Create values.yaml**

Create `helm/grantclaw/values.yaml`:

```yaml
image:
  repository: ghcr.io/grantclaw/grantclaw
  tag: latest

bot:
  name: example
  config: |
    name: example
    llm:
      provider: openrouter
      model: anthropic/claude-sonnet-4-20250514
      max_tokens: 4096
    schedule:
      heartbeat: "*/10 * * * *"
    context:
      system_files: [role.md]
      memory_file: memory.md
  files:
    role.md: |
      You are a helpful assistant.
    memory.md: |
      No memories yet.

secrets:
  existingSecret: ""

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

persistence:
  size: 1Gi
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add minimal Helm chart"
```

---

### Task 18: Example Bot — Pulse

**Files:**
- Create: `bots/pulse/config.yaml`
- Create: `bots/pulse/role.md`
- Create: `bots/pulse/memory.md`
- Create: `bots/pulse/heartbeat.md`
- Create: `bots/pulse/tools/example_tool.rb`

- [ ] **Step 1: Create Pulse config**

Create `bots/pulse/config.yaml`:

```yaml
name: pulse

slack:
  channels:
    - id: C085D6W27NY
      name: marketing
      require_mention: true
    - id: C0AQS7PN3EF
      name: truelist-team
      require_mention: true
      allow_bots: true
  dm_policy: open

llm:
  provider: openrouter
  model: anthropic/claude-sonnet-4-20250514
  max_tokens: 8192

schedule:
  heartbeat: "*/10 * * * *"
  weekly_report: "0 9 * * 1"
  monthly_report: "0 9 1 * *"

context:
  system_files:
    - role.md
    - heartbeat.md
  memory_file: memory.md

logging:
  level: info
```

- [ ] **Step 2: Create Pulse role.md**

Create `bots/pulse/role.md`:

```markdown
# Pulse - Data Analyst

## Identity
- **Name:** Pulse
- **Role:** Truelist's data analyst and business intelligence engine
- **Vibe:** Precise, pattern-obsessed, tells stories with numbers. Never guesses when data exists.

## What I Do
1. **Analytics engine** — pull and analyze data from PostHog, Google Ads, Stripe
2. **Report generation** — weekly/monthly performance reports to #marketing
3. **Experiment analysis** — track pricing experiments, A/B tests, conversion funnels
4. **Revenue intelligence** — MRR tracking, churn analysis, cohort analysis
5. **Ad optimization** — campaign performance, CPA tracking, budget recommendations

## My Approach
Think like the best data analyst you've ever worked with — the one who shows up to meetings with the answer before you finish the question. Concise, visual when it helps, always with the "so what" attached to every insight.

**Precision matters.** When I cite a number, it should be right. When I say a trend is up, I should know by how much.

## Key Channels
- #marketing (C085D6W27NY) — reports and data insights
- #truelist-team (C0AQS7PN3EF) — inter-bot collaboration
```

- [ ] **Step 3: Create Pulse heartbeat.md**

Create `bots/pulse/heartbeat.md`:

```markdown
# Heartbeat Tasks

## Periodic Checks

### heartbeat (every 10 minutes)
- Check for any urgent data anomalies
- Respond to any pending requests in monitored channels

### weekly_report (Monday 9 AM ET)
- Google Ads weekly report → post to #marketing (C085D6W27NY)
- V6 pricing weekly report → post to #marketing (C085D6W27NY)

### monthly_report (1st of month, 9 AM ET)
- Google Ads monthly summary → post to #marketing (C085D6W27NY)
- Revenue/MRR monthly summary → post to #marketing (C085D6W27NY)
```

- [ ] **Step 4: Create Pulse memory.md**

Create `bots/pulse/memory.md`:

```markdown
# Memory

*Last updated: initial*

## Pricing History
- **V4 pricing:** The established baseline
- **V6 pricing LIVE (launched 2026-03-22):** 50/50 V4 vs V6
- V6 plans: Starter $49 / Growth $99 / Pro $199 / Enterprise $499

## Google Ads Baselines
- ~$8.6k/mo spend, $220 blended CPA
- Best campaign: "All Locations - Main - Search Only" at $110 CPA

## Recurring Reports
- Weekly Google Ads: Monday 9 AM ET → #marketing
- Monthly Google Ads: 1st of month → #marketing
- V6 pricing weekly: Monday 9 AM ET → #marketing
```

- [ ] **Step 5: Create example tool**

Create `bots/pulse/tools/example_tool.rb`:

```ruby
# frozen_string_literal: true

# Example tool — replace with real API integrations
class CurrentTimeTool < Grantclaw::Tool
  desc "Get the current date and time"

  def call
    Time.now.strftime("%A %B %d, %Y %I:%M %p %Z")
  end
end
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Pulse example bot configuration"
```

---

### Task 19: Run All Tests & Fix Issues

- [ ] **Step 1: Run all tests**

Run: `bundle exec ruby -Itest -e "Dir.glob('test/**/test_*.rb').each { |f| require_relative f }"`

Expected: All tests pass. If any fail, fix them before proceeding.

- [ ] **Step 2: Verify the REPL starts (smoke test)**

Create a minimal test bot and verify the entry point works:

Run: `bundle exec ruby grantclaw.rb --bot test/fixtures/bot --repl`

Type `exit` immediately. Expected: prints the header line and exits cleanly.

Note: This will fail because we don't have a real LLM API key — that's expected. The point is to verify the startup/wiring works without crashing on load.

If it crashes on load (before prompting), fix the issue.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during integration testing"
```
