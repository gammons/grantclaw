# Grantclaw Design Spec

A simple Ruby-based AI bot framework for Kubernetes, replacing OpenClaw with something slimmer, easier to understand, debug, and deploy.

## Problem

OpenClaw is a full-featured TypeScript/Node.js AI assistant platform with 25+ channel integrations, browser automation, a skills marketplace, and complex session management. Deploying a single bot requires:

- A 311-line Helm values.yaml wrapping the bjw-s app-template library chart
- An inline JSON config embedded in the YAML
- Init containers to copy markdown files from ConfigMaps to a PVC
- A Chromium sidecar for browser automation
- 300m-2000m CPU, 1-4Gi RAM, 10Gi PVC per bot

Most of this is unnecessary for bots that just need to: read a persona, talk to an LLM, call some APIs, and post to Slack on a schedule.

## Goals

- Single Ruby script, easy to read end-to-end
- Bot defined as a simple directory (config.yaml + markdown files + tool scripts)
- Pluggable LLM providers via adapter pattern
- Slack integration via socket mode
- Internal cron scheduler for heartbeat/periodic tasks
- Debug REPL for local testing without deploying
- Minimal Helm chart (no library chart dependencies)
- Resource footprint: ~100m CPU, ~128Mi RAM, 1Gi PVC

## Non-Goals

- Image/video generation
- Transcription or text-to-speech
- Browser automation
- Multi-bot per process (each bot is its own process)
- Horizontal scaling (single instance per bot)
- Web UI (debug REPL is terminal-only)

## Architecture

### Process Model

Grantclaw is a long-running Ruby process with three concurrent threads:

1. **Slack listener** -- receives messages via Slack Socket Mode, filters by config, dispatches to the message processor
2. **Cron scheduler** -- uses rufus-scheduler to fire heartbeat and scheduled tasks
3. **Debug REPL** (optional) -- readline-based interactive chat for local testing

All three feed into a single message processor that builds prompts, calls the LLM, executes tool calls, and routes responses.

```
+----------------------------------------------+
|              Grantclaw Process               |
|                                              |
|  +-------------+     +------------------+    |
|  | Slack Socket |---->|                  |    |
|  |  Listener    |     |   Message        |    |
|  +-------------+     |   Processor      |    |
|                       |                  |    |
|  +-------------+     |  1. Build prompt  |    |
|  | Cron        |---->|  2. Call LLM      |--->|--> LLM API
|  | Scheduler   |     |  3. Execute tools |    |
|  +-------------+     |  4. Respond       |    |
|                       +------------------+    |
|  +-------------+                              |
|  | Debug REPL  |-------- (same pipeline) ---->|
|  +-------------+                              |
+----------------------------------------------+
```

### Bot Directory Structure

Each bot is defined as a directory:

```
bots/pulse/
  config.yaml          # LLM, schedule, Slack config, tool declarations
  role.md              # Persona / system prompt
  memory.md            # Long-term memory (writable at runtime)
  heartbeat.md         # Instructions for scheduled tasks
  tools/               # Ruby files defining tool classes
    stripe.rb
    posthog.rb
    google_ads.rb
```

### Configuration Format

`config.yaml` contains all bot configuration in one place:

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
  provider: openrouter      # "openrouter", "anthropic", or "custom"
  model: anthropic/claude-sonnet-4-20250514
  max_tokens: 8192
  # For custom providers:
  # base_url: https://api.z.ai/api/anthropic
  # format: anthropic          # "openai" or "anthropic"
  # api_key_env: ZAI_API_KEY

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
  level: info   # debug, info, warn, error
```

## Components

### LLM Adapter Pattern

A base class defines the interface. Each provider implements `chat`:

```ruby
module Grantclaw
  module LLM
    class Base
      def chat(messages:, tools: [], model: nil)
        # Returns:
        # {
        #   role: "assistant",
        #   content: "text response",
        #   tool_calls: [{ id: "...", name: "...", arguments: {...} }]
        # }
        raise NotImplementedError
      end
    end
  end
end
```

**Adapters:**

- `LLM::OpenRouter` -- POST to `https://openrouter.ai/api/v1/chat/completions`. Accepts any model string. OpenAI-compatible format.
- `LLM::Anthropic` -- POST to `https://api.anthropic.com/v1/messages`. Anthropic's native format (system prompt separate, different tool call structure).
- `LLM::Custom` -- configurable `base_url`, model, and `format` (`openai` or `anthropic`). For providers like Z.AI that expose a compatible API. The format field determines which request/response structure to use.

The adapter handles format translation. The rest of the system works with a normalized message format.

**API keys** are passed via environment variables. The adapter reads from `ENV` based on the provider name (`OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, or a custom env var specified in config via `api_key_env`).

### Tool System

Tools are Ruby classes that follow a simple convention:

```ruby
class StripeTool < Grantclaw::Tool
  desc "Check Stripe MRR and subscription metrics"
  param :metric, type: :string, enum: %w[mrr churn subscriptions], required: true
  param :period, type: :string, desc: "Time period (e.g., 'last_30_days')", default: "current"

  def call(metric:, period: "current")
    # Implementation
    # Return value is serialized to JSON and sent back to the LLM as the tool result
  end
end
```

The `Grantclaw::Tool` base class provides:
- `desc` -- tool description for the LLM
- `param` -- parameter declarations with type, description, enum, required, default
- Automatic JSON schema generation from param declarations (for LLM tool calling)
- Error wrapping -- exceptions in `call` are caught and returned as error tool results

Tools are loaded from the `tools/` directory via `Dir.glob("tools/*.rb")`. Each file is `require`'d and any class inheriting from `Grantclaw::Tool` is registered automatically via Ruby's `inherited` hook.

**Built-in tools** (always available, no configuration needed):
- `update_memory` -- writes new content to the bot's memory.md file on the PVC
- `slack_post` -- posts a message to a specified Slack channel (in REPL mode, prints to stdout instead)

In REPL mode, tools that interact with Slack print their output to the terminal instead of posting to Slack. This lets you test the full pipeline locally without side effects.

### Slack Integration

Uses `slack-ruby-client` gem in Socket Mode.

**Event handling:**
1. Receive event (message, app_mention, reaction)
2. Check against channel allowlist from config
3. Check require_mention setting
4. For messages in threads: fetch thread history via `conversations.replies`
5. Build context and dispatch to message processor
6. Post response to the same channel/thread

**Thread context:** When a message is in a Slack thread, the full thread history is fetched and included in the LLM conversation as prior messages. This gives the bot conversational continuity within a thread without any session management.

**Posting messages:** Tool calls can post to Slack channels directly (the Slack client is available as a built-in tool). Responses to direct mentions are posted as thread replies.

### Cron Scheduler

Uses `rufus-scheduler` running in its own thread.

Each entry in `config.yaml`'s `schedule` section is registered:

```ruby
config[:schedule].each do |name, cron_expr|
  scheduler.cron(cron_expr) do
    processor.handle_cron(trigger: name)
  end
end
```

A cron-triggered invocation builds this message:

```
System: [role.md] [heartbeat.md] [memory.md]
User: "Heartbeat triggered: weekly_report. Current time: Monday April 19, 2026 9:00 AM ET.
       Check your heartbeat instructions and execute the appropriate tasks for this trigger."
```

The LLM reads heartbeat.md, determines what to do for the "weekly_report" trigger, and uses tools to execute.

### Context & Memory

**System prompt construction:**

Each invocation (Slack message, cron trigger, or REPL input) builds a system prompt by concatenating the files listed in `context.system_files` plus `context.memory_file`:

```
[Contents of role.md]
---
[Contents of heartbeat.md]
---
[Contents of memory.md]
```

**Memory updates:** The bot can update its memory via a built-in `update_memory` tool. This writes to `memory.md` on the PVC. The next invocation picks up the updated memory.

**Slack thread context:** For Slack messages in threads, the thread history is included as conversation messages (not part of the system prompt). This provides natural conversational continuity.

**No session management.** Each invocation is independent. Context comes from: files (persistent, explicit) and Slack threads (implicit, scoped to thread). This is simple and debuggable -- you can read the memory file to see exactly what the bot "knows."

### Debug REPL

A readline-based interactive chat for local testing:

```
$ ruby grantclaw.rb --bot bots/pulse --repl
Grantclaw v0.1 | Bot: pulse | LLM: openrouter/anthropic/claude-sonnet-4-20250514
> What's our current MRR?

[tool:stripe] StripeTool(metric: "mrr") -> { mrr: 42350, ... }

Based on Stripe data, your current MRR is $42,350...

>
```

Features:
- Shows tool calls and results inline
- Same message processor as Slack (tests the full pipeline)
- Maintains conversation history within the REPL session
- No Slack connection needed

**CLI interface:**

```
ruby grantclaw.rb --bot <path>         # Production: Slack + cron
ruby grantclaw.rb --bot <path> --repl  # Debug: REPL only
ruby grantclaw.rb --bot <path> --dry   # Dry run: one heartbeat cycle, print output, exit
```

## Deployment

### Container Image

A single generic Docker image shared by all bots:

```dockerfile
FROM ruby:3.3-slim
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY lib/ lib/
COPY grantclaw.rb .
ENTRYPOINT ["ruby", "grantclaw.rb"]
CMD ["--bot", "/config"]
```

Bot-specific configuration is injected via Kubernetes ConfigMaps and Secrets. The image contains only the Grantclaw framework and its gem dependencies.

### Helm Chart

A minimal custom chart with no library chart dependencies:

```
helm/grantclaw/
  Chart.yaml
  templates/
    deployment.yaml
    configmap.yaml
    pvc.yaml
    _helpers.tpl
  values.yaml
```

**values.yaml for deploying Pulse:**

```yaml
image:
  repository: ghcr.io/yourusername/grantclaw
  tag: latest

bot:
  name: pulse
  config: |
    name: pulse
    slack:
      channels:
        - id: C085D6W27NY
          name: marketing
          require_mention: true
    llm:
      provider: openrouter
      model: anthropic/claude-sonnet-4-20250514
    schedule:
      heartbeat: "*/10 * * * *"
      weekly_report: "0 9 * * 1"
    context:
      system_files: [role.md, heartbeat.md]
      memory_file: memory.md

  files:
    role.md: |
      # Pulse - Data Analyst
      ...
    heartbeat.md: |
      # Heartbeat Tasks
      ...
    memory.md: |
      # Initial Memory
      ...

secrets:
  existingSecret: grantclaw-pulse-env
  # Expected: SLACK_BOT_TOKEN, SLACK_APP_TOKEN, OPENROUTER_API_KEY

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

**What the chart generates:**
- **ConfigMap** with bot config.yaml and markdown files, mounted read-only at `/config`
- **Deployment** with single replica, Recreate strategy, env vars from secret
- **PVC** (1Gi) mounted read-write at `/data` for memory.md and state.json at runtime

**First boot:** An entrypoint script checks if `/data/memory.md` exists. If not, copies the initial `memory.md` from `/config` to `/data`. Subsequent runs read from `/data`.

### Resource Comparison

| | OpenClaw (Pulse) | Grantclaw (Pulse) |
|---|---|---|
| CPU request | 300m | 100m |
| CPU limit | 2000m | 500m |
| Memory request | 1Gi | 128Mi |
| Memory limit | 4Gi | 256Mi |
| PVC | 10Gi | 1Gi |
| Containers | 3 (main + chromium + init) | 1 |
| Helm values | 311 lines | ~40 lines |
| Config format | JSON embedded in YAML | YAML |

## Error Handling

**LLM API errors:** Retry with exponential backoff, 3 attempts. If all retries fail, log the error and post to the bot's primary Slack channel (or a configurable error channel).

**Tool execution errors:** Catch exceptions in the tool's `call` method. Return the error message and backtrace to the LLM as the tool result. The LLM can decide to retry, try a different approach, or report the failure to the user.

**Slack connection drops:** `slack-ruby-client` handles reconnection in socket mode automatically.

**Cron task failures:** Log the error, do not crash the process. The next scheduled run will try again.

**Unhandled exceptions:** Top-level rescue in the main loop. Log, attempt recovery (reconnect Slack, reinitialize scheduler), continue running.

## Logging

Structured logging to stdout (captured by Kubernetes):

```
[2026-04-19 09:00:00] INFO  [cron] Triggered: weekly_report
[2026-04-19 09:00:01] INFO  [llm]  Request: 1,247 tokens | Model: anthropic/claude-sonnet-4-20250514
[2026-04-19 09:00:03] INFO  [tool] StripeTool(metric: "mrr") -> { mrr: 42350 }
[2026-04-19 09:00:05] INFO  [llm]  Response: 847 tokens | 2 tool calls
[2026-04-19 09:00:05] INFO  [slack] Posted to #marketing (C085D6W27NY)
```

Log level configurable via `LOG_LEVEL` environment variable or `config.yaml`.

## Dependencies

Ruby gems:

| Gem | Purpose |
|-----|---------|
| `slack-ruby-client` | Slack Socket Mode + Web API |
| `rufus-scheduler` | Internal cron scheduling |
| `faraday` | HTTP client for LLM APIs |
| `json` | JSON parsing (stdlib) |
| `yaml` | YAML config parsing (stdlib) |
| `readline` | Debug REPL (stdlib) |
| `logger` | Structured logging (stdlib) |

Minimal external dependencies. Most functionality comes from Ruby's stdlib.

## File Layout

```
grantclaw/
  grantclaw.rb           # Entry point, CLI parsing, main loop
  Gemfile                 # Gem dependencies
  Dockerfile              # Container image
  lib/
    grantclaw/
      bot.rb              # Bot loader (reads config dir, sets up components)
      message_processor.rb # Core: builds prompts, calls LLM, handles tool loop
      llm/
        base.rb           # LLM adapter interface
        openrouter.rb     # OpenRouter adapter
        anthropic.rb      # Anthropic adapter
        custom.rb         # Custom provider adapter
      tool.rb             # Tool base class (desc, param, schema generation)
      tool_registry.rb    # Loads and registers tools from tools/ directory
      slack_listener.rb   # Slack socket mode event handler
      scheduler.rb        # Cron scheduler wrapper
      repl.rb             # Debug REPL
      memory.rb           # Memory file read/write
      logger.rb           # Structured logging
  helm/
    grantclaw/
      Chart.yaml
      values.yaml
      templates/
        deployment.yaml
        configmap.yaml
        pvc.yaml
        _helpers.tpl
  bots/                   # Example bot configurations
    pulse/
      config.yaml
      role.md
      memory.md
      heartbeat.md
      tools/
        stripe.rb
        posthog.rb
        google_ads.rb
```
